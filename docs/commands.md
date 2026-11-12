---
title: "Commands"
sidebar_position: 4
---


# Commands

No in-game chat commands. Two console-only rcon commands exist purely for development and are completely absent unless `Config.debug = true`.

## Debug commands (Config.debug only)

### `voicedump`

Prints every occupied radio channel and its current member list to the server console.

| Field | Details |
| --- | --- |
| Context | Server console only (`src == 0`) |
| Arguments | none |
| Access | Server console only; refuses any in-game caller. Only registered at all when `Config.debug` is true, so a production server carries no command surface that could leak which frequencies are occupied. |

**Example**

```text
voicedump
```

**Result**

One console line per occupied channel: `[kora_voice] radio <n>: <src, src, ...>`.

### `voicerequest <src> <channel|0>`

Runs a radio join request AS that player, through the exact same untrusted/policy-checked path a real client uses (not the trusted assign path) — intended to let you exercise the policy layer from the console.

| Field | Details |
| --- | --- |
| Context | Server console only |
| Arguments | src — required, target player's server id. channel — required; 0 (or omitted/invalid) requests leaving the radio. |
| Access | Server console only. |

**Example**

```text
voicerequest 3 2
```

**Result**

Prints `[kora_voice] request(3, 2) -> true` or `-> false (<reason>)` to the console.

## Keybinds

All keybinds are registered through `Kora.keybind.add`, so they appear in FiveM's key binding settings and players can rebind them. Defaults come from `Config.keybinds`.

| Keybind name | Default | Behaviour |
| --- | --- | --- |
| `kora_voice_proximity` | `GRAVE` | Cycles the proximity mode by one step. |
| `kora_voice_radio` | `CAPITAL` (Caps Lock) | Push-to-talk on the current radio channel while held. Does nothing without a published channel. Plays click sounds if enabled and fires `kora_voice:client:radioActive`. |
| `kora_voice_megaphone` | unbound | Hold to use the megaphone range (`Config.submix.megaphone.range`). Restores the player's own mode on release. |

No keybind changes channel membership.

## Console command registration

There are no player commands. Two console-only commands are registered only when `Config.debug` is true; with it off the file registers nothing. Both are registered as restricted commands and both return immediately when run by a player (`source` is not 0), so they work from the server console only.

## Permissions

The resource defines no ACE permissions of its own. Channel access is controlled by job and duty from `kora_core`, grants, hooks and channel checks. See [Features](./features.md).
