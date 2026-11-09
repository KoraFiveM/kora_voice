Config = {}

-- Development commands and verbose logging. Off by default; server/dev.lua
-- self-disables entirely unless this is true, so a production server carries no
-- command surface for setting its own radio channel.
Config.debug = false

-- --- proximity --------------------------------------------------------------
--
-- The ordered list of talk ranges the cycle key walks. ORDER IS THE UI: the
-- cycle key steps 1 -> 2 -> 3 -> 1, so these must read quietest-to-loudest or
-- the key feels wrong. `name` is the stable identifier every export and the
-- state bag publish; `label` is the only string a player ever sees.
--
-- Ranges are metres and are passed to Mumble as the audio input/output
-- distance. They are deliberately NOT symmetric with GTA's own voice ranges:
-- Mumble owns the audio entirely once this resource is running.
Config.proximity = {
    modes = {
        { name = 'whisper', label = 'Whisper', range = 3.0 },  -- same-table conversation
        { name = 'normal',  label = 'Normal',  range = 12.0 }, -- the default, a room or a pavement
        { name = 'shout',   label = 'Shout',   range = 35.0 }, -- across a street
    },

    -- Index into `modes` a player starts on, and returns to on respawn. Stored
    -- as an INDEX rather than a name because the cycle is index arithmetic and
    -- a name would have to be resolved back to one on every keypress.
    default = 2,

    -- Whether the cycle wraps past the last mode back to the first. With this
    -- false the key saturates at both ends, which some servers prefer because
    -- "one more press" can then never quietly drop a shouting player to a
    -- whisper mid-sentence.
    wrap = true,

    -- Told to the player when the mode changes. A silent range change is
    -- indistinguishable from a broken key, and the player has no other way to
    -- tell how far they are being heard.
    notify = true,
}

-- --- radio ------------------------------------------------------------------
Config.radio = {
    -- Inclusive channel id range. Channels are plain integers: they are the
    -- thing a job resource, a phone app and a physical radio item all have to
    -- agree on, and an integer is the only identifier all three can round-trip
    -- through a numeric keypad without a lookup table.
    minChannel = 1,
    maxChannel = 1000,

    -- Inventory item that opens the frequency dialog (server/item.lua registers
    -- the use handler under this name). The item definition itself lives in
    -- kora_core; change both together.
    item = 'radio',

    -- Channels a player may NOT simply join. The key is the channel id; the
    -- value declares who may. This is the SERVER's list -- a client never sees
    -- it and never evaluates it, because a client that decides its own
    -- eligibility is a client that can listen to the police tac channel.
    --
    -- `jobs` matches a kora_core job NAME, `jobTypes` a kora_core job TYPE (so 'leo'
    -- covers police, sheriff and state troopers at once). `onDuty` requires the
    -- player be clocked on, which is what stops an off-duty officer sitting on
    -- the tac channel while playing a civilian.
    --
    -- Any channel absent from this table is OPEN. That default is deliberate:
    -- a whitelist would make every unconfigured server's radio completely dead,
    -- and "the radio does nothing" is a far worse first-run experience than
    -- "channel 400 is not restricted yet".
    restricted = {
        [1]  = { label = 'LEO Dispatch', jobTypes = { 'leo' }, onDuty = true },
        [2]  = { label = 'LEO Tac 1',    jobTypes = { 'leo' }, onDuty = true },
        [10] = { label = 'EMS Dispatch', jobTypes = { 'ems' }, onDuty = true },
        [20] = { label = 'Recovery',     jobTypes = { 'recovery' } }, -- towing works off duty
    },

    -- Message a player gets when the server refuses a channel. Kept generic on
    -- purpose: naming the job that WOULD be allowed tells every civilian which
    -- channel the police are on, which is exactly the reconnaissance the
    -- restriction exists to prevent.
    refusedMessage = 'That frequency is restricted.',

    -- Radio talk is push-to-talk on its own key, independent of proximity talk.
    -- Two separate keys is the whole point: a player has to be able to say
    -- something to the room without it going out over the air.
    submix = true,      -- run received radio audio through the radio submix
    clicks = true,      -- play a click on transmit start/stop

    -- Frontend sounds for the transmit click. Frontend (2D) rather than
    -- positional -- it is the player's own radio, not a world object.
    clickOn  = { name = 'Menu_Accept',      set = 'Phone_SoundSet_Default' },
    clickOff = { name = 'Highlight_Cancel', set = 'DLC_HEIST_PLANNING_BOARD_SOUNDS' },
}

