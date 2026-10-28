-- THE suite. Everything here is one property: a client asks, and the server
-- decides. A client that can add itself to a radio channel can listen to any
-- channel on the server, because the published roster is the only thing between
-- a player and a channel's audio.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local net = mocks.install()
dofile('config.lua')
dofile('shared/modes.lua')
dofile('shared/channels.lua')
dofile('server/store.lua')
dofile(arg[1] or 'server/policy.lua')
dofile('server/publish.lua')
dofile(arg[2] or 'server/api.lua')
dofile('server/net.lua')
dofile('server/compat.lua')

local OFFICER = 1  -- police, on duty
local CIVILIAN = 2 -- unemployed
local TOWIE = 3    -- tow, off duty

local function reset()
    for _, src in ipairs({ OFFICER, CIVILIAN, TOWIE }) do Voice.api.drop(src) end
    Voice.store._reset()
    Voice.policy._reset()
    net.clear()

    net.setPlayer(OFFICER, 'police', 'leo', true)
    net.setPlayer(CIVILIAN, 'unemployed', 'civ', false)
    net.setPlayer(TOWIE, 'tow', 'recovery', false)
end

h.test('a client cannot join a restricted channel', function()
    reset()

    -- Channel 2 is 'LEO Tac 1' in the stock config.
    local ok, reason = net.invokeCallback('qbvoice:requestRadio', CIVILIAN, 2)

    h.assertFalse(ok, 'the request must be refused')
    h.assertEqual(reason, Config.radio.refusedMessage, 'and carry the generic reason')
    h.assertEqual(Voice.store.getRadio(CIVILIAN), nil, 'nothing was recorded')
    h.assertEqual(#net.writesFor(CIVILIAN, Config.state.radio), 0,
        'and nothing was published -- a refused request must not write an optimistic value')
    h.assertEqual(#net.pushesTo(CIVILIAN), 0, 'no roster reached them, so they have no voice target')
end)

h.test('the refusal reason never names the job that would be allowed', function()
    reset()
    local _, reason = net.invokeCallback('qbvoice:requestRadio', CIVILIAN, 2)

    -- Naming the eligible job would tell every civilian which channel the
    -- police are on -- exactly the reconnaissance the restriction prevents.
    h.assertFalse(reason:lower():find('police') ~= nil, 'the reason must not mention police')
    h.assertFalse(reason:lower():find('leo') ~= nil, 'nor the job type')
end)

h.test('an eligible client is allowed onto the same channel', function()
    reset()
    local ok = net.invokeCallback('qbvoice:requestRadio', OFFICER, 2)

    h.assertTrue(ok, 'an on-duty officer may join the LEO tac channel')
    h.assertEqual(Voice.store.getRadio(OFFICER), 2, 'and the server recorded it')
end)

h.test('an off-duty officer is refused a duty-gated channel', function()
    reset()
    net.setPlayer(OFFICER, 'police', 'leo', false)

    h.assertFalse(net.invokeCallback('qbvoice:requestRadio', OFFICER, 2), 'duty is part of the check')
end)

h.test('a channel whose restriction does not require duty allows an off-duty player', function()
    reset()
    -- Channel 20 is 'Recovery' with no onDuty flag: towing works off duty.
    h.assertTrue(net.invokeCallback('qbvoice:requestRadio', TOWIE, 20), 'recovery works off duty')
end)

h.test('an unrestricted channel is open to anybody', function()
    reset()
    h.assertTrue(net.invokeCallback('qbvoice:requestRadio', CIVILIAN, 400), 'channel 400 is unlisted')
    h.assertEqual(Voice.store.getRadio(CIVILIAN), 400, 'and recorded')
end)

h.test('leaving is always permitted', function()
    reset()
    net.invokeCallback('qbvoice:requestRadio', OFFICER, 2)

    -- A player must never be able to get stuck on a channel, including one a
    -- policy hook has since decided they may not be on. Leaving grants no
    -- audio, so there is nothing to protect.
    Voice.policy.addHook(function() return false, 'no' end)

    h.assertTrue(net.invokeCallback('qbvoice:requestRadio', OFFICER, 0), 'zero means leave')
    h.assertEqual(Voice.store.getRadio(OFFICER), nil, 'and it took effect despite the refusing hook')
end)

h.test('a data grant opens a restricted channel for one player only', function()
    reset()
    Voice.policy.grant(CIVILIAN, { 2 })

    h.assertTrue(net.invokeCallback('qbvoice:requestRadio', CIVILIAN, 2), 'the granted player gets in')

    Voice.store._reset()
    h.assertFalse(net.invokeCallback('qbvoice:requestRadio', TOWIE, 2), 'nobody else does')
end)

h.test('a grant is dropped on disconnect', function()
    reset()
    Voice.policy.grant(CIVILIAN, { 2 })
    Voice.api.drop(CIVILIAN)

    -- Source ids are reused. A leftover grant would hand the tac channel to
    -- whoever next occupies that id.
    h.assertFalse(net.invokeCallback('qbvoice:requestRadio', CIVILIAN, 2), 'the grant went with them')
end)

h.test('a policy hook can refuse an otherwise-open channel', function()
    reset()
    Voice.policy.addHook(function(_, channel)
        if channel == 400 then return false, 'jammed' end
        return nil
    end)

    local ok, reason = net.invokeCallback('qbvoice:requestRadio', CIVILIAN, 400)
    h.assertFalse(ok, 'the hook refused')
    h.assertEqual(reason, 'jammed', 'with its own reason')

    -- Abstaining on every other channel is the correct default: a hook that
    -- refused everything outside its range would veto every other job.
    h.assertTrue(net.invokeCallback('qbvoice:requestRadio', CIVILIAN, 401), 'other channels unaffected')
end)

h.test('a policy hook can allow a restricted channel', function()
    reset()
    Voice.policy.addHook(function(src, channel)
        if src == CIVILIAN and channel == 2 then return true end
        return nil
    end)

    h.assertTrue(net.invokeCallback('qbvoice:requestRadio', CIVILIAN, 2), 'an explicit allow overrides config')
end)

h.test('an erroring policy hook abstains instead of taking voice down', function()
    reset()
    Voice.policy.addHook(function() error('broken job resource') end)

    -- The erroring resource is the broken one. Taking the radio down with it
    -- would turn one bug into a server-wide outage.
    h.assertTrue(net.invokeCallback('qbvoice:requestRadio', CIVILIAN, 400), 'open channels still work')
    h.assertFalse(net.invokeCallback('qbvoice:requestRadio', CIVILIAN, 2), 'and restrictions still hold')
end)

h.test('removing a hook does not renumber anybody elses handle', function()
    reset()
    local first = Voice.policy.addHook(function() return nil end)
    local second = Voice.policy.addHook(function() return false, 'second' end)

    Voice.policy.removeHook(first)

    -- If removal compacted the list, `second` would now address a different
    -- hook -- and a job resource cleaning up its own would remove somebody
    -- else's.
    local _, reason = net.invokeCallback('qbvoice:requestRadio', CIVILIAN, 400)
    h.assertEqual(reason, 'second', 'the surviving hook is still the one it was')
    h.assertTrue(Voice.policy.removeHook(second), 'and its handle still addresses it')
end)

h.test('the untrusted path never reaches the trusted one', function()
    reset()

    -- Replaces `assign` with a tripwire. `request` must refuse a restricted
    -- channel through its own policy check, not by delegating to the trusted
    -- assign function -- if a future refactor routes it through there, the
    -- restricted request would succeed and this fails.
    local original = Voice.api.assign
    local reached = false
    Voice.api.assign = function(...) reached = true; return original(...) end

    net.invokeCallback('qbvoice:requestRadio', CIVILIAN, 2)
    Voice.api.assign = original

    h.assertFalse(reached, 'Voice.api.request must not call Voice.api.assign')
end)

h.test('the trusted server export bypasses policy, as documented', function()
    reset()

    -- This is the intended asymmetry: another SERVER resource is trusted, and
    -- a job resource putting an officer on the tac channel must not have to
    -- satisfy the config table it owns.
    h.assertTrue(Voice.api.assign(CIVILIAN, 2), 'assign does not consult policy')
    h.assertEqual(Voice.store.getRadio(CIVILIAN), 2, 'and it took effect')
end)

h.test('every client-facing callback carries a rate limit', function()
    -- A join request is the one message a client sends unprompted. Unlimited,
    -- it lets a client walk every channel id looking for an open one.
    for _, name in ipairs({ 'qbvoice:requestRadio', 'qbvoice:leaveRadio', 'qbvoice:leaveCall', 'qbvoice:sync' }) do
        local entry = net.serverCallbacks[name]
        h.assertTrue(entry ~= nil, ('%s should be registered'):format(name))
        h.assertTrue(entry.opts and entry.opts.rateLimit ~= nil, ('%s has no rate limit'):format(name))
    end
end)

h.test('there is no client-facing way to JOIN a call channel', function()
    -- A client asking to join a call channel is a client asking to listen to
    -- somebody else's phone call. Only leaving is exposed.
    h.assertEqual(net.serverCallbacks['qbvoice:requestCall'], nil, 'no join callback exists')
    h.assertTrue(net.serverCallbacks['qbvoice:leaveCall'] ~= nil, 'but hanging up is allowed')
end)

h.test('the pma-voice net events take the player from source, not the payload', function()
    reset()

    -- pma-voice's equivalents let the payload name the player, which means any
    -- client could put ANY player on ANY channel by firing a well-known event
    -- name. Here the civilian fires it and is refused; the officer named in the
    -- payload is untouched.
    net.fireNet('pma-voice:setPlayerRadio', CIVILIAN, 2, OFFICER)

    h.assertEqual(Voice.store.getRadio(CIVILIAN), nil, 'the caller was refused')
    h.assertEqual(Voice.store.getRadio(OFFICER), nil, 'and the player they named was never touched')
end)

h.test('the pma-voice net event still works for an eligible caller', function()
    reset()
    net.fireNet('pma-voice:addPlayerToRadio', OFFICER, 2)

    h.assertEqual(Voice.store.getRadio(OFFICER), 2, 'the legacy event reaches the real request path')
end)

h.test('pma-voice events share the same bounded client request path', function()
    reset()
    for _ = 1, Config.rateLimit.radio.max do
        net.fireNet('pma-voice:setPlayerRadio', OFFICER, 5)
    end
    net.fireNet('pma-voice:setPlayerRadio', OFFICER, 6)

    h.assertEqual(Voice.store.getRadio(OFFICER), 5, 'the compatibility event cannot bypass the shared limiter')
end)

h.test('a stale leave cannot kick a player off the channel they just joined', function()
    reset()
    Voice.api.assign(OFFICER, 5)

    -- A radio UI a moment behind the server fires "leave channel 3". The
    -- channel argument is a GUARD, not a target.
    h.assertFalse(Voice.api.removeFromRadio(OFFICER, 3), 'the mismatched leave is ignored')
    h.assertEqual(Voice.store.getRadio(OFFICER), 5, 'and the real channel survives')

    h.assertTrue(Voice.api.removeFromRadio(OFFICER, 5), 'a matching leave works')
    h.assertEqual(Voice.store.getRadio(OFFICER), nil, 'as does an unqualified one')
end)

h.test('radio and call memberships are independent', function()
    reset()
    Voice.api.assign(OFFICER, 2)
    Voice.api.assignCall(OFFICER, 5551234)

    -- The whole reason they are two stores: an officer on the phone to a
    -- witness while dispatch talks over the air is normal play.
    h.assertEqual(Voice.store.getRadio(OFFICER), 2, 'the radio survived joining a call')
    h.assertEqual(Voice.store.getCall(OFFICER), 5551234, 'and the call is live alongside it')

    Voice.api.removeFromCall(OFFICER, nil)
    h.assertEqual(Voice.store.getRadio(OFFICER), 2, 'hanging up does not leave the radio')
end)

h.test('an invalid channel is reported rather than silently treated as "leave"', function()
    reset()
    Voice.api.assign(OFFICER, 5)

    local ok, err = Voice.api.assign(OFFICER, 99999)
    h.assertFalse(ok, 'an out-of-range channel is a caller bug')
    h.assertTrue(type(err) == 'string', 'and says so')
    h.assertEqual(Voice.store.getRadio(OFFICER), 5, 'the existing channel is untouched')
end)

h.test('character unload retires a static job-approved radio through normal publication', function()
    reset()
    h.assertTrue(net.invokeCallback('qbvoice:requestRadio', OFFICER, 2))
    Voice.api.assign(TOWIE, 2)
    Voice.api.assignCall(OFFICER, 5551234)
    Voice.policy.grant(OFFICER, { 3 })
    net.clear()
    TriggerEvent('QBCore:Server:OnPlayerUnload', OFFICER)

    h.assertEqual(Voice.store.getRadio(OFFICER), nil)
    h.assertEqual(Voice.store.radioMembersOf(2)[1], TOWIE)
    h.assertEqual(#Voice.store.radioMembersOf(2), 1)
    local cleared = net.writesFor(OFFICER, Config.state.radio)
    h.assertEqual(#cleared, 1)
    h.assertEqual(cleared[1].value, false)
    h.assertFalse(cleared[1].wasNil)
    h.assertEqual(net.pushesTo(OFFICER)[1].payload.channel, false)
    h.assertEqual(#net.pushesTo(OFFICER)[1].payload.members, 0)
    h.assertEqual(net.pushesTo(TOWIE)[1].payload.members[1], TOWIE)
    h.assertEqual(Voice.store.getCall(OFFICER), 5551234)
    h.assertEqual(Voice.policy.grantsOf(OFFICER)[1], 3)
    net.setPlayer(OFFICER, 'unemployed', 'civ', false)
    h.assertFalse(net.invokeCallback('qbvoice:requestRadio', OFFICER, 2))
    net.clear()
    TriggerEvent('QBCore:Server:OnPlayerUnload', OFFICER)
    h.assertEqual(#net.bagWrites, 0)
end)

h.test('character unload preserves open, granted and provider-hook memberships', function()
    reset()
    Voice.policy.grant(CIVILIAN, { 2 })
    h.assertTrue(net.invokeCallback('qbvoice:requestRadio', CIVILIAN, 2))
    h.assertTrue(net.invokeCallback('qbvoice:requestRadio', TOWIE, 400))
    local calls = 0
    Voice.policy.addHook(function(src, channel)
        calls = calls + 1
        if src == OFFICER and channel == 2 then return true end
    end)
    h.assertTrue(net.invokeCallback('qbvoice:requestRadio', OFFICER, 2))
    net.clear()
    TriggerEvent('QBCore:Server:OnPlayerUnload', OFFICER)
    TriggerEvent('QBCore:Server:OnPlayerUnload', CIVILIAN)
    TriggerEvent('QBCore:Server:OnPlayerUnload', TOWIE)
    h.assertEqual(Voice.store.getRadio(OFFICER), 2)
    h.assertEqual(Voice.store.getRadio(CIVILIAN), 2)
    h.assertEqual(Voice.store.getRadio(TOWIE), 400)
    h.assertEqual(Voice.policy.grantsOf(CIVILIAN)[1], 2)
    h.assertEqual(calls, 1, 'unload does not reevaluate provider policy')
    h.assertEqual(#net.bagWrites, 0)
    h.assertEqual(#net.pushes, 0)
end)

h.test('same-channel trusted assignment retains ownership through a later client request', function()
    reset()
    h.assertTrue(net.invokeCallback('qbvoice:requestRadio', OFFICER, 2))
    net.clear()
    h.assertTrue(exports.kora_voice:setPlayerRadio(OFFICER, 2))
    h.assertTrue(net.invokeCallback('qbvoice:requestRadio', OFFICER, 2))
    h.assertEqual(#net.bagWrites, 0)
    TriggerEvent('QBCore:Server:OnPlayerUnload', OFFICER)
    h.assertEqual(Voice.store.getRadio(OFFICER), 2)
    h.assertEqual(#net.bagWrites, 0)
    h.assertTrue(Voice.compat.server.setPlayerRadio(CIVILIAN, 2))
    h.assertFalse(net.invokeCallback('qbvoice:requestRadio', CIVILIAN, 2))
    TriggerEvent('QBCore:Server:OnPlayerUnload', CIVILIAN)
    h.assertEqual(Voice.store.getRadio(CIVILIAN), 2)
end)

h.test('rejected client requests and invalid trusted assignments preserve job ownership', function()
    reset()
    h.assertTrue(net.invokeCallback('qbvoice:requestRadio', OFFICER, 2))
    net.clear()
    local ok, reason = net.invokeCallback('qbvoice:requestRadio', OFFICER, 20)
    h.assertFalse(ok)
    h.assertEqual(reason, Config.radio.refusedMessage)
    h.assertFalse(exports.kora_voice:setPlayerRadio(OFFICER, 99999))
    net.setPlayer(OFFICER, 'unemployed', 'civ', false)
    h.assertFalse(net.invokeCallback('qbvoice:requestRadio', OFFICER, 2))
    h.assertEqual(Voice.store.getRadio(OFFICER), 2)
    h.assertEqual(#net.bagWrites, 0)
    TriggerEvent('QBCore:Server:OnPlayerUnload', OFFICER)
    h.assertEqual(Voice.store.getRadio(OFFICER), nil)
end)

h.test('legacy joins, explicit leave and hard disconnect retain their contracts', function()
    reset()
    net.fireNet('pma-voice:addPlayerToRadio', OFFICER, 2)
    h.assertEqual(Voice.store.getRadio(OFFICER), 2)
    h.assertFalse(Voice.api.removeFromRadio(OFFICER, 20))
    TriggerEvent('QBCore:Server:OnPlayerUnload', OFFICER)
    h.assertEqual(Voice.store.getRadio(OFFICER), nil)
    net.fireNet('pma-voice:setPlayerRadio', OFFICER, 2)
    h.assertTrue(net.invokeCallback('qbvoice:leaveRadio', OFFICER))
    net.clear()
    TriggerEvent('QBCore:Server:OnPlayerUnload', OFFICER)
    h.assertEqual(#net.bagWrites, 0)
    Voice.policy.grant(OFFICER, { 2 })
    h.assertTrue(net.invokeCallback('qbvoice:requestRadio', OFFICER, 2))
    source = OFFICER
    TriggerEvent('playerDropped')
    h.assertEqual(Voice.store.getRadio(OFFICER), nil)
    h.assertEqual(#Voice.policy.grantsOf(OFFICER), 0)
end)

h.test('granting permission does not transfer an existing job membership', function()
    reset()
    h.assertTrue(net.invokeCallback('qbvoice:requestRadio', OFFICER, 2))
    net.clear()
    h.assertEqual(exports.kora_voice:grantRadioChannels(OFFICER, { 2 }), 1)
    h.assertEqual(Voice.store.getRadio(OFFICER), 2)
    h.assertEqual(#net.bagWrites, 0)
    TriggerEvent('QBCore:Server:OnPlayerUnload', OFFICER)
    h.assertEqual(Voice.store.getRadio(OFFICER), nil)
    h.assertEqual(Voice.policy.grantsOf(OFFICER)[1], 2)
    net.setPlayer(OFFICER, 'unemployed', 'civ', false)
    h.assertTrue(net.invokeCallback('qbvoice:requestRadio', OFFICER, 2))
    TriggerEvent('QBCore:Server:OnPlayerUnload', OFFICER)
    h.assertEqual(Voice.store.getRadio(OFFICER), 2)
end)

h.report('authority')
