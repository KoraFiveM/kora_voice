---
title: "How to use"
sidebar_position: 3
---


# How to use

The authority model is the whole design: `Voice.api.assign`/`assignCall` are TRUSTED and reachable only from server-side export calls (a job resource, a phone resource); `Voice.api.request` is UNTRUSTED, policy-checked, and is the only path a client can reach at all, through a rate-limited kora_lib callback. No membership-changing function is ever exposed to a client for radio joins.

## Player experience

1. **Proximity** — The cycle key (`GRAVE` by default) steps whisper (3m) -> normal (12m) -> shout (35m) and back, applying the new range to every available Mumble distance native (current and legacy) and notifying the player of the new mode and range, unless `Config.proximity.notify` is off.

2. **Radio** — A radio channel is requested by this resource's own radio item dialog (see [Items](./items.md)) or by another resource's UI (a phone app) calling `exports.kora_voice:addPlayerToRadio(channel)` from the client, which asks the server and waits for the published state-bag value — it never assumes success locally. Holding the radio key (`CAPITAL` by default) transmits only while a channel is actually granted; releasing it, or never having a channel, transmits nothing.

3. **Restricted channels** — A channel listed in `Config.radio.restricted` additionally requires the player's kora_core job name or job type (and, for some entries, on-duty status) to match — evaluated purely on the server. The refusal message is deliberately generic (`Config.radio.refusedMessage`) so a civilian cannot learn which job would have been allowed just by trying restricted channel numbers.

4. **Calls** — A phone call is a second, fully independent membership (its own store, state-bag key, and voice-target contribution) so a player can transmit on the radio and be on a call simultaneously. Calls are never client-requestable to JOIN — only a trusted server export assigns both ends of a call — but a player may always leave their own call.

5. **Megaphone** — Holding a megaphone (set via `exports.kora_voice:setMegaphone(true)`, bound to a vehicle/prop by another resource, not to a bare key by default) overrides the player's proximity range to `Config.submix.megaphone.range` while held (no speaker is routed through the megaphone submix; see [Troubleshooting](./troubleshooting.md)), then restores whatever proximity mode they were on before.

6. **Wall muffling** — With `Config.muffling.enabled` (default on), a speaker on the far side of a synchronous line-of-sight probe is heard at a reduced (not silenced) volume — tested at chest height to avoid false positives on sloped ground, and only within `Config.muffling.maxDistance` to keep the per-rebuild cost bounded.

## Architecture: who may change what

- `server/store.lua` — pure membership bookkeeping (who is on which radio channel / call). No authority decision, no publication.
- `server/policy.lua` — the ONLY authority decision for radio joins: a legacy per-channel check, then ordered policy hooks (`addRadioPolicy`), then per-player grants (`grantRadioChannels`), then falling through to `Config.radio.restricted`. An empty restriction record (`{}`) satisfies nobody, by design — a channel marked restricted with nobody listed means locked, not open.
- `server/publish.lua` — the only place membership leaves the server: a replicated state-bag value (`kora_voice:radio`/`kora_voice:call`, "what channel am I on", visible to everyone) and a roster push over `Kora.events.push` ("whose audio may I receive", sent only to that channel's own members, filtered by routing bucket on the server, never the client).
- `server/api.lua` — the only file that actually changes membership, with TWO differently-named entry points: `Voice.api.assign`/`assignCall` (trusted, server callers only) and `Voice.api.request` (untrusted, policy-enforced, the only one reachable from `server/net.lua`). Different names rather than a `trusted` boolean flag are deliberate: a defaulted flag on the wrong call site is a client that can join the police channel; a missing function name is a hard error instead.
- `server/net.lua` — the client-facing surface: three rate-limited kora_lib callbacks (`kora_voice:requestRadio`, `kora_voice:leaveRadio`, `kora_voice:leaveCall`) plus a resync callback (`kora_voice:sync`). Nothing here can reach `Voice.api.assign`.
- `client/targets.lua` — the only place Mumble is told who may receive this player's audio. A single numbered voice target (`Config.mumble.targetId`) is cleared and rebuilt from three sources every tick: the local proximity grid, the server-pushed radio roster, and the server-pushed call roster — never extended locally.

## Server: assign a player to a radio channel (trusted)

```lua title="server.lua"
-- Server, from a job resource (TRUSTED path — no policy check)
exports.kora_voice:setPlayerRadio(src, 1) -- put an on-duty officer on LEO Dispatch
exports.kora_voice:setPlayerRadio(src, nil) -- take them off the radio entirely
```

## Server: connect two players in a phone call

```lua title="server.lua"
-- Server, from a phone resource: put two players in the same call channel
local channel = callerNumber -- the call channel id IS the phone number
exports.kora_voice:setPlayerCall(callerSrc, channel)
exports.kora_voice:setPlayerCall(calleeSrc, channel)
-- on hang up
exports.kora_voice:removePlayerFromCall(callerSrc)
exports.kora_voice:removePlayerFromCall(calleeSrc)
```

## Server: open a channel to your own job dynamically

Prefer `grantRadioChannels` (data-based, survives your own resource restarting) unless the decision genuinely must be made at request time.

```lua title="server.lua"
-- Server, from a job resource: open a frequency to your own members only
local handle = exports.kora_voice:addRadioPolicy(function(src, channel)
    if channel ~= 42 then return nil end -- abstain; let grants/config decide other channels
    local job = exports.kora_core:getJob(src)
    if job and job.name == 'mechanic' then return true end
    return false, 'That is the mechanics'' private channel.'
end)
-- later: exports.kora_voice:removeRadioPolicy(handle)
```

## Client: request a channel (the only client-reachable path)

```lua title="client.lua"
-- Client: ask the server for a radio channel (must run inside a coroutine)
local ok, reason = exports.kora_voice:addPlayerToRadio(2)
if ok == nil then
    -- the round trip timed out -- the server never actually refused
elseif not ok then
    print('refused: ' .. tostring(reason))
end
```
