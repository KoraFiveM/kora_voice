-- Client proximity: a mode index becoming an actual audible range through the
-- voice-distance natives.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local net = mocks.install()
dofile('config.lua')
dofile('shared/modes.lua')
dofile('client/state.lua')
dofile('client/proximity.lua')

local function rangeOfName(name)
    return Voice.modes.rangeOf(Voice.modes.indexOfName(name))
end

h.test('the client starts on the configured default mode', function()
    -- A player whose first press of the cycle key moved them from an undeclared
    -- mode would see the wrong label on that first press.
    h.assertEqual(Voice.state.mode(), Voice.modes.defaultIndex(), 'default applied at load')
end)

h.test('applying a mode pushes the range into every voice-distance native', function()
    net.clear()
    Voice.proximity.set('whisper')

    local expected = rangeOfName('whisper')

    -- All four generations are set, not one. Which of them a given FiveM build
    -- honours varies, and a resource that only set the newest behaves
    -- differently per build.
    for _, native in ipairs({
        'MumbleSetAudioInputDistance', 'MumbleSetAudioOutputDistance',
        'MumbleSetTalkerProximity', 'NetworkSetTalkerProximity',
    }) do
        local calls = net.nativesNamed(native)
        h.assertTrue(#calls > 0, ('%s was never called'):format(native))
        h.assertEqual(calls[#calls].args[1], expected, ('%s got the wrong range'):format(native))
    end
end)

h.test('cycling walks the configured ranges in order and wraps', function()
    Voice.proximity.set(1)

    local seen = {}
    for _ = 1, Voice.modes.count() do
        local _, range = Voice.proximity.cycle(1)
        seen[#seen + 1] = range
    end

    h.assertEqual(#seen, Voice.modes.count(), 'one range per mode')
    h.assertEqual(seen[#seen], Voice.modes.rangeOf(1), 'a full lap returns to the first range')
end)

h.test('no amount of cycling produces an unconfigured range', function()
    local valid = {}
    for index = 1, Voice.modes.count() do valid[Voice.modes.rangeOf(index)] = true end

    for _ = 1, 200 do
        local _, range = Voice.proximity.cycle(1)
        h.assertTrue(valid[range], ('%s is not a configured range'):format(tostring(range)))
    end
end)

h.test('the mode change is told to the player', function()
    Config.proximity.notify = true
    net.clear()
    Voice.proximity.cycle(1)

    -- A silent range change is indistinguishable from a broken key, and the
    -- player has no other way to tell how far they are being heard.
    h.assertEqual(#net.notifications, 1, 'exactly one notification')
    h.assertTrue(net.notifications[1].message:find('m') ~= nil, 'and it names the distance')
end)

h.test('notifications can be turned off without breaking the cycle', function()
    Config.proximity.notify = false
    net.clear()
    Voice.proximity.cycle(1)

    h.assertEqual(#net.notifications, 0, 'silent')
    h.assertTrue(#net.nativesNamed('MumbleSetAudioInputDistance') > 0, 'but the range still applied')

    Config.proximity.notify = true
end)

h.test('the megaphone overrides the proximity mode entirely', function()
    Voice.proximity.set('whisper')
    Voice.state.setMegaphone(true)
    net.clear()

    local range = Voice.proximity.apply()

    -- The megaphone is not a fourth mode -- it also changes the submix, which a
    -- mode cannot -- and a player on one whose range was still whisper would be
    -- inaudible while visibly using it.
    h.assertEqual(range, Config.submix.megaphone.range, 'the megaphone range wins')
    h.assertEqual(net.nativesNamed('MumbleSetTalkerProximity')[1].args[1], range, 'and reaches the natives')
end)

h.test('putting the megaphone down restores the players own mode, not the default', function()
    Voice.proximity.set('whisper')
    Voice.state.setMegaphone(true)
    Voice.proximity.apply()

    Voice.state.setMegaphone(false)
    h.assertEqual(Voice.proximity.apply(), rangeOfName('whisper'),
        'someone who was whispering before should be whispering again after')
end)

h.test('a mode change marks the voice target dirty', function()
    Voice.state.clearDirty()
    Voice.proximity.set(Voice.modes.next(Voice.state.mode(), 1))

    -- Proximity decides who is in range, so the target list changes with it.
    h.assertTrue(Voice.state.isDirty(), 'the target needs rebuilding')
end)

h.test('a missing native degrades instead of erroring', function()
    local original = _G.MumbleSetAudioInputDistance
    _G.MumbleSetAudioInputDistance = nil

    -- A build missing one of the four must still apply the others. An error
    -- here would leave the player on whatever range they had, silently.
    net.clear()
    Voice.proximity.set('shout')
    h.assertTrue(#net.nativesNamed('MumbleSetTalkerProximity') > 0, 'the remaining natives still applied')

    _G.MumbleSetAudioInputDistance = original
end)

h.report('proximity')
