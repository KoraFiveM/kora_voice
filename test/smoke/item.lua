-- The radio item's server half: it registers a use handler for the configured
-- item, registers again when kora_inventory restarts, survives kora_core being
-- absent, and its handler only asks the client to open the dialog.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); mocks.install()
dofile('config.lua')

local registrations = {}
local clientEvents = {}

-- Colon-call dispatch passes the export table as `self`; the stub drops it, as
-- mocks.lua's export proxy does.
exports.kora_core = {
    createUseable = function(_self, name, fn)
        registrations[#registrations + 1] = { name = name, fn = fn }
    end,
}
_G.TriggerClientEvent = function(name, src)
    clientEvents[#clientEvents + 1] = { name = name, src = src }
end

dofile('server/item.lua')

h.test('the use handler is registered for the configured item at load', function()
    h.assertEqual(#registrations, 1, 'one registration at load')
    h.assertEqual(registrations[1].name, Config.radio.item, 'under Config.radio.item')
    h.assertEqual(Config.radio.item, 'radio', 'which defaults to the radio item')
end)

h.test('using the item asks the owning client to open the dialog', function()
    local ret = registrations[1].fn(7, { name = 'radio' })

    h.assertEqual(clientEvents[#clientEvents].name, 'qbvoice:client:openRadio', 'the client is told to open the dialog')
    h.assertEqual(clientEvents[#clientEvents].src, 7, 'addressed to the player who used the item')
    h.assertTrue(ret ~= false, 'and does not report a rejected use to the inventory')
end)

h.test('re-registers when kora_inventory starts, and not for other resources', function()
    TriggerEvent('onResourceStart', 'kora_police')
    h.assertEqual(#registrations, 1, 'an unrelated resource start does nothing')

    TriggerEvent('onResourceStart', 'kora_inventory')
    h.assertEqual(#registrations, 2, 'kora_inventory start registers again')
    h.assertEqual(registrations[2].name, 'radio', 'under the same item')
end)

h.test('a missing kora_core does not raise out of the registration', function()
    exports.kora_core = nil
    local ok = pcall(TriggerEvent, 'onResourceStart', 'kora_inventory')
    h.assertTrue(ok, 'kora_voice must still start when the core is not running')
end)

h.report('item')
