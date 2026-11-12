---
title: "Server: API & client surface"
sidebar_position: 4
---


# Server: API & client surface

## Server

All server-side membership mutation goes through exactly two functions: `Voice.api.assign`/`assignCall` (trusted) and `Voice.api.request` (untrusted, policy-checked). Every export and callback listed here calls one or the other; `test/smoke/authority.lua` specifically fails if a client-reachable path is ever wired to the trusted one.

Namespace: `exports.kora_voice` · Source: `server/api.lua, server/net.lua, server/compat.lua`

### How it works

Three kora_lib callbacks are the entire client-facing surface: `kora_voice:requestRadio` and `kora_voice:leaveRadio` (both rate-limited via `Config.rateLimit.radio`), and `kora_voice:leaveCall` (`Config.rateLimit.call`) -- calls cannot be joined by a client at all, only left. `kora_voice:sync` (`Config.rateLimit.sync`) re-publishes everything a client needs after a resource restart or on a fresh spawn, since the client arms its own subscriptions after the session starts and may have missed changes before that. `playerJoining` writes an explicit cleared state-bag value immediately, so a reader can never confuse 'never set' with 'not replicated yet'.

### Terms used on this page

| Term | Meaning |
| --- | --- |
| Rate limit | `Config.rateLimit.{radio,call,sync}` -- `{ max, window }` sliding-window limits applied per player per callback, since a channel-join request is the one message a client can send completely unprompted, and unlimited attempts would let a client walk all 1000 channel ids looking for an open one. |

### Functions

