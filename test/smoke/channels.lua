-- Channel normalisation. Every phone resource, radio item and admin command
-- spells "off" differently, and each spelling reaching a different code path is
-- how a player ends up on a channel they cannot leave.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); mocks.install()
dofile('config.lua')
dofile('shared/channels.lua')

h.test('every spelling of "no channel" normalises to nil', function()
    for _, value in ipairs({ 0, -1, '', '0' }) do
        h.assertEqual(Voice.channels.normalise(value), nil,
            ('%s should mean "no channel"'):format(tostring(value)))
    end

    h.assertEqual(Voice.channels.normalise(nil), nil, 'nil means no channel')
    h.assertEqual(Voice.channels.normalise(false), nil, 'false means no channel')
end)

h.test('a valid channel survives every input form', function()
    h.assertEqual(Voice.channels.normalise(7), 7, 'a number')
    h.assertEqual(Voice.channels.normalise('7'), 7, 'a numeric string, as a keypad sends')
    h.assertEqual(Voice.channels.normalise(7.9), 7, 'a float is floored, not rounded')
end)

h.test('out-of-range and non-numeric values are refused', function()
    h.assertEqual(Voice.channels.normalise(Config.radio.maxChannel + 1), nil, 'above the ceiling')
    h.assertEqual(Voice.channels.normalise('police'), nil, 'a non-numeric string')
    h.assertEqual(Voice.channels.normalise({}), nil, 'a table')
    -- tonumber('nan') yields a real NaN in Lua 5.4, and NaN passes every
    -- comparison-based bounds check silently.
    h.assertEqual(Voice.channels.normalise(0 / 0), nil, 'NaN')
end)

h.test('calls have their own, much larger id space', function()
    -- Phone resources use the phone NUMBER as the channel, so the call ceiling
    -- has to clear seven digits while the radio ceiling stays small.
    local phoneNumber = 5551234
    h.assertEqual(Voice.channels.normalise(phoneNumber), nil, 'too large for a radio channel')
    h.assertEqual(Voice.channels.normaliseCall(phoneNumber), phoneNumber, 'fine as a call channel')
end)

h.test('the restriction table is a lookup, not a decision', function()
    -- The table names channels; whether a PLAYER may join one needs their job
    -- and lives server-side. This module must not be able to answer that.
    h.assertTrue(Voice.channels.isRestricted(1), 'channel 1 is restricted in the stock config')
    h.assertFalse(Voice.channels.isRestricted(400), 'an unlisted channel is open')
    h.assertEqual(Voice.channels.restriction(400), nil, 'and has no record')
end)

h.test('a job satisfies a restriction by name or by type', function()
    local record = { jobs = { 'tow' }, jobTypes = { 'leo' } }

    h.assertTrue(Voice.channels.jobSatisfies(record, { name = 'tow', type = 'recovery' }), 'by job name')
    h.assertTrue(Voice.channels.jobSatisfies(record, { name = 'sheriff', type = 'leo' }), 'by job type')
    h.assertFalse(Voice.channels.jobSatisfies(record, { name = 'unemployed', type = 'civ' }), 'by neither')
end)

h.test('onDuty is enforced when the record asks for it', function()
    local record = { jobTypes = { 'leo' }, onDuty = true }

    h.assertTrue(Voice.channels.jobSatisfies(record, { name = 'police', type = 'leo', onduty = true }), 'on duty')
    h.assertFalse(Voice.channels.jobSatisfies(record, { name = 'police', type = 'leo', onduty = false }),
        'an off-duty officer must not sit on the tac channel while playing a civilian')
end)

h.test('an unreadable job satisfies nothing', function()
    -- kora_core restarting makes the job read fail. The failure mode has to be a
    -- REFUSED restricted channel, never an allowed one.
    h.assertFalse(Voice.channels.jobSatisfies({ jobTypes = { 'leo' } }, nil), 'nil job')
    h.assertFalse(Voice.channels.jobSatisfies({ jobTypes = { 'leo' } }, 'not a table'), 'garbage job')
end)

h.test('an empty restriction record locks the channel rather than opening it', function()
    -- A server that listed a channel as restricted and forgot to say who may
    -- use it meant "locked". The opposite default would silently un-restrict a
    -- channel on a config typo.
    h.assertFalse(Voice.channels.jobSatisfies({}, { name = 'police', type = 'leo', onduty = true }),
        'nobody satisfies an empty record')
end)

h.report('channels')
