# kora_voice

First-party voice for the kora_lib framework, and a drop-in replacement for
pma-voice: whisper/normal/shout proximity, numbered radio channels, phone calls
that run alongside the radio, radio and megaphone submixes, and muffling through
walls.

Everything a player can *hear* comes from a Mumble voice target, and that target
is built from what the **server published**. A client asks to join a channel; it
never says that it has.

---

## The authority boundary

This is the one design constraint the whole resource is arranged around.

**Channel membership lives on the server.** The server decides, records, and
publishes. A client may send a *request*; the answer arrives as a published
value it then renders.

```
client                        server
------                        ------
requestRadio(2)  ---------->  policy: hooks -> grants -> Config.radio.restricted
                              |
                              +-- refused: nothing recorded, nothing published
                              |
                              +-- allowed: store  -> state bag -> roster push
                                                                      |
        state bag / roster push  <-----------------------------------—+
        |
        +-- MumbleClearVoiceTarget + MumbleAddVoiceTargetPlayerByServerId
```

Why it has to be this way: the only thing between a player and a channel's audio
is the voice target their client builds. A client that could add a member to that
target itself could listen to any channel on the server — the police tac channel
included — with no server involvement at all. So `Config.radio.restricted` is
never sent to a client, no client-reachable code path evaluates it, and there is
no client export or event anywhere in this resource that writes membership.

The two server entry points are named differently on purpose:

| Function | Trust | Reachable from | Policy checked |
| --- | --- | --- | --- |
| `Voice.api.assign` | trusted | another **server** resource's export call | no |
| `Voice.api.request` | untrusted | the rate-limited client callback only | **yes** |

A flag would have defaulted; a missing function name is a hard error.

---

## Proximity

Three modes by default, cycled with one key (`Z`):

| Mode | Range |
| --- | --- |
| Whisper | 3 m |
| Normal | 12 m |
| Shout | 35 m |

The set is `Config.proximity.modes` and is walked by index, so adding a fourth
mode is a config edit. `Config.proximity.wrap = false` makes the ends saturate
instead of wrapping, which stops "one more press" quietly dropping a shouting
player to a whisper.

Four voice-distance natives are set on every change —
`MumbleSetAudioInputDistance`, `MumbleSetAudioOutputDistance`,
`MumbleSetTalkerProximity` and `NetworkSetTalkerProximity` — each guarded, because
which of them a given FiveM build honours varies.

A respawn returns the player to `Config.proximity.default`. Shouting is a
deliberate act, and a player who died mid-shout should not respawn broadcasting
to 35 metres.

---

## Radio

Numbered integer channels (`Config.radio.minChannel`..`maxChannel`), because a
channel id is the thing a job resource, a phone app and a physical radio item
all have to agree on.

Push-to-talk on its own key (caps lock by default), separate from proximity talk
— a player has to be able to say something to the room without it going out over
the air. Pressing it with no channel does nothing, silently.

### The radio item

Using the `radio` inventory item (`Config.radio.item`) opens a small frequency
dialog. The server registers the use handler through `kora_core`'s
`createUseable`, and re-registers it when `kora_inventory` restarts.

Flow: use item → server tells the client to open the dialog
(`kora_voice:client:openRadio`) → the client sends a normal request through
`addPlayerToRadio` (or `removePlayerFromRadio` for 0 or an empty value) → the
server decides as it does for every request. Refusals show the server's generic
reason. Cancelling the dialog changes nothing. The item grants no membership on
its own and is not required to talk.

### Restricting frequencies

Three ways a channel opens up, evaluated in this order:

**1. A policy hook** — for a decision that genuinely has to be made at request
time.

```lua
local handle = exports.kora_voice:addRadioPolicy(function(src, channel)
    if channel ~= 2 then return nil end                 -- abstain: not ours
    if not isFirefighter(src) then return false, 'Fire only.' end
    return true                                          -- allow, overriding config
end)
```

`nil` means *abstain* and is the right default — a hook that returned `false` for
everything outside its own range would veto every other job's channels. A hook
that **errors** abstains too: the erroring resource is the broken one, and taking
voice down with it would turn one bug into a server-wide outage.

**2. A per-player grant** — the recommended integration, because it is data. A
funcref is only callable while the resource that created it is running, so a job
resource restarting leaves a dead hook behind; a grant survives.

```lua
exports.kora_voice:grantRadioChannels(src, { 1, 2, 3 })
exports.kora_voice:revokeRadioChannels(src)
```