-- --- calls ------------------------------------------------------------------
--
-- A call channel is a SECOND, completely independent membership. A player can
-- be transmitting on the radio and in a phone call at the same time, and both
-- audio paths stay live -- which is why call membership is its own store, its
-- own state bag key and its own voice-target contribution rather than a flag on
-- the radio channel.
Config.calls = {
    minChannel = 1,
    maxChannel = 999999999, -- phone resources use the phone NUMBER as the channel id, so this has to clear nine digits

    -- Call audio is always live once joined -- there is no push-to-talk for a
    -- phone call, because holding a key to speak into a phone is not what a
    -- phone is. Proximity talk continues alongside it.
    submix = false, -- phone audio through the radio submix; off, phones sound clean
}

-- --- mumble / voice targets -------------------------------------------------
Config.mumble = {
    -- Mumble supports several numbered voice targets; this resource uses
    -- exactly ONE and rebuilds it. Mixing targets would mean tracking which
    -- target held which membership, and a stale target is a player who can
    -- still hear a channel they left.
    targetId = 1,

    -- ms between voice-target rebuilds. This is the single most important
    -- performance number in the resource: the rebuild walks every nearby player
    -- plus every channel member, so it must NOT be per-frame. 500ms is well
    -- inside human tolerance for "someone joined my channel and I can hear
    -- them", and costs 2 rebuilds a second instead of 60.
    refreshInterval = 500,

    -- Rebuild immediately (rather than waiting up to refreshInterval) when
    -- membership changes. Without this, joining a channel has a visible delay
    -- before you can be heard, which reads as the radio being broken.
    refreshOnChange = true,
}

-- --- submixes ---------------------------------------------------------------
--
-- The radio-effect parameter names are GTA's own, hashed at call time. They are
-- hashed with GetHashKey rather than CFX backtick literals ON PURPOSE: a
-- backtick literal is not valid Lua 5.4, so a file containing one cannot be
-- loaded by the plain-Lua smoke tests and dies SILENTLY when dofile'd.
Config.submix = {
    -- Received radio audio: band-limited and ring-modulated, the classic
    -- handheld sound.
    radio = {
        name = 'qbvoice_radio',
        effectSlot = 0,
        params = {
            freq_low    = 300.0,
            freq_hi     = 5000.0,
            fudge       = 0.0,
            rm_mod_freq = 0.0,
            rm_mix      = 0.16,
            o_freq_lo   = 348.0,
            o_freq_hi   = 4900.0,
        },
    },

    -- Megaphone: a much wider band than the radio, because a megaphone is loud
    -- and harsh rather than thin. Distinct submix so a player on the radio and
    -- a player on a megaphone never sound the same.
    megaphone = {
        name = 'qbvoice_megaphone',
        effectSlot = 1,
        params = {
            freq_low    = 300.0,
            freq_hi     = 6000.0,
            fudge       = 0.0,
            rm_mod_freq = 0.0,
            rm_mix      = 0.0,
            o_freq_lo   = 120.0,
            o_freq_hi   = 6000.0,
        },
        -- Metres. A megaphone overrides the talker's proximity mode entirely
        -- while it is held; it is not a fourth entry in Config.proximity.modes
        -- because it also changes the submix, which a proximity mode cannot.
        range = 50.0,
    },
}

-- --- muffling ---------------------------------------------------------------
--
-- Walls. A player on the other side of a door is heard at a reduced volume
-- rather than at full strength, which is what makes an interior feel like an
-- interior. Implemented as a Mumble per-speaker volume override, NOT as a
-- proximity change: proximity is symmetric and shared, occlusion is per-pair.
Config.muffling = {
    enabled = true,

    -- Volume multiplier applied to an occluded speaker. Not 0.0 -- a completely
    -- silenced neighbour is indistinguishable from a disconnected one, and
    -- players legitimately need to hear shouting through a door.
    occludedVolume = 0.25,

    -- Only players inside this many metres are LOS-tested. The probe is a
    -- synchronous shape test, so this cap is what keeps the rebuild bounded:
    -- without it a 32-player server on shout range would fire 31 probes every
    -- refresh.
    maxDistance = 20.0,

    -- Test at chest height rather than at the ped origin. A ray between two
    -- ped origins clips the ground on any slope and reports every player on a
    -- hill as occluded.
    heightOffset = 0.7,
}

