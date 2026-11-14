-- Proximity: turning a mode index into an actual audible range.
--
-- Four natives are set, not one, and each is guarded by a type check. FiveM has
-- accumulated several generations of "how far can this player be heard" and
-- which ones a given build honours varies:
--
--   MumbleSetAudioInputDistance  / MumbleSetAudioOutputDistance -- current
--   MumbleSetTalkerProximity                                    -- Mumble-era
--   NetworkSetTalkerProximity                                   -- GTA-era
--
-- Setting all of them costs four native calls on a keypress and makes the
-- resource behave the same on every build. Guarding each one means a build
-- missing one of them degrades to "the others still apply", not to an error
-- that leaves the player on whatever range they had before -- which would be
-- silent and would present as "the cycle key does nothing".

Voice = Voice or {}
Voice.proximity = {}

local Prox = Voice.proximity

---@param native function|nil
---@param range number
local function apply(native, range)
    if type(native) ~= 'function' then return end
    pcall(native, range)
end

---The range this player should currently be heard at.
---
---The megaphone WINS over the proximity mode: it is not a fourth mode (it also
---changes the submix, which a mode cannot), and a player on a megaphone whose
---range was still whisper would be inaudible while visibly using one.
---@return number
function Prox.currentRange()
    if Voice.state.data.megaphone then
        return (tonumber(Config.submix.megaphone.range) or 0.0) + 0.0
    end

    return Voice.modes.rangeOf(Voice.state.mode())
end

---Pushes the current range into every voice-distance native available.
---@return number range
function Prox.apply()
    local range = Prox.currentRange()

    apply(MumbleSetAudioInputDistance, range)
    apply(MumbleSetAudioOutputDistance, range)
    apply(MumbleSetTalkerProximity, range)
    apply(NetworkSetTalkerProximity, range)

    return range
end

---Steps the mode and applies it.
---
---`Voice.modes.next` guarantees the result is inside the configured set, so
---this function cannot produce an unconfigured range no matter how many times
---it is called or with what step.
---@param step integer|nil defaults to 1
---@return integer index, number range
function Prox.cycle(step)
    local index = Voice.modes.next(Voice.state.mode(), step)
    Voice.state.setMode(index)

    local range = Prox.apply()

    if Config.proximity.notify then
        local mode = Voice.modes.get(index)
        Kora.notify.send({
            title = Kora.lang('title.voice'),
            message = Kora.lang('notify.proximity_mode', mode and mode.label or '?', range),
            type = 'info',
        })
    end

    return index, range
end

---Sets a specific mode by index or name and applies it.
---@param value integer|string
---@return integer index, number range
function Prox.set(value)
    Voice.state.setMode(value)
    return Voice.state.mode(), Prox.apply()
end
