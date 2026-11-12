---
title: Items
sidebar_position: 8
---

# Items

## radio

The item name is `Config.radio.item` (default `radio`). At server start, and again when `kora_inventory` starts, the server calls `exports.kora_core:createUseable(item, handler)`. If registration fails (for example `kora_core` is not ready) a console line is printed and the resource keeps running.

Using the item sends `kora_voice:client:openRadio` to the player, which opens a `Frequency` number dialog (through `Kora.nui.openInputDialog`) prefilled with the current channel. Behaviour:

- Cancelling changes nothing.
- 0 or an empty value leaves the channel.
- A non-whole number, or a channel outside `Config.radio.minChannel` to `maxChannel`, shows an error notification locally.
- Otherwise the client calls the `addPlayerToRadio` client export (a normal request). A refusal shows the server's reason; a timeout stays silent. Success shows `Connected to frequency N`.
- Only one dialog can be open at a time.

The item grants no membership by itself and is not required to talk on the radio. The item definition itself must exist in your inventory configuration; this resource does not define it, and where that definition lives (the config comment says `kora_core`) was not verified here.
