# Converted from the communitybot legacy tests by kora-qa-panel/scripts/convert-legacy.mjs.
# The """ block under each Scenario is the original test text, verbatim. Review before applying.
Feature: kora_voice — game tests

  @kora_voice @legacy:voice-start @target:1
  Scenario: Resource starts cleanly
    """
    1. After the server restart (or /server resource kora_voice), watch the server console.
    2. Join and open F8.
    Expect: kora_voice starts with no red errors and no message about a pma-voice conflict. Voice chat works as soon as you are spawned in.
    """
    When I manually: watch the server console after the resource starts
    And I manually: join the server and open F8
    And the F8 console should show no errors
    Then I confirm: kora_voice starts with no red errors and no message about a pma-voice conflict in the server console
    And I confirm: voice chat works as soon as I am spawned in
    And there should be no script errors

  @kora_voice @legacy:voice-basic @target:2 @needs:players:2 @manual
  Scenario: Two players can hear each other
    """
    Needs 2 testers. 1. Both turn Voice Chat on in Settings and stand next to each other.
    2. Take turns talking.
    Expect: each of you hears the other clearly, in both directions, with no echo, cutting out or one-way audio. Say if one of you could only hear and not be heard.
    """
    When I manually: turn Voice Chat on in Settings and stand next to a second player who has done the same
    And I manually: take turns talking with the second player
    Then I confirm: each of us hears the other clearly in both directions, with no echo, cutting out or one-way audio

  @kora_voice @legacy:voice-distance @target:2 @needs:players:2 @manual
  Scenario: Voice gets quieter with distance
    """
    Needs 2 testers. 1. Both on Normal range. One talks while the other slowly walks away, up to about 20 metres.
    Expect: the voice fades as you move apart and is gone at roughly 12 metres. It comes back when you walk back. Voices also come from the right direction (left/right).
    """
    When I manually: set my range to Normal and ask a second player to also be on Normal range
    And I manually: talk while the second player slowly walks away up to about 20 metres
    Then I confirm: the voice fades as we move apart and is gone at roughly 12 metres
    When I manually: ask the second player to walk back towards me while I keep talking
    Then I confirm: the voice comes back when the second player walks back
    And I confirm: voices come from the right direction (left/right)

  @kora_voice @legacy:voice-modes @target:2 @needs:players:2 @checklist @checklist:kora_voice:proximity-cycle @cat:social-and-comms @checklist:kora_voice:proximity-hearing @manual
  Scenario: Whisper, Normal and Shout ranges
    """
    Needs 2 testers. 1. Press ` to cycle the range. Each press shows a Voice notification such as Whisper (3m), Normal (12m), Shout (35m).
    2. Test how far each one carries with the other tester walking away.
    Expect: Whisper is only heard right next to you (about 3 m), Normal across a room (about 12 m), Shout across a street (about 35 m). After Shout the next press goes back to Whisper.
    Also checklist kora_voice:proximity-cycle (Cycle talk range (backtick key)): Press the backtick/grave key to cycle Whisper 3m, Normal 12m, Shout 35m; notification states the mode; docs mention Z but config uses GRAVE.
    Also checklist kora_voice:proximity-hearing (Range changes who hears you): With a second player, check they hear you at ~3m in whisper, ~12m normal, ~35m shout and not beyond.
    """
    When I manually: press ` to cycle the talk range
    Then I confirm: each press shows a Voice notification such as Whisper (3m), Normal (12m) or Shout (35m)
    When I manually: ask a second player to walk away while I talk on each range
    Then I confirm: Whisper is only heard right next to me (about 3 m)
    And I confirm: Normal is heard across a room (about 12 m)
    And I confirm: Shout is heard across a street (about 35 m)
    When I manually: press ` once more after Shout
    Then I confirm: after Shout the next press goes back to Whisper

  @kora_voice @legacy:voice-mode-key @target:1
  Scenario: Range key can be rebound
    """
    1. In Settings > Key Bindings > FiveM find "Voice: cycle talk range (whisper/normal/shout)" and bind it to another key.
    2. Press the new key.
    Expect: the new key cycles the range with the notification, and ` no longer does. The new key is kept after reconnecting.
    """
    When I manually: in Settings > Key Bindings > FiveM bind "Voice: cycle talk range (whisper/normal/shout)" to another key
    And I manually: press the new key
    Then I confirm: the new key cycles the range with the notification
    When I press the "`" key
    Then I confirm: ` no longer cycles the range
    When I manually: reconnect to the server
    Then I confirm: the new key binding is kept after reconnecting

  @kora_voice @legacy:voice-respawn @target:2 @checklist @checklist:kora_voice:respawn-reset @cat:social-and-comms
  Scenario: Range goes back to Normal on respawn
    """
    1. Switch to Shout (or Whisper).
    2. Die and respawn.
    Expect: after the respawn you are back on Normal (12 m) and the mic icon shows Normal talk. Voice chat still works after the respawn.
    Also checklist kora_voice:respawn-reset (Respawn resets to Normal range): Die/respawn while shouting: range returns to Normal.
    """
    Given I am dead
    When I manually: switch to Shout (or Whisper) before dying, then respawn
    Then I should be alive
    And I confirm: after the respawn I am back on Normal (12 m)
    And I confirm: the mic icon shows Normal talk
    And I confirm: voice chat still works after the respawn

  @kora_voice @legacy:voice-radio-item @target:2
  Scenario: Radio item opens the frequency dialog
    """
    Needs a radio item. 1. Use the radio from your inventory.
    2. Enter 50 and confirm.
    Expect: a small Radio dialog asks for a Frequency (0 leaves the channel). After confirming you get "Connected to frequency 50". Using the radio again shows 50 already filled in. Cancelling the dialog changes nothing.
    """
    Given I have 1 "radio"
    When I use the "radio"
    Then a menu titled "Radio" opens
    And I confirm: the Radio dialog asks for a Frequency (0 leaves the channel)
    When I manually: enter 50 and confirm
    Then I should see a notification containing "Connected to frequency 50"
    When I use the "radio"
    Then I confirm: the dialog shows 50 already filled in
    When I manually: cancel the dialog
    Then I confirm: cancelling the dialog changes nothing

  @kora_voice @legacy:voice-radio-talk @target:2 @needs:players:2
  Scenario: Talk on the radio with Caps Lock
    """
    Needs 2 testers with radios. 1. Both join the same frequency (for example 50) and walk well out of earshot of each other.
    2. Take turns holding Caps Lock and talking.
    Expect: you hear each other only while Caps Lock is held, with a click when the talker presses and releases. The voice sounds like a radio (thinner, filtered). Without Caps Lock you are not heard over the radio.
    """
    Given I have 1 "radio"
    When I use the "radio"
    And I manually: enter 50 and confirm, with a second player (who has a radio) joining the same frequency
    And I manually: walk well out of earshot of the second player
    And I manually: take turns holding Caps Lock and talking
    Then I confirm: we hear each other only while Caps Lock is held, with a click when the talker presses and releases
    And I confirm: the voice sounds like a radio (thinner, filtered)
    And I confirm: without Caps Lock I am not heard over the radio

  @kora_voice @legacy:voice-radio-separate @target:2 @needs:players:3
  Scenario: Radio and normal talk are separate
    """
    Needs 3 people if possible (2 on the radio, 1 not). 1. Two players on frequency 50 far apart. One stands next to a third player who is not on the radio.
    2. Talk without Caps Lock, then with it.
    Expect: without Caps Lock only the nearby player hears you. With Caps Lock the far radio player hears you too. Someone on another frequency never hears it.
    """
    Given I have 1 "radio"
    When I use the "radio"
    And I manually: enter 50 and confirm, with a second player far away on frequency 50 and a third player without a radio standing next to me
    And I manually: talk without Caps Lock, then with Caps Lock held
    Then I confirm: without Caps Lock only the nearby player hears me
    And I confirm: with Caps Lock the far radio player hears me too
    And I confirm: a player on another frequency never hears it

  @kora_voice @legacy:voice-radio-nearby @target:2 @needs:players:2
  Scenario: Radio member next to you sounds normal
    """
    Needs 2 testers on the same frequency. 1. Stand next to each other and talk while holding Caps Lock.
    2. Walk far apart and do it again.
    Expect: close together you sound like a normal voice, not a filtered radio. Far apart you hear the radio effect.
    """
    Given I have 1 "radio"
    When I use the "radio"
    And I manually: enter 50 and confirm, with a second player on the same frequency
    And I manually: stand next to the second player and talk while holding Caps Lock
    Then I confirm: close together I sound like a normal voice, not a filtered radio
    When I manually: walk far apart and talk again while holding Caps Lock
    Then I confirm: far apart we hear the radio effect

  @kora_voice @legacy:voice-radio-switch @target:2 @needs:players:2
  Scenario: Change and leave frequency
    """
    Needs 2 testers. 1. Both on frequency 50. One switches to 51 with the radio item and talks with Caps Lock.
    2. Then that tester enters 0 (or leaves the box empty).
    Expect: after switching, the player on 50 no longer hears them. Entering 0 shows "You left the frequency." and Caps Lock then does nothing (no click, no transmission).
    """
    Given I have 1 "radio"
    When I use the "radio"
    And I manually: enter 50 and confirm, with a second player also on frequency 50
    And I use the "radio"
    And I manually: enter 51 and confirm, then talk with Caps Lock
    Then I confirm: the second player on 50 no longer hears me
    When I use the "radio"
    And I manually: enter 0 and confirm
    Then I should see a notification containing "You left the frequency."
    When I press the "CAPS" key
    Then I confirm: Caps Lock does nothing (no click, no transmission)

  @kora_voice @legacy:voice-radio-invalid @target:1
  Scenario: Bad frequency numbers
    """
    1. Use the radio and try 1001, then 2.5, then -3.
    Expect: each is refused, either by the dialog itself or with a message (1001 gives "Frequency must be between 1 and 1000."). Nothing is joined for any of them, and you stay on your old frequency if you had one.
    """
    Given I have 1 "radio"
    When I use the "radio"
    And I manually: enter 1001 and confirm
    Then I should see a notification containing "Frequency must be between"
    When I use the "radio"
    And I manually: enter 2.5 and confirm
    Then I confirm: 2.5 is refused, either by the dialog or with a message
    When I use the "radio"
    And I manually: enter -3 and confirm
    Then I confirm: -3 is refused, either by the dialog or with a message
    And I confirm: nothing is joined for any of them and I stay on my old frequency if I had one

  @kora_voice @legacy:voice-radio-restricted @target:2
  Scenario: Police and EMS channels are locked
    """
    1. As a civilian use the radio and try frequencies 1, 2 and 10.
    Expect: each is refused with "That frequency is restricted." and you are not connected. The message does not say which job is allowed. Normal frequencies like 50 still work.
    """
    Given I have 1 "radio"
    And my job is "unemployed"
    When I use the "radio"
    And I manually: enter frequency 1 and confirm
    Then I should see a notification containing "That frequency is restricted."
    When I use the "radio"
    And I manually: enter frequency 2 and confirm
    Then I should see a notification containing "That frequency is restricted."
    When I use the "radio"
    And I manually: enter frequency 10 and confirm
    Then I should see a notification containing "That frequency is restricted."
    And I confirm: I am not connected to any of frequencies 1, 2 and 10
    And I confirm: the refusal message does not say which job is allowed
    When I use the "radio"
    And I manually: enter frequency 50 and confirm
    Then I confirm: I am connected to frequency 50

  @kora_voice @legacy:voice-radio-leo @target:1
  Scenario: Police on duty can join 1 and 2
    """
    Needs a police tester. 1. Off duty, try frequency 1. 2. Go on duty and try 1 and 2, then 10.
    Expect: off duty, 1 is refused. On duty, police can join 1 (LEO Dispatch) and 2 (LEO Tac 1), but 10 (EMS) is still refused. Do the same with an EMS tester for 10 if one is around.
    """
    Given I have 1 "radio"
    And my job is "police"
    And I am off duty
    When I use the "radio"
    And I manually: enter frequency 1 and confirm
    Then I should see a notification containing "That frequency is restricted."
    When I run the command "/setduty"
    Then I should be on duty
    When I use the "radio"
    And I manually: enter frequency 1 and confirm
    Then I confirm: I am connected to frequency 1 (LEO Dispatch)
    When I use the "radio"
    And I manually: enter frequency 2 and confirm
    Then I confirm: I am connected to frequency 2 (LEO Tac 1)
    When I use the "radio"
    And I manually: enter frequency 10 and confirm
    Then I should see a notification containing "That frequency is restricted."
    When I manually: if an EMS tester is available, ask them to go on duty and join frequency 10 with a radio
    Then I confirm: the EMS tester can join frequency 10 (skip if no EMS tester is available)

  @kora_voice @legacy:voice-radio-reconnect @target:2 @needs:players:2
  Scenario: Radio after reconnect
    """
    Needs 2 testers. 1. Both on frequency 50. One reconnects.
    2. The other talks on the radio.
    Expect: after reconnecting the player is no longer on 50 and hears nothing until they join again. After rejoining 50 both hear each other again.
    """
    Given I have 1 "radio"
    When I use the "radio"
    And I manually: enter 50 and confirm, with a second player also on frequency 50
    And I manually: reconnect to the server
    And I manually: ask the second player to talk on the radio
    Then I confirm: after reconnecting I am no longer on 50 and hear nothing
    When I use the "radio"
    And I manually: enter 50 and confirm
    Then I confirm: I am connected to frequency 50
    And I confirm: after rejoining 50 both of us hear each other again

  @kora_voice @legacy:voice-walls @target:2 @needs:players:2 @checklist @checklist:kora_voice:wall-muffling @cat:social-and-comms @manual
  Scenario: Voices are muffled through walls
    """
    Needs 2 testers. 1. Stand a few metres apart in the open and talk.
    2. One goes behind a closed door or wall at the same distance and talks again (try Shout too).
    Expect: through the wall the voice is clearly quieter but still audible, not silent. It returns to full volume as soon as you can see each other again. A hill or slope between you does not muffle.
    Also checklist kora_voice:wall-muffling (Voice muffled through walls): Stand on the other side of a wall/door within 20m: the other player is heard at reduced volume.
    """
    When I manually: stand a few metres from a second player in the open and talk
    And I manually: go behind a closed door or wall at the same distance and talk again (try Shout too)
    Then I confirm: through the wall the voice is clearly quieter but still audible, not silent
    When I manually: step back into line of sight of the second player
    Then I confirm: the voice returns to full volume as soon as we can see each other
    And I confirm: a hill or slope between us does not muffle

  @kora_voice @legacy:voice-buckets @target:1 @needs:players:2 @checklist @checklist:kora_voice:routing-buckets @cat:social-and-comms
  Scenario: No voice from another instance
    """
    Needs 2 testers. 1. Stand next to each other on the same radio frequency. One logs out to character select (a separate instance) while the other stays in the world.
    2. Talk normally and on the radio.
    Expect: you cannot hear each other while in different instances, not even over the radio. It comes back when both are back in the same world (rejoin the frequency if needed).
    Also checklist kora_voice:routing-buckets (No voice across routing buckets): Player in an instance (different bucket) is not audible to players in the main world.
    """
    Given I have 1 "radio"
    When I use the "radio"
    And I manually: join the same radio frequency as the second player and stand next to them
    And I manually: ask a second player to log out to character select while I stay in the world
    And I manually: talk normally and then talk on the radio
    Then I confirm: we cannot hear each other while in different instances, not even over the radio
    When I manually: ask the second player to log back in to the same world and rejoin the frequency if needed
    Then I confirm: we can hear each other again, normally and on the radio

  @kora_voice @legacy:voice-many @target:1 @needs:players:4 @manual
  Scenario: Voice with a group of players
    """
    Needs 4 or more testers. 1. Stand together and take turns talking, then all talk at once briefly.
    2. Spread out and repeat on Shout.
    Expect: everyone in range hears everyone else, nobody drops out or becomes one-way, and there is no noticeable lag or FPS drop. Say how many players were there.
    """
    When I manually: stand together with at least 3 other players and take turns talking
    And I manually: all talk at once briefly
    Then I confirm: everyone in range hears everyone else, nobody drops out or becomes one-way
    When I manually: spread out with the other players, switch to Shout and repeat the talking
    Then I confirm: everyone in range hears everyone else on Shout, nobody drops out or becomes one-way
    And I confirm: there is no noticeable lag or FPS drop
    And I confirm: I have noted how many players were there

  @kora_voice @legacy:voice-restart @target:1 @needs:admin @needs:players:2
  Scenario: Voice after a kora_voice restart
    """
    Needs a Mod and 2 testers on a radio frequency. 1. A Mod runs /server resource kora_voice.
    2. Talk normally and on the radio.
    Expect: normal voice works again within a few seconds without a relog. Say whether you are still on your frequency or have to join it again.
    """
    Given I have 1 "radio"
    When I use the "radio"
    And I manually: join a radio frequency together with a second player
    And I run the command "/restartresource"
    And I manually: talk normally and then talk on the radio
    Then I confirm: normal voice works again within a few seconds without a relog
    And I confirm: I noted whether I am still on my frequency or had to join it again
