-- The client's local mirror of voice state.
--
-- Everything in here is either PRESENTATION (which mode am I on, am I holding
-- the radio key) or a CACHE OF WHAT THE SERVER PUBLISHED (my channel, my
-- channel's roster). Nothing in this file decides membership, and nothing in it
-- is ever sent to another client -- the setters below are called by the
-- state-bag handler and the roster push in client/sync.lua, never by a keypress.
--
-- The `dirty` flag is the whole reason this is a module rather than a handful of
-- locals: the voice-target rebuild is on a bounded tick, and it needs to know
-- whether anything actually changed since the last one. Without it the rebuild
-- either runs every tick regardless (pointless native churn) or misses a
-- membership change until the next scheduled pass.

Voice = Voice or {}
Voice.state = {}

local State = Voice.state

local data = {
    -- Proximity: an INDEX into Config.proximity.modes, never a range. The range
    -- is derived; storing it would let the two drift when a server edits config.
    mode = 1,

    -- Published membership. `false`, not nil, for "not on a channel" -- the same
    -- cleared value the server writes to the state bag, so a reader never has to
    -- treat the two differently.
    radio = false,
    call = false,

    -- Bucket-filtered member arrays, exactly as the server pushed them. Never
    -- appended to locally: a member this client added itself would be a
    -- self-granted voice target.
    radioMembers = {},
    callMembers = {},

    -- Local input state.
    radioTalking = false,
    megaphone = false,

    -- pma-voice's per-path volume overrides, kept because its call sites set
    -- them. Applied to received audio, so they cannot grant anything.
    radioVolume = 1.0,
    callVolume = 1.0,
}

State.data = data

local dirty = true
local listeners = {}

local function notify(what)
    for _, handler in ipairs(listeners) do
        local ok, err = pcall(handler, what, data)
        if not ok then
            print(('[kora_voice] state listener errored on %s: %s'):format(tostring(what), tostring(err)))
        end
    end
end

---Marks the voice target as needing a rebuild.
function State.markDirty()
    dirty = true
end

---@return boolean
function State.isDirty()
    return dirty
end

---Consumes the dirty flag. Called by the rebuild once it has actually applied
---the natives, so a rebuild that yields and is superseded does not clear a
---change it never saw.
function State.clearDirty()
    dirty = false
end

---Sets the proximity mode. Clamped, so no caller can put this outside the
---configured set.
---@param index integer|string index or mode name
---@return boolean changed, integer index
function State.setMode(index)
    local resolved = Voice.modes.resolve(index)
    if resolved == data.mode then return false, resolved end

    data.mode = resolved
    -- Proximity affects who is in range, so the target list changes with it.
    State.markDirty()
    notify('mode')

    return true, resolved
end

---@return integer
function State.mode()
    return data.mode
end

---Records the server's published radio channel.
---@param channel integer|false
---@return boolean changed
function State.setRadio(channel)
    local value = channel or false
    if value == data.radio then return false end

    data.radio = value
    -- Leaving clears the roster locally too. Waiting for a roster push to do it
    -- would never happen: the push only reaches CURRENT members.
    if not value then data.radioMembers = {} end

    State.markDirty()
    notify('radio')
    return true
end

---@param channel integer|false
---@return boolean changed
function State.setCall(channel)
    local value = channel or false
    if value == data.call then return false end

    data.call = value
    if not value then data.callMembers = {} end

    State.markDirty()
    notify('call')
    return true
end

---Replaces the radio roster with the server's list.
---@param members integer[]
function State.setRadioMembers(members)
    data.radioMembers = type(members) == 'table' and members or {}
    State.markDirty()
    notify('radioMembers')
end

---@param members integer[]
function State.setCallMembers(members)
    data.callMembers = type(members) == 'table' and members or {}
    State.markDirty()
    notify('callMembers')
end

---@param talking boolean
---@return boolean changed
function State.setRadioTalking(talking)
    local value = talking == true
    if value == data.radioTalking then return false end

    data.radioTalking = value
    notify('radioTalking')
    return true
end

---@param active boolean
---@return boolean changed
function State.setMegaphone(active)
    local value = active == true
    if value == data.megaphone then return false end

    data.megaphone = value
    -- The megaphone overrides the talk range, so the in-range set changes.
    State.markDirty()
    notify('megaphone')
    return true
end

---Sets a received-audio volume multiplier.
---@param which 'radio'|'call'
---@param volume number 0.0-1.0; clamped
---@return number applied
function State.setVolume(which, volume)
    local n = tonumber(volume) or 1.0
    -- pma-voice call sites pass 0-100 as often as 0.0-1.0. Anything above 1 is
    -- read as a percentage rather than clamped to 1.0, because clamping would
    -- turn "setRadioVolume(50)" into full volume -- the opposite of the intent.
    if n > 1.0 then n = n / 100.0 end
    if n < 0.0 then n = 0.0 end
    if n > 1.0 then n = 1.0 end

    data[which == 'call' and 'callVolume' or 'radioVolume'] = n
    State.markDirty()
    notify(which .. 'Volume')

    return n
end

---Registers `handler(what, data)`, called whenever any of the above changes.
---`what` is the field name, so a HUD can ignore changes it does not render.
---@param handler fun(what: string, data: table)
function State.onChange(handler)
    listeners[#listeners + 1] = handler
end

---Whether this player is transmitting on the radio right now: holding the key
---AND actually on a channel. Both halves matter -- the key fires whether or not
---the server ever granted a channel.
---@return boolean
function State.isRadioActive()
    return data.radioTalking and data.radio ~= false
end

-- Applied once at load rather than left at 1: Config.proximity.default is the
-- documented starting mode and a player whose first press of the cycle key
-- moved them from an undeclared mode would see the wrong label.
data.mode = Voice.modes.defaultIndex()
