---
title: Events
sidebar_position: 7
---

# Events

## Local events emitted on the client

| Event | Payload | When |
| --- | --- | --- |
| `kora_voice:client:radioChanged` | channel or `false` | The published radio channel changed. |
| `kora_voice:client:callChanged` | channel or `false` | The published call channel changed. |
| `kora_voice:client:radioActive` | boolean | The radio key was pressed or released while on a channel (keybind only). |
| `kora_voice:client:megaphone` | boolean | The megaphone keybind was pressed or released. |
| `pma-voice:setRadioChannel` | channel or `0` | Emitted alongside `radioChanged` for pma-voice UIs. |
| `pma-voice:setCallChannel` | channel or `0` | Emitted alongside `callChanged`. |
| `pma-voice:radioActive` | boolean | Emitted alongside `radioActive`. |

## Local events emitted on the server

| Event | Payload | When |
| --- | --- | --- |
| `kora_voice:server:radioChanged` | `src, channel, previous` | A radio membership changed. Values are `false` for none. |
| `kora_voice:server:callChanged` | `src, channel, previous` | A call membership changed. |

## Local server events handled

| Event | Description |
| --- | --- |
| `kora_voice:server:bucketChanged` | Takes a player source and re-pushes that player's rosters. See `refreshVoiceTargets` in [Exports](./api/exports.md). |
| `playerDropped` | Forgets the player's memberships and grants and re-pushes the rosters they were in. |
| `QBCore:Server:OnPlayerUnload` | Removes a radio membership that was approved by the static job rules. See [Features](./features.md). |
| `playerJoining` | Writes the cleared state-bag values for the joining player. |
| `onResourceStart` | Re-registers the radio item when `kora_inventory` starts. |
| `onResourceStop` | Disables channel checks owned by the stopped resource. |

## Net events accepted from clients

These exist only when `Config.compat.pmaVoice` is true. Each is treated as an untrusted request for `source`; a player id in the payload is ignored. They go through the radio rate limit (`Config.rateLimit.radio`, or `call` for call leave).

| Event | Payload | Behaviour |
| --- | --- | --- |
| `pma-voice:setPlayerRadio` | channel | Request, policy enforced. |
| `pma-voice:addPlayerToRadio` | channel | Request, policy enforced. |
| `pma-voice:removePlayerFromRadio` | channel | Leave; if a valid channel is given, only if the player is on it. |
| `pma-voice:removePlayerFromCall` | channel | Leave the call, with the same guard. |

## Net events accepted by clients

| Event | Description |
| --- | --- |
| `kora_voice:client:openRadio` | Sent by the server when the radio item is used; opens the frequency dialog. |
| `pma-voice:setTalkingMode` | Sets the proximity mode (compat only). |
| `pma-voice:setVoiceProperty` | Sets a local voice property (compat only). |

`pma-voice:setRadioChannel` and `pma-voice:setCallChannel` are intentionally not registered as inbound events.

## kora_lib callbacks and pushes

| Name | Direction | Description |
| --- | --- | --- |
| `kora_voice:requestRadio` | client to server callback | Request a channel; returns `true`, or `false, reason`. Rate limited. |
| `kora_voice:leaveRadio` | client to server callback | Leave the radio. |
| `kora_voice:leaveCall` | client to server callback | Leave the call. Rate limited by `Config.rateLimit.call`. |
| `kora_voice:sync` | client to server callback | Re-publishes the caller's memberships and returns `radio` and `call`. Rate limited by `Config.rateLimit.sync`. |
| `kora_voice:radio:roster` | server push | Payload `channel`, `members`. Sent to the members of a radio channel, filtered by bucket. `channel = false` with no members when cleared. |
| `kora_voice:call:roster` | server push | Same for calls. |

## State bag keys

`Config.state.radio` and `Config.state.call` on the player state bag; see [Features](./features.md).
