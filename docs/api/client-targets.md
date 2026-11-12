---
title: "Client: proximity, submix & voice targets"
sidebar_position: 5
---


# Client: proximity, submix & voice targets

`Voice.state` is the local mirror of published truth plus presentation state (never a decision). `Voice.proximity` turns a mode index into actual Mumble ranges across four natives for build compatibility. `Voice.submix` creates and routes the band-limited radio/megaphone audio chains. `Voice.targets` is the ONLY place Mumble is told who may receive this player's audio, rebuilt from exactly three sources (proximity grid, radio roster, call roster) and never extended locally -- a self-added member would be a self-granted voice target, the exact exploit the server authority boundary exists to prevent.

Namespace: `Voice.state / Voice.proximity / Voice.submix / Voice.targets` · Source: `client/state.lua, client/proximity.lua, client/submix.lua, client/targets.lua, client/sync.lua`

## How it works

`client/sync.lua` arms the inbound state-bag subscriptions (`Kora.state.onChange` on `Config.state.radio`/`Config.state.call`) and roster pushes (`Kora.events.onPush` on `kora_voice:radio:roster`/`kora_voice:call:roster`) only AFTER the network session is live and this client's own server id is readable -- registering earlier binds permanently to `player:-1` and the radio silently never works. A state-bag handler always uses its `value` argument, never a re-read of `LocalPlayer.state`, because the handler fires BEFORE the new value commits locally. After arming, it calls `kora_voice:sync` once as a catch-up for anything that changed before the subscriptions existed (for example `ensure kora_voice` against an already-logged-in session).

## Terms used on this page

| Term | Meaning |
| --- | --- |
| Dirty flag | `Voice.state`'s single boolean, set whenever anything the rebuild cares about changes. Lets the bounded tick skip a rebuild entirely when nothing changed, while an immediate change-driven refresh still happens right away. |
| Volume override combination | Mumble has exactly ONE volume-override slot per speaker, so occlusion and the per-path radio/call volumes are combined (the quietest wins) and written once per rebuild rather than each separately overwriting the other. |

## Functions

Selected functions across the four modules; the full set also includes `Voice.state.setRadio`/`setCall`/`setRadioMembers`/`setCallMembers`/`setVolume`/`onChange`, `Voice.proximity.currentRange`/`set`, and `Voice.submix.ids`.

### `Voice.state.setMode(index)`

Sets the local proximity mode index (clamped/resolved), marking the voice target dirty on change.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `index` | integer \| string | An index or mode name. |

**Returns**

- **`boolean changed, integer index`.**

**Example**

```lua
Voice.state.setMode('shout')
```

### `Voice.state.isRadioActive()`

Whether the player is transmitting on the radio right now.

**Parameters**



**Returns**

- **`boolean` -- both holding the key AND actually on a granted channel.**

**Example**

```lua
Voice.state.isRadioActive()
```

**Representative console output**

```text
Backs the `isRadioActive` export.
```

### `Voice.proximity.apply()`

Pushes the current effective range (mode, or megaphone override if active) into every available Mumble distance native.

**Parameters**



**Returns**

- **`number range` applied.**

**Example**

```lua
Voice.proximity.apply()
```

**Representative console output**

```text
Sets four natives (`MumbleSetAudioInputDistance`/`OutputDistance`, `MumbleSetTalkerProximity`, `NetworkSetTalkerProximity`), each individually guarded, so a build missing one still applies the rest instead of silently doing nothing.
```

### `Voice.proximity.cycle(step?)`

Steps the mode and applies it, notifying the player of the new mode/range.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `step?` | integer | Defaults to 1. |

**Returns**

- **`integer index, number range`.**

**Example**

```lua
Voice.proximity.cycle(1)
```

**Representative console output**

```text
What the default `kora_voice_proximity` keybind calls.
```

### `Voice.submix.ensure()`

Creates the radio and megaphone audio submixes if they do not exist yet. Idempotent.

**Parameters**



**Returns**

- **`integer|nil radio, integer|nil megaphone` submix ids.**

**Example**

```lua
Voice.submix.ensure()
```

**Representative console output**

```text
`CreateAudioSubmix` returning -1 (pool full) is treated as failure rather than applying effect parameters to submix -1, which would otherwise silently route speakers into dead air.
```

### `Voice.submix.applyTo(serverId, kind)`

Routes one speaker's audio through a submix.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `serverId` | integer | Required. |
| `kind` | 'radio' \| 'megaphone' | Required. |

**Returns**

- **`boolean applied`.**

**Example**

```lua
Voice.submix.applyTo(5, 'radio')
```

### `Voice.submix.clearFor(serverId)`

Returns one speaker to unprocessed audio. Called every rebuild for every speaker NOT currently on the radio/call, not only on the transition, since an uncleared submix otherwise persists for the rest of the session.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `serverId` | integer | Required. |

**Returns**

- **`boolean cleared`.**

**Example**

```lua
Voice.submix.clearFor(5)
```

### `Voice.targets.rebuild()`

Rebuilds the single Mumble voice target from scratch: the local proximity grid, the server-pushed radio roster (only while transmitting AND granted), and the server-pushed call roster (always, once joined).

**Parameters**



**Returns**

- **`integer count` of members added to the target.**

**Example**

```lua
Voice.targets.rebuild()
```

**Representative console output**

```text
Guarded against re-entrancy: an interleaved rebuild from the bounded tick and a change-driven rebuild landing in the same frame would otherwise each clear the other's half-built target.
```

### `Voice.targets.refresh()`

Rebuilds only if `Voice.state`'s dirty flag is set.

**Parameters**



**Returns**

- **`boolean rebuilt`.**

**Example**

```lua
Voice.targets.refresh()
```

**Representative console output**

```text
Called immediately after a membership/roster change, in its own thread (synchronous shape tests inside a state-bag handler would stall the whole handler chain every resource shares).
```

### `Voice.targets.start()`

Starts the bounded refresh tick (`Config.mumble.refreshInterval`, 500ms by default). Rebuilds unconditionally on every tick, not only when dirty, since a player walking out of range changes nothing EXCEPT position.

**Parameters**



**Returns**

- **`integer` timer id.**

**Example**

```lua
Voice.targets.start()
```

**Representative console output**

```text
Called once from `client/sync.lua` once the session is live.
```

## Limits and related APIs

Client-only in every one of these files. `Voice.targets.rebuild` fires a synchronous line-of-sight shape test per nearby player when muffling is enabled, which is why it runs on a bounded tick (500ms default) rather than per frame.

## Related guides

- [Server: API & client surface](./exports.md)
- [Proximity modes & channel helpers](./modes-channels.md)
