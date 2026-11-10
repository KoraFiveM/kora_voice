-- The authority layer: the only file that changes membership.
--
-- There are deliberately TWO entry points, and which one a call site uses is
-- the whole security model:
--
--   Voice.api.assign(src, channel)   -- TRUSTED. No policy check. Reachable
--                                       only from another server resource's
--                                       export call: a job resource putting an
--                                       officer on the tac channel, a phone
--                                       resource opening a call.
--
--   Voice.api.request(src, channel)  -- UNTRUSTED. Policy enforced. The ONLY
--                                       path a client can reach, through the
--                                       rate-limited callback in server/net.lua.
--
-- Naming them differently rather than passing a `trusted` flag is intentional:
-- a flag defaults, and a defaulted flag on the wrong call site is a client that
-- can join the police channel. A missing function name is a hard error.

Voice = Voice or {}
Voice.api = {}

local A = Voice.api
local clientRequests = {}
local characterRadio = {}

local function consumeClientRequest(src, kind)
    local limit = Config.rateLimit[kind]
    if not limit then return true end

    local key = ('%s:%s'):format(src, kind)
    local bucket = clientRequests[key] or {}
    local current = GetGameTimer()
    local cutoff = current - limit.window
    local retained = {}
    for i = 1, #bucket do
        if bucket[i] > cutoff then retained[#retained + 1] = bucket[i] end
    end
    if #retained >= limit.max then
        clientRequests[key] = retained
        return false
    end

    retained[#retained + 1] = current
    clientRequests[key] = retained
    return true
end

---Applies a radio membership change and publishes the consequences.
---
---Publication order is load bearing: the store is updated first, then the state
---bag, then the rosters -- so a client that reacts to the roster push by reading
---its own state bag sees the channel it was just told about, not the previous
---one.
---@param src integer
---@param channel integer|nil
---@param characterOwned boolean|nil
---@return boolean changed
local function commitRadio(src, channel, characterOwned)
    local previous, current = Voice.store.setRadio(src, channel)
    if previous == current then return false end
    characterRadio[src] = characterOwned or nil

    Voice.publish.membership(src)

    -- Both rosters, always. The channel just LEFT has to be re-pushed or every
    -- remaining member keeps a voice target for someone who can no longer hear
    -- them -- a one-way radio that looks like a network fault.
    Voice.publish.roster('radio', previous)

    if current then
        Voice.publish.roster('radio', current)
    else
        -- The leaver is no longer in any roster, so no roster push reaches them.
        Voice.publish.cleared(src, 'radio')
    end

    TriggerEvent('kora_voice:server:radioChanged', src, current or false, previous or false)
    return true
end

---@param src integer
---@param channel integer|nil
---@return boolean changed
local function commitCall(src, channel)
    local previous, current = Voice.store.setCall(src, channel)
    if previous == current then return false end

    Voice.publish.membership(src)
    Voice.publish.roster('call', previous)

    if current then
        Voice.publish.roster('call', current)
    else
        Voice.publish.cleared(src, 'call')
    end

    TriggerEvent('kora_voice:server:callChanged', src, current or false, previous or false)
    return true
end

---Assigns a radio channel. TRUSTED -- no policy check.
---
---For server code. Passing nil removes the player from whatever they are on,
---which is how every "holster the radio" path spells it.
---@param src integer
---@param channel integer|nil
---@return boolean ok, string|nil error
function A.assign(src, channel)
    if type(src) ~= 'number' then return false, 'kora_voice: src must be a number' end

    local normalised = Voice.channels.normalise(channel)
    -- A channel that was GIVEN but did not normalise is a caller bug worth
    -- reporting, not a silent "leave the radio". Only an explicit nil/false
    -- means leave.
    if channel ~= nil and channel ~= false and not normalised then
        return false, ('kora_voice: %s is not a valid radio channel'):format(tostring(channel))
    end

    characterRadio[src] = nil
    commitRadio(src, normalised)
    return true
end

---Handles a CLIENT's request for a radio channel. Policy enforced.
---@param src integer
---@param channel integer|nil
---@return boolean ok, string|nil reason
function A.request(src, channel)
    local normalised = Voice.channels.normalise(channel)

    -- Leaving is always permitted. A player must never be able to get stuck on
    -- a channel, including one a policy hook has since decided they may not be
    -- on -- and "leave" grants no audio, so there is nothing to protect.
    if not normalised then
        commitRadio(src, nil)
        return true
    end

    local allowed, reason, characterOwned = Voice.policy.canJoin(src, normalised)
    if not allowed then
        -- Nothing is committed and nothing is published. The client's own state
        -- bag still says whatever it said before, which is the point: a refused
        -- request leaves the published truth untouched rather than writing an
        -- optimistic value the client would render.
        return false, reason or Config.radio.refusedMessage
    end

    commitRadio(src, normalised, characterOwned)
    return true
end

---Rate-limited client request shared by kora_lib callbacks and pma-voice events.
---@param src integer
---@param channel integer|nil
---@return boolean ok, string|nil reason
function A.requestClient(src, channel)
    if not consumeClientRequest(src, 'radio') then return false, 'Voice request limit reached.' end
    return A.request(src, channel)
end

---@param src integer
---@param channel integer|nil
---@return boolean removed, string|nil reason
function A.removeRadioClient(src, channel)
    if not consumeClientRequest(src, 'radio') then return false, 'Voice request limit reached.' end
    return A.removeFromRadio(src, channel)
end

---@param src integer
---@param channel integer|nil
---@return boolean removed, string|nil reason
function A.removeCallClient(src, channel)
    if not consumeClientRequest(src, 'call') then return false, 'Voice request limit reached.' end
    return A.removeFromCall(src, channel)
end

---Assigns a call channel. TRUSTED.
---
---Calls are not restriction-checked at all. A call channel is a phone number
---negotiated by a phone resource that already decided who may ring whom;
---duplicating that decision here would mean this resource had to know what a
---phone number is.
---@param src integer
---@param channel integer|nil
---@return boolean ok, string|nil error
function A.assignCall(src, channel)
    if type(src) ~= 'number' then return false, 'kora_voice: src must be a number' end

    local normalised = Voice.channels.normaliseCall(channel)
    if channel ~= nil and channel ~= false and not normalised then
        return false, ('kora_voice: %s is not a valid call channel'):format(tostring(channel))
    end

    commitCall(src, normalised)
    return true
end

---Removes a player from a radio channel, but ONLY if they are on that exact
---channel.
---
---The channel argument is a guard, not a target. pma-voice's
---`removePlayerFromRadio(src, channel)` is called from radio UIs that may be a
---moment behind the server, and an unconditional removal would let a stale
---"leave channel 3" click kick the player off the channel 5 they just joined.
---@param src integer
---@param channel integer|nil nil removes whatever they are on
---@return boolean removed
function A.removeFromRadio(src, channel)
    local current = Voice.store.getRadio(src)
    if not current then return false end

    local normalised = Voice.channels.normalise(channel)
    if normalised and normalised ~= current then return false end

    return commitRadio(src, nil)
end

---@param src integer
---@param channel integer|nil
---@return boolean removed
function A.removeFromCall(src, channel)
    local current = Voice.store.getCall(src)
    if not current then return false end

    local normalised = Voice.channels.normaliseCall(channel)
    if normalised and normalised ~= current then return false end

    return commitCall(src, nil)
end

---Forgets a disconnecting player and re-pushes the rosters they were in.
---@param src integer
function A.drop(src)
    characterRadio[src] = nil
    clientRequests[('%s:radio'):format(src)] = nil
    clientRequests[('%s:call'):format(src)] = nil
    local radio, call = Voice.store.forget(src)
    Voice.policy.forget(src)

    -- No membership publish: the player is gone and their bag with them. The
    -- rosters still need it, or the remaining members keep a voice target for a
    -- source id the server is about to hand to somebody else.
    Voice.publish.roster('radio', radio)
    Voice.publish.roster('call', call)
end

AddEventHandler('playerDropped', function()
    A.drop(source)
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    if characterRadio[src] then commitRadio(src, nil) end
end)

-- All server-side, all trusted. There is no client export that changes
-- membership anywhere in this resource -- see client/exports.lua.

---Puts a player on a radio channel. `exports.kora_voice:setPlayerRadio(src, 3)`
---@param src integer
---@param channel integer|nil
---@return boolean ok, string|nil error
exports('setPlayerRadio', function(src, channel)
    return A.assign(src, channel)
end)

---Alias of setPlayerRadio, for pma-voice call sites.
exports('addPlayerToRadio', function(src, channel)
    return A.assign(src, channel)
end)

---@param src integer
---@param channel integer|nil
---@return boolean
exports('removePlayerFromRadio', function(src, channel)
    return A.removeFromRadio(src, channel)
end)

---@param src integer
---@param channel integer|nil
---@return boolean ok, string|nil error
exports('setPlayerCall', function(src, channel)
    return A.assignCall(src, channel)
end)

---@param src integer
---@param channel integer|nil
---@return boolean
exports('removePlayerFromCall', function(src, channel)
    return A.removeFromCall(src, channel)
end)

---Members of a radio channel, in pma-voice's shape: a map of source -> true.
---
---A map rather than an array because that is what pma-voice returns and what
---existing call sites index. `getRadioMembers` below is the array form for new
---code that wants to iterate or count.
---@param channel integer
---@return table<integer, boolean>
exports('getPlayersInRadioChannel', function(channel)
    local out = {}
    for _, src in ipairs(Voice.store.radioMembersOf(Voice.channels.normalise(channel))) do
        out[src] = true
    end
    return out
end)

---@param channel integer
---@return table<integer, boolean>
exports('getPlayersInCall', function(channel)
    local out = {}
    for _, src in ipairs(Voice.store.callMembersOf(Voice.channels.normaliseCall(channel))) do
        out[src] = true
    end
    return out
end)

---Sorted array form of the above.
---@param channel integer
---@return integer[]
exports('getRadioMembers', function(channel)
    return Voice.store.radioMembersOf(Voice.channels.normalise(channel))
end)

---@param src integer
---@return integer|false false rather than nil, so the value survives the exports boundary intact
exports('getRadioChannel', function(src)
    return Voice.store.getRadio(src) or false
end)

---@param src integer
---@return integer|false
exports('getCallChannel', function(src)
    return Voice.store.getCall(src) or false
end)

---Grants one player a set of channels they may join regardless of the
---restriction table. The recommended way for a job resource to open its own
---frequencies: data, so a restart of the granting resource cannot leave a dead
---callback behind.
---@param src integer
---@param channels integer[]|integer|nil nil revokes
---@return integer count
exports('grantRadioChannels', function(src, channels)
    return Voice.policy.grant(src, channels)
end)

---@param src integer
---@return integer count always 0; returned for symmetry with grantRadioChannels
exports('revokeRadioChannels', function(src)
    return Voice.policy.grant(src, nil)
end)

---Registers a dynamic policy hook. Returns a handle for removeRadioPolicy.
---
---Prefer `grantRadioChannels` unless the decision genuinely has to be made at
---request time -- a funcref is only callable while the resource that created it
---is running.
---@param fn fun(src: integer, channel: integer): boolean|nil, string|nil
---@return integer handle
exports('addChannelCheck', Voice.policy.addChannelCheck)
exports('removeChannelCheck', Voice.policy.removeChannelCheck)

exports('addRadioPolicy', function(fn)
    return Voice.policy.addHook(fn)
end)

---@param handle integer
---@return boolean
exports('removeRadioPolicy', function(handle)
    return Voice.policy.removeHook(handle)
end)

---Whether a channel is restricted at all. Server-only on purpose: this is the
---one crumb of the restriction table that is safe to answer, and it is answered
---to server code, never to a client.
---@param channel integer
---@return boolean
exports('isChannelRestricted', function(channel)
    return Voice.channels.isRestricted(Voice.channels.normalise(channel))
end)

-- Bucket changes do not change membership, but both channel rosters must be rebuilt.
---@param src integer
---@return boolean ok
---@return string|nil reason
local function refreshVoiceTargets(src)
    src = tonumber(src)
    if not src then return false, 'kora_voice: src must be a number' end
    if not Config.buckets.enforce then return true end

    Voice.publish.roster('radio', Voice.store.getRadio(src))
    Voice.publish.roster('call', Voice.store.getCall(src))
    return true
end

AddEventHandler('kora_voice:server:bucketChanged', refreshVoiceTargets)
exports('refreshVoiceTargets', refreshVoiceTargets)
