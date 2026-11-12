---
title: Features
sidebar_position: 6
---

# Features

## The authority boundary

Channel membership lives on the server. A client may send a request; the server decides, stores and publishes the result. Everything a player can hear comes from a Mumble voice target built from what the server published, so a client that could write its own membership could listen to any channel.

- `Config.radio.restricted` is evaluated only on the server, and no export, push or state-bag key in this resource carries it to a client. (`config.lua` itself is a shared script; see [Configuration](./api/configuration.md).)
- Two server entry points: `assign` (trusted, no policy check, reachable only through server exports) and `request` (untrusted, policy enforced, used by the client callbacks and the pma-voice compatibility events). The two are deliberately different function names rather than one function with a trust flag.
- Client net events and callbacks always act on `source`, never on a player id in the payload.
- Clients replace their roster with exactly what the server pushed and never extend it.
- There is no client-reachable way to join a call. Leaving a call or the radio is always allowed.
- Every client-facing route (kora_lib callbacks and pma-voice events) passes through a per-player rate limiter, see `Config.rateLimit`.

## Proximity

Modes are listed in `Config.proximity.modes` and walked by index. The defaults are whisper (3 m), normal (12 m) and shout (35 m). The cycle key steps through them; with `Config.proximity.wrap = false` the ends saturate instead of wrapping. With `Config.proximity.notify` on, the player gets a notification with the mode label and range on each change.

On each change the range is passed to `MumbleSetAudioInputDistance`, `MumbleSetAudioOutputDistance`, `MumbleSetTalkerProximity` and `NetworkSetTalkerProximity`, each only if the native exists in the running build.

The mode returns to `Config.proximity.default` when `kora_core:client:onPlayerLoaded` fires on the client. All mode indexes pass through one clamp, so an out-of-range value from an export or event never produces an unconfigured range.

## Radio

Channels are integers from `Config.radio.minChannel` to `Config.radio.maxChannel` (default 1 to 1000). Anything that does not normalise to a valid channel (nil, false, 0, an empty string, a non-number, an out-of-range number) means "no channel".

Transmission is push-to-talk on its own key (default Caps Lock). It only transmits when the player is on a server-published channel; pressing it with no channel does nothing. While the key is held, the channel roster is added to the voice target; on release the target is rebuilt immediately. Transmit start and stop play frontend click sounds when `Config.radio.clicks` is on.

Players join through the radio item dialog, or through the client export or the pma-voice compatibility events. All of these are requests that go through the policy decision below.

### Who may join a channel

For a client request the server evaluates, in order:

1. A channel check registered with `addChannelCheck` for that exact channel decides alone. Only an explicit `true` allows; a refusal, an error, or a stopped provider resource all deny.
2. Policy hooks registered with `addRadioPolicy`, in registration order. `false, reason` refuses, `true` allows, `nil` abstains. A hook that errors abstains and logs a console line.
3. A per-player grant from `grantRadioChannels`.
4. `Config.radio.restricted`. A channel not listed is open. A listed channel requires the player's `kora_core` job to match `jobs` (job name) or `jobTypes` (job type), and `onDuty = true` additionally requires the job to be on duty. An entry with neither `jobs` nor `jobTypes` is locked to everyone. If the job cannot be read from `kora_core`, the restricted channel is refused.

Refusals show `Config.radio.refusedMessage` unless a hook supplied its own reason.

Trusted server exports (`setPlayerRadio`, `addPlayerToRadio`) skip all of this.

A radio membership that was approved purely by the static job rules is "character owned": it is removed when the `QBCore:Server:OnPlayerUnload` event fires for that player (character logout). Memberships assigned through the trusted export, through a hook or through a grant are not removed by that event.

Grants and memberships are dropped when the player disconnects.

## Phone calls

A call channel is a second membership, independent of the radio, with its own state-bag key. A call and a radio transmission can be live at once. Call channels range from `Config.calls.minChannel` to `Config.calls.maxChannel` (default 1 to 999999999, so phone numbers fit).

Calls are not policy checked and cannot be joined by a client. A phone resource assigns both ends with the trusted `setPlayerCall` export. Call audio is always live once joined; there is no push-to-talk. A client may leave its call.

## Submixes

Two submixes are created once on the client: `radio` and `megaphone`, configured in `Config.submix`.

Radio audio is filtered by membership with an earshot exception: a channel member who is inside your proximity grid is heard unprocessed, and a member outside it is routed through the radio submix when `Config.radio.submix` is on. `Config.calls.submix` (default off) does the same for call members using the radio effect.

The megaphone submix is created but the resource does not route any speaker through it. The megaphone's effect today is its range: while `setMegaphone` is active, the talk range becomes `Config.submix.megaphone.range` instead of the proximity mode range. See [Troubleshooting](./troubleshooting.md).

`setRadioVolume` and `setCallVolume` apply to the same remote members that are outside the proximity grid. A speaker has a single Mumble volume override, so occlusion and the radio or call volume are combined and the quietest value wins.

## Muffling

With `Config.muffling.enabled`, speakers within `Config.muffling.maxDistance` metres are tested with a synchronous line-of-sight probe against world geometry at `Config.muffling.heightOffset` above each ped origin. An occluded speaker is heard at `Config.muffling.occludedVolume`. The override is removed when it is no longer wanted.

## Voice targets

One Mumble target, `Config.mumble.targetId`, is cleared and rebuilt on a timer every `Config.mumble.refreshInterval` milliseconds. With `Config.mumble.refreshOnChange` on, a membership change or roster push also triggers an immediate rebuild in its own thread. A reentrancy guard stops two rebuilds overlapping.

The target contains: players in the proximity grid within talk range, the radio roster only while the radio key is held on a channel, and the call roster while in a call. Members are added by server id so a radio member out of scope still works.

## Routing buckets

The server filters pushed rosters by routing bucket when `Config.buckets.enforce` is on (default). The grid needs no filter because `GetActivePlayers` already respects buckets. After a bucket change, call the server `refreshVoiceTargets` export or trigger the server-local event `kora_voice:server:bucketChanged`. See [Events](./events.md).

## State bags

The server writes the player's state bag keys named in `Config.state.radio` and `Config.state.call` (defaults `kora_voice:radio` and `kora_voice:call`). The value is the integer channel or `false`; clearing is always an explicit `false`, never nil. Both keys are written when a player joins. `Config.state.replicate` (default true) controls whether the keys are replicated to all clients.

## Late start and resync

On client start the resource waits for the session and a valid server id, arms its state-bag handlers, then calls the `kora_voice:sync` callback so that `ensure kora_voice` on a running server restores each player's membership.
