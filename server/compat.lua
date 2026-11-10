-- pma-voice compatibility, server side.
--
-- Two mechanisms, because Cfx treats them as unrelated identities:
--
--   * the EXPORT identity. `exports['pma-voice']:setPlayerRadio(...)` resolves
--     to whichever resource registered the `__cfx_export_pma-voice_<name>`
--     event, so registering those handlers here makes an untouched pma-voice
--     call site work with no wrapper resource. `provide 'pma-voice'` in the
--     manifest separately satisfies a `dependency 'pma-voice'`. Neither implies
--     the other -- see resources/[compat]/README.md for the full table.
--
--   * the EVENTS. pma-voice's own client half fires these at the server, so
--     anything that reimplemented that half still works.
--
-- THE ONE PLACE THIS DIVERGES FROM PMA-VOICE, DELIBERATELY: every net event
-- below is treated as an UNTRUSTED CLIENT REQUEST and its target is `source`,
-- never a src argument in the payload. pma-voice's equivalents let the payload
-- name the player, which means any client can put ANY player on ANY channel by
-- firing a well-known event name -- the exact exploit this resource's authority
-- boundary exists to close. Server code that legitimately needs to assign
-- another player's channel calls the export, which is trusted.

Voice = Voice or {}

if not Config.compat.pmaVoice then return end

-- Refuse to start alongside a real pma-voice folder. Two resources rebuilding
-- the same Mumble voice target fight every tick, and the symptom is
-- intermittent one-directional audio that reads as a network fault rather than
-- a resource conflict. `GetResourceState('pma-voice')` cannot be used for this:
-- it resolves our own `provide` back to this resource and would report a
-- conflict with ourselves. Provided identities are not entries in the resource
-- list; a separately started pma-voice folder is.
local function conflicting(name)
    if type(GetNumResources) ~= 'function' or type(GetResourceByFindIndex) ~= 'function'
        or type(GetResourceState) ~= 'function' then
        return false
    end

    for index = 0, GetNumResources() - 1 do
        if GetResourceByFindIndex(index) == name then
            local state = GetResourceState(name)
            return state == 'started' or state == 'starting'
        end
    end

    return false
end

if Config.compat.refuseOnConflict and conflicting('pma-voice') then
    error('kora_voice: pma-voice is running; stop it before starting kora_voice (both drive the same Mumble voice target)')
end

RegisterNetEvent('pma-voice:setPlayerRadio', function(channel)
    Voice.api.requestClient(source, channel)
end)

RegisterNetEvent('pma-voice:addPlayerToRadio', function(channel)
    Voice.api.requestClient(source, channel)
end)

RegisterNetEvent('pma-voice:removePlayerFromRadio', function(channel)
    Voice.api.removeRadioClient(source, channel)
end)

-- Joining a call is not client-requestable here; see server/net.lua. Leaving
-- one is, because hanging up grants no audio.
RegisterNetEvent('pma-voice:removePlayerFromCall', function(channel)
    Voice.api.removeCallClient(source, channel)
end)

-- Only the SERVER half of pma-voice's surface. The client half is registered
-- from client/compat.lua, in the client realm, where those exports live.
local surface = {
    addChannelCheck = Voice.policy.addChannelCheck,
    removeChannelCheck = Voice.policy.removeChannelCheck,
    setPlayerRadio = Voice.api.assign,
    addPlayerToRadio = Voice.api.assign,
    removePlayerFromRadio = Voice.api.removeFromRadio,
    setPlayerCall = Voice.api.assignCall,
    removePlayerFromCall = Voice.api.removeFromCall,

    getPlayersInRadioChannel = function(channel)
        local out = {}
        for _, src in ipairs(Voice.store.radioMembersOf(Voice.channels.normalise(channel))) do
            out[src] = true
        end
        return out
    end,

    getPlayersInCall = function(channel)
        local out = {}
        for _, src in ipairs(Voice.store.callMembersOf(Voice.channels.normaliseCall(channel))) do
            out[src] = true
        end
        return out
    end,

    getRadioChannel = function(src) return Voice.store.getRadio(src) or false end,
    getCallChannel = function(src) return Voice.store.getCall(src) or false end,
}

for name, fn in pairs(surface) do
    Kora.compat.provideExport('pma-voice', name, fn)
end

Voice.compat = Voice.compat or {}
Voice.compat.server = surface
