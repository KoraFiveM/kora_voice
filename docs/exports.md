---
title: Exports
sidebar_position: 6
---

# Exports

Use `exports.kora_voice:name(...)`. The same names are also registered under `pma-voice` (see [Compatibility](./compatibility.md)).

## Server exports

All server exports that change membership are trusted: they skip the radio restriction policy and must only be called from server code.

| Export | Returns | Description |
| --- | --- | --- |
| `setPlayerRadio(src, channel)` | `ok, err` | Puts a player on a radio channel. nil, false or no value leaves. A given but invalid channel returns `false` and an error string. |
| `addPlayerToRadio(src, channel)` | `ok, err` | Alias of `setPlayerRadio`. |
| `removePlayerFromRadio(src, channel)` | `removed` | Removes the player from the radio. If a valid `channel` is given, only when the player is on exactly that channel. |
| `setPlayerCall(src, channel)` | `ok, err` | Puts a player on a call channel (not policy checked). |
| `removePlayerFromCall(src, channel)` | `removed` | Same guard behaviour as radio removal. |
| `getPlayersInRadioChannel(channel)` | table | Map of server id to `true`. |
| `getPlayersInCall(channel)` | table | Map of server id to `true`. |
| `getRadioMembers(channel)` | array | Sorted server ids. |
| `getRadioChannel(src)` | channel or `false` | The player's radio channel. |
| `getCallChannel(src)` | channel or `false` | The player's call channel. |
| `grantRadioChannels(src, channels)` | count | Lets the player join the listed channels regardless of `Config.radio.restricted`. Accepts a number or a list; replaces any previous grant. Hooks and channel checks still run first. |
| `revokeRadioChannels(src)` | `0` | Clears the player's grants. |
| `addRadioPolicy(fn)` | handle | Registers a hook `fn(src, channel)` returning `false, reason`, `true`, or nil to abstain. |
| `removeRadioPolicy(handle)` | boolean | Removes a hook by handle. |
| `addChannelCheck(channel, fn)` | none | Registers a check `fn(src)` that alone decides joins for that channel; only `true` allows. Raises an error for an invalid channel or non-callable `fn`. |
| `removeChannelCheck(channel)` | none | Removes the check. |
| `isChannelRestricted(channel)` | boolean | Whether `Config.radio.restricted` lists the channel. |
| `refreshVoiceTargets(src)` | `ok, err` | Re-pushes the player's current radio and call rosters, for use after a routing bucket change. Does nothing when `Config.buckets.enforce` is false. |

Server code that moves players between routing buckets with the raw `SetPlayerRoutingBucket` native should call `refreshVoiceTargets` or trigger the server-local event `kora_voice:server:bucketChanged`.

A channel check provider stops counting when its resource stops: joins to that channel are then refused until the provider registers again.

## Client exports

Client exports never change membership directly; the channel ones are requests.

| Export | Returns | Description |
| --- | --- | --- |
| `addPlayerToRadio(channel)` | `ok, reason` | Requests a channel through the server. Must run in a coroutine. `false, nil` means the round trip timed out; `false, reason` is a refusal. `true` means the server agreed; the local state follows from the published value. |
| `removePlayerFromRadio()` | boolean | Leaves the radio. |
| `removePlayerFromCall()` | boolean | Leaves the call. |
| `getRadioChannel()` | channel or `false` | Server-published channel. |
| `getCallChannel()` | channel or `false` | Server-published call channel. |
| `setTalkingMode(mode)` | `index, range` | Mode by index or name. |
| `cycleTalkingMode(step)` | `index, range` | Steps modes; default step 1. Shows a notification when `Config.proximity.notify` is on. |
| `getTalkingMode()` | table | `index`, `name`, `label`, `range` (current range, including megaphone). |
| `isRadioActive()` | boolean | True while the radio key is held and a channel is set. |
| `setMegaphone(active)` | boolean | Switches megaphone range on or off; returns whether it changed. Does not fire the `kora_voice:client:megaphone` event (only the keybind does). |
| `setRadioVolume(volume)`, `setCallVolume(volume)` | applied | 0.0 to 1.0, or 0 to 100 (values above 1 are treated as percentages). |
| `setVoiceProperty(name, value)` | boolean | Sets `radioVolume`, `callVolume`, `micClicks`, `submix`, `talkingMode` or `muffling`. An unknown name prints a console line and returns `false`. |
| `getVoiceProperty(name)` | any | Reads the same properties, plus `radioChannel` and `callChannel`. nil for unknown names. |
| `refreshVoiceTargets()` | boolean | Forces a voice target rebuild from the last server rosters; it does not request new ones. |
