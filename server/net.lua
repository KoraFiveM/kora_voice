-- The client-facing surface. Every one of these is a REQUEST.
--
-- There is no event or callback anywhere in this resource through which a
-- client asserts membership. `Voice.api.request` is the only api function
-- reachable from here, and it is the only one that consults the policy layer;
-- the trusted `assign` path is not referenced in this file at all. If a future
-- change makes it reachable from here, that is the bug -- and
-- test/smoke/authority.lua fails on it.
--
-- Every registration carries a rate limit. A join request is cheap, but it is
-- also the one message a client sends unprompted, and an unlimited one lets a
-- client walk all 1000 channel ids looking for an open frequency.

Voice = Voice or {}

QB.callback.register('qbvoice:requestRadio', function(src, channel)
    local ok, reason = Voice.api.requestClient(src, channel)
    if ok then return true end

    -- Two values, and the client distinguishes them: `false` is a refusal with
    -- a reason worth showing, whereas NO values (a dropped round trip) is not a
    -- refusal at all and must stay silent. Inventing a message for a timeout
    -- would tell the player something the server never said.
    return false, reason
end, { rateLimit = Config.rateLimit.radio })

QB.callback.register('qbvoice:leaveRadio', function(src)
    return Voice.api.requestClient(src, nil)
end, { rateLimit = Config.rateLimit.radio })

-- Calls are NOT client-requestable. A call channel is negotiated by a phone
-- resource that already decided who may ring whom, and it assigns both ends
-- through the trusted server export. A client asking to join a call channel is
-- a client asking to listen to somebody else's phone call, so leaving is the
-- only call operation exposed here -- hanging up on yourself grants no audio.
QB.callback.register('qbvoice:leaveCall', function(src)
    return Voice.api.removeCallClient(src, nil)
end, { rateLimit = Config.rateLimit.call })

---Re-publishes everything one player needs.
---
---Needed because a client's state can be newer than its subscriptions: on
---`ensure qbvoice` against a live server, and on a fresh spawn, the client
---arms its state-bag handlers after the session starts and has missed every
---change that happened before that. It asks; the server re-states.
QB.callback.register('qbvoice:sync', function(src)
    Voice.publish.resync(src)

    return {
        radio = Voice.store.getRadio(src) or false,
        call = Voice.store.getCall(src) or false,
    }
end, { rateLimit = Config.rateLimit.sync })

-- A player who joins mid-session has no memberships, but their state bag has no
-- KEYS either -- and a client reading a missing key cannot tell "never set"
-- from "not replicated yet". Writing the explicit cleared value at load gives
-- every reader a definite answer from the first frame.
AddEventHandler('playerJoining', function()
    Voice.publish.membership(source)
end)
