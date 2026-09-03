# qbvoice agent guide

Proximity voice, server-authoritative radio channels, phone calls, submixes and
wall muffling. See `docs/index.md` for the module reference. This file is about
how to change it without breaking it.

## The authority boundary — read this before touching anything

**Channel membership lives on the server. A client REQUESTS; the server DECIDES
and PUBLISHES.**

This is not a preference. The only thing between a player and a channel's audio
is the Mumble voice target their client builds. A client that can add a member to
that target — or evaluate its own eligibility, or write its own membership — can
listen to any channel on the server, including whatever the police are using.
Every rule below follows from that one sentence.

1. **`Config.radio.restricted` never leaves the server.** No client export, no
   push, no state-bag key carries it or any part of it. `Voice.channels`
   (shared) is a *lookup* only; the *decision* is `Voice.policy.canJoin`, which
   is server-only and reads the player's job.

2. **Two api entry points, named differently on purpose.**
   `Voice.api.assign` is trusted and skips policy — it is for another **server**
   resource's export call. `Voice.api.request` is untrusted and enforces
   policy — it is the only api function `server/net.lua` and
   `server/compat.lua` may call. A `trusted` *flag* would default, and a
   defaulted flag on the wrong call site is a client on the tac channel. A
   missing function name is a hard error. `test/smoke/authority.lua` installs a
   tripwire over `assign` and fails if `request` ever reaches it.

3. **A net event's target is `source`, never a payload field.** pma-voice's
   inbound events let the payload name the player; that means any client can put
   any player on any channel by firing a well-known event name. Do not "restore
   compatibility" by honouring a payload `src`.

4. **Clients never extend a roster.** `client/sync.lua` replaces the member array
   with exactly what the server pushed. A merge, an append, or a locally-derived
   member is a self-granted voice target.

5. **Every client-facing callback carries a `rateLimit`.** A join request is the
   one message a client sends unprompted, and an unlimited one lets a client walk
   every channel id looking for an open frequency. `test/smoke/authority.lua`
   fails if a registration appears without one.

6. **There is no client-reachable way to JOIN a call.** Leaving is fine (it
   grants no audio); joining would be a client asking to listen to somebody
   else's phone call. A phone resource assigns both ends through the trusted
   export.

## Shape

```
config.lua              policy and tuning only -- no membership, ever
shared/modes.lua        the ONE proximity bounds check, both realms
shared/channels.lua     channel normalisation + restriction LOOKUP (not decision)
server/store.lua        pure bookkeeping: who is on what. No authority, no publication
server/policy.lua       the authority DECISION: hooks -> grants -> config
server/publish.lua      the only place membership leaves the server
server/api.lua          composes the three above; assign (trusted) vs request (untrusted)
server/net.lua          the client-facing surface; may only call `request`
server/compat.lua       pma-voice events + export identity
server/dev.lua          debug commands, self-disabling
client/state.lua        local mirror of what the server published
client/proximity.lua    mode index -> voice-distance natives
client/submix.lua       radio + megaphone effect chains
client/targets.lua      clear-and-rebuild the voice target, on a bounded tick
client/sync.lua         inbound subscriptions; arms them AFTER the session is live
client/keybinds.lua     three keys, none of which changes membership
client/exports.lua      local audio properties + requests
client/compat.lua       pma-voice export identity, client half
```

Load order is declared file-by-file in `fxmanifest.lua` and is load bearing:
`store` owns the registry every server file reads, `policy` and `publish` are the
halves `api` composes, `net` may only exist after `api`. Client-side, `state` owns
the mirror everything reads and `sync` needs `targets` already defined.

## Rules

**One bounds check per thing.** `Voice.modes.clamp` is the only place a mode index
is bounded; `Voice.channels.normalise` is the only place a channel id is. Both are
reached from a keypress *and* from an untrusted pma-voice call site, and a second
subtly-different check is how one path ends up more permissive than the other.

**Clear a replicated state key with an explicit `false`.** Never
`state:set(key, nil, true)`. A nil write is a key *deletion*, and a deletion does
not replicate the way a value change does — clients keep reading the last channel
forever. `server/publish.lua` spells this as an `if`, not as
`value == nil and false or value`: that idiom evaluates to `false or nil` and
hands back the nil it was meant to replace. It reads correct and is silently
wrong. `test/smoke/publish.lua` fails on either mistake.

**Arm client bag handlers after `NetworkIsSessionStarted()`, and spin until the
server id is > 0.** At chunk load `GetPlayerServerId(PlayerId())` is `-1`, and
`AddStateBagChangeHandler` resolves the bag *name* once — a handler registered at
load subscribes to `player:-1` forever and the radio silently never works. Then
do the catch-up resync, *after* the handlers exist.

**Act on a bag handler's `value` argument.** The handler runs before the value is
committed to the local store, so re-reading the bag inside it yields the previous
value for the key that just changed. `test/mocks.lua`'s `fireBagChange`
deliberately never commits, so a re-read fails offline.

**No backtick hash literals, anywhere.** A CFX `` `default` `` is not valid Lua
5.4: a file containing one cannot be `dofile`'d by the smoke tests and dies
*silently*, printing a suite header with no summary. Use `GetHashKey`. Always
compare `run.sh`'s header count against its summary count.

**Never per-frame.** The voice-target rebuild walks every in-scope player and
fires a synchronous shape test per nearby one. It belongs on
`Config.mumble.refreshInterval` via `QB.timers.setInterval`, with an immediate
rebuild on membership change. `test/smoke/targets.lua` asserts exactly one timer
at the configured interval.

**Clear and rebuild the voice target; never edit it.** There is no
"remove one player from a target" native, so a partial update leaves a member who
can still hear a channel they left.

**Add members by server id.** `MumbleAddVoiceTargetPlayerByServerId`, not
`MumbleAddVoiceTargetPlayer`. A radio member outside this client's scope has no
local player handle, and a radio that only works within earshot is not a radio.
The mocks deliberately do not define the handle-taking native, so a regression
onto it fails offline.

**Prefer a grant to a funcref.** `grantRadioChannels` is data and survives the
granting resource restarting; an `addRadioPolicy` funcref dies with it. Offer the
hook, recommend the grant.

## Threading

`client/targets.rebuild` fires synchronous shape tests. It must never be called
inline from a state-bag handler or an event handler — those chains are shared with
every other resource on the server. `client/sync.lua` always hands the rebuild to
a `CreateThread`.

`Voice.targets.rebuild` has a reentrancy guard. The bounded tick and a
change-driven rebuild can land in the same frame, and two interleaved rebuilds
would each clear the other's half-built target, leaving a player audible to
nobody.

## Do not

- Add a NUI. The mic indicator belongs to qbhud, which reads
  `NetworkIsPlayerTalking` and needs nothing from here. A second indicator puts
  two on screen.
- Add a `Config.radio.restricted` read anywhere in `client/` or `shared/` that
  answers "may *I* join".
- Route `server/compat.lua` or `server/net.lua` through `Voice.api.assign`.
- Mutate `Voice.store` from anywhere but `server/api.lua`. The store does not
  publish, so a direct write is a membership change no client ever hears about.
