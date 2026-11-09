# Sleeper: spec

The decisions behind the game, from the design sessions on 2026-11-08 and 2026-11-09, and the rules as built.

## Product

- A social deduction game in the style of Among Us (its rules only; the look is original) that lives in the Mac notch.
- Setting: **The Abyss**, eight domes on the deep ocean floor joined by glass tunnels.
- Crew: **axolotls**. Every player uses the same character. **Colour** tells players apart (12 colours), and hats
  personalise it (5 hats). Colour names are shown in meetings, so colour is never the only way to tell players apart.
- Art: **storybook**, ink lines and watercolour. Chosen over hi-bit pixel, flat vector and claymation; the samples are in
  `docs/style-compare/`.
- View: **2.5D, three-quarter top-down**. The camera follows you and you swim freely (WASD or arrows). You only see what
  your axolotl can see.
- Container: a **NotchKit island**. It docks to the notch (NotchKit's notch shape) or floats as a card, and folds into the
  notch as a status strip. Opening it takes the keyboard; folding it gives the keyboard back and pauses the game.
- Play: **focused rounds** of about 4 to 5 minutes.
- Now: **solo**, you plus 7 AI crew. Later: LAN, then online multiplayer. The game core has no UI, so a network layer can
  drive it.

## The island

- Launches docked to the notch, about 780 × 550 pt, with a black header band the height of the notch.
- Esc folds it into the notch: a strip the notch's width plus about 170 pt, showing your axolotl and either task progress,
  the oxygen countdown or "Meeting". The game pauses. A click or ⌃⌥S opens it again.
- Dragging the header moves it. Letting go within about 110 pt of the top and 220 pt of the centre docks it (the outline
  turns pink beforehand); anywhere else it floats, kept on screen below the menu bar. Double-clicking the header docks it
  or floats it at the top centre.
- The game pauses whenever the island loses the keyboard.

## The map

- Eight round domes: Sonar, Kelp Farm, Pearl Lab, Mess Hall (the centre, with the meeting table), Thermal Vent, Ballast
  Tanks, Pressure Lock and Hatchery.
- Glass tunnels, two tiles wide, join them; one long tunnel runs along the bottom.
- Dome hulls block walking and sight. Tunnel glass blocks walking but not sight, and so does open water, so you can see
  across the sea between tunnels (never into a dome).
- 14 task stations, one emergency button (anywhere next to the Mess Hall table), one lights panel (Thermal Vent) and two
  oxygen consoles (Pressure Lock and Ballast Tanks).

## Rules

- 8 players, 1 traitor. Your role is random by default; the lobby can make you crew or the traitor every time.
- Crew: 5 tasks each, done as mini-games (hold a key to fill a gauge, press arrows in order, or stop a needle in a zone
  three times). The crew wins when every crew task is done, or when the traitor is voted out.
- Traitor: takes out a crewmate standing next to them (25 s cooldown, 15 s at the start and after each meeting), and
  sabotages:
  - **Lights:** crew sight drops from 6 to 2.2 tiles until someone fixes the panel in Thermal Vent.
  - **Oxygen leak:** both consoles must be sealed within 45 s.
  - 35 s cooldown between sabotages.
- The traitor wins when traitors are at least as many as the living crew, or when the oxygen runs out.
- Anyone near an unreported body can report it (R). Each player has one emergency meeting at the Mess Hall table (E),
  but not during an oxygen leak. A meeting ends any sabotage.
- Meetings last up to 75 s. Everyone alive speaks and votes. The most votes ejects that player, unless it's a tie or
  skips outnumber it. The ejection says whether they were the traitor.
- Dead crew become ghosts: invisible to the living, able to pass through walls and finish tasks, unable to speak, vote or
  fix sabotage.

## AI

- **Crew AI:** walks to its tasks (A* pathfinding), does them, goes to report any body it sees, sometimes runs to fix
  sabotage, and remembers who it saw where and when, and which rooms it passed through itself.
- **Suspicion:** a crew AI suspects whoever it saw near a body around the time of the kill, anyone it saw kill (the
  strongest), anyone whose alibi it can disprove (it saw them somewhere else in the 15 s before the meeting), and anyone
  others accuse, less so when the accuser is suspicious themselves. Vouching lowers suspicion. A crew AI votes for its
  top suspect, or skips if no one is suspicious enough.
- **Traitor AI:** pretends to do tasks; hunts a crewmate who is alone; kills only when no one else can see; sabotages
  now and then; sometimes reports its own kill; in meetings tells the truth about where it was, except the room with the
  body, and sometimes points at someone; votes with the crowd.
- **Meeting lines** come from templates. Honest crew give true alibis, so they are never caught out. With Apple's
  on-device model available, alibis and body reports are restyled in each crew member's own voice; accusations keep their
  exact wording.
- **Typed chat:** your messages are read for player names or colours (an accusation, a vouch, or a mention) and for
  "I was in …" alibis. A crew member you accuse answers with their alibi; the traitor deflects.
- **Balance:** with the human idle, crew and traitor wins split roughly evenly.

## Architecture

- `SleeperCore` (pure Swift, tested): map, pathfinding, line of sight, game state and rules, AI, meetings, chat
  understanding. Fixed 30 Hz step, seeded random generator.
- `SleeperApp` (AppKit, SwiftUI, SpriteKit, NotchKit, FoundationModels):
  - the island panel, menu bar item, global hot key (⌃⌥S), and the header drag with notch docking;
  - the SpriteKit scene, depth-sorted for 2.5D: sea, tunnels and domes drawn in code from painted textures; props,
    hats and the crew from generated storybook sprites (the crew recoloured per player); line-of-sight fog;
  - SwiftUI screens: lobby, header band and folded strip, HUD, mini-games, map, meeting with chat, ejection, results;
  - debug modes: `--selftest`, `--snapshots`, `--cut-assets`, and `SLEEPER_DOCK_DEBUG`.
- `Sleeper`: the executable.

## Not yet

LAN and online multiplayer, vents, sound, more than one traitor, and cosmetics beyond hats.