Grants are dropped on disconnect — source ids are reused, and a leftover grant
would hand the tac channel to whoever next occupies that id.

**3. `Config.radio.restricted`** — the static table.

```lua
Config.radio.restricted = {
    [2] = { label = 'LEO Tac 1', jobTypes = { 'leo' }, onDuty = true },
}
```

`jobs` matches a kora_core job **name**, `jobTypes` a kora_core job **type** (so `leo`
covers police, sheriff and state troopers at once). A channel absent from the
table is **open**; an entry with neither `jobs` nor `jobTypes` is **locked**, so a
config typo fails closed.

The refusal message is deliberately generic. Naming the job that *would* be
allowed tells every civilian which channel the police are on.

---

## Phone calls

A call channel is a second, completely independent membership: its own store, its
own state-bag key, its own contribution to the voice target. A radio
transmission and a live call coexist, because an officer on the phone to a
witness while dispatch talks over the air is normal play.

Call channels are **not** restriction-checked and **not** client-joinable. A phone
resource already decided who may ring whom and assigns both ends through the
trusted server export; a client asking to join a call channel is a client asking
to listen to somebody else's phone call. Hanging up *is* client-reachable —
leaving grants no audio.

The call id space is much larger than the radio's, because phone resources use
the phone number as the channel.

---

## Submixes and muffling

Two submixes, created once at load: `radio` (band-limited and ring-modulated) and
`megaphone` (a much wider, harsher band). Parameter names are hashed with
`GetHashKey`, never with CFX backtick literals — a backtick literal is not valid
Lua 5.4 and would make the smoke tests die silently.

Radio audio is filtered **by membership, with an earshot exception**: a channel
member standing next to you is heard through the air unprocessed, because
filtering them would make a face-to-face conversation sound like a radio. A member
who is *not* in your proximity grid has no path to you but the radio, so they are
filtered. (pma-voice instead toggles this per transmission off its own
`radioActive` event; membership plus earshot needs no extra round trip and gives
the same answer for every case either resource can distinguish.)

`setRadioVolume` / `setCallVolume` apply to the same set, and for the same
reason: a speaker you can hear through the air is proximity audio, so a *radio*
volume has no business reducing them. Mumble has exactly one volume override slot
per speaker, so occlusion and the per-path volumes are combined into a single
number before it is written — the quietest wins — rather than each writing their
own and silently discarding the other. `Config.calls.submix` (off by default)
also routes call audio through the radio effect, for a server that wants the
retro-telephone sound; a phone is not a handheld radio, so it is not the default.

Muffling is a per-speaker Mumble volume override, not a proximity change —
proximity is symmetric and shared, occlusion is per-pair. A synchronous shape
test at chest height (`Config.muffling.heightOffset`, so a slope does not read as
a wall) decides, and only for speakers inside `Config.muffling.maxDistance`. The
override is lifted with `-1.0`, Mumble's "no override" — writing `1.0` would pin
the speaker at full volume and defeat every other volume control.

---

## Voice targets

One numbered target (`Config.mumble.targetId`), **cleared and rebuilt**. There is
no "remove one player from a target" native, so rebuilding is the only way to drop
a member — and a stale target is a listening exploit, not a cosmetic bug.

Three contributions, one of them local:

* the **proximity grid**, derived from `GetActivePlayers`. That native is already
  routing-bucket-aware — a player in another bucket is not in scope and does not
  appear — which is why the grid needs no bucket filter of its own.
* the **radio roster**, exactly as the server pushed it, and only while the talk
  key is held.
* the **call roster**, likewise, with no key.

The rosters *do* need bucket filtering, and it happens **on the server**: a radio
member in another bucket is a server fact with no local scope entry, and Mumble
has no concept of a bucket at all — hand a client a member from another world and
the audio flows. `Config.buckets.enforce = false` turns it off for a server that
deliberately uses radio across instances.

The rebuild runs on a **bounded tick** (`Config.mumble.refreshInterval`, 500 ms),
never per frame: it walks every in-scope player and fires a shape test per nearby
one. Membership changes additionally trigger an immediate rebuild, because half a
second of silence after joining a channel reads as the radio being broken.

---

## Server exports

