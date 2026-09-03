-- Publication: membership is PUBLISHED by the server, never accepted from a
-- client -- and the two ways it leaves the server carry different things on
-- purpose. The state bag says "what channel is this player on" to anybody; the
-- roster push says "whose audio may I receive" and goes only to members.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local net = mocks.install()
dofile('config.lua')
dofile('shared/channels.lua')
dofile('server/store.lua')
dofile('server/policy.lua')
dofile('server/publish.lua')
dofile('server/api.lua')
dofile('server/net.lua')

local A, B, C = 1, 2, 3

local function reset()
    Voice.store._reset()
    Voice.policy._reset()
    net.clear()
    net.setBucket(A, 0); net.setBucket(B, 0); net.setBucket(C, 0)
end

local function lastWrite(src, key)
    local writes = net.writesFor(src, key)
    return writes[#writes]
end

h.test('joining publishes the channel onto the players state bag', function()
    reset()
    Voice.api.assign(A, 7)

    local write = lastWrite(A, Config.state.radio)
    h.assertTrue(write ~= nil, 'a bag write happened')
    h.assertEqual(write.value, 7, 'carrying the channel the server decided')
    h.assertEqual(write.replicated, Config.state.replicate, 'replicated per config')
end)

h.test('leaving clears the key with an explicit false, never a nil', function()
    reset()
    Voice.api.assign(A, 7)
    net.clear()
    Voice.api.assign(A, nil)

    local write = lastWrite(A, Config.state.radio)
    h.assertTrue(write ~= nil, 'the clear was written')
    h.assertFalse(write.wasNil,
        'a nil write is a key DELETION and does not replicate like a value change -- clients would keep reading 7 forever')
    h.assertEqual(write.value, false, 'the cleared value is an explicit false')
end)

h.test('both keys are always defined, so a reader never sees a missing key', function()
    reset()
    Voice.publish.membership(A)

    -- A client cannot tell "never set" from "not replicated yet". Writing the
    -- explicit cleared value gives every reader a definite answer from the
    -- first frame.
    h.assertEqual(lastWrite(A, Config.state.radio).value, false, 'radio defined')
    h.assertEqual(lastWrite(A, Config.state.call).value, false, 'call defined')
end)

h.test('a player joining gets their keys initialised', function()
    reset()
    _G.source = C
    TriggerEvent('playerJoining')

    h.assertTrue(lastWrite(C, Config.state.radio) ~= nil, 'the join handler published the cleared values')
end)

h.test('the roster reaches members and nobody else', function()
    reset()
    Voice.api.assign(A, 7)
    Voice.api.assign(B, 7)
    net.clear()
    Voice.api.assign(C, 8)

    -- C joining channel 8 must not tell channel 7 anything: the roster is what
    -- becomes a voice target, so it is never broadcast.
    h.assertEqual(#net.pushesTo(A), 0, 'A heard nothing about another channel')
    h.assertEqual(#net.pushesTo(B), 0, 'nor did B')
    h.assertTrue(#net.pushesTo(C) > 0, 'C got their own roster')
end)

h.test('every member of a channel is re-pushed when one joins', function()
    reset()
    Voice.api.assign(A, 7)
    net.clear()
    Voice.api.assign(B, 7)

    local toA = net.pushesTo(A)
    h.assertEqual(#toA, 1, 'A was told the roster changed')
    h.assertEqual(#toA[1].payload.members, 2, 'and it now has two members')
end)

h.test('the channel just LEFT is re-pushed too', function()
    reset()
    Voice.api.assign(A, 7)
    Voice.api.assign(B, 7)
    net.clear()

    -- Without this, A keeps a voice target for B forever: a one-way radio that
    -- looks like a network fault.
    Voice.api.assign(B, nil)

    local toA = net.pushesTo(A)
    h.assertEqual(#toA, 1, 'A was re-pushed')
    h.assertEqual(#toA[1].payload.members, 1, 'B is gone from the roster')
end)

h.test('the leaver is told separately, since they are in no roster', function()
    reset()
    Voice.api.assign(A, 7)
    net.clear()
    Voice.api.assign(A, nil)

    local toA = net.pushesTo(A)
    h.assertEqual(#toA, 1, 'the leaver got exactly one push')
    h.assertEqual(toA[1].payload.channel, false, 'saying the channel is cleared -- false, not omitted')
    h.assertEqual(#toA[1].payload.members, 0, 'with an empty roster')
end)

h.test('a disconnect re-pushes the rosters the player was in', function()
    reset()
    Voice.api.assign(A, 7)
    Voice.api.assign(B, 7)
    net.clear()

    _G.source = B
    TriggerEvent('playerDropped')

    local toA = net.pushesTo(A)
    h.assertEqual(#toA, 1, 'A was told')
    h.assertEqual(#toA[1].payload.members, 1, 'and B is gone -- source ids get reused')
end)

h.test('the roster is filtered by routing bucket, on the server', function()
    reset()
    -- Two players in different routing buckets are in different worlds, and
    -- Mumble has no concept of a bucket: hand a client a member from another
    -- world and the audio flows.
    net.setBucket(B, 12)

    Voice.api.assign(A, 7)
    Voice.api.assign(B, 7)
    net.clear()
    Voice.api.assign(C, 7)

    local toA = net.pushesTo(A)[1]
    local toB = net.pushesTo(B)[1]

    h.assertEqual(#toA.payload.members, 2, 'A sees only the two players in bucket 0')
    h.assertEqual(#toB.payload.members, 1, 'B, alone in bucket 12, sees only themselves')
end)

h.test('bucket filtering can be turned off for a cross-instance channel', function()
    reset()
    Config.buckets.enforce = false
    net.setBucket(B, 12)

    Voice.api.assign(A, 7)
    Voice.api.assign(B, 7)

    local toA = net.pushesTo(A)
    h.assertEqual(#toA[#toA].payload.members, 2, 'with enforcement off, buckets are ignored')

    Config.buckets.enforce = true
end)

h.test('a resync re-states everything one player needs', function()
    reset()
    Voice.api.assign(A, 7)
    Voice.api.assignCall(A, 5551234)
    net.clear()

    -- This is what makes `ensure qbvoice` against a live server work: the
    -- client arms its subscriptions after the session starts and has missed
    -- every change before that.
    local published = net.invokeCallback('qbvoice:sync', A)

    h.assertEqual(published.radio, 7, 'the answer carries the radio channel')
    h.assertEqual(published.call, 5551234, 'and the call channel')
    h.assertTrue(#net.pushesTo(A) >= 2, 'and both rosters were re-pushed')
    h.assertTrue(lastWrite(A, Config.state.radio) ~= nil, 'and the bag re-written')
end)

h.test('a no-op assignment publishes nothing', function()
    reset()
    Voice.api.assign(A, 7)
    net.clear()
    Voice.api.assign(A, 7)

    -- Re-publishing an unchanged value would re-push the whole channel's roster
    -- every time a radio UI re-asserted the channel it was already on.
    h.assertEqual(#net.bagWrites, 0, 'no bag write')
    h.assertEqual(#net.pushes, 0, 'no roster push')
end)

h.test('membership changes announce themselves to other server resources', function()
    reset()
    local seen = {}
    AddEventHandler('qbvoice:server:radioChanged', function(src, channel, previous)
        seen[#seen + 1] = { src = src, channel = channel, previous = previous }
    end)

    Voice.api.assign(A, 7)
    Voice.api.assign(A, nil)

    h.assertEqual(#seen, 2, 'both transitions were announced')
    h.assertEqual(seen[1].channel, 7, 'the join carries the new channel')
    h.assertEqual(seen[2].channel, false, 'the leave carries false, not nil, so it survives an event boundary')
    h.assertEqual(seen[2].previous, 7, 'and names the channel left')
end)

h.report('publish')
