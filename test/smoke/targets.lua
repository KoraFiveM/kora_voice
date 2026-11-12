-- Voice target management. The target is CLEARED and REBUILT, and what goes
-- into it is the proximity grid plus exactly what the server published --
-- never anything the client decided for itself.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local net = mocks.install()
dofile('config.lua')
dofile('shared/modes.lua')
dofile('client/state.lua')
dofile('client/proximity.lua')
dofile('client/submix.lua')
dofile('client/targets.lua')

local ME = 1

local function reset()
    net.clearWorld()
    net.setOccluded(false)
    net.clear()

    Voice.state.setRadio(false)
    Voice.state.setCall(false)
    Voice.state.setRadioTalking(false)
    Voice.state.setMegaphone(false)
    Voice.state.setRadioMembers({})
    Voice.state.setCallMembers({})
    Voice.proximity.set('normal')
    Voice.state.setVolume('radio', 1.0)
    Voice.state.setVolume('call', 1.0)

    net.placePlayer(ME, 0.0, 0.0, 0.0)
end

---Every server id added to the voice target during the last rebuild.
local function added()
    local out = {}
    for _, call in ipairs(net.nativesNamed('MumbleAddVoiceTargetPlayerByServerId')) do
        out[call.args[2]] = true
    end
    return out
end

h.test('the target is cleared before anything is added to it', function()
    reset()
    net.placePlayer(2, 3.0, 0.0, 0.0)
    net.clear()

    Voice.targets.rebuild()

    -- There is no "remove one player from a target" native, so the only way to
    -- drop a member is to rebuild without them. A rebuild that added before
    -- clearing would discard its own work.
    local clearAt = net.nativeIndex('MumbleClearVoiceTarget')
    local addAt = net.nativeIndex('MumbleAddVoiceTargetPlayerByServerId')

    h.assertTrue(clearAt ~= nil, 'the target was cleared')
    h.assertTrue(addAt ~= nil, 'and rebuilt')
    h.assertTrue(clearAt < addAt, 'clear must come first')
end)

h.test('the target is committed after it is built', function()
    reset()
    net.placePlayer(2, 3.0, 0.0, 0.0)
    net.clear()
    Voice.targets.rebuild()

    local setAt = net.nativeIndex('MumbleSetVoiceTarget')
    h.assertTrue(setAt ~= nil, 'MumbleSetVoiceTarget was called')
    h.assertTrue(setAt > net.nativeIndex('MumbleAddVoiceTargetPlayerByServerId'), 'after the members were added')
    h.assertEqual(net.nativesNamed('MumbleSetVoiceTarget')[1].args[1], Config.mumble.targetId,
        'on the one configured target -- mixing targets leaves a stale one behind')
end)

h.test('the proximity grid respects the current talk range', function()
    reset()
    net.placePlayer(2, 3.0, 0.0, 0.0)   -- inside whisper
    net.placePlayer(3, 25.0, 0.0, 0.0)  -- outside normal, inside shout
    net.clear()

    Voice.proximity.set('normal')
    Voice.targets.rebuild()
    local inNormal = added()
    h.assertTrue(inNormal[2], 'the close player is a target')
    h.assertFalse(inNormal[3], 'the far one is not')

    net.clear()
    Voice.proximity.set('shout')
    Voice.targets.rebuild()
    h.assertTrue(added()[3], 'shouting reaches them')
end)

h.test('this player is never in their own target', function()
    reset()
    net.clear()
    Voice.targets.rebuild()

    h.assertFalse(added()[ME], 'adding yourself would route your own audio back at you')
end)

h.test('the radio roster is only in the target while the key is held', function()
    reset()
    -- A member far outside any talk range: the only path to them is the radio.
    net.placePlayer(9, 500.0, 0.0, 0.0)
    Voice.state.setRadio(3)
    Voice.state.setRadioMembers({ ME, 9 })

    net.clear()
    Voice.targets.rebuild()
    h.assertFalse(added()[9], 'being ON a channel does not transmit -- otherwise every word in a room goes out over the air')

    Voice.state.setRadioTalking(true)
    net.clear()
    Voice.targets.rebuild()
    h.assertTrue(added()[9], 'holding the key does')
end)