```lua
exports.kora_voice:setPlayerRadio(src, channel)        --> ok, err   -- trusted, no policy check
exports.kora_voice:addPlayerToRadio(src, channel)      --> ok, err   -- alias
exports.kora_voice:removePlayerFromRadio(src, channel) --> removed   -- channel is a GUARD, not a target
exports.kora_voice:setPlayerCall(src, channel)         --> ok, err
exports.kora_voice:removePlayerFromCall(src, channel)  --> removed
exports.kora_voice:refreshVoiceTargets(src)             --> ok, err   -- republish current bucket-filtered rosters

exports.kora_voice:getPlayersInRadioChannel(channel)   --> { [src] = true }   -- pma-voice shape
exports.kora_voice:getPlayersInCall(channel)           --> { [src] = true }
exports.kora_voice:getRadioMembers(channel)            --> integer[]          -- sorted array form
exports.kora_voice:getRadioChannel(src)                --> integer | false
exports.kora_voice:getCallChannel(src)                 --> integer | false

exports.kora_voice:grantRadioChannels(src, channels)   --> count
exports.kora_voice:revokeRadioChannels(src)            --> 0
exports.kora_voice:addRadioPolicy(fn)                  --> handle
exports.kora_voice:removeRadioPolicy(handle)           --> boolean
exports.kora_voice:isChannelRestricted(channel)        --> boolean
```

The server `refreshVoiceTargets(src)` republishes that player's current radio and
call rosters after a routing bucket change, without changing membership. The
shipped Kora player bucket setters notify the server-local
`kora_voice:server:bucketChanged` event. External resources using the raw
`SetPlayerRoutingBucket` native must call this export or trigger that local event
after the native succeeds. The no-argument client export only rebuilds the targets
from the last server roster; it does not fetch a new roster.

`removePlayerFromRadio`'s channel argument is a **guard**: the removal only
happens if the player is on that exact channel. A radio UI a moment behind the
server fires "leave channel 3", and an unconditional removal would kick the player
off the channel 5 they just joined.

`getRadioChannel` returns `false`, not `nil`, for "no channel" — a `nil` does not
survive the exports boundary as a distinguishable value.

---

## Client exports

```lua
exports.kora_voice:addPlayerToRadio(channel)      --> ok, reason   -- a REQUEST; must run in a coroutine
exports.kora_voice:removePlayerFromRadio()        --> boolean
exports.kora_voice:removePlayerFromCall()         --> boolean
exports.kora_voice:getRadioChannel()              --> integer | false   -- what the SERVER published
exports.kora_voice:getCallChannel()               --> integer | false

exports.kora_voice:setTalkingMode(mode)           --> index, range      -- index or name ('whisper')
exports.kora_voice:cycleTalkingMode(step)         --> index, range
exports.kora_voice:getTalkingMode()               --> { index, name, label, range }
exports.kora_voice:isRadioActive()                --> boolean
exports.kora_voice:setMegaphone(active)           --> changed

exports.kora_voice:setRadioVolume(volume)         --> applied           -- 0.0-1.0 or 0-100
exports.kora_voice:setCallVolume(volume)          --> applied
exports.kora_voice:setVoiceProperty(name, value)  --> ok
exports.kora_voice:getVoiceProperty(name)         --> any
exports.kora_voice:refreshVoiceTargets()          --> boolean
```

`addPlayerToRadio` returns whether the **server agreed** — not that the local
player is on that channel. Membership arrives afterwards as a published value.
Code that needs to act on the real thing should listen for
`kora_voice:client:radioChanged`.

`false, nil` means the round trip **timed out**; `false, '<reason>'` means the
server refused. They are different events and this resource never conflates them.

`setVoiceProperty` accepts `radioVolume`, `callVolume`, `micClicks`, `submix`,
`talkingMode` and `muffling`. Every one is local audio only — there is
deliberately no property that changes membership. `getVoiceProperty` additionally
*reads* `radioChannel` and `callChannel`; reading is fine, writing is not.

---

## Events

Client-side, emitted:

| Event | Payload |
| --- | --- |
| `kora_voice:client:radioChanged` | `channel \| false` |
| `kora_voice:client:callChanged` | `channel \| false` |
| `kora_voice:client:radioActive` | `boolean` |
| `kora_voice:client:megaphone` | `boolean` |
| `pma-voice:setRadioChannel` | `channel \| 0` |
| `pma-voice:setCallChannel` | `channel \| 0` |
| `pma-voice:radioActive` | `boolean` |

