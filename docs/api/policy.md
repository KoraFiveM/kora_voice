---
title: "Server: store, policy & publish"
sidebar_position: 3
---


# Server: store, policy & publish

The three layers `server/api.lua` composes. `store` is pure bookkeeping (no decisions, no publication); `policy` is the ONLY authority decision for radio joins and is never evaluated on the client; `publish` is the only place membership actually leaves the server, on two channels that answer different questions: the replicated state bag ("what channel am I on", visible to everyone) and the roster push ("whose audio may I receive", sent only to that channel's own members).

Namespace: `Voice.store / Voice.policy / Voice.publish` · Source: `server/store.lua, server/policy.lua, server/publish.lua`

## How it works

A character's state-bag write for `Config.state.radio`/`Config.state.call` always writes an explicit `false` for 'no channel', never a nil/deleted key -- a nil write is a key DELETION in FiveM's state-bag system and does not replicate the same way a value change does, which would otherwise leave every client forever showing a stale last-known channel. Grants and hooks are keyed by `src` (a connection), so both are dropped on disconnect (`Voice.policy.forget`) to stop a reused source id inheriting the previous occupant's tac-channel grant.

## Terms used on this page

| Term | Meaning |
| --- | --- |
| Legacy channel check | `Voice.policy.addChannelCheck(channel, fn)` -- a channel-specific check that owns its frequency outright, evaluated before the generic hook list. Cleared (not silently left open) automatically if the registering resource stops. |
| characterOwned | True only when `Voice.policy.canJoin` approved a channel via the static `Config.radio.restricted` fallthrough, as opposed to a hook or grant -- this is what lets `commitRadio` auto-clear that membership on `QBCore:Server:OnPlayerUnload` without also clearing a membership a job resource explicitly assigned. |

## Functions

Selected functions from each of the three files; see the source for the complete set (`setCall`/`getCall`/`callMembersOf`, `removeHook`/`addChannelCheck`/`grantsOf`, `membership`/`resync`, and more follow the same patterns).

### `Voice.store.setRadio(src, channel)`

Records (or clears, with `channel = nil`) a player's radio membership.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Required. |
| `channel` | integer \| nil | Required. |

**Returns**

- **`integer|nil previous, integer|nil current` -- the publisher needs BOTH to re-push the roster of the channel just left.**

**Example**

```lua
local previous, current = Voice.store.setRadio(1, 2)
```

**Representative console output**

```text
An emptied channel's member table is dropped entirely, since channel ids are 1 to 1000 and a long-running server would otherwise accumulate one table per channel anyone ever tuned to.
```

### `Voice.store.getRadio(src)`

A player's current radio channel.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Required. |

**Returns**

- **`integer | nil`.**

**Example**

```lua
Voice.store.getRadio(1)
```

### `Voice.store.radioMembersOf(channel)`

Sorted member list of a radio channel.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `channel` | integer \| nil | `nil` returns an empty list. |

**Returns**

- **`integer[]` -- sorted, so repeated calls are deterministic for roster-change comparisons.**

**Example**

```lua
Voice.store.radioMembersOf(2) -- { 1, 5, 9 }
```

### `Voice.store.forget(src)`

Forgets a disconnecting player entirely.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Required. |

**Returns**

- **`integer|nil radio, integer|nil call` -- the channels the player was just removed from, so the caller can re-push those rosters.**

**Example**

```lua
local radio, call = Voice.store.forget(1)
```

**Representative console output**

```text
Called from `Voice.api.drop` on `playerDropped`.
```

### `Voice.policy.addHook(fn)`

Registers a dynamic policy hook, run in registration order ahead of grants and `Config.radio.restricted`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `fn` | function(src, channel): boolean\|nil, string\|nil | `false, reason` refuses; `true` allows (overrides the restriction table); `nil` abstains and falls through. |

**Returns**

- **`integer` handle, for `removeHook`.**

**Example**

```lua
local handle = Voice.policy.addHook(function(src, channel) ... end)
```

**Representative console output**

```text
A hook that errors is treated as an abstain (logged, never crashes the radio) -- see `exports.addRadioPolicy`.
```

### `Voice.policy.grant(src, channels)`

Grants (or, with `channels = nil`, revokes) a set of channels a player may join regardless of `Config.radio.restricted`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Required. |
| `channels` | integer[] \| integer \| nil | A single channel, a list, or nil/empty to revoke. |

**Returns**

- **`integer` count of channels now granted.**

**Example**

```lua
Voice.policy.grant(1, { 1, 2, 10 })
```

**Representative console output**

```text
Data, not a funcref -- survives the granting resource restarting, unlike a hook.
```

### `Voice.policy.canJoin(src, channel)`

The full authority decision for a (normalised) radio channel.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Required. |
| `channel` | integer | Required; must already be normalised -- this function does not bounds-check. |

**Returns**

- **`boolean allowed, string|nil reason, boolean|nil characterOwned` -- `characterOwned` is true only when the channel was approved by falling through to the static job-rule in `Config.radio.restricted` (as opposed to a hook or grant), which is what makes that membership get cleared automatically on character unload.**

**Example**

```lua
local ok, reason = Voice.policy.canJoin(1, 2)
```

**Representative console output**

```text
Order: legacy channel check (owns the frequency outright) -> ordered hooks -> grants -> `Config.radio.restricted` fallthrough (open if absent).
```

### `Voice.publish.roster(kind, channel)`

Pushes a channel's member roster to every one of its own members, filtered per-recipient by routing bucket.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `kind` | 'radio' \| 'call' | Required. |
| `channel` | integer \| nil | No-op for nil. |

**Returns**

- **No return value.**

**Example**

```lua
Voice.publish.roster('radio', 2)
```

**Representative console output**

```text
Each recipient is told only the members who SHARE their own bucket -- not the full channel roster -- because Mumble has no bucket concept and would happily carry audio across them if the client built a voice target from an unfiltered list.
```

### `Voice.publish.cleared(src, kind)`

Tells one player their membership of `kind` was cleared, even though a roster push alone would never reach them (they are no longer a current member of anything).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Required. |
| `kind` | 'radio' \| 'call' | Required. |

**Returns**

- **No return value.**

**Example**

```lua
Voice.publish.cleared(1, 'radio')
```

**Representative console output**

```text
Sends `channel = false` explicitly rather than omitting the field, matching the state-bag clearing convention.
```

## Limits and related APIs

Server-only in every file here. `Voice.store._reset()` and `Voice.policy._reset()` exist and are used by the test suite; calling them in production would silently wipe all live membership and policy state.

## Related guides

- [Proximity modes & channel helpers](./modes-channels.md)
- [Server: API & client surface](./exports.md)
