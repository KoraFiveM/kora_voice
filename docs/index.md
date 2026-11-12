---
title: kora_voice
sidebar_position: 1
---

# kora_voice

`kora_voice` is first-party proximity voice for Kora servers and a drop-in replacement for `pma-voice`. It provides whisper/normal/shout proximity modes, numbered radio channels, phone call channels that run alongside the radio, radio and megaphone audio submixes, and wall muffling.

Current version: see `version` in `fxmanifest.lua`.

The central design rule is the authority boundary: channel membership lives on the server. A client only sends a request; the server decides, records and publishes, and the client builds its Mumble voice target from exactly what the server published. See [Features](./features.md).

## Pages

- [Installation](./installation.md) - dependencies, replacing pma-voice, start order.
- [Features](./features.md) - proximity, radio, calls, submixes, muffling, voice targets, state bags.
- [Configuration](./configuration.md) - every `Config` option in `config.lua`.
- [Commands and keybinds](./commands.md) - the three player keybinds and the debug-only console commands.
- [Exports](./exports.md) - server and client exports.
- [Events](./events.md) - local events emitted, net events accepted, callbacks and pushes.
- [Items](./items.md) - the `radio` inventory item.
- [Compatibility](./compatibility.md) - pma-voice compatibility surface and its deliberate differences.
- [Troubleshooting](./troubleshooting.md) - common problems and their causes.

## No UI, no database

The resource has no NUI (no `ui_page`, no `files`) and uses no database tables. The only dialog is the radio item's frequency prompt, shown through `Kora.nui.openInputDialog` from `kora_lib`. The microphone indicator belongs to `kora_hud`.
