-- The `radio` inventory item, client half.
--
-- The server tells this client to open the frequency dialog. The answer is sent
-- back as a REQUEST through the same exports every other caller uses. This file
-- never decides membership: the server decides, and the answer arrives as a
-- published state bag value (client/sync.lua applies it).

local dialogOpen = false -- one dialog at a time, so repeated uses cannot stack

local function notify(message, kind)
    Kora.notify.send({ title = 'Radio', message = message, type = kind or 'info' })
end

---@return integer|nil whole number, or nil when the input is not one
local function parseFrequency(value)
    local n = tonumber(value)
    if not n or n ~= math.floor(n) then return nil end
    return math.floor(n)
end

local function leaveFrequency()
    if exports.kora_voice:removePlayerFromRadio() then
        notify('You left the frequency.')
    end
end

local function openFrequencyDialog()
    local current = exports.kora_voice:getRadioChannel() or 0

    local result = Kora.nui.openInputDialog({
        {
            id = 'channel',
            label = 'Frequency',
            type = 'number',
            min = 0,
            max = Config.radio.maxChannel,
            wholeNumber = true,
            default = current,
            description = '0 leaves the channel',
        },
    }, 'Radio')

    -- Cancelled (or the dialog timed out): change nothing.
    if not result or not result.values then return end

    local raw = result.values.channel
    if raw == nil or raw == '' then return leaveFrequency() end

    local channel = parseFrequency(raw)
    if channel == nil then
        return notify('Enter a whole frequency number.', 'error')
    end

    if channel == 0 then return leaveFrequency() end

    if channel < Config.radio.minChannel or channel > Config.radio.maxChannel then
        return notify(('Frequency must be between %d and %d.'):format(Config.radio.minChannel, Config.radio.maxChannel), 'error')
    end

    -- Suspends until the server answers. The server re-validates the channel.
    local ok, reason = exports.kora_voice:addPlayerToRadio(channel)
    if ok then
        notify(('Connected to frequency %d'):format(channel))
    elseif reason then
        -- A refusal carries the server's generic reason. A timeout (no reason)
        -- stays silent: inventing a message would tell the player something the
        -- server never said.
        notify(reason, 'error')
    end
end

RegisterNetEvent('kora_voice:client:openRadio', function()
    if dialogOpen then return end
    dialogOpen = true

    CreateThread(function()
        local ok, err = pcall(openFrequencyDialog)
        dialogOpen = false
        if not ok then
            print(('[kora_voice] radio item dialog failed: %s'):format(tostring(err)))
        end
    end)
end)