h.test('holding the radio key with no channel transmits to nobody', function()
    reset()
    net.placePlayer(9, 500.0, 0.0, 0.0)
    Voice.state.setRadioMembers({ ME, 9 })
    Voice.state.setRadioTalking(true)

    -- The key fires whether or not the server ever granted a channel. A roster
    -- left over from a channel the player has since left must not be usable.
    net.clear()
    Voice.targets.rebuild()
    h.assertFalse(added()[9], 'no published channel, no transmission')
end)

h.test('a call is live without any key, and alongside a radio transmission', function()
    reset()
    net.placePlayer(8, 500.0, 0.0, 0.0)
    net.placePlayer(9, 600.0, 0.0, 0.0)

    Voice.state.setCall(5551234)
    Voice.state.setCallMembers({ ME, 8 })
    Voice.state.setRadio(3)
    Voice.state.setRadioMembers({ ME, 9 })
    Voice.state.setRadioTalking(true)

    net.clear()
    Voice.targets.rebuild()

    local target = added()
    h.assertTrue(target[8], 'the call is in the target with no key held')
    h.assertTrue(target[9], 'and the radio transmission is too, at the same time')
end)

h.test('leaving a channel empties the roster locally as well', function()
    reset()
    net.placePlayer(9, 500.0, 0.0, 0.0)
    Voice.state.setRadio(3)
    Voice.state.setRadioMembers({ ME, 9 })
    Voice.state.setRadioTalking(true)

    Voice.state.setRadio(false)
    net.clear()
    Voice.targets.rebuild()

    -- Waiting for a roster push to clear it would never happen: the push only
    -- reaches CURRENT members.
    h.assertFalse(added()[9], 'the stale roster cannot be transmitted to')
end)

