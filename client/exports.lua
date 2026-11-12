-- The client exports: presentation, local audio properties, and REQUESTS.
--
-- Read the return contract of `addPlayerToRadio` carefully -- it is the one
-- place the authority boundary is visible from the client API. It returns
-- whether the SERVER agreed. It does not put the player on a channel; it asks,
-- and the answer arrives as a published state bag value which
-- client/sync.lua applies. A caller that treats a `true` return as "I am now on
-- channel 3" is reading it right; a caller that assumes the local state
-- already reflects it on the next line is not, and should listen for
-- `kora_voice:client:radioChanged` instead.

Voice = Voice or {}

---Asks the server for a radio channel.
---
---Must be called from a coroutine (a command handler, a CreateThread, a
---keybind callback) -- it suspends until the server answers.
---@param channel integer|nil nil or 0 leaves the current channel
---@return boolean ok, string|nil reason nil `reason` on a false means the round trip timed out, NOT that the server refused silently
exports('addPlayerToRadio', function(channel)
    local ok, reason = Kora.callback.trigger('kora_voice:requestRadio', channel)

    -- A timed-out callback returns NO values, so `ok` is nil rather than false.
    -- Reporting that as a refusal would invent a decision the server never
    -- made; the caller gets nil and can tell the two apart.
    if ok == nil then return false, nil end

    return ok, reason
end)

---Leaves the current radio channel. Always permitted -- a player must never be
---able to get stuck on a channel.
---@return boolean
exports('removePlayerFromRadio', function()
    return Kora.callback.trigger('kora_voice:leaveRadio') == true
end)

---Leaves the current call.
---@return boolean
exports('removePlayerFromCall', function()
    return Kora.callback.trigger('kora_voice:leaveCall') == true
end)

---This player's published radio channel, or false.
---
---Read from the local mirror of what the SERVER published, never from a local
---assumption -- so it is false until the server has actually agreed.
---@return integer|false
exports('getRadioChannel', function()
    return Voice.state.data.radio
end)

---@return integer|false
exports('getCallChannel', function()
    return Voice.state.data.call
end)

---Sets the proximity talk mode.
---@param mode integer|string an index into Config.proximity.modes, or a mode name ('whisper')
---@return integer index, number range
exports('setTalkingMode', function(mode)
    return Voice.proximity.set(mode)
end)

---Steps the proximity mode by `step` (default 1), wrapping per config.
---@param step integer|nil
---@return integer index, number range
exports('cycleTalkingMode', function(step)
    return Voice.proximity.cycle(step)
end)

---The current mode as a table, for a HUD.
---@return { index: integer, name: string, label: string, range: number }
exports('getTalkingMode', function()
    local index = Voice.state.mode()
    local mode = Voice.modes.get(index) or {}

    return {
        index = index,
        name = mode.name,
        label = mode.label,
        range = Voice.proximity.currentRange(),
    }
end)

---Whether this player is transmitting on the radio right now.
---
---This is what a mic indicator should use to distinguish radio traffic from
---proximity speech. Plain "am I talking" is a different question and the
---native `NetworkIsPlayerTalking` already answers it -- which is why kora_hud's
---mic indicator needs no integration with this resource at all.
---@return boolean
exports('isRadioActive', function()
    return Voice.state.isRadioActive()
end)

---@param active boolean
---@return boolean changed
exports('setMegaphone', function(active)
    local changed = Voice.state.setMegaphone(active)
    if changed then
        Voice.proximity.apply()
        Voice.state.markDirty()
    end
    return changed
end)

---@param volume number 0.0-1.0, or 0-100
---@return number applied
exports('setRadioVolume', function(volume)
    return Voice.state.setVolume('radio', volume)
end)

---@param volume number
---@return number applied
exports('setCallVolume', function(volume)
    return Voice.state.setVolume('call', volume)
end)

-- The pma-voice `setVoiceProperty` surface. Every property is LOCAL AUDIO
-- ONLY: a volume, an effect toggle, a mode. There is deliberately no property
-- that changes membership, because `setVoiceProperty` is a client-side setter
-- and a client-side membership setter is the exploit this resource exists to
-- close.
local properties = {
    radioVolume = function(value) Voice.state.setVolume('radio', value) end,
    callVolume = function(value) Voice.state.setVolume('call', value) end,

    micClicks = function(value)
        Config.radio.clicks = value == true or value == 1
    end,

    submix = function(value)
        Config.radio.submix = value == true or value == 1
        Voice.state.markDirty()
    end,

    -- pma-voice's own name for the proximity mode setter.
    talkingMode = function(value) Voice.proximity.set(value) end,

    muffling = function(value)
        Config.muffling.enabled = value == true or value == 1
        Voice.state.markDirty()
    end,
}

---Sets one local voice property.
---@param property string
---@param value any
---@return boolean ok false for an unknown property name
exports('setVoiceProperty', function(property, value)
    local setter = properties[property]
    if not setter then
        -- Reported rather than silently ignored: an unknown property is a
        -- typo'd call site, and a silently dropped setVoiceProperty presents as
        -- "the volume slider does nothing".
        print(('[kora_voice] setVoiceProperty: unknown property %s'):format(tostring(property)))
        return false
    end

    setter(value)
    return true
end)

---Reads one local voice property.
---@param property string
---@return any
exports('getVoiceProperty', function(property)
    local data = Voice.state.data

    if property == 'radioVolume' then return data.radioVolume end
    if property == 'callVolume' then return data.callVolume end
    if property == 'micClicks' then return Config.radio.clicks end
    if property == 'submix' then return Config.radio.submix end
    if property == 'muffling' then return Config.muffling.enabled end
    if property == 'talkingMode' then return Voice.state.mode() end
    if property == 'radioChannel' then return data.radio end
    if property == 'callChannel' then return data.call end

    return nil
end)

---Forces a voice-target rebuild now.
---
---For a resource that just moved the player between routing buckets: the grid
---is derived from scope, and scope changes without any voice state changing at
---all, so nothing would mark the target dirty.
---@return boolean
exports('refreshVoiceTargets', function()
    Voice.state.markDirty()
    return Voice.targets.refresh()
end)
