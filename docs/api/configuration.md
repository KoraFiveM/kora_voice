---
title: "Configuration"
sidebar_position: 6
---


# Configuration

A single shared `Config` table, heavily commented in the source with the reasoning behind each default. `Config.radio.restricted` is additionally registered with kora_lib's `/config` as a live, server-scoped map (`Kora.config.map`), so an admin can edit who may join a restricted channel without a resource restart — though editing does not remove players already listening on a channel they would no longer be allowed to join.

Namespace: `Config` · Source: `config.lua`

## All options

Every key of `Config` in `config.lua`. See the source comments for the full reasoning behind each default; this table summarizes effect and apply-timing.

| Key | Type | Default | Effect | Applies |
| --- | --- | --- | --- | --- |
| debug | boolean | false | Enables the `voicedump`/`voicerequest` console commands. Off by default so a production server carries no debug command surface. | Restart. |
| proximity.modes | table[] | whisper 3.0m, normal 12.0m, shout 35.0m | Ordered talk-range set the cycle key walks. Order IS the UI: must read quietest to loudest. | Restart. |
| proximity.default | integer | 2 (normal) | Starting/respawn mode index, itself clamped into range. | Restart. |
| proximity.wrap | boolean | true | Whether the cycle wraps past the last mode back to the first, vs. saturating at both ends. | Restart. |
| proximity.notify | boolean | true | Whether the player is told their new mode/range on every change. | Immediately. |
| radio.minChannel / maxChannel | integer | 1 / 1000 | Inclusive valid radio channel id range. | Restart. |
| radio.restricted | table&lt;integer, record> | LEO Dispatch/Tac 1, EMS Dispatch, Recovery | Per-channel restriction records (`label`, `jobs`, `jobTypes`, `onDuty`). A channel absent here is OPEN by default. | Immediately (server-only check). |
| radio.refusedMessage | string | That frequency is restricted. | Generic refusal text, deliberately not naming which job would be allowed. | Immediately. |
| radio.submix / clicks | boolean | true / true | Whether received radio audio is band-limited, and whether a click plays on transmit start/stop. | Immediately (client). |
| radio.clickOn / clickOff | &#123; name, set &#125; | Menu_Accept / Highlight_Cancel | Frontend sound played via `Kora.sound.playFrontend` for radio key press/release. | Immediately (client). |
| calls.minChannel / maxChannel | integer | 1 / 999999999 | Call channel id range (wide, since phone resources use the phone number as the id). | Restart. |
| calls.submix | boolean | false | Whether call audio is also routed through the radio submix. Off by default: a phone call should not sound like a handheld radio. | Immediately (client). |
| mumble.targetId | integer | 1 | The single numbered Mumble voice target this resource owns and rebuilds. | Restart. |
| mumble.refreshInterval | integer (ms) | 500 | Bounded voice-target rebuild tick. The single most important performance number in the resource -- NOT per-frame. | Restart. |
| mumble.refreshOnChange | boolean | true | Rebuild immediately on a membership change instead of waiting for the next tick. | Restart. |
| submix.radio / submix.megaphone | table | see config.lua | GTA radio-effect parameters (frequency band, ring-mod) for each submix, hashed with `GetHashKey` (not CFX backtick literals, which would break the plain-Lua smoke tests). | Restart. |
| muffling.enabled | boolean | true | Wall occlusion via a per-speaker Mumble volume override, not a proximity change (occlusion is per-pair, proximity is symmetric/shared). | Immediately (client). |
| muffling.occludedVolume | number | 0.25 | Volume multiplier for an occluded speaker. Deliberately not 0.0 -- a fully silenced neighbour looks identical to a disconnected one. | Immediately. |
| muffling.maxDistance | number | 20.0 | Only players within this range are LOS-tested, bounding the per-rebuild shape-test cost. | Immediately. |
| muffling.heightOffset | number | 0.7 | Probe height above the ped origin (chest height), to avoid false occlusion on sloped ground. | Immediately. |
| buckets.enforce | boolean | true | Filters radio/call audio to members sharing the listener's routing bucket. Mumble has no bucket concept, so the server does this filtering, not the client. | Immediately (server). |
| state.radio / state.call | string | kora_voice:radio / kora_voice:call | State-bag key names published to every client. Config, not hard-coded, so a HUD/phone/job script can name them once. | Restart (consumers should read these names, not hard-code them). |
| state.replicate | boolean | true | Whether radio/call membership is visible to every client (not just the owner) via the state bag. Set false to hide channel numbers from other players -- listening is still gated by the server-built voice target either way, not by this key. | Immediately. |
| keybinds.cycleProximity / radioTalk / megaphone | string | GRAVE / CAPITAL / '' (unbound) | Default FiveM key bindings; every one goes through `Kora.keybind.add`, so players can rebind any of them in FiveM's own settings. | Restart. |
| compat.pmaVoice | boolean | true | Registers the `pma-voice` export identity and `pma-voice:*` events for drop-in compatibility. Costs nothing when unused. | Restart. |
| compat.refuseOnConflict | boolean | true | Refuses to start (errors) if a real, separately-started `pma-voice` resource folder is also running. | Restart. |
| rateLimit.radio / call / sync | &#123; max, window &#125; | 10/10s, 10/10s, 5/10s | Sliding-window rate limits per player per client-facing callback. | Restart. |

