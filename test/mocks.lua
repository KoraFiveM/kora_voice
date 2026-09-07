-- Mocks for smoke-testing qbvoice under plain lua5.4 (no FiveM, no Mumble, no
-- qbcore).
--
-- Two things are deliberately RECORDED rather than simulated, because they are
-- what the tests are actually about:
--
--   * every state-bag write, with its `replicated` flag AND its exact value --
--     so a test can assert that clearing writes an explicit `false` and never a
--     nil. A mock that stored nil and false identically would let the bug this
--     server has already paid for pass silently.
--
--   * every Mumble native call, in order -- so a test can assert the voice
--     target is CLEARED before it is rebuilt. Order is the property; a mock
--     that only kept a final member set could not see a missing clear.
--
-- Nothing here auto-advances and nothing here yields: CreateThread runs its
-- body immediately and Wait is a no-op, so a client file's session-wait thread
-- completes during the dofile rather than needing a scheduler.

local M = {}

function M.install()
    local eventHandlers = {}
    local netHandlers = {}
    local localEvents = {}
    local commands = {}
    local intervals = {}

    -- src -> { key -> value }, plus an ordered write log.
    local bags = {}
    local bagWrites = {}

    local pushes = {}
    local notifications = {}
    local keybinds = {}
    local stateListeners = {}
    local serverCallbacks = {}
    local sounds = {}

    -- Ordered log of every native call: { name = 'MumbleClearVoiceTarget', args = {...} }
    local natives = {}

    local function record(name, ...)
        natives[#natives + 1] = { name = name, args = { ... } }
    end

    -- --- core FiveM surface ---
    function _G.AddEventHandler(name, cb)
        eventHandlers[name] = eventHandlers[name] or {}
        table.insert(eventHandlers[name], cb)
        return name
    end

    function _G.RegisterNetEvent(name, cb)
        if not cb then return name end
        netHandlers[name] = netHandlers[name] or {}
        table.insert(netHandlers[name], cb)
        return name
    end

    function _G.TriggerEvent(name, ...)
        localEvents[#localEvents + 1] = { name = name, args = { ... } }
        for _, fn in ipairs(eventHandlers[name] or {}) do fn(...) end
        for _, fn in ipairs(netHandlers[name] or {}) do fn(...) end
    end

    function _G.RegisterCommand(name, cb) commands[name] = cb end
    function _G.CreateThread(fn) fn() end
    function _G.Wait(_) end
    function _G.SetTimeout(_, fn) fn() end
    function _G.GetInvokingResource() return nil end
    function _G.GetCurrentResourceName() return 'qbvoice' end
    function _G.GetHashKey(value) return #tostring(value) end
    function _G.joaat(value) return #tostring(value) end
    function _G.GetGameTimer() return math.floor(os.clock() * 1000) end

    -- No other resource is running, so the pma-voice conflict check finds
    -- nothing. Returning 0 rather than leaving these undefined is deliberate:
    -- server/compat.lua's guard degrades to "no conflict" when the natives are
    -- missing, and a test that never exercised the real loop would not notice
    -- the loop being wrong.
    function _G.GetNumResources() return 0 end
    function _G.GetResourceByFindIndex(_) return nil end
    function _G.GetResourceState(_) return 'missing' end

    -- --- server: state bags ---
    local bagMeta = {}
    bagMeta.__index = bagMeta

    function bagMeta:set(key, value, replicated)
        bagWrites[#bagWrites + 1] = {
            src = self.__src, key = key, value = value, replicated = replicated,
            -- Recorded separately from `value`, because `value == nil` and "no
            -- write happened" are indistinguishable once stored in a table.
            wasNil = value == nil,
        }
        bags[self.__src] = bags[self.__src] or {}
        bags[self.__src][key] = value
    end

    function _G.Player(src)
        return { state = setmetatable({ __src = src }, bagMeta) }
    end

    -- src -> bucket. Everyone shares bucket 0 unless a test says otherwise.
    local buckets = {}
    function _G.GetPlayerRoutingBucket(src) return buckets[src] or 0 end

    -- --- client: identity and world ---
    local coordsOf = {}   -- ped handle -> { x, y, z }
    local activePlayers = {}
    local occluded = false

    function _G.PlayerId() return 1 end
    function _G.GetPlayerServerId(player) return player end
    function _G.GetPlayerFromServerId(serverId) return serverId end
    function _G.GetPlayerPed(player) return 1000 + player end
    function _G.GetActivePlayers() return activePlayers end
    function _G.GetEntityCoords(ped) return coordsOf[ped] or { x = 0.0, y = 0.0, z = 0.0 } end
    function _G.NetworkIsSessionStarted() return true end

    function _G.StartExpensiveSynchronousShapeTestLosProbe(...)
        record('StartExpensiveSynchronousShapeTestLosProbe', ...)
        return 1
    end
    function _G.GetShapeTestResult(_) return 2, occluded and 1 or 0 end

    -- --- client: mumble / audio ---
    function _G.MumbleClearVoiceTarget(...) record('MumbleClearVoiceTarget', ...) end
    function _G.MumbleSetVoiceTarget(...) record('MumbleSetVoiceTarget', ...) end
    function _G.MumbleAddVoiceTargetPlayerByServerId(...) record('MumbleAddVoiceTargetPlayerByServerId', ...) end
    function _G.MumbleSetTalkerProximity(...) record('MumbleSetTalkerProximity', ...) end
    function _G.NetworkSetTalkerProximity(...) record('NetworkSetTalkerProximity', ...) end
    function _G.MumbleSetAudioInputDistance(...) record('MumbleSetAudioInputDistance', ...) end
    function _G.MumbleSetAudioOutputDistance(...) record('MumbleSetAudioOutputDistance', ...) end
    function _G.MumbleSetVolumeOverrideByServerId(...) record('MumbleSetVolumeOverrideByServerId', ...) end
    function _G.MumbleSetSubmixForServerId(...) record('MumbleSetSubmixForServerId', ...) end

    -- MumbleAddVoiceTargetPlayer is deliberately NOT defined. It takes a local
    -- PLAYER HANDLE, which a radio member outside this client's scope does not
    -- have -- so it is the fallback, not the path, and defining it here would
    -- let a regression onto it pass the tests and then produce a radio that
    -- only works within earshot.

    local nextSubmix = 0
    function _G.CreateAudioSubmix(name)
        record('CreateAudioSubmix', name)
        nextSubmix = nextSubmix + 1
        return nextSubmix
    end
    function _G.SetAudioSubmixEffectRadioFx(...) record('SetAudioSubmixEffectRadioFx', ...) end
    function _G.SetAudioSubmixEffectParamInt(...) record('SetAudioSubmixEffectParamInt', ...) end
    function _G.SetAudioSubmixEffectParamFloat(...) record('SetAudioSubmixEffectParamFloat', ...) end
    function _G.AddAudioSubmixOutput(...) record('AddAudioSubmixOutput', ...) end

    -- --- qbcore ---
    --
    -- Job records mirror qbcore/shared/jobs.lua's real relationships, because
    -- the restriction table is evaluated against real job->type pairs and a
    -- mock with a different shape would test nothing.
    local players = {}

    local qbcore = {}
    function qbcore:getJob(src)
        local p = players[src]
        if not p then return nil end
        return { name = p.job, type = p.type, onduty = p.onDuty }
    end
    function qbcore:getPlayers()
        local out = {}
        for src in pairs(players) do out[#out + 1] = src end
        table.sort(out)
        return out
    end

    -- FXServer's `exports` is both callable (registration) and indexable
    -- (invocation). Mocked as both, so a file that registers and a file that
    -- calls a sibling resource's export both work. Colon-call dispatch passes
    -- the receiver as `self`, which the proxy drops -- so each mocked export's
    -- arguments line up with the real signature exactly.
    local registered = {}

    local function proxy(_, name)
        return function(_self, ...)
            local fn = registered[name]
            if not fn then
                error(('mocks: exports.qbvoice:%s was called but never registered'):format(tostring(name)), 2)
            end
            return fn(...)
        end
    end

    _G.exports = setmetatable(
        { qbcore = qbcore, qbvoice = setmetatable({}, { __index = proxy }) },
        { __call = function(_, name, fn) registered[name] = fn end })

    -- --- qblib ---
    local callbackResponses = {}

    _G.QB = {
        events = {
            push = function(src, name, payload)
                pushes[#pushes + 1] = { src = src, name = name, payload = payload }
            end,
            onPush = function(name, handler)
                netHandlers['__push:' .. name] = netHandlers['__push:' .. name] or {}
                table.insert(netHandlers['__push:' .. name], handler)
            end,
            register = function() end,
            trigger = function() return true end,
        },

        callback = {
            register = function(name, handler, opts)
                serverCallbacks[name] = { handler = handler, opts = opts }
            end,
            -- Client side. Returns whatever a test scripted, or NOTHING at all
            -- (not false) when unscripted -- which is what a timed-out callback
            -- really does, and the case client/exports.lua has to distinguish
            -- from a refusal.
            trigger = function(name)
                local scripted = callbackResponses[name]
                if scripted == nil then return end
                return table.unpack(scripted, 1, scripted.n or #scripted)
            end,
        },

        state = {
            onChange = function(key, bagName, handler)
                stateListeners[#stateListeners + 1] = { key = key, bagName = bagName, handler = handler }
                return #stateListeners
            end,
            offChange = function() return true end,
        },

        keybind = {
            add = function(options)
                keybinds[options.name] = options
                return options
            end,
        },

        notify = {
            send = function(payload) notifications[#notifications + 1] = payload end,
        },

        timers = {
            setInterval = function(fn, ms)
                intervals[#intervals + 1] = { fn = fn, ms = ms }
                return #intervals
            end,
            clearInterval = function() return true end,
            setTimeout = function(fn) fn(); return 0 end,
        },

        sound = {
            playFrontend = function(name, set)
                sounds[#sounds + 1] = { name = name, set = set }
                return 1
            end,
        },

        cache = {
            playerId = function() return 1 end,
            serverId = function() return 1 end,
        },
    }

    return {
        eventHandlers = eventHandlers,
        netHandlers = netHandlers,
        localEvents = localEvents,
        commands = commands,
        intervals = intervals,
        bagWrites = bagWrites,
        pushes = pushes,
        notifications = notifications,
        keybinds = keybinds,
        stateListeners = stateListeners,
        serverCallbacks = serverCallbacks,
        sounds = sounds,
        natives = natives,
        registeredExports = registered,

        ---Puts a player in a job for the restriction check.
        setPlayer = function(src, job, jobType, onDuty)
            players[src] = { job = job, type = jobType, onDuty = onDuty and true or false }
        end,
        removePlayer = function(src) players[src] = nil end,

        ---Puts a player in a routing bucket.
        setBucket = function(src, bucket) buckets[src] = bucket end,

        ---Places a player in the world for the proximity grid, and makes them
        ---appear in GetActivePlayers.
        placePlayer = function(serverId, x, y, z)
            coordsOf[1000 + serverId] = { x = x + 0.0, y = y + 0.0, z = z + 0.0 }
            for _, existing in ipairs(activePlayers) do
                if existing == serverId then return end
            end
            activePlayers[#activePlayers + 1] = serverId
        end,
        clearWorld = function()
            for i = #activePlayers, 1, -1 do activePlayers[i] = nil end
            for ped in pairs(coordsOf) do coordsOf[ped] = nil end
        end,

        ---Whether shape tests report a wall.
        setOccluded = function(value) occluded = value and true or false end,

        ---Scripts what QB.callback.trigger returns for one name on the client.
        ---Pass nothing to simulate a timed-out round trip.
        setCallbackResponse = function(name, ...)
            callbackResponses[name] = table.pack(...)
        end,

        ---Invokes a server callback the way qblib would, with an explicit src.
        invokeCallback = function(name, src, ...)
            local entry = serverCallbacks[name]
            if not entry then error(('mocks: no server callback named %s'):format(name), 2) end
            return entry.handler(src, ...)
        end,

        ---Fires a net event with `source` set, the way FXServer does.
        fireNet = function(name, src, ...)
            _G.source = src
            for _, fn in ipairs(netHandlers[name] or {}) do fn(...) end
        end,

        ---Delivers a server push to the client handler registered for it.
        deliverPush = function(name, payload)
            for _, fn in ipairs(netHandlers['__push:' .. name] or {}) do fn(payload) end
        end,

        ---Fires a state-bag change the way FiveM does: the handler runs BEFORE
        ---the value is committed to the local store, so a handler that re-reads
        ---the bag instead of using its `value` argument sees the stale value and
        ---fails the test. This is not pedantry -- it is the exact shape of a bug
        ---this server has already shipped once.
        fireBagChange = function(bagName, key, value)
            for _, listener in ipairs(stateListeners) do
                local keyMatch = listener.key == nil or listener.key == key
                local bagMatch = listener.bagName == nil or listener.bagName == bagName
                if keyMatch and bagMatch then
                    listener.handler({ bagName = bagName, key = key, value = value, entity = 0, replicated = true })
                end
            end
        end,

        ---Every recorded native call with a given name.
        nativesNamed = function(name)
            local out = {}
            for _, call in ipairs(natives) do
                if call.name == name then out[#out + 1] = call end
            end
            return out
        end,

        ---Index of the first recorded call to `name`, or nil.
        nativeIndex = function(name)
            for index, call in ipairs(natives) do
                if call.name == name then return index end
            end
            return nil
        end,

        ---Every push sent to one player.
        pushesTo = function(src)
            local out = {}
            for _, push in ipairs(pushes) do
                if push.src == src then out[#out + 1] = push end
            end
            return out
        end,

        ---Every bag write for one player and key.
        writesFor = function(src, key)
            local out = {}
            for _, write in ipairs(bagWrites) do
                if write.src == src and write.key == key then out[#out + 1] = write end
            end
            return out
        end,

        clear = function()
            for i = #bagWrites, 1, -1 do bagWrites[i] = nil end
            for i = #pushes, 1, -1 do pushes[i] = nil end
            for i = #natives, 1, -1 do natives[i] = nil end
            for i = #localEvents, 1, -1 do localEvents[i] = nil end
            for i = #notifications, 1, -1 do notifications[i] = nil end
            for i = #sounds, 1, -1 do sounds[i] = nil end
        end,
    }
end

return M
