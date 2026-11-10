-- Development commands. Self-disabling: with Config.debug off this file
-- registers nothing at all, so a production server carries no command surface
-- for putting a player on a restricted channel.

Voice = Voice or {}

if not Config.debug then return end

---Dumps every occupied radio channel and its members to the server console.
RegisterCommand('voicedump', function(src)
    -- Console only (`src == 0`). An in-game admin command that printed every
    -- channel's membership would be a live map of which frequencies the police
    -- are on, which is precisely what the restriction table protects.
    if src ~= 0 then return end

    for _, channel in ipairs(Voice.store.activeRadioChannels()) do
        print(('[kora_voice] radio %d: %s'):format(
            channel, table.concat(Voice.store.radioMembersOf(channel), ', ')))
    end
end, true)

---Runs a channel request AS a player, through the untrusted path, and prints
---the answer. The point is to exercise the policy layer exactly as a client
---would -- a dev command that called `assign` would prove nothing.
RegisterCommand('voicerequest', function(src, args)
    if src ~= 0 then return end

    local target = tonumber(args[1])
    local channel = tonumber(args[2])
    if not target then return print('[kora_voice] usage: voicerequest <src> <channel|0>') end

    local ok, reason = Voice.api.request(target, channel)
    print(('[kora_voice] request(%d, %s) -> %s%s'):format(
        target, tostring(channel), tostring(ok), reason and (' (' .. reason .. ')') or ''))
end, true)
