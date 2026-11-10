-- Inbound: everything the server publishes, landing in the local mirror.
--
-- TWO TIMING RULES ARE LOAD BEARING HERE, and both of them have cost a
-- debugging session on this server before:
--
--  1. THE HANDLERS ARE ARMED AFTER THE SESSION IS LIVE. At client chunk load
--     GetPlayerServerId(PlayerId()) is -1, so a bag subscription registered
--     then binds to `player:-1` permanently and no replicated change ever
--     arrives. AddStateBagChangeHandler resolves the bag NAME once, at
--     registration -- it does not re-resolve later. The wait below is not
--     defensive; without it the radio silently never works.
--
--  2. THE HANDLER USES ITS `value` ARGUMENT, NEVER A RE-READ. A state bag
--     change handler fires BEFORE the new value is committed to the local
--     store, so LocalPlayer.state[key] inside the handler still returns the
--     PREVIOUS value for the very key that changed. Reading it back would
--     apply the channel the player just left.

Voice = Voice or {}
Voice.sync = {}

local Sync = Voice.sync

---Rebuilds the voice target now, if membership changed, instead of waiting for
---the next bounded tick.
local function refreshNow()
    if not Config.mumble.refreshOnChange then return end

    -- In its own thread: the caller is a state-bag handler or an event handler,
    -- and the rebuild fires synchronous shape tests. Doing that inline inside a
    -- bag handler stalls the handler chain every other resource shares.
    CreateThread(function()
        Voice.targets.refresh()
    end)
end

---Applies a published radio channel.
---@param value integer|false|nil nil is treated exactly as false -- see the clearing convention in config.lua
local function applyRadio(value)
    local channel = tonumber(value) or false

    if not Voice.state.setRadio(channel) then return end

    -- Both event names on purpose: the kora_voice one for new code, the pma-voice
    -- one because a phone or radio UI written against pma-voice listens for it
    -- and would otherwise show a channel the player is no longer on.
    TriggerEvent('kora_voice:client:radioChanged', channel)
    TriggerEvent('pma-voice:setRadioChannel', channel or 0)

    refreshNow()
end

---@param value integer|false|nil
local function applyCall(value)
    local channel = tonumber(value) or false

    if not Voice.state.setCall(channel) then return end

    TriggerEvent('kora_voice:client:callChanged', channel)
    TriggerEvent('pma-voice:setCallChannel', channel or 0)

    refreshNow()
end

Sync.applyRadio = applyRadio
Sync.applyCall = applyCall

---Accepts a roster push.
---
---The member list is taken verbatim and never merged with what was there
---before. A merge would mean a client accumulated members across pushes, and a
---member who was never removed is a voice target for a channel the player left.
---@param kind 'radio'|'call'
---@param payload { channel: integer|false, members: integer[] }
function Sync.applyRoster(kind, payload)
    if type(payload) ~= 'table' then return end

    local members = {}
    for _, serverId in ipairs(payload.members or {}) do
        local id = tonumber(serverId)
        if id and id > 0 then members[#members + 1] = id end
    end

    if kind == 'call' then
        Voice.state.setCallMembers(members)
    else
        Voice.state.setRadioMembers(members)
    end

    refreshNow()
end

CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(0) end

    -- The session flag can flip a tick before the server id is readable, and
    -- Kora.cache only re-reads its natives on kora_lib's shared tick -- so spinning
    -- on the flag alone can still leave this at -1. Spin on the id itself.
    local serverId = GetPlayerServerId(PlayerId())
    while not serverId or serverId <= 0 do
        Wait(0)
        serverId = GetPlayerServerId(PlayerId())
    end

    local bag = ('player:%s'):format(serverId)

    Kora.state.onChange(Config.state.radio, bag, function(change)
        applyRadio(change.value)
    end)

    Kora.state.onChange(Config.state.call, bag, function(change)
        applyCall(change.value)
    end)

    Kora.events.onPush('kora_voice:radio:roster', function(payload)
        -- The roster push also carries the channel, and it is applied FIRST:
        -- on a resource restart the push can arrive before the bag replicates,
        -- and members without a channel would be dropped by
        -- Voice.state.setRadio's own clear.
        if payload and payload.channel ~= nil then applyRadio(payload.channel) end
        Sync.applyRoster('radio', payload)
    end)

    Kora.events.onPush('kora_voice:call:roster', function(payload)
        if payload and payload.channel ~= nil then applyCall(payload.channel) end
        Sync.applyRoster('call', payload)
    end)

    -- Catch-up, AFTER the handlers are armed. This is what makes
    -- `ensure kora_voice` against a live, already-logged-in server work: every
    -- change that happened before the subscriptions existed is re-stated here.
    -- Ordering matters -- asking first and arming second would race the answer.
    local published = Kora.callback.trigger('kora_voice:sync')
    if type(published) == 'table' then
        applyRadio(published.radio)
        applyCall(published.call)
    end

    -- Proximity is purely local, but it has to be pushed into the natives once
    -- at spawn: a fresh client is on whatever range the last resource to touch
    -- Mumble left it on, which is usually GTA's own default and not the
    -- configured normal mode.
    Voice.proximity.apply()
    Voice.submix.ensure()
    Voice.targets.start()
end)

-- A respawn resets the proximity mode to the configured default. Shouting is a
-- deliberate act, and a player who died mid-shout and respawned still shouting
-- is broadcasting to 35 metres without having chosen to.
AddEventHandler('kora_core:client:onPlayerLoaded', function()
    Voice.proximity.set(Voice.modes.defaultIndex())
end)
