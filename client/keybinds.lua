-- The three keys. Every one goes through Kora.keybind.add, so all of them appear
-- in FiveM's own key-binding settings and every player can rebind them.
--
-- Note what NONE of these do: none of them change membership. The radio key
-- gates TRANSMISSION on a channel the server already published -- pressing it
-- with no channel does nothing at all. That is not a convenience check; a key
-- that could put its own player on a channel would be the same exploit as a
-- client-side restriction check.

Voice = Voice or {}

Kora.keybind.add({
    name = 'kora_voice_proximity',
    description = 'Voice: cycle talk range (whisper/normal/shout)',
    defaultKey = Config.keybinds.cycleProximity,
    onPressed = function()
        Voice.proximity.cycle(1)
    end,
})

---Plays one of the transmit clicks, if clicks are enabled.
---@param spec { name: string, set: string }
local function click(spec)
    if not Config.radio.clicks or not spec then return end
    Kora.sound.playFrontend(spec.name, spec.set)
end

Kora.keybind.add({
    name = 'kora_voice_radio',
    description = 'Voice: talk on the radio (push to talk)',
    defaultKey = Config.keybinds.radioTalk,

    onPressed = function()
        -- Silent with no channel. A notification here would fire on every
        -- accidental brush of caps lock for the whole civilian population.
        if not Voice.state.data.radio then return end
        if not Voice.state.setRadioTalking(true) then return end

        click(Config.radio.clickOn)

        -- The voice target has to be rebuilt to INCLUDE the roster before the
        -- first word: a rebuild deferred to the bounded tick would drop up to
        -- half a second of speech, which is exactly long enough to lose a
        -- callsign.
        Voice.state.markDirty()
        CreateThread(function() Voice.targets.refresh() end)

        TriggerEvent('kora_voice:client:radioActive', true)
        -- pma-voice's name for the same event, for UIs written against it.
        TriggerEvent('pma-voice:radioActive', true)
    end,

    onReleased = function()
        if not Voice.state.setRadioTalking(false) then return end

        click(Config.radio.clickOff)

        -- Rebuild on release too, and immediately. Leaving the roster in the
        -- target until the next tick means half a second of speech intended for
        -- the room still going out over the air after the key came up.
        Voice.state.markDirty()
        CreateThread(function() Voice.targets.refresh() end)

        TriggerEvent('kora_voice:client:radioActive', false)
        TriggerEvent('pma-voice:radioActive', false)
    end,
})

Kora.keybind.add({
    name = 'kora_voice_megaphone',
    description = 'Voice: megaphone',
    -- Unbound by default: a megaphone belongs to a vehicle or a prop, and a
    -- resource that owns one calls exports.kora_voice:setMegaphone instead. The
    -- bind exists so a server that wants a bare key can set one in config
    -- without editing code.
    defaultKey = Config.keybinds.megaphone,

    onPressed = function()
        if not Voice.state.setMegaphone(true) then return end

        Voice.proximity.apply()
        CreateThread(function() Voice.targets.refresh() end)
        TriggerEvent('kora_voice:client:megaphone', true)
    end,

    onReleased = function()
        if not Voice.state.setMegaphone(false) then return end

        -- Restores the player's own proximity mode, not the default: someone
        -- who was whispering before they picked up a megaphone should be
        -- whispering again after they put it down.
        Voice.proximity.apply()
        CreateThread(function() Voice.targets.refresh() end)
        TriggerEvent('kora_voice:client:megaphone', false)
    end,
})
