---
title: Configuration
sidebar_position: 4
---

# Configuration

All options are in `config.lua`, loaded as a shared script. The restricted channel table is registered with `kora_lib` config adoption (server scope, live) when `Kora.config` is available, so saved changes govern subsequent join requests without a restart; they do not remove players already listening. This is the only place the resource uses that mechanism.

## General

| Option | Default | Description |
| --- | --- | --- |
| `Config.debug` | `false` | Enables the console debug commands in `server/dev.lua`. See [Commands](./commands.md). |

## Proximity

| Option | Default | Description |
| --- | --- | --- |
| `Config.proximity.modes` | whisper 3.0, normal 12.0, shout 35.0 | Ordered list of `name`, `label`, `range` (metres). Order is the cycle order, quietest first. |
| `Config.proximity.default` | `2` | Index of the starting mode, also applied on `kora_core:client:onPlayerLoaded`. Clamped into range. |
| `Config.proximity.wrap` | `true` | Whether the cycle wraps. When false, it stops at the ends. |
| `Config.proximity.notify` | `true` | Notify the player on a mode change made by the cycle. |

## Radio

| Option | Default | Description |
| --- | --- | --- |
| `Config.radio.minChannel`, `maxChannel` | `1`, `1000` | Inclusive valid channel range. |
| `Config.radio.item` | `'radio'` | Inventory item whose use opens the frequency dialog. Empty or non-string disables registration. |
| `Config.radio.restricted` | channels 1, 2 (leo, on duty), 10 (ems, on duty), 20 (recovery) | Map of channel to rule. Fields: `label` (informational), `jobs` (job names), `jobTypes` (job types), `onDuty` (boolean). A channel not listed is open; an entry with no `jobs` and no `jobTypes` is locked. |
| `Config.radio.refusedMessage` | `'That frequency is restricted.'` | Generic refusal message. |
| `Config.radio.submix` | `true` | Apply the radio effect to remote members outside earshot. Can also be changed at runtime with `setVoiceProperty`. |
| `Config.radio.clicks` | `true` | Play transmit click sounds. Runtime-changeable through `setVoiceProperty`. |
| `Config.radio.clickOn`, `clickOff` | see file | Frontend sound `name` and `set` for transmit start and stop. |

## Calls

| Option | Default | Description |
| --- | --- | --- |
| `Config.calls.minChannel`, `maxChannel` | `1`, `999999999` | Valid call channel range. |
| `Config.calls.submix` | `false` | Route call audio from members outside earshot through the radio effect. |

## Mumble and submixes

| Option | Default | Description |
| --- | --- | --- |
| `Config.mumble.targetId` | `1` | The single voice target the resource rebuilds. |
| `Config.mumble.refreshInterval` | `500` | Milliseconds between rebuilds. |
| `Config.mumble.refreshOnChange` | `true` | Rebuild immediately on membership or roster change. |
| `Config.submix.radio` | see file | `name`, `effectSlot`, and `params` (float parameters hashed by name). |
| `Config.submix.megaphone` | see file | Same fields plus `range` (metres, default `50.0`) used as the talk range while the megaphone is active. |

## Muffling and buckets

| Option | Default | Description |
| --- | --- | --- |
| `Config.muffling.enabled` | `true` | Enable wall muffling. Runtime-changeable through `setVoiceProperty`. |
| `Config.muffling.occludedVolume` | `0.25` | Volume multiplier for an occluded speaker. |
| `Config.muffling.maxDistance` | `20.0` | Only speakers within this many metres are tested. |
| `Config.muffling.heightOffset` | `0.7` | Height above each ped's origin for the probe. |
| `Config.buckets.enforce` | `true` | Filter pushed rosters by routing bucket on the server. Turn off only to allow radio across instances. |

## State, keybinds, compatibility, rate limits

| Option | Default | Description |
| --- | --- | --- |
| `Config.state.radio`, `call` | `'kora_voice:radio'`, `'kora_voice:call'` | Player state-bag key names. |
| `Config.state.replicate` | `true` | Replicate the keys to all clients. |
| `Config.keybinds.cycleProximity` | `'GRAVE'` | Default key for cycling the proximity mode. |
| `Config.keybinds.radioTalk` | `'CAPITAL'` | Default radio push-to-talk key. |
| `Config.keybinds.megaphone` | `''` | Default megaphone key; unbound by default. |
| `Config.compat.pmaVoice` | `true` | Register the pma-voice exports and events. |
| `Config.compat.refuseOnConflict` | `true` | Error at server start if a real pma-voice resource is running. Only evaluated when `Config.compat.pmaVoice` is true. |
| `Config.rateLimit.radio`, `call`, `sync` | 10 per 10000 ms, 10 per 10000 ms, 5 per 10000 ms | Per-player limits (`max`, `window` in ms) for radio requests, call leave requests and the resync callback. |

## Notes

- Key defaults only apply the first time; players can rebind in FiveM's key bindings. The keybind names are `kora_voice_proximity`, `kora_voice_radio` and `kora_voice_megaphone`.
- `Config.radio.clicks`, `Config.radio.submix` and `Config.muffling.enabled` are mutated at runtime on the client by `setVoiceProperty`, for that client only.
- `config.lua` is a `shared_script`, so FiveM delivers the file to clients; proximity, submix, muffling and keybind values are read on the client. No client code reads `Config.radio.restricted`, and the resource never sends it anywhere, but the file itself is shared. The `kora_lib` config adoption declares that table with `scope = 'server'`; whether that strips it from the client copy is a `kora_lib` behaviour that was not verified here.
