---
title: Troubleshooting
sidebar_position: 10
---

# Troubleshooting

## The resource refuses to start

The console shows `kora_voice: pma-voice is running; stop it before starting kora_voice`. A real `pma-voice` resource is started. Stop it. The check can be switched off with `Config.compat.refuseOnConflict`, but two resources then fight over the same Mumble voice target, which shows up as one-directional audio.

## The radio key does nothing

The key only transmits on a channel the server has published. Check `exports.kora_voice:getRadioChannel()` on the client. Pressing the key with no channel is silent by design.

## Joining a channel is refused

`That frequency is restricted.` is the generic message. Check the channel in `Config.radio.restricted`: the player's `kora_core` job name or type must match, and `onDuty` requires the job to be on duty. A channel entry with no `jobs` and no `jobTypes` is locked to everyone. If `kora_core` is stopped or restarting, restricted channels are refused. Also check registered channel checks and policy hooks from other resources.

## Rate limit messages

`Voice request limit reached.` means a player exceeded `Config.rateLimit` for radio or call requests.

## The radio item does nothing

Check that an item named `Config.radio.item` exists, that `kora_core` could register it (the console prints `could not register the radio use handler` otherwise), and restart `kora_inventory` or this resource so the handler is registered again.

## Phone calls cannot be joined from a client

By design. The phone resource must assign both participants with the `setPlayerCall` server export.

## Players in another routing bucket still hear a channel

Check that `Config.buckets.enforce` is true. After changing buckets with the raw native, call the `refreshVoiceTargets` server export or trigger `kora_voice:server:bucketChanged`.

## The megaphone has no radio-style effect

The megaphone submix is created from `Config.submix.megaphone` but no code routes a speaker through it; the megaphone only changes the talk range. Changing its `params` has no audible effect.

## Debug commands are not found

`voicedump` and `voicerequest` exist only when `Config.debug` is true and only run from the server console.
