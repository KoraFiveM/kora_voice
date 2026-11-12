---
title: Commands and keybinds
sidebar_position: 5
---

# Commands and keybinds

## Keybinds

All keybinds are registered through `Kora.keybind.add`, so they appear in FiveM's key binding settings and players can rebind them. Defaults come from `Config.keybinds`.

| Keybind name | Default | Behaviour |
| --- | --- | --- |
| `kora_voice_proximity` | `GRAVE` | Cycles the proximity mode by one step. |
| `kora_voice_radio` | `CAPITAL` (Caps Lock) | Push-to-talk on the current radio channel while held. Does nothing without a published channel. Plays click sounds if enabled and fires `kora_voice:client:radioActive`. |
| `kora_voice_megaphone` | unbound | Hold to use the megaphone range (`Config.submix.megaphone.range`). Restores the player's own mode on release. |

No keybind changes channel membership.

## Console commands

There are no player commands. Two console-only commands are registered only when `Config.debug` is true; with it off the file registers nothing. Both are registered as restricted commands and both return immediately when run by a player (`source` is not 0), so they work from the server console only.

| Command | Description |
| --- | --- |
| `voicedump` | Prints every occupied radio channel and its member server ids. |
| `voicerequest <src> <channel>` | Runs a request for player `src` through the untrusted `request` path (policy enforced) and prints the result. A channel of 0 leaves. |

## Permissions

The resource defines no ACE permissions of its own. Channel access is controlled by job and duty from `kora_core`, grants, hooks and channel checks. See [Features](./features.md).
