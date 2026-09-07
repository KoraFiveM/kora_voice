-- Publication. The only place membership leaves the server.
--
-- Two channels out, and they answer two different questions:
--
--   * the STATE BAG (`qbvoice:radio` / `qbvoice:call`) answers "what channel is
--     this player on" for anybody who wants to know -- a HUD, a phone UI, a job
--     script. It is a fact about a player, replicated like any other.
--
--   * the ROSTER PUSH answers "whose audio may I receive", and is sent only to
--     the members of that channel. It is what the client turns into a Mumble
--     voice target, so it is the thing that actually grants listening -- and it
--     is therefore never broadcast.
--
-- The roster is filtered by ROUTING BUCKET here, on the server, not on the
-- client. Mumble has no concept of a bucket: if a client is handed a member in
-- another world and adds them as a voice target, the audio flows. Filtering
-- client-side would mean trusting the client with the unfiltered list, which is
-- the same mistake as letting it evaluate restrictions.

Voice = Voice or {}
Voice.publish = {}

local Pub = Voice.publish

---The routing bucket a player is in, or 0 when the native is unavailable.
---@param src integer
---@return integer
local function bucketOf(src)
    if not Config.buckets.enforce then return 0 end
    if type(GetPlayerRoutingBucket) ~= 'function' then return 0 end

    local ok, bucket = pcall(GetPlayerRoutingBucket, src)
    return (ok and tonumber(bucket)) or 0
end

---Writes one of this resource's keys onto a player's state bag.
---
---`value` of nil is turned into an explicit `false`. That conversion is the
---whole reason this helper exists: a nil write is a key DELETION, and a
---deletion does not replicate to clients the way a value change does -- every
---client would keep reading the last channel forever and keep showing a player
---on a channel they had left. Every reader in this resource treats nil and
---false alike, so `false` is a safe cleared value and a missing key is not.
---@param src integer
---@param key string
---@param value integer|nil
local function writeBag(src, key, value)
    local player = Player(src)
    if not player or not player.state then return end

    -- Spelled as an if, NOT as `value == nil and false or value`: that idiom
    -- evaluates to `false or nil` and hands back the nil it was meant to
    -- replace, which is the exact deletion this helper exists to prevent. It
    -- reads correct and is silently wrong.
    if value == nil then value = false end

    player.state:set(key, value, Config.state.replicate)
end

---Publishes a player's own memberships onto their state bag.
---@param src integer
function Pub.membership(src)
    writeBag(src, Config.state.radio, Voice.store.getRadio(src))
    writeBag(src, Config.state.call, Voice.store.getCall(src))
end

---Groups a member list by routing bucket.
---@param members integer[]
---@return table<integer, integer[]>
local function byBucket(members)
    local groups = {}

    for _, src in ipairs(members) do
        local bucket = bucketOf(src)
        groups[bucket] = groups[bucket] or {}
        groups[bucket][#groups[bucket] + 1] = src
    end

    return groups
end

---Pushes a channel's roster to its members.
---
---Each member receives only the members sharing their own bucket. The receiver
---is left IN their own list on purpose: the client needs the count to render
---"3 on channel", and it skips itself when building voice targets anyway --
---removing it here would cost a per-recipient table copy for nothing.
---@param kind 'radio'|'call'
---@param channel integer|nil no-op for nil, since an empty channel has no members left to tell
function Pub.roster(kind, channel)
    if not channel then return end

    local members = kind == 'call'
        and Voice.store.callMembersOf(channel)
        or Voice.store.radioMembersOf(channel)

    local groups = byBucket(members)

    for _, src in ipairs(members) do
        QB.events.push(src, ('qbvoice:%s:roster'):format(kind), {
            channel = channel,
            members = groups[bucketOf(src)] or { src },
        })
    end
end

---Tells one player their channel membership was cleared.
---
---Needed as its own push because `Pub.roster` only reaches CURRENT members: a
---player who just left is, by definition, not in the roster any more and would
---otherwise never be told to drop its voice targets. Sends `channel = false`
---rather than omitting the field, for the same reason the state bag does.
---@param src integer
---@param kind 'radio'|'call'
function Pub.cleared(src, kind)
    QB.events.push(src, ('qbvoice:%s:roster'):format(kind), {
        channel = false,
        members = {},
    })
end

---Re-pushes everything one player needs after a resource restart or a fresh
---join: their own memberships plus the roster of whatever they are on.
---@param src integer
function Pub.resync(src)
    Pub.membership(src)

    local radio = Voice.store.getRadio(src)
    if radio then Pub.roster('radio', radio) else Pub.cleared(src, 'radio') end

    local call = Voice.store.getCall(src)
    if call then Pub.roster('call', call) else Pub.cleared(src, 'call') end
end
