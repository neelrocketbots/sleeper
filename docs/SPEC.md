# Sleeper: spec (v1)

Decisions made during brainstorming on 2026-11-08, then built while the user was away.

## Product
- A social deduction game in the style of Among Us (rules only, original look) that opens from the Mac notch.
- Setting: **The Abyss**, a research station on the deep ocean floor.
- Crew: **axolotls**. Every player uses the same character; **colour** tells players apart, and cosmetics (hats) personalise it. Colour names are shown in meetings as a colour-blind backup.
- Art: **hi-bit pixel art**, rendered at low resolution and scaled up with nearest-neighbour filtering (cheap on GPU and memory, crisp on Retina).
- Container: a **NotchKit floating island** of about 780 × 550 pt with a 32 pt black header band. Drag by the header; Esc folds (hides and pauses).
- View: **free roam, top-down**, camera follows you, WASD/arrow movement, limited sight blocked by walls.
- Play: **focused session**, 5–10 minute rounds.
- v1 is **solo**: you plus 7 AI crew. LAN and online multiplayer come later; the game core is kept free of UI so a network layer can drive it.

## Rules (v1)
- 8 players, 1 traitor. Your role is random by default; the lobby can force crew or traitor.
- Crew: finish tasks (mini-games at stations). The crew wins when every task is done or the traitor is voted out.
- Traitor: kill (cooldown 25 s, must be next to the target), sabotage (Lights: crew sight shrinks until fixed at the Thermal Vent panel; Oxygen leak: 45 s timer, fixed at two consoles). The traitor wins when traitors ≥ living crew or the oxygen timer runs out.
- Bodies can be reported (R) by anyone near them; each player has one emergency meeting at the Mess Hall table (E).
- Meeting: everyone alive speaks (AI statements built from what they actually saw; the traitor lies), then votes. Plurality ejects; ties or a skip majority eject nobody. Ejection says whether they were the traitor.
- Dead crew become ghosts: invisible, can still finish tasks.

## AI
- Crew AI: picks tasks, pathfinds (A*), does them, notices bodies and reports them, witnesses kills in its line of sight, remembers where it saw whom, and votes on suspicion (witnessed kill > seen near the body > caught lying about its location > accused by others).
- Traitor AI: fakes tasks, kills only when no one else can see, sabotages now and then, sometimes self-reports, and lies about where it was.
- Meeting lines come from templates. When Apple's on-device model (FoundationModels) is available, lines are rephrased by it in the background; templates are always the fallback.

## Architecture
- `SleeperCore` (pure Swift, tested): map, pathfinding, line of sight, game state and rules, AI, meetings. Fixed 30 Hz step, seeded RNG.
- `SleeperApp` (AppKit + SwiftUI + SpriteKit + NotchKit): island panel, menu bar item and hotkey, SpriteKit scene (baked map texture, sprites, fog), SwiftUI overlays (HUD, tasks, meeting, lobby, results), pixel art generated in code from palette-indexed grids.
- `Sleeper` executable.

## Out of scope for v1
LAN/online multiplayer, vents, sound, more than one traitor, cosmetics beyond hats.