h.test('a member is added by SERVER ID, not by player handle', function()
    reset()
    net.placePlayer(9, 500.0, 0.0, 0.0)
    Voice.state.setRadio(3)
    Voice.state.setRadioMembers({ 9 })
    Voice.state.setRadioTalking(true)
    net.clear()

    Voice.targets.rebuild()

    -- A radio member outside this client's scope has no local player handle at
    -- all, so the handle-taking native cannot reach them -- a radio that only
    -- works within earshot is not a radio.
    h.assertTrue(#net.nativesNamed('MumbleAddVoiceTargetPlayerByServerId') > 0, 'the ByServerId form was used')
end)

h.test('an occluded neighbour is muffled, and unmuffled again when the wall clears', function()
    reset()
    net.placePlayer(2, 5.0, 0.0, 0.0)
    net.setOccluded(true)
    net.clear()

    Voice.targets.rebuild()
    local calls = net.nativesNamed('MumbleSetVolumeOverrideByServerId')
    h.assertTrue(#calls > 0, 'an override was applied')
    h.assertEqual(calls[#calls].args[2], Config.muffling.occludedVolume, 'at the configured occluded volume')

    net.setOccluded(false)
    net.clear()
    Voice.targets.rebuild()

    calls = net.nativesNamed('MumbleSetVolumeOverrideByServerId')
    h.assertTrue(#calls > 0, 'the override was lifted')
    -- -1.0 is Mumble's "no override". Writing 1.0 would pin the speaker at full
    -- volume and defeat every other volume control.
    h.assertEqual(calls[#calls].args[2], -1.0, 'with -1.0, not 1.0')
end)

h.test('muffling does not probe towards distant speakers', function()
    reset()
    net.placePlayer(2, 5.0, 0.0, 0.0)
    -- Well outside Config.muffling.maxDistance but inside shout range.
    Voice.proximity.set('shout')
    net.placePlayer(3, 30.0, 0.0, 0.0)
    net.clear()

    Voice.targets.rebuild()

    -- A speaker across the street is not "behind a wall", and a shape test
    -- towards them is the cost this cap exists to bound.
    h.assertEqual(#net.nativesNamed('StartExpensiveSynchronousShapeTestLosProbe'), 1,
        'exactly one probe, for the one speaker in muffling range')
end)

h.test('muffling can be turned off entirely', function()
    reset()
    Config.muffling.enabled = false
    net.placePlayer(2, 5.0, 0.0, 0.0)
    net.setOccluded(true)
    net.clear()

    Voice.targets.rebuild()
    h.assertEqual(#net.nativesNamed('StartExpensiveSynchronousShapeTestLosProbe'), 0, 'no probes at all')

    Config.muffling.enabled = true
end)

h.test('a radio member out of earshot is routed through the radio submix', function()
    reset()
    net.placePlayer(9, 500.0, 0.0, 0.0)
    Voice.state.setRadio(3)
    Voice.state.setRadioMembers({ ME, 9 })
    net.clear()

    Voice.targets.rebuild()

    local calls = net.nativesNamed('MumbleSetSubmixForServerId')
    local routed = false
    for _, call in ipairs(calls) do
        if call.args[1] == 9 and call.args[2] >= 0 then routed = true end
    end
    h.assertTrue(routed, 'their only path to us is the radio, so they should sound like one')
end)

h.test('a radio member standing next to you is NOT filtered', function()
    reset()
    net.placePlayer(2, 3.0, 0.0, 0.0)
    Voice.state.setRadio(3)
    Voice.state.setRadioMembers({ ME, 2 })
    net.clear()

    Voice.targets.rebuild()

    -- You hear them through the air. Filtering them would make a face-to-face
    -- conversation sound like a radio.
    for _, call in ipairs(net.nativesNamed('MumbleSetSubmixForServerId')) do
        if call.args[1] == 2 then
            h.assertEqual(call.args[2], -1, 'an in-earshot member is left unprocessed')
        end
    end
end)

h.test('the refresh runs on a bounded tick, not per frame', function()
    local before = #net.intervals
    Voice.targets.start()

    h.assertEqual(#net.intervals, before + 1, 'exactly one timer')
    h.assertEqual(net.intervals[#net.intervals].ms, Config.mumble.refreshInterval,
        'at the configured interval -- the rebuild fires shape tests and walks every in-scope player')
    h.assertTrue(Config.mumble.refreshInterval >= 100,
        'a sub-100ms interval would be a per-frame rebuild in all but name')
end)

h.test('refresh is a no-op until something changes', function()
    reset()
    Voice.targets.rebuild()

    h.assertFalse(Voice.state.isDirty(), 'a rebuild consumes the dirty flag')
    h.assertFalse(Voice.targets.refresh(), 'so a change-driven refresh does nothing')

    Voice.state.markDirty()
    h.assertTrue(Voice.targets.refresh(), 'and runs once something changes')
end)

h.test('the radio volume is applied to speakers heard only over the radio', function()
    reset()
    net.placePlayer(9, 500.0, 0.0, 0.0)
    Voice.state.setRadio(3)
    Voice.state.setRadioMembers({ ME, 9 })
    Voice.state.setVolume('radio', 0.4)
    net.clear()

    Voice.targets.rebuild()

    -- setRadioVolume that stored a number and never reached Mumble would look
    -- exactly like a working volume slider that does nothing.
    local calls = net.nativesNamed('MumbleSetVolumeOverrideByServerId')
    h.assertEqual(#calls, 1, 'one override, for the one radio-only speaker')
    h.assertEqual(calls[1].args[1], 9, 'the right speaker')
    h.assertEqual(calls[1].args[2], 0.4, 'at the configured radio volume')
end)

h.test('the radio volume does not touch a member you can hear through the air', function()
    reset()
    net.placePlayer(2, 3.0, 0.0, 0.0)
    Voice.state.setRadio(3)
    Voice.state.setRadioMembers({ ME, 2 })
    Voice.state.setVolume('radio', 0.4)
    net.clear()

    Voice.targets.rebuild()

    -- Their audio is proximity audio, not radio audio, so a radio volume has no
    -- business reducing it. Asserted per SPEAKER rather than as a call count,
    -- because the same pass legitimately lifts a previous speaker's override.
    for _, call in ipairs(net.nativesNamed('MumbleSetVolumeOverrideByServerId')) do
        if call.args[1] == 2 then
            h.assertEqual(call.args[2], -1.0, 'the in-earshot member is left at full volume')
        end
    end
end)

h.test('occlusion and a turned-down path resolve to the quietest of the two', function()
    reset()
    -- One speaker who is both in earshot behind a wall AND on the call.
    net.placePlayer(4, 5.0, 0.0, 0.0)
    Voice.state.setCall(5551234)
    Voice.state.setCallMembers({ ME, 4 })
    Voice.state.setVolume('call', 0.9)
    net.setOccluded(true)
    net.clear()

    Voice.targets.rebuild()

    -- Mumble has ONE override slot per speaker. Writing occlusion and the call
    -- volume separately would mean whichever ran last silently discarded the
    -- other.
    local calls = net.nativesNamed('MumbleSetVolumeOverrideByServerId')
    h.assertEqual(#calls, 1, 'exactly one write per speaker')
    h.assertEqual(calls[1].args[2], Config.muffling.occludedVolume, 'the harder reduction wins')
end)

h.test('an override is lifted for a speaker who left scope entirely', function()
    reset()
    net.placePlayer(2, 5.0, 0.0, 0.0)
    net.setOccluded(true)
    Voice.targets.rebuild()

    -- They disconnect or walk out of scope: they are gone from
    -- GetActivePlayers, so nothing in the current world state would ever lift
    -- their override and they would still be quiet tomorrow.
    net.clearWorld()
    net.placePlayer(ME, 0.0, 0.0, 0.0)
    net.clear()
    Voice.targets.rebuild()

    local calls = net.nativesNamed('MumbleSetVolumeOverrideByServerId')
    h.assertEqual(#calls, 1, 'the tracked override was revisited')
    h.assertEqual(calls[1].args[2], -1.0, 'and lifted')
end)

h.test('call audio is unprocessed by default and filtered only on request', function()
    reset()
    net.placePlayer(8, 500.0, 0.0, 0.0)
    Voice.state.setCall(5551234)
    Voice.state.setCallMembers({ ME, 8 })
    net.clear()

    Voice.targets.rebuild()

    -- A phone is not a handheld radio; band-limiting it by default would make
    -- every call sound like one.
    local routed = false
    for _, call in ipairs(net.nativesNamed('MumbleSetSubmixForServerId')) do
        if call.args[1] == 8 and call.args[2] >= 0 then routed = true end
    end
    h.assertFalse(routed, 'no effect with Config.calls.submix off')

    Config.calls.submix = true
    net.clear()
    Voice.targets.rebuild()

    routed = false
    for _, call in ipairs(net.nativesNamed('MumbleSetSubmixForServerId')) do
        if call.args[1] == 8 and call.args[2] >= 0 then routed = true end
    end
    h.assertTrue(routed, 'and the retro-telephone effect when a server asks for it')

    -- Turning it back off must actually clear the routing, not leave the
    -- speaker filtered for the rest of the session.
    Config.calls.submix = false
    net.clear()
    Voice.targets.rebuild()

    local cleared = false
    for _, call in ipairs(net.nativesNamed('MumbleSetSubmixForServerId')) do
        if call.args[1] == 8 and call.args[2] == -1 then cleared = true end
    end
    h.assertTrue(cleared, 'the routing was lifted')
end)

h.report('targets')