## How it works

Most values are read once at a natural point (resource start, a rebuild's capture of the tick interval) and flagged Restart below; values flagged Immediately are read fresh at the point of use, which for anything evaluated on the server (the whole of `radio.restricted`, `buckets.enforce`) means an edit governs the very next request without any restart.

## Options

Each option as a `Config` path with its default and apply timing; edit `config.lua` and restart unless the row says Immediately.

| Option | Type | Description |
| --- | --- | --- |
| `debug` | boolean | Default false. Enables the `voicedump`/`voicerequest` console commands. Off by default so a production server carries no debug command surface. Applies: Restart. |
| `proximity.modes` | table[] | Default whisper 3.0m, normal 12.0m, shout 35.0m. Ordered talk-range set the cycle key walks. Order IS the UI: must read quietest to loudest. Applies: Restart. |
| `proximity.default` | integer | Default 2 (normal). Starting/respawn mode index, itself clamped into range. Applies: Restart. |
| `proximity.wrap` | boolean | Default true. Whether the cycle wraps past the last mode back to the first, vs. saturating at both ends. Applies: Restart. |
| `proximity.notify` | boolean | Default true. Whether the player is told their new mode/range on every change. Applies: Immediately. |
| `radio.minChannel / maxChannel` | integer | Default 1 / 1000. Inclusive valid radio channel id range. Applies: Restart. |
| `radio.restricted` | table&lt;integer, record> | Default LEO Dispatch/Tac 1, EMS Dispatch, Recovery. Per-channel restriction records (`label`, `jobs`, `jobTypes`, `onDuty`). A channel absent here is OPEN by default. Applies: Immediately (server-only check). |
| `radio.refusedMessage` | string | Default That frequency is restricted.. Generic refusal text, deliberately not naming which job would be allowed. Applies: Immediately. |
| `radio.submix / clicks` | boolean | Default true / true. Whether received radio audio is band-limited, and whether a click plays on transmit start/stop. Applies: Immediately (client). |
| `radio.clickOn / clickOff` | &#123; name, set &#125; | Default Menu_Accept / Highlight_Cancel. Frontend sound played via `Kora.sound.playFrontend` for radio key press/release. Applies: Immediately (client). |
| `calls.minChannel / maxChannel` | integer | Default 1 / 999999999. Call channel id range (wide, since phone resources use the phone number as the id). Applies: Restart. |
| `calls.submix` | boolean | Default false. Whether call audio is also routed through the radio submix. Off by default: a phone call should not sound like a handheld radio. Applies: Immediately (client). |
| `mumble.targetId` | integer | Default 1. The single numbered Mumble voice target this resource owns and rebuilds. Applies: Restart. |
| `mumble.refreshInterval` | integer (ms) | Default 500. Bounded voice-target rebuild tick. The single most important performance number in the resource -- NOT per-frame. Applies: Restart. |
| `mumble.refreshOnChange` | boolean | Default true. Rebuild immediately on a membership change instead of waiting for the next tick. Applies: Restart. |
| `submix.radio / submix.megaphone` | table | Default see config.lua. GTA radio-effect parameters (frequency band, ring-mod) for each submix, hashed with `GetHashKey` (not CFX backtick literals, which would break the plain-Lua smoke tests). Applies: Restart. |
| `muffling.enabled` | boolean | Default true. Wall occlusion via a per-speaker Mumble volume override, not a proximity change (occlusion is per-pair, proximity is symmetric/shared). Applies: Immediately (client). |
| `muffling.occludedVolume` | number | Default 0.25. Volume multiplier for an occluded speaker. Deliberately not 0.0 -- a fully silenced neighbour looks identical to a disconnected one. Applies: Immediately. |
| `muffling.maxDistance` | number | Default 20.0. Only players within this range are LOS-tested, bounding the per-rebuild shape-test cost. Applies: Immediately. |
| `muffling.heightOffset` | number | Default 0.7. Probe height above the ped origin (chest height), to avoid false occlusion on sloped ground. Applies: Immediately. |
| `buckets.enforce` | boolean | Default true. Filters radio/call audio to members sharing the listener's routing bucket. Mumble has no bucket concept, so the server does this filtering, not the client. Applies: Immediately (server). |
| `state.radio / state.call` | string | Default kora_voice:radio / kora_voice:call. State-bag key names published to every client. Config, not hard-coded, so a HUD/phone/job script can name them once. Applies: Restart (consumers should read these names, not hard-code them). |
| `state.replicate` | boolean | Default true. Whether radio/call membership is visible to every client (not just the owner) via the state bag. Set false to hide channel numbers from other players -- listening is still gated by the server-built voice target either way, not by this key. Applies: Immediately. |
| `keybinds.cycleProximity / radioTalk / megaphone` | string | Default GRAVE / CAPITAL / '' (unbound). Default FiveM key bindings; every one goes through `Kora.keybind.add`, so players can rebind any of them in FiveM's own settings. Applies: Restart. |
| `compat.pmaVoice` | boolean | Default true. Registers the `pma-voice` export identity and `pma-voice:*` events for drop-in compatibility. Costs nothing when unused. Applies: Restart. |
| `compat.refuseOnConflict` | boolean | Default true. Refuses to start (errors) if a real, separately-started `pma-voice` resource folder is also running. Applies: Restart. |
| `rateLimit.radio / call / sync` | &#123; max, window &#125; | Default 10/10s, 10/10s, 5/10s. Sliding-window rate limits per player per client-facing callback. Applies: Restart. |

## Functions

No functions are exported from this module; it is plain config read directly by the other modules.

## Limits and related APIs

`config.lua` is a shared script, so it loads identically into both VMs; `Config.radio.restricted`'s live-editability through `/config` is server-scoped specifically because a client must never see the restriction table at all.

## Additional options

Options present in `config.lua` that the tables above do not list.

| Option | Default | Description |
| --- | --- | --- |
| `Config.radio.item` | `'radio'` | Inventory item whose use opens the frequency dialog (`server/item.lua` registers the use handler under this name). Empty or non-string disables registration. See [Items](../items.md). |

## Notes


- Key defaults only apply the first time; players can rebind in FiveM's key bindings. The keybind names are `kora_voice_proximity`, `kora_voice_radio` and `kora_voice_megaphone`.
- `Config.radio.clicks`, `Config.radio.submix` and `Config.muffling.enabled` are mutated at runtime on the client by `setVoiceProperty`, for that client only.
- `config.lua` is a `shared_script`, so FiveM delivers the file to clients; proximity, submix, muffling and keybind values are read on the client. No client code reads `Config.radio.restricted`, and the resource never sends it anywhere, but the file itself is shared. The `kora_lib` config adoption declares that table with `scope = 'server'`; whether that strips it from the client copy is a `kora_lib` behaviour that was not verified here.
