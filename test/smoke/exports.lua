-- The client surface: qbvoice's own exports, the pma-voice client identity, and
-- the keys.
--
-- The property under test throughout is that NOTHING here asserts membership.
-- Every client entry point is either a local audio property or a request whose
-- answer arrives as a published value.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local net = mocks.install()
dofile('config.lua')
dofile('shared/modes.lua')
dofile('shared/channels.lua')
dofile('client/state.lua')
dofile('client/proximity.lua')
dofile('client/submix.lua')
dofile('client/targets.lua')
dofile('client/keybinds.lua')
dofile('client/exports.lua')
dofile('client/compat.lua')

---Resolves an `exports['pma-voice']:<name>` the way Cfx does.
---@param name string
---@return function|nil
local function pmaExport(name)
    local handlers = net.eventHandlers[('__cfx_export_pma-voice_%s'):format(name)]
    if not handlers or #handlers == 0 then return nil end

    local captured
    handlers[1](function(fn) captured = fn end)
    return captured
end

h.test('the qbvoice client surface is registered', function()
    for _, name in ipairs({
        'addPlayerToRadio', 'removePlayerFromRadio', 'removePlayerFromCall',
        'getRadioChannel', 'getCallChannel',
        'setTalkingMode', 'cycleTalkingMode', 'getTalkingMode',
        'isRadioActive', 'setMegaphone',
        'setRadioVolume', 'setCallVolume',
        'setVoiceProperty', 'getVoiceProperty', 'refreshVoiceTargets',
    }) do
        h.assertTrue(type(net.registeredExports[name]) == 'function',
            ('exports.qbvoice:%s is missing'):format(name))
    end
end)

h.test('the pma-voice client identity resolves to this resource', function()
    for _, name in ipairs({
        'setVoiceProperty', 'getVoiceProperty', 'setRadioVolume', 'setCallVolume',
        'setTalkingMode', 'addPlayerToRadio', 'removePlayerFromRadio',
        'removePlayerFromCall', 'getRadioChannel', 'getCallChannel',
    }) do
        h.assertTrue(pmaExport(name) ~= nil, ('exports[pma-voice]:%s is missing'):format(name))
    end
end)

h.test('addPlayerToRadio asks, and never asserts', function()
    Voice.state.setRadio(false)
    net.setCallbackResponse('qbvoice:requestRadio', true)

    local ok = exports.qbvoice:addPlayerToRadio(3)
    h.assertTrue(ok, 'the server agreed')

    -- THE point. A `true` return means "the server agreed", not "I am on
    -- channel 3 now": membership arrives as a published state bag value, which
    -- client/sync.lua applies. A client that wrote it locally would be
    -- self-granting a channel.
    h.assertEqual(exports.qbvoice:getRadioChannel(), false,
        'local membership is still whatever the server last published')
end)

h.test('a refusal is reported with the servers reason', function()
    net.setCallbackResponse('qbvoice:requestRadio', false, 'That frequency is restricted.')

    local ok, reason = exports.qbvoice:addPlayerToRadio(2)
    h.assertFalse(ok, 'refused')
    h.assertEqual(reason, 'That frequency is restricted.', 'with the servers own wording')
end)

h.test('a timed-out round trip is distinguishable from a refusal', function()
    -- qblib returns NO values on a timeout, so `ok` is nil rather than false.
    -- Inventing a reason for a dropped round trip would tell the player
    -- something the server never said.
    net.setCallbackResponse('qbvoice:requestRadio')

    local ok, reason = exports.qbvoice:addPlayerToRadio(3)
    h.assertFalse(ok, 'not treated as success')
    h.assertEqual(reason, nil, 'and carries no invented reason')
end)

h.test('setTalkingMode reaches the real voice-distance natives', function()
    net.clear()
    local index, range = exports.qbvoice:setTalkingMode('shout')

    h.assertEqual(index, Voice.modes.indexOfName('shout'), 'resolved by name')
    h.assertEqual(net.nativesNamed('MumbleSetTalkerProximity')[1].args[1], range, 'and applied')
end)

