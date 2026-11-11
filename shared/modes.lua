-- Proximity modes: the ordered whisper/normal/shout set and the arithmetic that
-- walks it.
--
-- This is shared rather than client-only because the SERVER validates a mode
-- index too. A mode arrives from a client in exactly one place (the pma-voice
-- `setTalkingMode` compat path, which historically took a raw integer), and a
-- client handing over index 47 must be clamped by the same code that the cycle
-- key uses -- not by a second, subtly different bounds check.
--
-- Everything here is pure: no natives, no state. That is what lets the smoke
-- tests exercise the cycle without a game.

Voice = Voice or {}
Voice.modes = {}

local M = Voice.modes

---How many modes are configured.
---@return integer
function M.count()
    local modes = Config.proximity.modes
    return type(modes) == 'table' and #modes or 0
end

---The mode at `index`, or nil when out of range.
---
---Returns the CONFIG TABLE ITSELF, not a copy. Callers read `.name`, `.label`
---and `.range`; nothing mutates a mode, and copying one on every voice-target
---rebuild would allocate for no reason.
---@param index integer
---@return { name: string, label: string, range: number }|nil
function M.get(index)
    if type(index) ~= 'number' then return nil end
    return Config.proximity.modes[index]
end

---Forces any value into a valid mode index.
---
---This is the single bounds check in the resource. A nil, a string, a float, a
---negative and a 900 all come out as a real index -- because every caller of
---this either has a key press or an untrusted number, and neither has anywhere
---sensible to report a failure to.
---@param index any
---@return integer
function M.clamp(index)
    local count = M.count()
    if count == 0 then return 1 end

    local n = math.floor(tonumber(index) or 0)
    if n < 1 then return M.defaultIndex() end
    if n > count then return count end
    return n
end

---The configured starting index, itself clamped -- a config typo of
---`default = 9` must not produce a player with no mode at all.
---@return integer
function M.defaultIndex()
    local count = M.count()
    if count == 0 then return 1 end

    local n = math.floor(tonumber(Config.proximity.default) or 1)
    if n < 1 then return 1 end
    if n > count then return count end
    return n
end

---The next index in the cycle.
---
---With `Config.proximity.wrap` the cycle is a ring; without it the ends
---saturate. Either way the result is ALWAYS a valid index into the configured
---set -- the cycle can never step outside it, which is the property that makes
---"a player is on a range nobody configured" impossible.
---@param index integer current index
---@param step integer|nil defaults to 1; negative steps backwards
---@return integer
function M.next(index, step)
    local count = M.count()
    if count == 0 then return 1 end

    local current = M.clamp(index)
    local delta = math.floor(tonumber(step) or 1)

    if Config.proximity.wrap then
        -- Lua's % is already floored (a negative operand yields a non-negative
        -- result for a positive modulus), so a backwards step wraps correctly
        -- without a sign branch.
        return ((current - 1 + delta) % count) + 1
    end

    local target = current + delta
    if target < 1 then return 1 end
    if target > count then return count end
    return target
end

---Index of the mode with `name`, or nil.
---
---Used by the exports, where a caller naming 'whisper' is far more readable
---than one passing 1 -- and survives a server reordering the mode list.
---@param name string
---@return integer|nil
function M.indexOfName(name)
    if type(name) ~= 'string' then return nil end

    for index, mode in ipairs(Config.proximity.modes) do
        if mode.name == name then return index end
    end

    return nil
end

---Resolves either an index or a mode name to a valid index.
---@param value integer|string
---@return integer
function M.resolve(value)
    return M.clamp(M.indexOfName(value) or value)
end

---The talk range in metres for `index`.
---@param index integer
---@return number
function M.rangeOf(index)
    local mode = M.get(M.clamp(index))
    return mode and (tonumber(mode.range) or 0.0) + 0.0 or 0.0
end
