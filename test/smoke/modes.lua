-- Proximity mode cycling: the invariant is that the cycle can NEVER produce an
-- index outside the configured set, no matter what it is fed or how many times.
-- A range nobody configured is a player being heard at a distance the server
-- never agreed to.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); mocks.install()
dofile('config.lua')
dofile('shared/modes.lua')

local COUNT = #Config.proximity.modes

h.test('the stock config has a real mode set', function()
    h.assertTrue(COUNT >= 2, 'cycling needs at least two modes to be meaningful')
    h.assertEqual(Voice.modes.count(), COUNT, 'count matches the config')
end)

h.test('cycling forwards stays inside the configured set', function()
    local index = Voice.modes.defaultIndex()

    -- Far more presses than there are modes, so a wrap that overshot by one
    -- would be caught rather than sitting just past the end.
    for _ = 1, 500 do
        index = Voice.modes.next(index, 1)
        h.assertTrue(index >= 1 and index <= COUNT,
            ('index %s escaped the configured set'):format(tostring(index)))
        h.assertTrue(Voice.modes.get(index) ~= nil, 'every cycled index resolves to a real mode')
    end
end)

h.test('cycling backwards stays inside the configured set', function()
    local index = Voice.modes.defaultIndex()

    for _ = 1, 500 do
        index = Voice.modes.next(index, -1)
        h.assertTrue(index >= 1 and index <= COUNT, 'a negative step escaped the set')
    end
end)

h.test('the wrapping cycle visits every mode and returns to the start', function()
    Config.proximity.wrap = true

    local start = 1
    local index = start
    local seen = {}

    for _ = 1, COUNT do
        seen[index] = true
        index = Voice.modes.next(index, 1)
    end

    h.assertEqual(index, start, 'one full lap returns to where it began')
    for expected = 1, COUNT do
        h.assertTrue(seen[expected], ('mode %d was never reached'):format(expected))
    end
end)

h.test('with wrap off the cycle saturates instead of wrapping', function()
    Config.proximity.wrap = false

    -- The reason a server would want this: "one more press" must never quietly
    -- drop a shouting player to a whisper mid-sentence.
    h.assertEqual(Voice.modes.next(COUNT, 1), COUNT, 'the top saturates')
    h.assertEqual(Voice.modes.next(1, -1), 1, 'the bottom saturates')

    Config.proximity.wrap = true
end)

h.test('garbage is clamped rather than passed through', function()
    -- Every one of these can arrive from a pma-voice setTalkingMode call site,
    -- which historically took a raw integer from a UI.
    for _, bad in ipairs({ 0, -5, 999, 2.7 }) do
        local clamped = Voice.modes.clamp(bad)
        h.assertTrue(clamped >= 1 and clamped <= COUNT,
            ('clamp(%s) produced %s'):format(tostring(bad), tostring(clamped)))
    end

    h.assertEqual(Voice.modes.clamp(nil), Voice.modes.defaultIndex(), 'nil falls back to the default mode')
    h.assertEqual(Voice.modes.clamp('nonsense'), Voice.modes.defaultIndex(), 'a non-numeric string too')
end)

h.test('modes resolve by name as well as by index', function()
    local whisper = Voice.modes.indexOfName('whisper')
    h.assertTrue(whisper ~= nil, 'the stock config has a whisper mode')
    h.assertEqual(Voice.modes.resolve('whisper'), whisper, 'a name resolves to its index')
    h.assertEqual(Voice.modes.resolve(whisper), whisper, 'an index resolves to itself')

    -- An unknown NAME must not silently become an index. It falls through to
    -- clamp, which yields the default -- never a neighbouring mode.
    h.assertEqual(Voice.modes.resolve('bullhorn'), Voice.modes.defaultIndex(),
        'an unknown mode name falls back to the default, not to mode 1 by accident')
end)

h.test('every mode has a usable range', function()
    for index = 1, COUNT do
        local range = Voice.modes.rangeOf(index)
        h.assertTrue(range > 0.0, ('mode %d has no range'):format(index))
    end

    -- Order is the UI: the cycle key steps quietest-to-loudest, and a config
    -- that broke that ordering would make the key feel backwards.
    for index = 2, COUNT do
        h.assertTrue(Voice.modes.rangeOf(index) > Voice.modes.rangeOf(index - 1),
            ('mode %d is not louder than mode %d'):format(index, index - 1))
    end
end)

h.test('a config default outside the set is itself clamped', function()
    local original = Config.proximity.default

    Config.proximity.default = 99
    h.assertTrue(Voice.modes.defaultIndex() <= COUNT, 'a config typo cannot produce a modeless player')

    Config.proximity.default = 0
    h.assertTrue(Voice.modes.defaultIndex() >= 1, 'nor can a zero')

    Config.proximity.default = original
end)

h.report('modes')
