-- Voice target management: the one place Mumble is told who may receive this
-- player's audio.
--
-- A single numbered voice target (Config.mumble.targetId) is CLEARED and
-- REBUILT, never edited incrementally. Incremental edits are how a player ends
-- up still audible on a channel they left: there is no "remove one player from
-- a target" native, so the only way to drop a member is to rebuild without
-- them. Rebuilding is cheap; a stale target is a listening exploit.
--
-- The rebuild runs on a BOUNDED TICK (Config.mumble.refreshInterval, 500ms),
-- not per frame. It walks every in-scope player and fires a shape test per
-- nearby one, so per-frame would be 60 passes a second of work whose result
-- changes at conversational speed. Membership changes additionally request an
-- immediate rebuild, because a half-second of silence after joining a channel
-- reads as the radio being broken.
--
-- THREE CONTRIBUTIONS, and only one of them is local:
--   * the PROXIMITY GRID  -- derived locally from GetActivePlayers
--   * the RADIO ROSTER    -- exactly what the server pushed, never extended
--   * the CALL ROSTER     -- likewise
-- A member this client added to either roster itself would be a self-granted
-- voice target, which is the whole thing the server authority exists to prevent.

Voice = Voice or {}
Voice.targets = {}

local T = Voice.targets

-- serverId -> true for speakers we have applied a volume override or a submix
-- to, so the next rebuild can undo it. Tracked rather than recomputed because
-- "who did I change last time" is not derivable from the current world state:
-- a player who walked out of scope is gone from GetActivePlayers, and their
-- override would never be cleared.
local overridden = {}
local submixed = {}

local rebuilding = false

---This client's own server id, or nil before the session is live.
---
---Read fresh rather than cached at load: at client chunk load
---GetPlayerServerId(PlayerId()) is -1, and a -1 cached here would put this
---player in its own grid forever.
---@return integer|nil
local function myServerId()
    if type(GetPlayerServerId) ~= 'function' or type(PlayerId) ~= 'function' then return nil end

    local id = GetPlayerServerId(PlayerId())
    return (id and id > 0) and id or nil
end

