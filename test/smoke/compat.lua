-- pma-voice compatibility, server half: the export identity and the legacy
-- events, and the fact that each maps onto the real authority layer rather than
-- a parallel implementation.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local net = mocks.install()
dofile('config.lua')
dofile('shared/channels.lua')
dofile('server/store.lua')
dofile('server/policy.lua')
dofile('server/publish.lua')
dofile('server/api.lua')
dofile('server/net.lua')
dofile('server/compat.lua')

local OFFICER, CIVILIAN = 1, 2

local function reset()
    Voice.store._reset()
    Voice.policy._reset()
    net.clear()
    net.setPlayer(OFFICER, 'police', 'leo', true)
    net.setPlayer(CIVILIAN, 'unemployed', 'civ', false)
end

---Resolves an `exports['pma-voice']:<name>` the way Cfx does: fire the
---`__cfx_export_pma-voice_<name>` event with a setCB stub and capture what it
---hands back. This is the actual resolution mechanism, not an approximation of
---it -- so a missing registration fails here exactly as it would in game.
---@param name string
---@return function|nil
local function pmaExport(name)
    local handlers = net.eventHandlers[('__cfx_export_pma-voice_%s'):format(name)]
    if not handlers or #handlers == 0 then return nil end

    local captured
    handlers[1](function(fn) captured = fn end)
    return captured
end

h.test('the pma-voice server surface is registered under its own identity', function()
    -- `provide 'pma-voice'` in the manifest satisfies a dependency; it does NOT
    -- make exports resolve. These handlers are the separate mechanism that does.
    for _, name in ipairs({
        'setPlayerRadio', 'addPlayerToRadio', 'removePlayerFromRadio',
        'setPlayerCall', 'removePlayerFromCall',
        'getPlayersInRadioChannel', 'getPlayersInCall',
        'getRadioChannel', 'getCallChannel',
    }) do
        h.assertTrue(pmaExport(name) ~= nil, ('exports[pma-voice]:%s is missing'):format(name))
    end
end)

h.test('qbvoice registers the same surface under its own name', function()
    for _, name in ipairs({
        'setPlayerRadio', 'addPlayerToRadio', 'removePlayerFromRadio',
        'setPlayerCall', 'removePlayerFromCall',
        'getPlayersInRadioChannel', 'getPlayersInCall', 'getRadioMembers',
        'getRadioChannel', 'getCallChannel',
        'grantRadioChannels', 'revokeRadioChannels',
        'addRadioPolicy', 'removeRadioPolicy', 'isChannelRestricted',
    }) do
        h.assertTrue(type(net.registeredExports[name]) == 'function',
            ('exports.qbvoice:%s is missing'):format(name))
    end
end)

h.test('setPlayerRadio goes through the real authority layer', function()
    reset()
    pmaExport('setPlayerRadio')(OFFICER, 3)

    h.assertEqual(Voice.store.getRadio(OFFICER), 3, 'the store was updated')
    h.assertTrue(#net.writesFor(OFFICER, Config.state.radio) > 0,
        'and it published -- a compat path that skipped publication would leave the client blind')
end)

h.test('getPlayersInRadioChannel returns pma-voices map shape', function()
    reset()
    pmaExport('setPlayerRadio')(OFFICER, 3)
    pmaExport('setPlayerRadio')(CIVILIAN, 3)

    local members = pmaExport('getPlayersInRadioChannel')(3)

    -- A map of source -> true, because that is what existing call sites index.
    h.assertEqual(members[OFFICER], true, 'the officer is keyed by source')
    h.assertEqual(members[CIVILIAN], true, 'so is the civilian')
    h.assertEqual(members[99], nil, 'and a non-member is absent')
end)

h.test('getRadioMembers is the array form, for iteration', function()
    reset()
    Voice.api.assign(OFFICER, 3)
    Voice.api.assign(CIVILIAN, 3)

    local members = net.registeredExports.getRadioMembers(3)
    h.assertEqual(#members, 2, 'a dense, sorted array')
    h.assertEqual(members[1], OFFICER, 'sorted, so it is deterministic')
end)

h.test('getRadioChannel returns false rather than nil when off the radio', function()
    reset()

    -- A nil does not survive the exports boundary as a distinguishable value:
    -- a caller cannot tell "no channel" from "the export does not exist".
    h.assertEqual(pmaExport('getRadioChannel')(OFFICER), false, 'false, not nil')

    Voice.api.assign(OFFICER, 3)
    h.assertEqual(pmaExport('getRadioChannel')(OFFICER), 3, 'and the channel once on one')
end)

h.test('the call exports drive the independent call store', function()
    reset()
    pmaExport('setPlayerRadio')(OFFICER, 3)
    pmaExport('setPlayerCall')(OFFICER, 5551234)

    h.assertEqual(Voice.store.getRadio(OFFICER), 3, 'the radio is untouched by the call')
    h.assertEqual(pmaExport('getCallChannel')(OFFICER), 5551234, 'and the call is live')

    pmaExport('removePlayerFromCall')(OFFICER, 5551234)
    h.assertEqual(Voice.store.getRadio(OFFICER), 3, 'hanging up leaves the radio alone')
end)

h.test('the legacy inbound events exist and are request-shaped', function()
    for _, name in ipairs({
        'pma-voice:setPlayerRadio', 'pma-voice:addPlayerToRadio',
        'pma-voice:removePlayerFromRadio', 'pma-voice:removePlayerFromCall',
    }) do
        h.assertTrue(net.netHandlers[name] ~= nil, ('%s is not registered'):format(name))
    end

    -- Deliberately absent: joining a CALL from a client. That would be a client
    -- asking to listen to somebody else's phone call.
    h.assertEqual(net.netHandlers['pma-voice:setPlayerCall'], nil,
        'a client must not be able to put itself into a call')
end)

h.test('the compat surface is exposed for introspection but not as a second path', function()
    -- server/compat.lua keeps its table on Voice.compat.server purely so a test
    -- can see it. Every entry must funnel into Voice.api -- a compat function
    -- that touched Voice.store directly would bypass publication entirely.
    reset()
    Voice.compat.server.setPlayerRadio(OFFICER, 4)

    h.assertTrue(#net.pushesTo(OFFICER) > 0, 'the compat call published a roster')
end)

h.report('compat')
