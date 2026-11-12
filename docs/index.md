---
title: kora_voice
sidebar_position: 1
---

# kora_voice

`kora_voice` is first-party proximity voice for Kora servers and a drop-in replacement for `pma-voice`. It provides whisper/normal/shout proximity modes, numbered radio channels, phone call channels that run alongside the radio, radio and megaphone audio submixes, and wall muffling.

Current version: see `version` in `fxmanifest.lua`.

The central design rule is the authority boundary: channel membership lives on the server. A client only sends a request; the server decides, records and publishes, and the client builds its Mumble voice target from exactly what the server published. See [Features](./features.md).

## Documentation map

- [Installation](./installation.md) - install steps, the full manifest, dependencies, replacing pma-voice, start order.
- [How to use](./how-to-use.md) - player experience, the authority architecture and server/client integration examples.
- [Features](./features.md) - proximity, radio, join rules, calls, submixes, muffling, voice targets, state bags.
- [Commands and keybinds](./commands.md) - the debug-only console commands, the three player keybinds and permissions.
- [Events](./events.md) - local events emitted, net events accepted, callbacks and pushes.
- [Items](./items.md) - the `radio` inventory item.
- [Compatibility](./compatibility.md) - pma-voice compatibility surface and its deliberate differences.
- [Troubleshooting](./troubleshooting.md) - common problems and their causes.
- [API reference](./api/index.md) - the module overview table.
  - [Proximity modes and channel helpers](./api/modes-channels.md) - `Voice.modes` and `Voice.channels` (shared).
  - [Server: store, policy and publish](./api/policy.md) - `Voice.store`, `Voice.policy`, `Voice.publish`.
  - [Server: API and client surface](./api/exports.md) - every server and client export, callbacks, and an export quick reference.
  - [Client: proximity, submix and voice targets](./api/client-targets.md) - `Voice.state`, `Voice.proximity`, `Voice.submix`, `Voice.targets`.
  - [Configuration](./api/configuration.md) - every `Config` option with defaults and apply timing.

## No UI, no database

The resource has no NUI (no `ui_page`, no `files`) and uses no database tables. The only dialog is the radio item's frequency prompt, shown through `Kora.nui.openInputDialog` from `kora_lib`. The microphone indicator belongs to `kora_hud`.
