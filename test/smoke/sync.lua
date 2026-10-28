-- Inbound sync. Two timing rules are the whole suite, and both have cost a
-- debugging session on this server before:
--
--   * a bag handler registered at chunk load binds to `player:-1` and never
--     fires, because GetPlayerServerId(PlayerId()) is -1 until the session is
--     live and AddStateBagChangeHandler resolves the bag NAME once.
--
--   * a bag handler runs BEFORE the new value is committed to the local store,
--     so re-reading the bag inside it yields the PREVIOUS value for the key
--     that just changed. The mock fires handlers without committing anything,
--     which is exactly that shape: a handler that re-read would see nil.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local net = mocks.install()
dofile('config.lua')
dofile('shared/modes.lua')
dofile('shared/channels.lua')
dofile('client/state.lua')
dofile('client/proximity.lua')
dofile('client/submix.lua')
dofile('client/targets.lua')

-- Scripted BEFORE client/sync.lua loads, because its catch-up resync runs
-- during the load: the client asks the server to re-state everything that
-- changed before its subscriptions existed.
net.setCallbackResponse('qbvoice:sync', { radio = 5, call = false })

dofile('client/sync.lua')
dofile('client/exports.lua')

local BAG = 'player:1'

h.test('the bag handlers are bound to a real player bag, not to player:-1', function()
    h.assertTrue(#net.stateListeners >= 2, 'both keys are subscribed')

    for _, listener in ipairs(net.stateListeners) do
        h.assertEqual(listener.bagName, BAG, 'bound to this players bag')
        h.assertFalse(listener.bagName == 'player:-1',
            'a player:-1 subscription never fires and the radio silently never works')
    end
end)

h.test('the catch-up resync runs at load, after the handlers are armed', function()
    -- This is what makes `ensure kora_voice` against a live, already-logged-in
    -- server work. Asking first and arming second would race the answer.
    h.assertEqual(Voice.state.data.radio, 5, 'the published channel was applied')
end)

h.test('a published channel is applied from the handlers value argument', function()
    net.fireBagChange(BAG, Config.state.radio, 7)

    -- The mock never commits to a store, so a handler that re-read the bag
    -- instead of using `value` would apply nil and this would be false.
    h.assertEqual(Voice.state.data.radio, 7, 'the value argument was used')
    h.assertEqual(exports.kora_voice:getRadioChannel(), 7, 'and is what the export reports')
end)

h.test('an explicit false clears the channel', function()
    net.fireBagChange(BAG, Config.state.radio, 7)
    net.fireBagChange(BAG, Config.state.radio, false)

    h.assertEqual(Voice.state.data.radio, false, 'cleared')
end)

h.test('a nil is treated exactly as false', function()
    net.fireBagChange(BAG, Config.state.radio, 7)
    net.fireBagChange(BAG, Config.state.radio, nil)

    -- The server never writes nil, but a key that was never set reads as one --
    -- so every reader has to treat the two alike.
    h.assertEqual(Voice.state.data.radio, false, 'nil and false mean the same thing')
end)

h.test('radio and call keys are independent subscriptions', function()
    net.fireBagChange(BAG, Config.state.radio, 7)
    net.fireBagChange(BAG, Config.state.call, 5551234)

    h.assertEqual(Voice.state.data.radio, 7, 'the radio survived the call')
    h.assertEqual(Voice.state.data.call, 5551234, 'and the call is live alongside it')

    net.fireBagChange(BAG, Config.state.call, false)
    h.assertEqual(Voice.state.data.radio, 7, 'hanging up does not leave the radio')
end)

h.test('a channel change is announced under both event names', function()
    net.fireBagChange(BAG, Config.state.radio, false)
    net.clear()
    net.fireBagChange(BAG, Config.state.radio, 9)

    local names = {}
    for _, event in ipairs(net.localEvents) do names[event.name] = event.args[1] end

    h.assertEqual(names['qbvoice:client:radioChanged'], 9, 'the qbvoice event, for new code')
    h.assertEqual(names['pma-voice:setRadioChannel'], 9,
        'and pma-voices, so a radio UI written against it does not show a stale channel')
end)

h.test('the leave event carries 0 for pma-voice and false for qbvoice', function()
    net.fireBagChange(BAG, Config.state.radio, 9)
    net.clear()
    net.fireBagChange(BAG, Config.state.radio, false)

    local names = {}
    for _, event in ipairs(net.localEvents) do names[event.name] = event.args[1] end

    h.assertEqual(names['qbvoice:client:radioChanged'], false, 'false for qbvoice consumers')
    -- pma-voice used 0 for "no channel", and a UI written against it compares
    -- against 0 rather than against false.
    h.assertEqual(names['pma-voice:setRadioChannel'], 0, '0 for pma-voice consumers')
end)

h.test('a roster is taken verbatim, never merged with the previous one', function()
    net.deliverPush('qbvoice:radio:roster', { channel = 3, members = { 1, 2, 3 } })
    h.assertEqual(#Voice.state.data.radioMembers, 3, 'the first roster applied')

    net.deliverPush('qbvoice:radio:roster', { channel = 3, members = { 1 } })

    -- A merge would mean members accumulated across pushes, and a member who
    -- was never removed is a voice target for a channel the player has left.
    h.assertEqual(#Voice.state.data.radioMembers, 1, 'the second replaced it entirely')
end)

h.test('the roster push carries the channel and applies it first', function()
    net.fireBagChange(BAG, Config.state.radio, false)
    net.deliverPush('qbvoice:radio:roster', { channel = 4, members = { 1, 2 } })

    -- On a resource restart the push can arrive before the bag replicates.
    -- Applying the members first would have them dropped by the channel clear.
    h.assertEqual(Voice.state.data.radio, 4, 'the channel came from the push')
    h.assertEqual(#Voice.state.data.radioMembers, 2, 'and the members survived')
end)

h.test('a cleared roster push drops the membership', function()
    net.deliverPush('qbvoice:radio:roster', { channel = 4, members = { 1, 2 } })
    net.deliverPush('qbvoice:radio:roster', { channel = false, members = {} })

    h.assertEqual(Voice.state.data.radio, false, 'the leaver was told, since no roster reaches them')
    h.assertEqual(#Voice.state.data.radioMembers, 0, 'and their targets are gone')
end)

h.test('garbage in a roster is dropped rather than becoming a voice target', function()
    net.deliverPush('qbvoice:radio:roster', { channel = 4, members = { 1, 'police', -3, 0, 6 } })

    h.assertEqual(#Voice.state.data.radioMembers, 2, 'only the two real server ids survived')
end)

h.test('a membership change requests an immediate voice-target rebuild', function()
    net.clear()
    net.fireBagChange(BAG, Config.state.radio, 11)

    -- Waiting up to Config.mumble.refreshInterval before you can be heard
    -- reads as the radio being broken.
    h.assertTrue(#net.nativesNamed('MumbleClearVoiceTarget') > 0, 'the target was rebuilt at once')
end)

h.test('the refresh tick is started once the session is live', function()
    h.assertEqual(#net.intervals, 1, 'exactly one timer, from client/sync.lua')
    h.assertEqual(net.intervals[1].ms, Config.mumble.refreshInterval, 'at the configured interval')
end)

h.report('sync')
