-- The `radio` inventory item, server half.
--
-- Using the item only asks the owning client to open its frequency dialog. It
-- does NOT touch membership: the join itself is a client REQUEST through
-- `kora_voice:requestRadio`, like every other request. Nothing in this file calls
-- `Voice.api.assign` or any other trusted function.

local function registerUseable()
    local item = Config.radio.item
    if type(item) ~= 'string' or item == '' then return end

    -- kora_core / kora_inventory may not be started yet (or may be restarting).
    -- A failed registration must not stop kora_voice from starting; the
    -- onResourceStart handler below registers again once kora_inventory is up.
    local ok, err = pcall(function()
        exports.kora_core:createUseable(item, function(src)
            TriggerClientEvent('kora_voice:client:openRadio', src)
            return true
        end)
    end)

    if not ok then
        print(('[kora_voice] could not register the %s use handler: %s'):format(item, tostring(err)))
    end
end

registerUseable()

-- kora_inventory drops handlers registered before it (re)starts; register again.
AddEventHandler('onResourceStart', function(resource)
    if resource == 'kora_inventory' then registerUseable() end
end)