-- --- routing buckets --------------------------------------------------------
--
-- Two players in different routing buckets are in different worlds. Radio and
-- call membership is a SERVER fact and knows nothing about buckets, so without
-- this filter a player in an instanced apartment would be audible on the
-- channel to someone in the main world -- and, worse, Mumble would happily
-- carry the audio, since Mumble has no concept of a bucket at all.
Config.buckets = {
    -- Restrict radio/call audio to members sharing the listener's bucket. Turn
    -- this off only on a server that deliberately uses radio as a
    -- cross-instance channel (an admin bucket calling into the main world).
    enforce = true,
}

-- --- state bag keys ---------------------------------------------------------
--
-- The keys this resource publishes on a player's state bag. They are config so
-- a consumer (a HUD, a phone, a job script) can name them once rather than
-- hard-coding a string this resource might rename.
--
-- CLEARING CONVENTION: every one of these is cleared by writing an explicit
-- `false`, never by writing nil. A nil write is a key DELETION, and a deletion
-- does not replicate to clients the way a value change does -- a client would
-- keep reading the last channel forever and keep rendering itself on a channel
-- it had left.
Config.state = {
    radio = 'qbvoice:radio', -- integer channel, or false for "not on a radio"
    call  = 'qbvoice:call',  -- integer channel, or false for "not in a call"

    -- Replicate membership to every client, not just the owner. FiveM has no
    -- owner-only player bag: a replicated key is visible to everybody. That is
    -- accepted here because knowing a player is on channel 2 is not the exploit
    -- -- being able to LISTEN to channel 2 is, and listening is gated by the
    -- server-built voice target, not by this key. Set false on a server that
    -- would rather other players could not see channel numbers at all; the
    -- owner still learns its own membership through the roster push.
    replicate = true,
}

-- --- keybinds ---------------------------------------------------------------
--
-- Defaults only. Every one goes through Kora.keybind.add, so all of them appear
-- in FiveM's own key-binding settings and every player can rebind them.
Config.keybinds = {
    cycleProximity = 'GRAVE',      -- step whisper -> normal -> shout (the grave/tilde key)
    radioTalk      = 'CAPITAL',    -- push-to-talk on the radio channel (caps lock)
    megaphone      = '',           -- unbound by default; a megaphone is a vehicle/prop feature
}

-- --- compatibility ----------------------------------------------------------
Config.compat = {
    -- Register the `pma-voice` export identity and the `pma-voice:*` events, so
    -- a resource written against pma-voice keeps working unchanged. Costs
    -- nothing when unused: they are event handler registrations, not threads.
    pmaVoice = true,

    -- Refuse to start when a real pma-voice folder is also running. Two
    -- resources both rebuilding the same Mumble voice target fight each other
    -- every tick and the symptom is intermittent, one-directional audio that
    -- looks like a network problem.
    refuseOnConflict = true,
}

-- --- rate limits ------------------------------------------------------------
--
-- Every client-facing callback is rate limited. A join request is cheap but it
-- is also the one message a client can send unprompted, and an unbounded one
-- lets a client walk every channel id on the server looking for an open one.
Config.rateLimit = {
    radio = { max = 10, window = 10000 }, -- 10 join/leave requests per 10s
    call  = { max = 10, window = 10000 },
    sync  = { max = 5,  window = 10000 }, -- resource-restart resync
}

-- Registers this resource-owned configuration with kora_lib without changing its public Config table.
if Kora and Kora.config and Kora.config.adopt then
    Config.radio.restricted = Kora.config.map(Config.radio.restricted, nil, {
        keyType = 'integer',
        scope = 'server',
        live = true,
        label = 'Restricted radio channels',
        description = 'Controls who may join each restricted radio channel. Each row key is a channel number; its value lists allowed jobs or job types and can require on-duty status. Channels omitted here remain open. Saved changes govern subsequent join requests without a resource restart; they do not remove players already listening. These rules remain server-only.',
    })
    Config = Kora.config.adopt(Config)
end
