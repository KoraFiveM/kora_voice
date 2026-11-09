fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'kora_voice'
-- Keep the legacy resource name resolvable for exports['qbvoice'] callers.
provide 'qbvoice'
author 'qbcore2'
version '0.1.0'
description 'First-party voice: proximity modes, server-authoritative radio channels, phone calls, submixes and wall muffling'

-- kora_lib supplies keybinds, state-bag subscriptions, notifications, timers and
-- frontend sound. kora_core supplies the job/duty read the radio restriction table
-- is evaluated against -- and only on the SERVER, in server/policy.lua.
dependency 'kora_lib'
dependency 'kora_core'

-- Satisfies a third-party resource's `dependency 'pma-voice'`. It does NOT by
-- itself make `exports['pma-voice']:...` resolve here -- that is a separate
-- mechanism, the `__cfx_export_pma-voice_<name>` handlers in
-- {server,client}/compat.lua -- and neither of them satisfies a
-- `shared_script '@pma-voice/...'` include, which would need a real resource of
-- that name in resources/[compat]/. See resources/[compat]/README.md.
provide 'pma-voice'

shared_script '@kora_lib/init.lua'

shared_scripts {
    'config.lua',
    -- Both pure, both realms. modes.lua is shared rather than client-only
    -- because the server clamps a mode index arriving from a pma-voice
    -- `setTalkingMode` call site, and it must use the same bounds check the
    -- cycle key uses rather than a second, subtly different one.
    'shared/modes.lua',
    'shared/channels.lua',
}

-- Explicit, never globbed -- alphabetic glob order would put api before
-- policy and publish, and the load-order dependencies here are real.
--
-- store.lua owns the membership registry every other server file reads.
-- policy.lua and publish.lua are the two halves api.lua composes, so both must
-- precede it. net.lua registers the client-facing callbacks and must come
-- after api.lua, whose `request` is the only function it may call. compat.lua
-- last, because it wraps the finished api surface. dev.lua very last, and
-- self-disabling unless Config.debug is on.
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

-- state.lua owns the local mirror every other client file reads and must load
-- first. proximity and submix are leaves. targets.lua consumes all three.
-- sync.lua arms the inbound subscriptions and starts the refresh tick, so it
-- needs targets.lua already defined. keybinds/exports/compat are entry points
-- into everything above and come last.
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

-- No ui_page and no files{}: this resource has no NUI of its own. The mic
-- indicator already belongs to kora_hud, which reads the native talking state and
-- therefore needs no integration here -- adding a second indicator would put
-- two of them on screen.

-- kora_qa: Gherkin test scenarios (converted legacy tests), see [kora]/kora_qa/README.md
qa_feature 'tests/*.feature'