---The proximity grid: every in-scope player within the current talk range.
---
---GetActivePlayers is ALREADY routing-bucket-aware -- a player in a different
---bucket is not in this client's scope and does not appear. That is why the
---grid needs no bucket filter of its own, and why the ROSTERS do (a radio
---member in another bucket is a server fact with no local scope entry at all,
---so the server filters those before it pushes them).
---@return integer[] serverIds
---@return table<integer, number> distances metres, by server id
function T.grid()
    local ids, distances = {}, {}

    if type(GetActivePlayers) ~= 'function' then return ids, distances end

    local me = myServerId()
    if not me then return ids, distances end

    local myPed = GetPlayerPed(PlayerId())
    if not myPed or myPed == 0 then return ids, distances end

    local origin = GetEntityCoords(myPed)
    local range = Voice.proximity.currentRange()

    -- Muffling needs to know about speakers slightly further out than the talk
    -- range, so the grid is built to whichever is larger and the target list
    -- filters back down. One walk, two consumers.
    local reach = math.max(range, Config.muffling.enabled and Config.muffling.maxDistance or 0.0)

    for _, player in ipairs(GetActivePlayers()) do
        local serverId = GetPlayerServerId(player)

        if serverId and serverId > 0 and serverId ~= me then
            local ped = GetPlayerPed(player)

            if ped and ped ~= 0 then
                local coords = GetEntityCoords(ped)
                local dx, dy, dz = coords.x - origin.x, coords.y - origin.y, coords.z - origin.z
                -- Squared distance, compared against a squared reach: this runs
                -- once per in-scope player every rebuild and a square root per
                -- player buys nothing, since the only use is a comparison.
                local squared = dx * dx + dy * dy + dz * dz

                if squared <= reach * reach then
                    ids[#ids + 1] = serverId
                    distances[serverId] = math.sqrt(squared)
                end
            end
        end
    end

    return ids, distances
end

---Whether there is a clear line of sight between this player and `ped`.
---
---Tested at chest height, not at the ped origin: a ray between two origins
---clips the ground on any slope and would report every player standing uphill
---as being behind a wall.
---@param myPed integer
---@param ped integer
---@return boolean
local function hasLineOfSight(myPed, ped)
    if type(StartExpensiveSynchronousShapeTestLosProbe) ~= 'function' then return true end

    local offset = Config.muffling.heightOffset
    local a = GetEntityCoords(myPed)
    local b = GetEntityCoords(ped)

    -- Flag 1 is map/world geometry only. Including vehicles and peds would
    -- report a muffle every time somebody walked between two speakers, which
    -- reads as the audio cutting out at random.
    local handle = StartExpensiveSynchronousShapeTestLosProbe(
        a.x, a.y, a.z + offset, b.x, b.y, b.z + offset, 1, myPed, 4)

    local _, hit = GetShapeTestResult(handle)
    return not (hit == 1 or hit == true)
end

---Sets one speaker's volume override, or removes it when `volume` is nil.
---
---There is only ONE override slot per speaker in Mumble, so occlusion and the
---per-path radio/call volumes cannot each own one -- they are combined into a
---single value by the caller and written here once. Writing them separately
---would mean whichever ran last silently discarded the other.
---@param serverId integer
---@param volume number|nil
local function setVolumeOverride(serverId, volume)
    if type(MumbleSetVolumeOverrideByServerId) ~= 'function' then return end

    if volume then
        MumbleSetVolumeOverrideByServerId(serverId, volume + 0.0)
        overridden[serverId] = true
    elseif overridden[serverId] then
        -- -1.0 is Mumble's "no override", not "volume zero". Writing 1.0 instead
        -- would pin the speaker at full volume and defeat every other volume
        -- control, including the player's own Mumble settings.
        MumbleSetVolumeOverrideByServerId(serverId, -1.0)
        overridden[serverId] = nil
    end
end

---Rebuilds the voice target from scratch.
---@return integer count members added to the target
function T.rebuild()
    -- Reentrancy guard. The bounded tick and an immediate change-driven rebuild
    -- can land in the same frame; two interleaved rebuilds would each clear the
    -- other's half-built target and leave a player audible to nobody.
    if rebuilding then return 0 end
    rebuilding = true

    local target = Config.mumble.targetId
    local count = 0

    if type(MumbleClearVoiceTarget) == 'function' then MumbleClearVoiceTarget(target) end

    local added = {}

    ---@param serverId integer
    local function add(serverId)
        if not serverId or added[serverId] then return end
        added[serverId] = true
        count = count + 1

        -- ByServerId is REQUIRED, not merely preferred, for channel members: a
        -- radio member outside this client's scope has no local player handle
        -- at all, so MumbleAddVoiceTargetPlayer (which takes a handle) cannot
        -- reach them -- and a radio you can only hear people on when they are
        -- already in earshot is not a radio. The handle form is kept purely as
        -- a fallback for a build without the ByServerId native.
        if type(MumbleAddVoiceTargetPlayerByServerId) == 'function' then
            MumbleAddVoiceTargetPlayerByServerId(target, serverId)
        elseif type(MumbleAddVoiceTargetPlayer) == 'function' and type(GetPlayerFromServerId) == 'function' then
            local player = GetPlayerFromServerId(serverId)
            if player and player ~= -1 then MumbleAddVoiceTargetPlayer(target, player) end
        end
    end

    local me = myServerId()
    local grid, distances = T.grid()
    local range = Voice.proximity.currentRange()

    local inGrid = {}
    for _, serverId in ipairs(grid) do
        inGrid[serverId] = true
        -- The grid reaches as far as muffling needs; the target only as far as
        -- this player's actual talk range.
        if (distances[serverId] or math.huge) <= range then add(serverId) end
    end

    -- Radio: only while the talk key is held AND the server actually granted a
    -- channel. Adding the roster unconditionally would make every word spoken
    -- in a room go out over the air.
    local radioActive = Voice.state.isRadioActive()
    if radioActive then
        for _, serverId in ipairs(Voice.state.data.radioMembers) do
            if serverId ~= me then add(serverId) end
        end
    end

    -- Calls are always live once joined -- holding a key to speak into a phone
    -- is not what a phone is -- and are independent of the radio, so a
    -- transmission and a call are both in the target at once.
    if Voice.state.data.call then
        for _, serverId in ipairs(Voice.state.data.callMembers) do
            if serverId ~= me then add(serverId) end
        end
    end

    if type(MumbleSetVoiceTarget) == 'function' then MumbleSetVoiceTarget(target) end

    -- --- received-audio processing, same pass ---
    --
    -- Kept here rather than in its own tick because it needs the same grid and
    -- the same distances. A second tick would recompute both.
    local myPed = type(GetPlayerPed) == 'function' and GetPlayerPed(PlayerId()) or nil

    -- serverId -> the volume this speaker should be heard at. Accumulated
    -- first and written once at the end, because Mumble has a single override
    -- slot per speaker: occlusion and the per-path volumes have to be one
    -- number, not two competing writes.
    local desired = {}

    ---@param serverId integer
    ---@param volume number
    local function want(serverId, volume)
        -- The QUIETEST wins. A speaker who is both behind a wall and on a
        -- turned-down radio should be heard at the harder of the two
        -- reductions, not have one of them overwrite the other.
        local current = desired[serverId]
        if current == nil or volume < current then desired[serverId] = volume end
    end

    -- Submix routing by MEMBERSHIP, with an exception for earshot: a channel
    -- member standing next to you is heard through the air, so filtering them
    -- would make a face-to-face conversation sound like a radio. A member who
    -- is NOT in the grid has no path to you but the radio, so they are
    -- filtered -- and it is the same set that the radio volume applies to, for
    -- the same reason.
    -- (pma-voice instead toggles this per transmission, off its own
    -- radioActive event. Membership plus earshot needs no extra round trip and
    -- gives the same result for every case either resource can distinguish.)
    if Voice.state.data.radio then
        for _, serverId in ipairs(Voice.state.data.radioMembers) do
            if serverId ~= me and not inGrid[serverId] then
                if Config.radio.submix and Voice.submix.applyTo(serverId, 'radio') then
                    submixed[serverId] = true
                end
                if Voice.state.data.radioVolume < 1.0 then want(serverId, Voice.state.data.radioVolume) end
            end
        end
    end


    if Voice.state.data.call then
        for _, serverId in ipairs(Voice.state.data.callMembers) do
            if serverId ~= me and not inGrid[serverId] then
                -- Config.calls.submix ships OFF: a phone is not a handheld
                -- radio and band-limiting it makes every call sound like one.
                -- It exists for servers that want the retro-telephone effect.
                if Config.calls.submix and Voice.submix.applyTo(serverId, 'radio') then
                    submixed[serverId] = true
                end
                if Voice.state.data.callVolume < 1.0 then want(serverId, Voice.state.data.callVolume) end
            end
        end
    end

    -- Everything routed last pass that no longer earns the effect. Swept after
    -- BOTH the radio and call blocks, so a speaker who moved from one path to
    -- the other is not cleared and re-applied within a single rebuild -- and,
    -- more importantly, so a speaker who left both is actually cleared. A
    -- speaker whose submix was never cleared keeps it for the rest of the
    -- session, and nobody reports that as a bug: they just say voice sounds odd.
    for serverId in pairs(submixed) do
        local wantsRadio = Config.radio.submix and Voice.state.data.radio and not inGrid[serverId]
        local wantsCall = Config.calls.submix and Voice.state.data.call and not inGrid[serverId]

        if not (wantsRadio or wantsCall) then
            Voice.submix.clearFor(serverId)
            submixed[serverId] = nil
        end
    end

    -- Muffling: only for speakers actually in earshot. A radio member on the
    -- other side of the map is not "behind a wall", and probing towards them
    -- would be a shape test across the whole map for nothing.
    if Config.muffling.enabled and myPed and myPed ~= 0 then
        for _, serverId in ipairs(grid) do
            if (distances[serverId] or math.huge) <= Config.muffling.maxDistance then
                local ped = type(GetPlayerFromServerId) == 'function'
                    and GetPlayerPed(GetPlayerFromServerId(serverId)) or nil

                if ped and ped ~= 0 and not hasLineOfSight(myPed, ped) then
                    want(serverId, Config.muffling.occludedVolume)
                end
            end
        end
    end

    for serverId, volume in pairs(desired) do
        setVolumeOverride(serverId, volume)
    end

    -- Anything overridden last pass that nothing wants reduced any more. This
    -- has to walk the tracked set rather than the current grid: a player who
    -- walked out of scope is gone from GetActivePlayers entirely, and their
    -- override would never be lifted -- they would still be quiet tomorrow.
    for serverId in pairs(overridden) do
        if desired[serverId] == nil then setVolumeOverride(serverId, nil) end
    end

    Voice.state.clearDirty()
    rebuilding = false

    return count
end

---Rebuilds only if something changed since the last pass.
---@return boolean rebuilt
function T.refresh()
    if not Voice.state.isDirty() then return false end

    T.rebuild()
    return true
end

---Starts the bounded refresh tick.
---
---The tick rebuilds UNCONDITIONALLY rather than only when dirty: positions
---change without any state change at all, so a player walking out of range
---must drop out of the target even though nothing was marked dirty. The dirty
---flag exists for the opposite case -- reacting to a membership change without
---waiting for the next tick.
---@return integer timerId
function T.start()
    return QB.timers.setInterval(function()
        T.rebuild()
    end, Config.mumble.refreshInterval)
end
