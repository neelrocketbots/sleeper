# Sleeper

A social deduction game that floats out of the MacBook notch. Eight axolotls run **The Abyss**, a research station on the
deep ocean floor. One of them is a traitor.

![Playing in the Mess Hall](docs/screenshots/03-playing.png)

## Run it

```sh
scripts/build-app.sh            # builds .build/app/Sleeper.app (release, ad-hoc signed)
open .build/app/Sleeper.app
```

Or straight from source: `swift run Sleeper`.

The island opens near the top of the screen. A bubbles icon sits in the menu bar. **⌃⌥S** shows or folds the island from
any app.

## How to play

You and seven AI crew. Your role is random (change it in the lobby with **R**).

| Key | Action |
| --- | --- |
| WASD / arrows | Swim |
| E or Space | Use: a task, the emergency button at the Mess Hall table, a sabotage fix |
| R | Report a body you're standing near |
| Q | Take out a crewmate (traitor only, cooldown 25 s) |
| 1 / 2 | Sabotage lights / oxygen (traitor only) |
| Tab or M | Station map with your tasks |
| Esc | Close a task, or fold the island (the game pauses) |

**Crew** win by finishing every task or voting out the traitor. Tasks are small mini-games: hold E to fill a gauge, press
arrows in order, or stop a needle in the green three times. Yellow `!` markers show your task stations.

**The traitor** wins when the crew can't outnumber them, or when an oxygen leak runs out. Lights-out shrinks everyone's
sight until someone fixes the panel in Thermal Vent. The oxygen leak needs both consoles sealed (Pressure Lock and Ballast
Tanks) within 45 s.

You only see what your axolotl can see. Walls block sight, so other players vanish into the dark. Dead crew become
ghosts: they can still finish tasks but can't speak or vote.

### Meetings

A reported body or the emergency button calls everyone to the table. The AI crew say where they were and who they saw.
They vouch for each other, and they call out anyone whose story doesn't match what they saw. The traitor lies about being
near the body. Then everyone votes.

| Key | In a meeting |
| --- | --- |
| Arrows | Pick a player |
| A / V | Accuse / vouch for the picked player |
| [ ] then C | Choose a room, then say "I was in …" |
| Enter | Vote for the picked player |
| S | Skip |

When Apple's on-device model is available, the crew's alibis are restyled in their own voices. Accusations always keep
their exact wording. Without the model, the built-in lines are used.

![A meeting](docs/screenshots/11-meeting.png)

## What's inside

- `Sources/SleeperCore`: the game, with no UI. It has the map, A* pathfinding, line of sight, rules, AI crew and traitor,
  and meetings. It runs on a fixed 30 Hz step with a seeded RNG, so a network layer can drive it later.
- `Sources/SleeperApp`: the NotchKit floating island, the SpriteKit scene and SwiftUI overlays.
  - The map is baked into a single texture. Lights are additive glows. A line-of-sight fog texture is updated 30 times a
    second.
  - The hi-bit pixel art is generated in code from palette-indexed grids. There is one axolotl drawing, recoloured for 12
    player colours, plus 5 hats.
- `docs/SPEC.md`: the decisions from brainstorming, and the rules.

## Checks

```sh
swift test                                   # rules, map, AI games to completion, balance, meeting honesty
.build/debug/Sleeper --selftest              # plays through the real key path and prints PASS/FAIL
.build/debug/Sleeper --snapshots /tmp/snaps  # scripted game, renders each screen to PNG (no screen recording needed)
.build/debug/Sleeper --art-preview /tmp/art  # the baked map and the character sheet
```

With the human idle, AI-only games split roughly evenly between crew and traitor wins, and a round lasts about 4–5
minutes.

## Not yet

LAN and online multiplayer, vents, sound, more than one traitor, and cosmetics beyond hats.
