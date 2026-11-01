-- The authoritative membership registry.
--
-- This file is pure bookkeeping: it records who is on which radio channel and
-- which call, and nothing else. It contains NO authority decision and NO
-- publication -- both of those are server/api.lua's job. Keeping them apart is
-- what makes the authority boundary auditable: there is exactly one file that
-- decides, and it is not this one.
--
-- Two independent memberships per player, on purpose. A radio transmission and
-- a phone call are simultaneously live in real play (an officer on the phone to
-- a witness while dispatch talks over the air), so a single "voice channel"
-- field would force one to cancel the other.

Voice = Voice or {}
Voice.store = {}

local S = Voice.store

-- channel -> { [src] = true }. A set rather than an array so leave is O(1);
-- membership churn on a busy dispatch channel is constant.
local radioMembers = {}
local callMembers = {}

-- src -> channel. The reverse index exists because "which channel is this
-- player on" is asked on every disconnect, every publish and every voice-target
-- rebuild, and scanning every channel for it would make the rebuild O(channels).
local radioOf = {}
local callOf = {}

---@param channel integer
---@return table<integer, boolean>
local function radioBucket(channel)
    radioMembers[channel] = radioMembers[channel] or {}
    return radioMembers[channel]
end

---@param channel integer
---@return table<integer, boolean>
local function callBucket(channel)
    callMembers[channel] = callMembers[channel] or {}
    return callMembers[channel]
end

---Records `src` on a radio channel, or removes them when `channel` is nil.
---
---Returns the PREVIOUS channel as well as the new one, because every caller
---needs it: the publisher has to re-push the roster of the channel the player
---just left, and skipping that leaves everyone still on it holding a voice
---target for someone who cannot hear them.
---@param src integer
---@param channel integer|nil
---@return integer|nil previous, integer|nil current
function S.setRadio(src, channel)
    local previous = radioOf[src]
    if previous == channel then return previous, channel end

    if previous then
        local bucket = radioBucket(previous)
        bucket[src] = nil
        -- Drop an emptied channel table rather than leaving it behind. Channel
        -- ids come from phone keypads, so the id space is 1000 wide and a
        -- long-running server would otherwise accumulate a table per channel
        -- anyone ever tuned to.
        if next(bucket) == nil then radioMembers[previous] = nil end
    end

    if channel then radioBucket(channel)[src] = true end
    radioOf[src] = channel

    return previous, channel
end

---@param src integer
---@return integer|nil
function S.getRadio(src)
    return radioOf[src]
end

---Records `src` in a call channel, or removes them when `channel` is nil.
---@param src integer
---@param channel integer|nil
---@return integer|nil previous, integer|nil current
function S.setCall(src, channel)
    local previous = callOf[src]
    if previous == channel then return previous, channel end

    if previous then
        local bucket = callBucket(previous)
        bucket[src] = nil
        if next(bucket) == nil then callMembers[previous] = nil end
    end

    if channel then callBucket(channel)[src] = true end
    callOf[src] = channel

    return previous, channel
end

---@param src integer
---@return integer|nil
function S.getCall(src)
    return callOf[src]
end

---Sorted member list for a radio channel.
---
---Sorted so it is deterministic: this list is compared against the previous one
---to decide whether a roster push is needed, and an unordered pairs() walk
---would produce a different array for the same membership and re-push forever.
---@param channel integer|nil
---@return integer[]
function S.radioMembersOf(channel)
    local out = {}
    if not channel then return out end

    for src in pairs(radioMembers[channel] or {}) do out[#out + 1] = src end
    table.sort(out)
    return out
end

---@param channel integer|nil
---@return integer[]
function S.callMembersOf(channel)
    local out = {}
    if not channel then return out end

    for src in pairs(callMembers[channel] or {}) do out[#out + 1] = src end
    table.sort(out)
    return out
end

---Forgets a player entirely. Called on drop.
---
---Returns both channels the player was on so the caller can re-push those
---rosters. A disconnect that removed the player without re-pushing would leave
---every remaining member transmitting to a source id that no longer exists --
---harmless in Mumble, but it also means the next player to be assigned that
---source id joins the channel silently.
---@param src integer
---@return integer|nil radio, integer|nil call
function S.forget(src)
    local radio = radioOf[src]
    local call = callOf[src]

    S.setRadio(src, nil)
    S.setCall(src, nil)

    return radio, call
end

---Every radio channel with at least one member.
---@return integer[]
function S.activeRadioChannels()
    local out = {}
    for channel in pairs(radioMembers) do out[#out + 1] = channel end
    table.sort(out)
    return out
end

---Wipes the registry. Test-only.
function S._reset()
    radioMembers, callMembers, radioOf, callOf = {}, {}, {}, {}
end
