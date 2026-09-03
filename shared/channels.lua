-- Channel identifiers: normalisation and the restriction LOOKUP (not the
-- restriction DECISION).
--
-- The split matters. Everything here is a pure function of the config and an
-- untrusted value, so it is safe in either realm and safe in a test. Whether a
-- particular PLAYER may join a restricted channel is a server-only question --
-- it needs their job, their duty state and the policy hooks -- and lives in
-- server/policy.lua. Shipping the decision to the client would ship the
-- restriction table with it, which is a map of every channel worth listening to.

Voice = Voice or {}
Voice.channels = {}

local C = Voice.channels

---Turns an untrusted value into a valid radio channel id, or nil.
---
---nil means "no channel" and is the normal way to say "leave". That collapsing
---of nil/false/0/'' into one answer is deliberate: every phone resource, radio
---item and admin command spells "off" differently, and each of those spellings
---reaching a different code path is how a player ends up stuck on a channel
---they cannot leave.
---@param value any
---@param bounds { minChannel: integer, maxChannel: integer }|nil defaults to Config.radio
---@return integer|nil
function C.normalise(value, bounds)
    bounds = bounds or Config.radio

    if value == nil or value == false or value == '' then return nil end

    local n = tonumber(value)
    if not n or n ~= n then return nil end -- n ~= n catches NaN, which tonumber('nan') yields

    n = math.floor(n)
    if n < bounds.minChannel or n > bounds.maxChannel then return nil end

    return n
end

---Same, for a call channel -- a separate id space with a much larger ceiling,
---because phone resources use the phone NUMBER as the channel.
---@param value any
---@return integer|nil
function C.normaliseCall(value)
    return C.normalise(value, Config.calls)
end

---The restriction record for a radio channel, or nil when the channel is open.
---@param channel integer
---@return { label: string|nil, jobs: string[]|nil, jobTypes: string[]|nil, onDuty: boolean|nil }|nil
function C.restriction(channel)
    if type(channel) ~= 'number' then return nil end
    return Config.radio.restricted[channel]
end

---Whether a radio channel is restricted at all.
---@param channel integer
---@return boolean
function C.isRestricted(channel)
    return C.restriction(channel) ~= nil
end

---Whether a job/duty pair satisfies a restriction record.
---
---Pure, so the policy layer can be tested without a qbcore. An EMPTY
---restriction record (`{}` -- no jobs, no jobTypes) satisfies nobody: a server
---that lists a channel as restricted and then forgets to say who may use it
---means "locked", not "open to all". The opposite default would silently
---un-restrict a channel on a config typo.
---@param record table
---@param job { name: string|nil, type: string|nil, onduty: boolean|nil }|nil
---@return boolean
function C.jobSatisfies(record, job)
    if type(record) ~= 'table' then return true end
    if type(job) ~= 'table' then return false end

    if record.onDuty and not job.onduty then return false end

    for _, name in ipairs(record.jobs or {}) do
        if name == job.name then return true end
    end

    for _, jobType in ipairs(record.jobTypes or {}) do
        if jobType == job.type then return true end
    end

    return false
end