Eighteen server exports (fourteen are detailed below; `getPlayersInRadioChannel`, `getPlayersInCall`, `getCallChannel` and `removeRadioPolicy` are listed in the [export quick reference](#export-quick-reference)) plus the four rate-limited client callbacks.

#### `exports.kora_voice:setPlayerRadio(src, channel)`

TRUSTED. Assigns (or clears, with `channel = nil`) a player's radio channel with NO policy check.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | number | Required. |
| `channel` | number \| nil | Required; must be a valid radio channel or nil/false to clear. |

**Returns**

- **`boolean ok, string|nil error` -- error only for a genuinely invalid (non-normalisable) channel value, never a policy refusal.**

**Example**

```lua
exports.kora_voice:setPlayerRadio(src, 1)
```

**Representative console output**

```text
For server code only: a job resource putting an officer on the tac channel, a phone resource opening a call. Never reachable from a client.
```

#### `exports.kora_voice:addPlayerToRadio(src, channel)`

Alias of `setPlayerRadio`, kept for pma-voice call sites.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | number | Required. |
| `channel` | number \| nil | Required. |

**Returns**

- **Same as `setPlayerRadio`.**

**Example**

```lua
exports.kora_voice:addPlayerToRadio(src, 1)
```

#### `exports.kora_voice:removePlayerFromRadio(src, channel?)`

Removes a player from a radio channel, but ONLY if they are currently on that exact channel.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | number | Required. |
| `channel?` | number \| nil | A guard, not a target: nil removes whatever they are on; a mismatched channel number is a no-op. |

**Returns**

- **`boolean removed`.**

**Example**

```lua
exports.kora_voice:removePlayerFromRadio(src, 3)
```

**Representative console output**

```text
Guards against a stale 'leave channel 3' click from a radio UI kicking a player off the channel 5 they have since joined.
```

#### `exports.kora_voice:setPlayerCall(src, channel)`

TRUSTED. Assigns a call channel. Not restriction-checked at all: a phone resource has already decided who may ring whom.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | number | Required. |
| `channel` | number \| nil | A valid call channel id (see `Config.calls`), or nil/false to clear. |

**Returns**

- **`boolean ok, string|nil error`.**

**Example**

```lua
exports.kora_voice:setPlayerCall(src, phoneNumber)
```

#### `exports.kora_voice:removePlayerFromCall(src, channel?)`

Same guard semantics as `removePlayerFromRadio`, for the call channel.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | number | Required. |
| `channel?` | number \| nil | Optional guard. |

**Returns**

- **`boolean removed`.**

**Example**

```lua
exports.kora_voice:removePlayerFromCall(src)
```

#### `exports.kora_voice:getRadioMembers(channel)`

Sorted array of a radio channel's current members.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `channel` | number | Required. |

**Returns**

- **`integer[]`.**

**Example**

```lua
exports.kora_voice:getRadioMembers(1)
```

**Representative console output**

```text
`getPlayersInRadioChannel`/`getPlayersInCall` return the same data shaped as a `src -> true` map instead, matching pma-voice's own return shape for existing call sites.
```

#### `exports.kora_voice:getRadioChannel(src)`

A player's current radio channel.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | number | Required. |

**Returns**

- **`integer | false` -- false rather than nil, so the value survives the exports boundary intact.**

**Example**

```lua
exports.kora_voice:getRadioChannel(src)
```

**Representative console output**

```text
`getCallChannel(src)` is the call-channel equivalent.
```

#### `exports.kora_voice:grantRadioChannels(src, channels)`

Grants a player a set of channels they may join regardless of `Config.radio.restricted`. The recommended integration for a job resource opening its own frequencies.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | number | Required. |
| `channels` | integer[] \| integer \| nil | nil revokes. |

**Returns**

- **`integer` count granted.**

**Example**

```lua
exports.kora_voice:grantRadioChannels(src, { 1, 2 })
```

**Representative console output**

```text
Data, not a funcref -- a restart of the granting resource cannot leave a dead hook refusing (or wrongly allowing) every request.
```

#### `exports.kora_voice:revokeRadioChannels(src)`

Revokes all of a player's channel grants.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | number | Required. |

**Returns**

- **`integer` count, always 0 (returned only for call-site symmetry with `grantRadioChannels`).**

**Example**

```lua
exports.kora_voice:revokeRadioChannels(src)
```

#### `exports.kora_voice:addRadioPolicy(fn)`

Registers a dynamic policy hook when the decision genuinely must be made at request time (prefer `grantRadioChannels` otherwise).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `fn` | function(src, channel): boolean\|nil, string\|nil | `false, reason` refuses; `true` allows; `nil` abstains. |

**Returns**

- **`integer` handle for `removeRadioPolicy`.**

**Example**

```lua
local h = exports.kora_voice:addRadioPolicy(function(src, ch) ... end)
```

**Representative console output**

```text
A funcref is only callable while the registering resource is running -- it is NOT automatically cleaned up as 'closed' on that resource stopping the way `addChannelCheck` is; design hooks to abstain safely, or remove them on your own `onResourceStop`.
```

#### `exports.kora_voice:addChannelCheck(channel, fn)`

A legacy, channel-owning check that pre-empts the generic hook list entirely for one specific channel.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `channel` | number | Required, must be a valid radio channel. |
| `fn` | function(src): boolean | Must return exactly `true` to allow; anything else (including an error) refuses with the generic message. |

**Returns**

- **No return value.**

**Example**

```lua
exports.kora_voice:addChannelCheck(2, function(src) return isLeo(src) end)
```

**Representative console output**

```text
Automatically disabled (not removed, its `fn` is cleared) if the registering resource stops, so a stopped authorization provider cannot silently leave its frequency open.
```

#### `exports.kora_voice:removeChannelCheck(channel)`

Removes the legacy channel check registered for one channel with `addChannelCheck`, handing that frequency back to the generic grants and policy hooks.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `channel` | number | Required, must be a number. |

**Returns**

- **No return value.**

**Example**

```lua
exports.kora_voice:removeChannelCheck(2)
```

**Representative console output**

```text
Raises an error when `channel` is not a number; removing a channel that has no check does nothing.
```

#### `exports.kora_voice:isChannelRestricted(channel)`

Whether a channel is restricted at all. Server-only on purpose -- the one crumb of the restriction table safe to answer, and never answered to a client.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `channel` | number | Required. |

**Returns**

- **`boolean`.**

**Example**

```lua
exports.kora_voice:isChannelRestricted(2)
```

#### `exports.kora_voice:refreshVoiceTargets(src)`

Re-pushes both of a player's rosters without changing membership -- for a resource that just moved the player between routing buckets.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | number | Required. |

**Returns**

- **`boolean ok, string|nil reason`.**

**Example**

```lua
exports.kora_voice:refreshVoiceTargets(src)
```

**Representative console output**

```text
Also fired automatically on the local event `kora_voice:server:bucketChanged`. A no-op (returns true) when `Config.buckets.enforce` is off.
```

### Limits and related APIs

Server-only. There is no export anywhere in this resource, in either realm, that lets a CLIENT assert its own radio membership -- see `client/exports.lua` for the client-side mirror of this list.

### Related guides

- [Server: store, policy & publish](./policy.md)
- [Client: proximity, submix & voice targets](./client-targets.md)

## Client

Presentation, local-only audio properties, and REQUESTS. `addPlayerToRadio` is the one export whose return value needs care: it reports whether the server agreed, not that the local state already reflects the new channel on the next line.

Namespace: `exports.kora_voice` · Source: `client/exports.lua, client/compat.lua`

### How it works

The pma-voice compatibility surface (`client/compat.lua`) wraps these same functions under pma-voice's own names via `Kora.compat.provideExport('pma-voice', ...)`. `pma-voice:setRadioChannel`/`pma-voice:setCallChannel` are deliberately NOT registered as INBOUND events (only emitted locally once the server has actually published), since honouring them inbound would let a client assert its own membership by firing a well-known event name at itself.

### Functions

Fifteen client exports (thirteen are detailed below; `getCallChannel` and `setCallVolume` are described in the notes of their radio counterparts and in the [export quick reference](#export-quick-reference)).

#### `exports.kora_voice:addPlayerToRadio(channel)`

Asks the server for a radio channel. The ONLY client-reachable path to joining a radio channel. Must be called from a coroutine (a command handler, `CreateThread`, a keybind callback) -- it suspends until the server answers.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `channel` | integer \| nil | nil or 0 leaves the current channel. |

**Returns**

- **`boolean ok, string|nil reason` -- a timed-out round trip returns `nil` for `ok` (not `false`), which callers must distinguish from an actual server refusal.**

**Example**

```lua
local ok, reason = exports.kora_voice:addPlayerToRadio(2)
```

**Representative console output**

```text
Returning `true` means the server AGREED, not that the client's local state already reflects it -- read `Voice.state`/the exports below, or listen for `kora_voice:client:radioChanged`, for the applied value.
```

#### `exports.kora_voice:removePlayerFromRadio()`

Leaves the current radio channel. Always permitted.

**Parameters**



**Returns**

- **`boolean`.**

**Example**

```lua
exports.kora_voice:removePlayerFromRadio()
```

#### `exports.kora_voice:removePlayerFromCall()`

Leaves the current call.

**Parameters**



**Returns**

- **`boolean`.**

**Example**

```lua
exports.kora_voice:removePlayerFromCall()
```

#### `exports.kora_voice:getRadioChannel()`

This player's published radio channel, read from the local mirror of what the server last published -- never a local assumption.

**Parameters**



**Returns**

- **`integer | false`.**

**Example**

```lua
exports.kora_voice:getRadioChannel()
```

**Representative console output**

```text
`getCallChannel()` is the call equivalent.
```

#### `exports.kora_voice:setTalkingMode(mode)`

Sets the proximity talk mode directly (not through the cycle).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `mode` | integer \| string | An index into `Config.proximity.modes`, or a mode name such as `'whisper'`. |

**Returns**

- **`integer index, number range` -- the resulting (clamped) index and its talk range.**

**Example**

```lua
exports.kora_voice:setTalkingMode('shout')
```

#### `exports.kora_voice:cycleTalkingMode(step?)`

Steps the proximity mode by `step` (default 1), wrapping per `Config.proximity.wrap`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `step?` | integer | Defaults to 1. |

**Returns**

- **`integer index, number range`.**

**Example**

```lua
exports.kora_voice:cycleTalkingMode(-1)
```

**Representative console output**

```text
What the default cycle key itself calls.
```

#### `exports.kora_voice:getTalkingMode()`

The current mode as a table, for a HUD to render.

**Parameters**



**Returns**

- **`{ index, name, label, range }`.**

**Example**

```lua
local mode = exports.kora_voice:getTalkingMode()
```

**Representative console output**

```text
`range` accounts for an active megaphone override.
```

#### `exports.kora_voice:isRadioActive()`

Whether this player is transmitting on the radio right now (holding the key AND actually on a granted channel).

**Parameters**



**Returns**

- **`boolean`.**

**Example**

```lua
exports.kora_voice:isRadioActive()
```

**Representative console output**

```text
Plain 'am I talking at all' is answered by the native `NetworkIsPlayerTalking`; kora_hud's mic indicator needs no integration with this resource for that reason.
```

#### `exports.kora_voice:setMegaphone(active)`

Turns the megaphone override on or off (for a resource that owns a megaphone prop/vehicle; not bound to a bare key by default).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `active` | boolean | Required. |

**Returns**

- **`boolean changed`.**

**Example**

```lua
exports.kora_voice:setMegaphone(true)
```

#### `exports.kora_voice:setRadioVolume(volume)`

Sets a received-audio volume multiplier for radio traffic.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `volume` | number | 0.0-1.0, or 0-100 (values above 1 are read as a percentage, not clamped to full volume). |

**Returns**

- **`number` applied (0.0-1.0).**

**Example**

```lua
exports.kora_voice:setRadioVolume(50)
```

**Representative console output**

```text
`setCallVolume(volume)` is the call equivalent.
```

#### `exports.kora_voice:setVoiceProperty(property, value)`

The pma-voice `setVoiceProperty` surface. Every property is LOCAL AUDIO ONLY (a volume, an effect toggle, a mode) -- there is deliberately no property that changes membership.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `property` | string | One of `radioVolume`, `callVolume`, `micClicks`, `submix`, `talkingMode`, `muffling`. |
| `value` | any | Required. |

**Returns**

- **`boolean ok` -- false (and a console warning) for an unknown property name rather than silently doing nothing.**

**Example**

```lua
exports.kora_voice:setVoiceProperty('muffling', false)
```

#### `exports.kora_voice:getVoiceProperty(property)`

Reads one local voice property, including `radioChannel`/`callChannel` in addition to the `setVoiceProperty` list.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `property` | string | Required. |

**Returns**

- **`any` -- `nil` for an unknown property name.**

**Example**

```lua
exports.kora_voice:getVoiceProperty('radioVolume')
```

#### `exports.kora_voice:refreshVoiceTargets()`

Forces an immediate voice-target rebuild.

**Parameters**



**Returns**

- **`boolean`.**

**Example**

```lua
exports.kora_voice:refreshVoiceTargets()
```

**Representative console output**

```text
Needed after moving the player between routing buckets client-side, since scope changes without any voice STATE changing, so nothing would otherwise mark the target dirty.
```

### Limits and related APIs

Client-only. None of these functions can put the player on a radio channel without the server agreeing; `setVoiceProperty`/`setVoiceProperty`-style calls only ever touch local playback.

### Related guides

- [Client: proximity, submix & voice targets](./client-targets.md)

## Export quick reference

Use `exports.kora_voice:name(...)`. The same names are also registered under `pma-voice` (see [Compatibility](../compatibility.md)).

### Server export summary

All server exports that change membership are trusted: they skip the radio restriction policy and must only be called from server code.

| Export | Returns | Description |
| --- | --- | --- |
| `setPlayerRadio(src, channel)` | `ok, err` | Puts a player on a radio channel. nil, false or no value leaves. A given but invalid channel returns `false` and an error string. |
| `addPlayerToRadio(src, channel)` | `ok, err` | Alias of `setPlayerRadio`. |
| `removePlayerFromRadio(src, channel)` | `removed` | Removes the player from the radio. If a valid `channel` is given, only when the player is on exactly that channel. |
| `setPlayerCall(src, channel)` | `ok, err` | Puts a player on a call channel (not policy checked). |
| `removePlayerFromCall(src, channel)` | `removed` | Same guard behaviour as radio removal. |
| `getPlayersInRadioChannel(channel)` | table | Map of server id to `true`. |
| `getPlayersInCall(channel)` | table | Map of server id to `true`. |
| `getRadioMembers(channel)` | array | Sorted server ids. |
| `getRadioChannel(src)` | channel or `false` | The player's radio channel. |
| `getCallChannel(src)` | channel or `false` | The player's call channel. |
| `grantRadioChannels(src, channels)` | count | Lets the player join the listed channels regardless of `Config.radio.restricted`. Accepts a number or a list; replaces any previous grant. Hooks and channel checks still run first. |
| `revokeRadioChannels(src)` | `0` | Clears the player's grants. |
| `addRadioPolicy(fn)` | handle | Registers a hook `fn(src, channel)` returning `false, reason`, `true`, or nil to abstain. |
| `removeRadioPolicy(handle)` | boolean | Removes a hook by handle. |
| `addChannelCheck(channel, fn)` | none | Registers a check `fn(src)` that alone decides joins for that channel; only `true` allows. Raises an error for an invalid channel or non-callable `fn`. |
| `removeChannelCheck(channel)` | none | Removes the check. |
| `isChannelRestricted(channel)` | boolean | Whether `Config.radio.restricted` lists the channel. |
| `refreshVoiceTargets(src)` | `ok, err` | Re-pushes the player's current radio and call rosters, for use after a routing bucket change. Does nothing when `Config.buckets.enforce` is false. |

Server code that moves players between routing buckets with the raw `SetPlayerRoutingBucket` native should call `refreshVoiceTargets` or trigger the server-local event `kora_voice:server:bucketChanged`.

A channel check provider stops counting when its resource stops: joins to that channel are then refused until the provider registers again.

### Client export summary

Client exports never change membership directly; the channel ones are requests.

| Export | Returns | Description |
| --- | --- | --- |
| `addPlayerToRadio(channel)` | `ok, reason` | Requests a channel through the server. Must run in a coroutine. `false, nil` means the round trip timed out; `false, reason` is a refusal. `true` means the server agreed; the local state follows from the published value. |
| `removePlayerFromRadio()` | boolean | Leaves the radio. |
| `removePlayerFromCall()` | boolean | Leaves the call. |
| `getRadioChannel()` | channel or `false` | Server-published channel. |
| `getCallChannel()` | channel or `false` | Server-published call channel. |
| `setTalkingMode(mode)` | `index, range` | Mode by index or name. |
| `cycleTalkingMode(step)` | `index, range` | Steps modes; default step 1. Shows a notification when `Config.proximity.notify` is on. |
| `getTalkingMode()` | table | `index`, `name`, `label`, `range` (current range, including megaphone). |
| `isRadioActive()` | boolean | True while the radio key is held and a channel is set. |
| `setMegaphone(active)` | boolean | Switches megaphone range on or off; returns whether it changed. Does not fire the `kora_voice:client:megaphone` event (only the keybind does). |
| `setRadioVolume(volume)`, `setCallVolume(volume)` | applied | 0.0 to 1.0, or 0 to 100 (values above 1 are treated as percentages). |
| `setVoiceProperty(name, value)` | boolean | Sets `radioVolume`, `callVolume`, `micClicks`, `submix`, `talkingMode` or `muffling`. An unknown name prints a console line and returns `false`. |
| `getVoiceProperty(name)` | any | Reads the same properties, plus `radioChannel` and `callChannel`. nil for unknown names. |
| `refreshVoiceTargets()` | boolean | Forces a voice target rebuild from the last server rosters; it does not request new ones. |
