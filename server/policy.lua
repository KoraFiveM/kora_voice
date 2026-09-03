-- Who may join which radio channel. The authority decision, server-only.
--
-- THE RULE THIS FILE EXISTS TO ENFORCE: a client asks; the server answers. No
-- part of this evaluation, and no part of Config.radio.restricted, is ever sent
-- to a client. A client that can evaluate its own eligibility is a client that
-- can listen to any channel on the server, because the only thing standing
-- between a player and a channel's audio is the voice target the server's
-- published roster builds.
--
-- Three ways a channel opens up, evaluated in this order:
--   1. a POLICY HOOK explicitly allows (a job resource's own rule)
--   2. an explicit per-player GRANT (a radio item, an on-duty hook)
--   3. the channel is not in Config.radio.restricted at all
-- and a hook may also explicitly refuse an otherwise-open channel.

Voice = Voice or {}
Voice.policy = {}

local P = Voice.policy

-- Ordered list of { resource, fn }. Order is registration order, and the first
-- hook to return a definite answer wins -- so a job resource that starts later
-- cannot silently override an earlier one's refusal by accident.
local hooks = {}

-- src -> { [channel] = true }. Grants are DATA, not a funcref, which is the
-- recommended integration: a funcref crossing the exports boundary is only
-- callable while the resource that created it is running, and a job resource
-- restarting would leave a dead hook refusing every request.
local grants = {}

---Registers a policy hook.
---
---`fn(src, channel)` returns:
---  * `false, reason` -- refuse, and tell the player `reason`
---  * `true`          -- allow, overriding Config.radio.restricted
---  * nil             -- abstain, fall through to grants and config
---
---Abstain is the correct default for a hook that only cares about its own
---frequencies. A hook that returned `false` for everything outside its range
---would veto every other job's channels.
---@param fn fun(src: integer, channel: integer): boolean|nil, string|nil
---@return integer handle
function P.addHook(fn)
    assert(type(fn) == 'function' or (type(fn) == 'table' and getmetatable(fn) and getmetatable(fn).__call),
        'qbvoice: a radio policy hook must be callable')

    hooks[#hooks + 1] = { resource = GetInvokingResource and GetInvokingResource() or nil, fn = fn }
    return #hooks
end

---Removes a hook by handle. Returns whether it was live.
---@param handle integer
---@return boolean
function P.removeHook(handle)
    if not hooks[handle] then return false end
    -- Blanked rather than table.remove'd: removing would renumber every later
    -- handle, and a job resource holding handle 3 would then be able to remove
    -- somebody else's hook.
    hooks[handle] = false
    return true
end

---Grants `src` a set of channels they may join regardless of the restriction
---table. Replaces any previous grant for that player.
---@param src integer
---@param channels integer[]|integer|nil nil or an empty list revokes
---@return integer count
function P.grant(src, channels)
    if type(channels) == 'number' then channels = { channels } end
    if type(channels) ~= 'table' then
        grants[src] = nil
        return 0
    end

    local set, count = {}, 0
    for _, value in ipairs(channels) do
        local channel = Voice.channels.normalise(value)
        if channel and not set[channel] then
            set[channel] = true
            count = count + 1
        end
    end

    grants[src] = count > 0 and set or nil
    return count
end

---@param src integer
---@return integer[]
function P.grantsOf(src)
    local out = {}
    for channel in pairs(grants[src] or {}) do out[#out + 1] = channel end
    table.sort(out)
    return out
end

---Drops a player's grants. Called on disconnect -- source ids are reused, and a
---leftover grant would hand the next player to occupy that id the tac channel.
---@param src integer
function P.forget(src)
    grants[src] = nil
end

---Reads a player's job through qbcore, or nil when qbcore is unavailable.
---
---pcall'd because the restriction check must not be the thing that takes the
---radio down when qbcore is restarting. A failed read yields nil, which
---`Voice.channels.jobSatisfies` treats as "satisfies nothing" -- so the failure
---mode is a REFUSED restricted channel, never an allowed one.
---@param src integer
---@return { name: string|nil, type: string|nil, onduty: boolean|nil }|nil
local function jobOf(src)
    local ok, job = pcall(function() return exports.qbcore:getJob(src) end)
    if not ok or type(job) ~= 'table' then return nil end
    return job
end

---Decides whether `src` may join `channel`.
---
---`channel` must already be normalised -- this function does not bounds-check,
---because a caller that skipped normalisation has a bug that a silent clamp
---here would hide.
---@param src integer
---@param channel integer
---@return boolean allowed, string|nil reason
function P.canJoin(src, channel)
    for _, entry in ipairs(hooks) do
        if entry then
            local ok, allowed, reason = pcall(entry.fn, src, channel)

            -- A hook that ERRORS abstains. It must not be able to lock every
            -- player off the radio by throwing: the erroring resource is the
            -- broken one, and taking voice down with it turns one bug into a
            -- server-wide outage.
            if not ok then
                print(('[qbvoice] radio policy hook from %s errored: %s')
                    :format(tostring(entry.resource), tostring(allowed)))
            elseif allowed == false then
                return false, type(reason) == 'string' and reason or Config.radio.refusedMessage
            elseif allowed == true then
                return true
            end
        end
    end

    local granted = grants[src]
    if granted and granted[channel] then return true end

    local record = Voice.channels.restriction(channel)
    if not record then return true end

    if Voice.channels.jobSatisfies(record, jobOf(src)) then return true end

    return false, Config.radio.refusedMessage
end

---Test/introspection helper: how many live hooks are registered.
---@return integer
function P.hookCount()
    local count = 0
    for _, entry in ipairs(hooks) do
        if entry then count = count + 1 end
    end
    return count
end

---Wipes hooks and grants. Test-only.
function P._reset()
    hooks, grants = {}, {}
end