Server-side, emitted: `kora_voice:server:radioChanged(src, channel, previous)` and
`kora_voice:server:callChanged(src, channel, previous)`. Both carry `false` rather
than `nil` for "no channel", so the value survives an event boundary.

Client-side, accepted: `pma-voice:setTalkingMode`, `pma-voice:setVoiceProperty` —
both local audio properties, so a server setting one grants nothing.

Server-side, accepted (as **untrusted client requests**):
`pma-voice:setPlayerRadio`, `pma-voice:addPlayerToRadio`,
`pma-voice:removePlayerFromRadio`, `pma-voice:removePlayerFromCall`.

---

## State bags

| Key | Value |
| --- | --- |
| `kora_voice:radio` | integer channel, or `false` |
| `kora_voice:call` | integer channel, or `false` |

Written server-side on the player's bag, and **cleared with an explicit
`false`, never a nil**. A nil write is a key *deletion*, and a deletion does not
replicate to clients the way a value change does — every client would keep reading
the last channel forever. Every reader here treats `nil` and `false` alike, so a
missing key is safe but a deletion is not.

Both keys are written when a player joins, so a reader never has to distinguish
"never set" from "not replicated yet".

`Config.state.replicate = false` makes them server-only. FiveM has no owner-only
player bag — a replicated key is visible to everybody — and that is accepted by
default because *knowing* a player is on channel 2 is not the exploit; *listening*
is, and listening is gated by the server-built voice target. Turn it off if you
would rather other players could not see channel numbers; the owner still learns
its own membership from the roster push.

---

## Replacing pma-voice

Stop `pma-voice`, `ensure kora_voice`. kora_voice refuses to start while a real
pma-voice folder is running (`Config.compat.refuseOnConflict`) — two resources
rebuilding the same Mumble voice target fight every tick, and the symptom is
intermittent one-directional audio that reads as a network fault.

Existing call sites keep working through three separate Cfx mechanisms, none of
which implies the others:

| Mechanism | Satisfied by |
| --- | --- |
| `dependency 'pma-voice'` | `provide 'pma-voice'` in `fxmanifest.lua` |
| `exports['pma-voice']:Fn()` | the `__cfx_export_pma-voice_<name>` handlers in `{server,client}/compat.lua` |
| `shared_script '@pma-voice/...'` | **neither** — that would need a real resource of that name in `resources/[compat]/` |

Nothing in this workspace uses the third form. See
`resources/[compat]/README.md` if something ever does.

**The one deliberate divergence:** pma-voice's inbound server events let the
*payload* name the player, which means any client can put any player on any
channel by firing a well-known event name. Here every net event's target is
`source`, and a payload `src` is ignored. Server code that legitimately needs to
assign another player's channel calls the export, which is trusted.

### kora_hud

No integration needed, and none was added. kora_hud's mic indicator reads FiveM's
own `NetworkIsPlayerTalking`, which reflects whichever Mumble-backed voice
resource is on top of it. Its `Config.voice.resource = "pma-voice"` is a label,
not a lookup. A HUD that wants to distinguish radio traffic from proximity
speech can call `exports.kora_voice:isRadioActive()`.

---

## Testing

`test/run.sh` — plain Lua, no FXServer, no Mumble, no database.

Each suite loads only the realm it exercises, and neither realm's suites mock the
other's natives, so a file reaching across the boundary fails offline rather than
in game. `test/mocks.lua` records rather than simulates the two things the tests
are about: every state-bag write (with its exact value *and* whether it was a
nil, so the clearing convention is testable) and every Mumble native call in
order (so "cleared before rebuilt" is testable).

`test/mocks.lua`'s `fireBagChange` fires handlers **without** committing to the
local store, matching FiveM's real ordering — a handler that re-read the bag
instead of using its `value` argument fails here.

Compare the header count against the summary count in the output: a CFX backtick
hash literal anywhere in a dofile'd file kills plain Lua *silently*, printing a
header and no summary.

## Legacy channel checks

The server exports `addChannelCheck(channel, callback)` and
`removeChannelCheck(channel)` are also available under `pma-voice`. A registered
check owns authorization for that channel before generic hooks, grants and the
configured restrictions. Callbacks receive the requesting player's server ID.
A refusal, error or stopped callback provider denies new joins; restarting the
provider must register its checks again.

Legacy client `addPlayerToCall` remains unsupported: a client-selected call ID
cannot authorize membership. Phone servers must assign both participants through
the trusted `setPlayerCall` server export. Native kora_phone uses that integration.
