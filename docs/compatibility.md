---
title: Compatibility
sidebar_position: 9
---

# Compatibility

## pma-voice

Three separate FiveM mechanisms are involved; each is satisfied differently.

| Mechanism | Satisfied by |
| --- | --- |
| `dependency 'pma-voice'` | `provide 'pma-voice'` in `fxmanifest.lua`. |
| `exports['pma-voice']:name()` | The `__cfx_export_pma-voice_name` handlers registered by `server/compat.lua` and `client/compat.lua` (needs `Config.compat.pmaVoice`). |
| `shared_script '@pma-voice/...'` | Not satisfied. That needs a real resource named `pma-voice`. |

Server exports under the `pma-voice` name: `addChannelCheck`, `removeChannelCheck`, `setPlayerRadio`, `addPlayerToRadio`, `removePlayerFromRadio`, `setPlayerCall`, `removePlayerFromCall`, `getPlayersInRadioChannel`, `getPlayersInCall`, `getRadioChannel`, `getCallChannel`.

Client exports under the `pma-voice` name: `setVoiceProperty`, `getVoiceProperty`, `setRadioVolume`, `setCallVolume`, `setTalkingMode`, `setRadioChannel`, `addPlayerToRadio`, `removePlayerFromRadio`, `removePlayerFromCall`, `getRadioChannel`, `getCallChannel`. The client channel functions are requests that go through the server.

## Differences from pma-voice

- Inbound net events act on `source`, never on a payload player id, so a client cannot put another player on a channel.
- A client cannot join a call. There is no client `addPlayerToCall`; a phone resource must use the trusted `setPlayerCall` server export.
- `pma-voice:setRadioChannel` and `pma-voice:setCallChannel` are emitted locally for UIs but are not accepted as inbound events.
- `removePlayerFromRadio(src, channel)` only removes the player when they are on that channel.
- Radio effect is applied by channel membership plus earshot, not toggled per transmission.
- Client `setVoiceProperty` supports only `radioVolume`, `callVolume`, `micClicks`, `submix`, `talkingMode` and `muffling`.
- Voice targets are a single rebuilt target; resources that touch Mumble voice targets themselves conflict with it.

## kora_hud

No integration is needed: the microphone indicator reads the native talking state. A HUD that wants to show radio traffic can call the `isRadioActive` client export.

## Native requirements

The client uses the Mumble natives (`MumbleSetVoiceTarget`, `MumbleClearVoiceTarget`, `MumbleAddVoiceTargetPlayerByServerId`, `MumbleSetVolumeOverrideByServerId`, `MumbleSetSubmixForServerId`) and the audio submix natives. Each is guarded with a type check, so a build without one degrades instead of erroring.