h.test('the pma-voice setTalkingMode maps onto the same path', function()
    net.clear()
    pmaExport('setTalkingMode')(1)

    h.assertTrue(#net.nativesNamed('MumbleSetAudioInputDistance') > 0, 'the legacy export applies a range')
    h.assertEqual(Voice.state.mode(), 1, 'and sets the mode')
end)

h.test('an out-of-range talking mode is clamped, not passed to a native', function()
    exports.qbvoice:setTalkingMode(99)

    -- A pma-voice call site historically passed a raw integer from a UI.
    h.assertTrue(Voice.state.mode() <= Voice.modes.count(), 'clamped into the configured set')
end)

h.test('getTalkingMode describes the mode for a HUD', function()
    exports.qbvoice:setTalkingMode('whisper')
    local mode = exports.qbvoice:getTalkingMode()

    h.assertEqual(mode.name, 'whisper', 'the stable name')
    h.assertTrue(type(mode.label) == 'string', 'a display label')
    h.assertTrue(mode.range > 0, 'and the live range')
end)

h.test('volumes accept both 0-1 and 0-100', function()
    h.assertEqual(exports.qbvoice:setRadioVolume(0.5), 0.5, 'a fraction is taken as-is')
    -- Clamping 50 to 1.0 would turn "setRadioVolume(50)" into full volume --
    -- the opposite of the intent.
    h.assertEqual(exports.qbvoice:setRadioVolume(50), 0.5, 'a percentage is converted')
    h.assertEqual(exports.qbvoice:setRadioVolume(-3), 0.0, 'and negatives floor at silence')
end)

h.test('setVoiceProperty covers the pma-voice property names', function()
    for _, property in ipairs({ 'radioVolume', 'callVolume', 'micClicks', 'submix', 'talkingMode', 'muffling' }) do
        h.assertTrue(exports.qbvoice:setVoiceProperty(property, 1),
            ('%s should be settable'):format(property))
    end
end)

h.test('an unknown voice property is refused rather than silently dropped', function()
    -- A silently dropped setVoiceProperty presents as "the volume slider does
    -- nothing", which is a call-site typo nobody can find.
    h.assertFalse(exports.qbvoice:setVoiceProperty('reverb', 1), 'refused')
end)

h.test('getVoiceProperty reads back what setVoiceProperty wrote', function()
    exports.qbvoice:setVoiceProperty('radioVolume', 0.25)
    h.assertEqual(exports.qbvoice:getVoiceProperty('radioVolume'), 0.25, 'volume round-trips')

    exports.qbvoice:setVoiceProperty('micClicks', false)
    h.assertFalse(exports.qbvoice:getVoiceProperty('micClicks'), 'a toggle round-trips')
    exports.qbvoice:setVoiceProperty('micClicks', true)
end)

h.test('no voice property can change membership', function()
    -- setVoiceProperty is a client-side setter. A client-side membership setter
    -- is the exploit this resource exists to close.
    Voice.state.setRadio(false)

    for _, property in ipairs({ 'radioChannel', 'callChannel', 'channel', 'radio' }) do
        h.assertFalse(exports.qbvoice:setVoiceProperty(property, 2),
            ('%s must not be settable'):format(property))
    end

    h.assertEqual(exports.qbvoice:getRadioChannel(), false, 'still on no channel')
end)

h.test('getVoiceProperty can still READ the channel', function()
    Voice.state.setRadio(6)
    h.assertEqual(exports.qbvoice:getVoiceProperty('radioChannel'), 6, 'reading is fine; writing is not')
end)

h.test('the three keys are registered and rebindable', function()
    for _, name in ipairs({ 'qbvoice_proximity', 'qbvoice_radio', 'qbvoice_megaphone' }) do
        local bind = net.keybinds[name]
        h.assertTrue(bind ~= nil, ('%s is not registered'):format(name))
        h.assertTrue(type(bind.description) == 'string' and #bind.description > 0,
            ('%s needs a description to appear in FiveMs key settings'):format(name))
    end
end)

h.test('the radio key does nothing at all with no published channel', function()
    Voice.state.setRadio(false)
    net.clear()

    net.keybinds.qbvoice_radio.onPressed()

    -- Silent by design: the default is caps lock, and a notification here would
    -- fire at the whole civilian population.
    h.assertFalse(Voice.state.isRadioActive(), 'not transmitting')
    h.assertEqual(#net.sounds, 0, 'no click')
    h.assertEqual(#net.notifications, 0, 'and no complaint')
end)

h.test('the radio key transmits and announces itself once on a channel', function()
    Voice.state.setRadio(3)
    Voice.state.setRadioMembers({ 1, 2 })
    net.clear()

    net.keybinds.qbvoice_radio.onPressed()

    h.assertTrue(Voice.state.isRadioActive(), 'transmitting')
    h.assertEqual(#net.sounds, 1, 'one transmit click')

    local names = {}
    for _, event in ipairs(net.localEvents) do names[event.name] = event.args[1] end
    h.assertEqual(names['pma-voice:radioActive'], true, 'pma-voices radioActive fired, so a radio UI lights up')
    h.assertEqual(names['qbvoice:client:radioActive'], true, 'and qbvoices own')

    net.clear()
    net.keybinds.qbvoice_radio.onReleased()
    h.assertFalse(Voice.state.isRadioActive(), 'and stops on release')

    -- The rebuild on release matters: leaving the roster in the target until
    -- the next tick sends half a second of room conversation over the air.
    h.assertTrue(#net.nativesNamed('MumbleClearVoiceTarget') > 0, 'the target was rebuilt immediately')
end)

h.test('the megaphone key changes the range and the submix routing', function()
    net.clear()
    net.keybinds.qbvoice_megaphone.onPressed()

    h.assertTrue(Voice.state.data.megaphone, 'active')
    h.assertEqual(net.nativesNamed('MumbleSetTalkerProximity')[1].args[1], Config.submix.megaphone.range,
        'and the megaphone range applied')

    net.keybinds.qbvoice_megaphone.onReleased()
    h.assertFalse(Voice.state.data.megaphone, 'and released')
end)

h.report('exports')
