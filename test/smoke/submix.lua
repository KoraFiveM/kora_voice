-- Submixes: the radio and megaphone effect chains, and the wiring each one
-- needs before a speaker can be routed through it.
--
-- This suite loads client/submix.lua on its own so the natives it records are
-- only ever its own. It also exists as the guard on the backtick rule: a CFX
-- backtick hash literal is not valid Lua 5.4, so if one ever appears in that
-- file this suite dies during the dofile and prints a header with no summary --
-- which test/run.sh's header-vs-summary count reports.
--
-- ORDER MATTERS IN THIS FILE. The last two tests each install a FRESH mock
-- recorder to get unambiguous call counts, which replaces the natives the
-- earlier tests' `net` was recording into. Anything reading `net` has to come
-- before them.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local net = mocks.install()
dofile('config.lua')
dofile('shared/modes.lua')
dofile('client/state.lua')
dofile('client/submix.lua')

h.test('both submixes are created on the first ensure', function()
    local radio, megaphone = Voice.submix.ensure()

    h.assertTrue(radio ~= nil, 'the radio submix was created')
    h.assertTrue(megaphone ~= nil, 'so was the megaphone')
    h.assertTrue(radio ~= megaphone,
        'distinct submixes -- a player on the radio and a player on a megaphone must not sound the same')
    h.assertEqual(#net.nativesNamed('CreateAudioSubmix'), 2, 'exactly two')
end)

h.test('ensure is idempotent', function()
    net.clear()
    Voice.submix.ensure()
    Voice.submix.ensure()

    -- CreateAudioSubmix claims a real slot. Calling it per transmission
    -- exhausts the pool over a session and the symptom is "voice randomly
    -- stopped working", which is near-impossible to trace.
    h.assertEqual(#net.nativesNamed('CreateAudioSubmix'), 0, 'no second allocation')
end)

h.test('routing a speaker in and back out uses -1 to clear', function()
    net.clear()

    h.assertTrue(Voice.submix.applyTo(7, 'radio'), 'routed')
    h.assertEqual(net.nativesNamed('MumbleSetSubmixForServerId')[1].args[2], Voice.submix.ids.radio,
        'to the radio submix')

    net.clear()
    h.assertTrue(Voice.submix.clearFor(7), 'cleared')
    h.assertEqual(net.nativesNamed('MumbleSetSubmixForServerId')[1].args[2], -1,
        'a speaker whose submix was never cleared keeps the effect for the whole session')
end)

h.test('an unknown submix kind routes nobody', function()
    net.clear()
    h.assertFalse(Voice.submix.applyTo(7, 'telephone'), 'refused')
    h.assertEqual(#net.nativesNamed('MumbleSetSubmixForServerId'), 0, 'and no native was called')
end)

h.test('each submix seeds the default radio curve and is routed to an output', function()
    -- A clean recorder, so the counts below are unambiguous: the tests above
    -- have already consumed the load-time log.
    local fresh = dofile('test/mocks.lua').install()
    dofile('config.lua')
    dofile('shared/modes.lua')
    dofile('client/state.lua')
    dofile('client/submix.lua')
    Voice.submix.ensure()

    h.assertEqual(#fresh.nativesNamed('SetAudioSubmixEffectRadioFx'), 2, 'the effect is installed on both')
    -- Without the 'default' int the named float parameters apply on top of an
    -- unset chain and the result is nearly inaudible.
    h.assertEqual(#fresh.nativesNamed('SetAudioSubmixEffectParamInt'), 2, 'and seeded on both')
    h.assertTrue(#fresh.nativesNamed('SetAudioSubmixEffectParamFloat') >= 10, 'and every named float applied')
    h.assertEqual(#fresh.nativesNamed('AddAudioSubmixOutput'), 2,
        'both are routed to an output -- without one the chain discards the audio and the speaker goes silent')
end)

h.test('a full submix pool degrades to unprocessed audio, not to silence', function()
    local fresh = dofile('test/mocks.lua').install()
    -- CreateAudioSubmix returns -1 when the pool is full.
    _G.CreateAudioSubmix = function() return -1 end

    dofile('config.lua')
    dofile('shared/modes.lua')
    dofile('client/state.lua')
    dofile('client/submix.lua')

    local radio = Voice.submix.ensure()
    h.assertTrue(radio == nil, 'no submix id was handed out')
    -- Carrying on would apply every parameter to submix -1 and then route
    -- speakers into it, which silences them -- far worse than no effect at all.
    h.assertEqual(#fresh.nativesNamed('SetAudioSubmixEffectRadioFx'), 0, 'and nothing was configured on it')
    h.assertFalse(Voice.submix.applyTo(7, 'radio'), 'and nobody is routed anywhere')
end)

h.report('submix')
