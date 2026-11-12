---
title: "Installation"
sidebar_position: 2
---


# Installation

Kora Voice is a first-party replacement for pma-voice: proximity talk ranges, server-authoritative radio channels (with per-channel job/duty restrictions), independent phone-call channels, a push-to-talk radio key with a band-limited submix, a megaphone override, line-of-sight wall muffling, and routing-bucket-aware audio scoping. Membership is decided ONLY on the server; the client only ever asks.

## Install Kora Voice

1. **Add the folder** — Place `kora_voice` in your resources directory (on the Kora recipe it is `resources/[standalone]/kora_voice`).

2. **Have its dependencies running** — The manifest declares `kora_lib` (keybinds, state-bag subscriptions, notifications, timers, frontend sound) and `kora_core` (the job/duty read the radio restriction table is evaluated against, in `server/policy.lua`; `kora_core` also registers the radio item, see [Items](./items.md)).

3. **Do not run pma-voice alongside it** — With `Config.compat.refuseOnConflict` true (the default), `server/compat.lua` detects a separately-started `pma-voice` folder (not this resource's own `provide 'pma-voice'` identity) and `error()`s on start rather than let two resources fight over the same Mumble voice target, which otherwise presents as intermittent, one-directional audio.

4. **Set sv_voiceChat convars as usual** — This resource configures Mumble behaviour (ranges, submixes, targets) but does not itself turn on voice chat at the FiveM/txAdmin level — the server's own Mumble/voice settings still apply.

5. **Review config.lua** — Proximity ranges and the default mode, the radio channel range and restriction table, call channel range, submix parameters, muffling, routing-bucket enforcement, state-bag key names, keybind defaults, pma-voice compatibility toggles, and per-callback rate limits are all here. See the Configuration page for the full list.

6. **No NUI of its own** — There is no `ui_page` and no `files{}` block. The mic indicator already belongs to kora_hud (which reads the native talking state directly), so adding one here would duplicate it.

## Manifest reference

Script order is explicit and never globbed, because the load-order dependencies are real: `store.lua` owns the membership registry every other server file reads; `policy.lua` and `publish.lua` are the two halves `api.lua` composes, so both precede it; `net.lua` registers client-facing callbacks and must come after `api.lua`; `compat.lua` wraps the finished API surface last; `dev.lua` loads very last and self-disables unless `Config.debug` is on. The client order is similarly load-bearing: `state.lua` first (owns the local mirror), then the leaves `proximity.lua`/`submix.lua`, then `targets.lua` (consumes all three), then `sync.lua` (arms inbound subscriptions, needs `targets.lua` already defined), then the entry points `keybinds.lua`/`exports.lua`/`radio_item.lua`/`compat.lua`. On the server, `item.lua` (the radio item use handler) loads after `net.lua` and before `compat.lua`.

```lua title="fxmanifest.lua"
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'kora_voice'

dependency 'kora_lib'
dependency 'kora_core'

-- Satisfies a third-party resource's dependency 'pma-voice' declaration only --
-- it does NOT make exports['pma-voice']:... resolve here by itself.
provide 'pma-voice'

shared_script '@kora_lib/init.lua'

shared_scripts {
    'config.lua',
    'shared/modes.lua',
    'shared/channels.lua',
}

server_scripts {
    'server/store.lua',
    'server/policy.lua',
    'server/publish.lua',
    'server/api.lua',
    'server/net.lua',
    'server/item.lua',
    'server/compat.lua',
    'server/dev.lua',
}

client_scripts {
    'client/state.lua',
    'client/proximity.lua',
    'client/submix.lua',
    'client/targets.lua',
    'client/sync.lua',
    'client/keybinds.lua',
    'client/exports.lua',
    'client/radio_item.lua',
    'client/compat.lua',
}

-- kora_qa: Gherkin test scenarios
qa_feature 'tests/*.feature'
```

- `provide 'pma-voice'` only satisfies a resource's `dependency 'pma-voice'` manifest line. It does NOT by itself make `exports['pma-voice']:...` resolve here (that is the separate `__cfx_export_pma-voice_<name>` registration in `{server,client}/compat.lua`), and neither mechanism satisfies a `shared_script '@pma-voice/...'` include, which needs a real `pma-voice` resource folder. See `resources/[compat]/README.md`.

## Dependencies in detail

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

- Review `Config.radio.restricted` so the restricted channels match your jobs. See [Configuration](./api/configuration.md).
- Make sure an inventory item named `Config.radio.item` (default `radio`) exists if you want the radio item. See [Items](./items.md).
- Keep `Config.debug` off in production.
