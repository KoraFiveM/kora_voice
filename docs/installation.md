---
title: Installation
sidebar_position: 2
---

# Installation

## Dependencies

`fxmanifest.lua` declares two dependencies:

- `kora_lib` - keybinds, state-bag subscriptions, callbacks, push events, notifications, timers, frontend sounds and the input dialog. Its `init.lua` is loaded as a shared script.
- `kora_core` - the server reads the player's job (`exports.kora_core:getJob`) when evaluating restricted radio channels, and registers the radio item through `exports.kora_core:createUseable`. The client also listens for `kora_core:client:onPlayerLoaded`.

The radio item additionally depends on `kora_inventory` at runtime: the server registers the use handler again when `kora_inventory` starts. It is not declared as a manifest dependency.

## Replacing pma-voice

The manifest has `provide 'pma-voice'`, so resources declaring `dependency 'pma-voice'` are satisfied. Stop `pma-voice` and run `ensure kora_voice`.

When `Config.compat.pmaVoice` and `Config.compat.refuseOnConflict` are both true (the defaults), the server script raises an error and refuses to start if a separately running `pma-voice` resource is found. See [Compatibility](./compatibility.md).

## Start order

Ensure `kora_lib` and `kora_core` before `kora_voice`. Server and client scripts are listed file by file in the manifest and their order matters; do not glob them.

## After installing

- Review `Config.radio.restricted` so the restricted channels match your jobs. See [Configuration](./configuration.md).
- Make sure an inventory item named `Config.radio.item` (default `radio`) exists if you want the radio item. See [Items](./items.md).
- Keep `Config.debug` off in production.
