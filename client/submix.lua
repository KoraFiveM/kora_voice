-- Audio submixes: the radio effect and the megaphone effect.
--
-- A submix is a processing chain Mumble can route one SPEAKER through. That
-- per-speaker routing is what makes the radio sound right: the officer talking
-- over the air is band-limited, while the civilian standing next to you at the
-- same moment is not. A global effect could not do this.
--
-- PARAMETER NAMES ARE HASHED WITH GetHashKey, NOT WITH BACKTICK LITERALS. A
-- CFX backtick hash literal is not valid Lua 5.4, so any file containing one
-- cannot be loaded by the plain-Lua smoke tests -- and a test file that
-- dofile's it dies SILENTLY, printing its header and no summary. GetHashKey is
-- the same hash at a negligible runtime cost.

Voice = Voice or {}
Voice.submix = {}

local Sub = Voice.submix

-- kind -> submix id. Created once; CreateAudioSubmix allocates a real slot and
-- calling it again per transmission would exhaust the pool over a session.
local ids = {}

Sub.ids = ids

---@param name string
---@return integer|nil
local function hash(name)
    if type(joaat) == 'function' then return joaat(name) end
    return nil
end

---Builds one submix from its config block.
---@param kind 'radio'|'megaphone'
---@return integer|nil
local function create(kind)
    local spec = Config.submix[kind]
    if not spec then return nil end

    if type(CreateAudioSubmix) ~= 'function' then return nil end

    local id = CreateAudioSubmix(spec.name)
    -- CreateAudioSubmix returns -1 when the pool is full. Carrying on would
    -- apply every effect parameter to submix -1 and then route speakers into
    -- it, which silences them -- a far worse failure than no effect at all.
    if not id or id < 0 then
        print(('[qbvoice] could not create the %s submix; audio will be unprocessed'):format(kind))
        return nil
    end

    local slot = spec.effectSlot or 0
    SetAudioSubmixEffectRadioFx(id, slot)

    -- 'default' seeds the effect with GTA's own radio curve; every named float
    -- below then overrides one part of it. Without this int the other
    -- parameters apply on top of an unset chain and the result is nearly
    -- inaudible.
    local defaultParam = hash('default')
    if defaultParam and type(SetAudioSubmixEffectParamInt) == 'function' then
        SetAudioSubmixEffectParamInt(id, slot, defaultParam, 1)
    end

    if type(SetAudioSubmixEffectParamFloat) == 'function' then
        for name, value in pairs(spec.params or {}) do
            local param = hash(name)
            if param then SetAudioSubmixEffectParamFloat(id, slot, param, value + 0.0) end
        end
    end

    -- Route the submix to output 0 -- without an output the chain processes
    -- audio and then discards it, so a speaker routed here goes completely
    -- silent rather than sounding filtered.
    if type(AddAudioSubmixOutput) == 'function' then
        AddAudioSubmixOutput(id, spec.outputSlot or 0)
    end

    return id
end

---Creates both submixes if they do not exist yet. Idempotent.
---@return integer|nil radio, integer|nil megaphone
function Sub.ensure()
    if ids.radio == nil then ids.radio = create('radio') or false end
    if ids.megaphone == nil then ids.megaphone = create('megaphone') or false end

    return ids.radio or nil, ids.megaphone or nil
end

---Routes one speaker through a submix.
---@param serverId integer
---@param kind 'radio'|'megaphone'
---@return boolean applied
function Sub.applyTo(serverId, kind)
    Sub.ensure()

    local id = ids[kind]
    if not id then return false end
    if type(MumbleSetSubmixForServerId) ~= 'function' then return false end

    MumbleSetSubmixForServerId(serverId, id)
    return true
end

---Returns one speaker to unprocessed audio.
---
---Called for every speaker that is NOT currently on the radio, every rebuild,
---rather than only on the transition. A speaker whose submix was never cleared
---keeps the radio effect for the rest of the session -- and because it only
---affects how they sound, nobody reports it as a bug, they just say voice
---"sounds weird".
---@param serverId integer
---@return boolean cleared
function Sub.clearFor(serverId)
    if type(MumbleSetSubmixForServerId) ~= 'function' then return false end

    MumbleSetSubmixForServerId(serverId, -1)
    return true
end
