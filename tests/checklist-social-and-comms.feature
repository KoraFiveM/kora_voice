# Converted from the communitybot legacy tests by kora-qa-panel/scripts/convert-legacy.mjs.
# The """ block under each Scenario is the original test text, verbatim. Review before applying.
Feature: kora_voice — Social & Comms

  @kora_voice @checklist @checklist:kora_voice:radio-ptt @cat:social-and-comms
  Scenario: Radio push-to-talk (Caps Lock)
    """
    Checklist test: Join a radio channel via a radio item/resource, hold Caps Lock to transmit; with no channel pressing does nothing.
    """
    Given I have 1 "radio"
    When I manually: hold Caps Lock without being on any radio channel
    Then I confirm: nothing happens when I press Caps Lock with no channel
    When I use the "radio"
    And I manually: join a radio channel and hold Caps Lock to transmit
    Then I confirm: I transmit on the radio while Caps Lock is held

  @kora_voice @checklist @checklist:kora_voice:radio-clicks-submix @cat:social-and-comms
  Scenario: Radio clicks and radio effect
    """
    Checklist test: Transmit start/stop plays a click and received radio audio has the radio filter.
    """
    Given I have 1 "radio"
    When I use the "radio"
    And I manually: join a radio channel together with a second player
    And I manually: hold Caps Lock to transmit and then release it
    Then I confirm: a click plays when transmit starts and when it stops
    When I manually: ask the second player to transmit on the radio
    Then I confirm: the received radio audio has the radio filter effect

  @kora_voice @checklist @checklist:kora_voice:radio-restricted @cat:social-and-comms
  Scenario: Restricted radio channels
    """
    Checklist test: Channels 1,2 (police on duty), 10 (EMS on duty), 20 (recovery) refuse civilians with 'That frequency is restricted.'; others open.
    """
    Given I have 1 "radio"
    And my job is "unemployed"
    When I use the "radio"
    And I manually: try to join frequency 1
    Then I should see a notification containing "That frequency is restricted."
    When I manually: try to join frequency 2
    Then I should see a notification containing "That frequency is restricted."
    When I manually: try to join frequency 10
    Then I should see a notification containing "That frequency is restricted."
    When I manually: try to join frequency 20
    Then I should see a notification containing "That frequency is restricted."
    When I manually: try to join frequency 400
    Then I should see a notification containing "Connected to frequency"

  @kora_voice @checklist @checklist:kora_voice:radio-channel-sync @cat:social-and-comms
  Scenario: Channel members hear each other
    """
    Checklist test: Two players on the same channel (1-1000) hear each other regardless of distance; different channels do not.
    """
    Given I have 1 "radio"
    When I use the "radio"
    And I manually: join a frequency between 1 and 1000 that is open, together with a second player far away from me
    And I manually: talk on the radio
    Then I confirm: the second player hears me regardless of distance
    When I manually: ask the second player to switch to a different frequency
    And I manually: talk on the radio again
    Then I confirm: the second player no longer hears me

  @kora_voice @checklist @checklist:kora_voice:phone-call @cat:social-and-comms
  Scenario: Phone call voice channel
    """
    Checklist test: Make a call via the phone: both parties hear each other at any distance; radio and call work at the same time.
    """
    Given I have 1 "phone"
    When I manually: call a second player via the phone and have them answer
    And I manually: move far away from the second player and talk
    Then I confirm: both parties hear each other at any distance
    When I manually: join a radio channel and transmit while the call is active
    Then I confirm: the radio and the call work at the same time

  @kora_voice @checklist @checklist:kora_voice:megaphone @cat:social-and-comms @manual
  Scenario: Megaphone (unbound by default)
    """
    Checklist test: Megaphone key is unset by default; set it in key bindings or via a resource export and verify extended range.
    """
    When I manually: open key bindings and check the megaphone key
    Then I confirm: the megaphone key is unset by default
    When I manually: set a megaphone key in key bindings and use it while talking
    Then I confirm: my voice has an extended range with the megaphone sound

  @kora_voice @checklist @checklist:kora_voice:pma-compat @cat:social-and-comms
  Scenario: pma-voice compatible events/exports
    """
    Checklist test: UIs/resources written for pma-voice (e.g. pma-voice:radioActive, exports) continue to work.
    """
    When I manually: use a UI or resource written for pma-voice, such as one using pma-voice:radioActive or its exports
    Then I confirm: the pma-voice compatible events and exports continue to work
    And there should be no script errors
