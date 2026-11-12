---
title: "Proximity modes & channel helpers"
sidebar_position: 2
---


# Proximity modes & channel helpers

Pure, natives-free helper tables available identically on client and server, so the exact same bounds-checking and restriction-lookup code backs both the client's cycle key and the server's own validation of an untrusted index arriving from the pma-voice `setTalkingMode` compat path.

Namespace: `Voice.modes / Voice.channels` · Source: `shared/modes.lua, shared/channels.lua`

## How it works

`Voice.channels` deliberately stops at the LOOKUP (is this channel restricted, and by what rule), never the DECISION (may THIS player join it) -- that decision needs a player's job/duty and lives server-only in `server/policy.lua`, specifically so the restriction table itself is never shipped to a client.

## Functions

Eight `Voice.modes` functions plus five `Voice.channels` functions, all pure functions of `Config` and their arguments.

### `Voice.modes.count()`

How many proximity modes are configured.

**Parameters**



**Returns**

- **`integer`.**

**Example**

```lua
Voice.modes.count() -- 3 with the stock config
```

**Representative console output**

```text
Reads `#Config.proximity.modes`; 0 if not a table.
```

### `Voice.modes.get(index)`

The mode table at `index`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `index` | integer | Required. |

**Returns**

- **`{ name, label, range } | nil`** — the CONFIG TABLE ITSELF, not a copy; nothing mutates it.

**Example**

```lua
local mode = Voice.modes.get(2) -- { name = 'normal', label = 'Normal', range = 12.0 }
```

**Representative console output**

```text
`nil` for a non-number index or one out of range.
```

### `Voice.modes.clamp(index)`

Forces any value into a valid mode index. The single bounds check in the resource.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `index` | any | nil, a string, a float, negative, or far out of range are all accepted. |

**Returns**

- **`integer`** — always a valid index (or 1 if no modes are configured).

**Example**

```lua
Voice.modes.clamp(900) -- clamps to the last configured mode
```

**Representative console output**

```text
A value below 1 clamps to `defaultIndex()`, not to 1, so a bad value lands on the configured starting mode rather than always whisper.
```

### `Voice.modes.defaultIndex()`

The configured starting index, itself clamped.

**Parameters**



**Returns**

- **`integer`.**

**Example**

```lua
Voice.modes.defaultIndex() -- 2 with the stock config (normal)
```

**Representative console output**

```text
A config typo like `default = 9` cannot produce an out-of-range starting mode.
```

### `Voice.modes.next(index, step?)`

The next index in the cycle, honouring `Config.proximity.wrap`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `index` | integer | Current index. |
| `step?` | integer | Defaults to 1; negative steps backwards. |

**Returns**

- **`integer`** — always a valid index into the configured set.

**Example**

```lua
Voice.modes.next(3, 1) -- 1 when Config.proximity.wrap is true (3 modes)
```

**Representative console output**

```text
With `wrap = false` the cycle saturates at both ends instead of wrapping.
```

### `Voice.modes.indexOfName(name)`

Finds a mode's index by its stable `name`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Required, e.g. `'whisper'`. |

**Returns**

- **`integer | nil`.**

**Example**

```lua
Voice.modes.indexOfName('shout') -- 3
```

**Representative console output**

```text
Survives the server reordering `Config.proximity.modes`.
```

### `Voice.modes.resolve(value)`

Resolves either an index or a mode name to a valid, clamped index.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | integer \| string | Required. |

**Returns**

- **`integer`.**

**Example**

```lua
Voice.modes.resolve('whisper') -- 1
```

**Representative console output**

```text
Used by `State.setMode` and the `setTalkingMode` export so callers can pass either form.
```

### `Voice.modes.rangeOf(index)`

The talk range in metres for a mode index.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `index` | integer | Required; clamped first. |

**Returns**

- **`number`.**

**Example**

```lua
Voice.modes.rangeOf(1) -- 3.0
```

**Representative console output**

```text
Returns 0.0 if the mode table has no numeric `range`.
```

### `Voice.channels.normalise(value, bounds?)`

Turns an untrusted value into a valid radio channel id, or nil.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | any | Any value; nil/false/'' all collapse to nil ('no channel'). |
| `bounds?` | &#123; minChannel, maxChannel &#125; | Defaults to `Config.radio`. |

**Returns**

- **`integer | nil`.**

**Example**

```lua
Voice.channels.normalise('3') -- 3
Voice.channels.normalise('abc') -- nil
```

**Representative console output**

```text
Floors the number and rejects anything (including NaN) outside the inclusive bounds.
```

### `Voice.channels.normaliseCall(value)`

Same as `normalise`, but bounded by `Config.calls` (a much larger ceiling, since phone resources use the phone number as the channel id).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | any | Required. |

**Returns**

- **`integer | nil`.**

**Example**

```lua
Voice.channels.normaliseCall(5551234) -- 5551234
```

**Representative console output**

```text
Separate id space from radio channels on purpose.
```

### `Voice.channels.restriction(channel)`

The restriction record for a radio channel.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `channel` | integer | Required. |

**Returns**

- **`{ label?, jobs?, jobTypes?, onDuty? } | nil`** — nil means the channel is open.

**Example**

```lua
Voice.channels.restriction(1) -- { label = 'LEO Dispatch', jobTypes = { 'leo' }, onDuty = true }
```

**Representative console output**

```text
Non-numeric input returns nil.
```

### `Voice.channels.isRestricted(channel)`

Whether a channel has a restriction record at all.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `channel` | integer | Required. |

**Returns**

- **`boolean`.**

**Example**

```lua
Voice.channels.isRestricted(400) -- false (not listed, so open)
```

**Representative console output**

```text
Any channel absent from `Config.radio.restricted` is open by default.
```

### `Voice.channels.jobSatisfies(record, job)`

Pure check of whether a job/duty pair satisfies a restriction record.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `record` | table | A restriction record, or any non-table (treated as 'no restriction', satisfies everyone). |
| `job` | &#123; name?, type?, onduty? &#125; \| nil | Required to be a table to satisfy anything. |

**Returns**

- **`boolean`.**

**Example**

```lua
Voice.channels.jobSatisfies({ jobTypes = { 'leo' }, onDuty = true }, { type = 'leo', onduty = true }) -- true
```

**Representative console output**

```text
An EMPTY restriction record (`{}`) satisfies nobody -- it means 'locked', not 'open to all'. This asymmetry is deliberate so a config typo cannot silently un-restrict a channel.
```

## Limits and related APIs

Shared realm only; neither module touches a native or any per-player state.

## Related guides

- [Server: store, policy & publish](./policy.md)
- [Server: API & client surface](./exports.md)
