-- pma-voice compatibility, client side.
--
-- The `__cfx_export_pma-voice_<name>` handlers are what make an untouched
-- `exports['pma-voice']:setTalkingMode(2)` call site resolve to this resource:
-- Cfx resolves an export by whichever resource registered that event, which is
-- a different mechanism from `provide` and from a `@pma-voice/...` file
-- include. See resources/[compat]/README.md for the full table of the three.
--
-- Registered in the CLIENT realm, for the client half of pma-voice's surface
-- only. The server half is in server/compat.lua; an export registered in the
-- wrong realm is simply not found, with no error to trace.

Voice = Voice or {}

if not Config.compat.pmaVoice then return end

local surface = {
    setVoiceProperty = function(property, value)
        return exports.kora_voice:setVoiceProperty(property, value)
    end,
    getVoiceProperty = function(property)
        return exports.kora_voice:getVoiceProperty(property)
    end,
    setRadioVolume = function(volume) return Voice.state.setVolume('radio', volume) end,
    setCallVolume = function(volume) return Voice.state.setVolume('call', volume) end,
    setTalkingMode = Voice.proximity.set,

    -- Requests, not assertions -- the same as kora_voice's own client exports.
    -- pma-voice's client `addPlayerToRadio` also went through its server, so
    -- this is not a behaviour change for a caller, only a stronger guarantee.
    setRadioChannel = function(channel)
        return exports.kora_voice:addPlayerToRadio(channel)
    end,
    addPlayerToRadio = function(channel)
        return exports.kora_voice:addPlayerToRadio(channel)
    end,
    removePlayerFromRadio = function()
        return exports.kora_voice:removePlayerFromRadio()
    end,
    removePlayerFromCall = function()
        return exports.kora_voice:removePlayerFromCall()
    end,

    getRadioChannel = function() return Voice.state.data.radio end,
    getCallChannel = function() return Voice.state.data.call end,
}

for name, fn in pairs(surface) do
    QB.compat.provideExport('pma-voice', name, fn)
end

Voice.compat = Voice.compat or {}
Voice.compat.client = surface

-- --- inbound events ---------------------------------------------------------
--
-- pma-voice's server half fires these at its clients. Both are local audio
-- properties, so a server telling a client to change one grants nothing.

RegisterNetEvent('pma-voice:setTalkingMode', function(mode)
    Voice.proximity.set(mode)
end)

RegisterNetEvent('pma-voice:setVoiceProperty', function(property, value)
    exports.kora_voice:setVoiceProperty(property, value)
end)

-- Deliberately NOT registered: `pma-voice:setRadioChannel` and
-- `pma-voice:setCallChannel` as INBOUND events. pma-voice used those names for
-- server-to-client channel assignment, and honouring them would mean a client
-- that fired the event at itself -- or at another client -- could assert
-- membership. Both names are still EMITTED locally by client/sync.lua once the
-- server has published, which is what every UI listening for them actually
-- wants.
