# Shotgun Chess — Game Design

Source: [Shotgun Chess design doc](https://docs.google.com/document/d/1gA-xHbcUpENdVX3_O49R_yyCUCjF6f7sPg0P0JDFYTQ/edit)

A reimagining of *Shotgun King: The Final Checkmate*. Players control an armed king, command summoned chess pieces, and wield fantasy shotguns that define their combat style. Supports single-player campaign (PvE) and multiplayer duels (PvP).

## Win Condition

Kill the enemy king.

## Board

- 12x12 board (columns A–L, rows 1–12).
- The player's king starts at F1.

## Turn System

The game is fully turn-based. All durations (stuns, souls, crafted weapons, etc.) are measured in turns.

Each player turn has two events:

1. **Movement Event** — the king moves like a chess king: one tile in any of the 8 directions.
2. **Action Event** — one of:
   - **Fire shotgun**
   - **Use special** (costs energy)
   - **Summon a piece** — placed on an empty tile within one tile of the king (costs energy)
   - **Command a piece** — move one of your pieces using its normal chess movement
   - **Appoint an Interrupt Card** to one of your pieces
   - **Use ultimate**

The turn ends automatically once both events are used, or early with **End Turn**.

### Enemy Turn

- Interrupt Cards can only be played during the enemy's turn. Playable cards glow yellow and are played by clicking them.
- One interrupt per enemy turn.
- *Prototype:* test dummies don't act, so the enemy turn is a fixed 5-second window (`MatchConfig.ENEMY_TURN_TIME`).

### Commanding Pieces

- Pieces move with normal chess movement and can't move onto an occupied tile. Sliding pieces are blocked by any piece.
- Pawns move one tile forward (toward the enemy side).
- Undecided: whether commanded pieces can capture or attack.

### Energy

- Each player gains 1 energy per turn.
- Energy is spent to summon pieces, fuse pieces, and use specials.

### Ultimate Charge

- Built by damaging enemy pieces.
- 100 charge required to use an ultimate.

## Shotgun (Fire Action)

Aiming follows the Shotgun King style: a curved arc centered on the king.

- The arc sits at the cursor's distance from the center of the king's tile, clamped between 1 and 3 tiles.
- The arc's angle is fixed (64°), so aiming closer draws a narrow arc and aiming farther draws a wide one.
- The shot is deterministic: the same aim always gives the same result, and the hit tiles are previewed while aiming.
- Every tile inside the cone between the king and the arc is hit.
- 5 pellets are spread evenly across the arc. They keep travelling past the arc along their line out to max range (3), hitting every tile they pass through. They stop at the board edge.
- **Point blank:** if an enemy is on the adjacent tile the shot points into (aim snapped to the nearest of 8 directions, or the cursor directly on an adjacent enemy), only that tile is hit and every pellet lands in it. Otherwise the normal cone fires.
- Shots don't pierce: each pellet, and each line of the cone, stops at the first enemy piece it hits, so enemies shield what's behind them. Friendly pieces don't block.
- Range, arc angle, and pellet count are tuning values in `ShotgunConfig`. *64° and 5 pellets are placeholders — confirm.*
- Damage depends on the enemy's tile distance from the king: 5 at 1 tile, 3.5 at 2, 2 at 3. That's a linear falloff from `MAX_DAMAGE` to `MIN_DAMAGE`; decimal damage is allowed. Each enemy takes damage once per shot.
- Friendly pieces aren't damaged. Undecided: friendly fire, and whether friendly pieces should block shots.
- Open question: because pellets always continue to max range, close and far aims currently cover nearly the same tiles.

## Pieces

| Piece  | Health |
|--------|--------|
| King   | 15     |
| Pawn   | 3      |
| Bishop | 5      |
| Knight | 5      |
| Rook   | 7      |
| Queen  | 9      |

## Defensive Interrupts *(idea in progress)*

- An interrupt window opens when the enemy plays an attack and the defender has a valid card.
- Only show the window when the defender has a valid card available.
- One defensive interrupt per attack.
- Short response timer (around 5 seconds).
- Ordinary movement and summoning never trigger interrupts.

## Shotgun Classes

### Necro
- **Primary:** Cursed Pellets
- **Passive:** Successful kills drop souls on the field
- **Special:** Harvest dead souls and use their abilities for one turn
- **Ultimate:** Revive one dead soul on your team

### Spark
- **Primary:** Electrified Pellets
- **Passive:** Successful shots build electric charge
- **Special:** Chain lightning shot that stuns nearby enemies for one turn
- **Ultimate:** Large electric discharge around you, stunning all enemies for one turn

### WindCharge
- **Primary:** Air-cannon shots
- **Passive:** Shots can recoil the king for better positioning
- **Special:** Wind blast that knocks nearby enemies back
- **Ultimate:** Reposition anywhere, landing with a large wind knockback

### Forge
- **Primary:** Normal shotgun pellets
- **Passive:** Dead enemies drop scrap on the field
- **Special:** Craft a revolver (up to 6 bullets) — more accurate shots, slightly more range
- **Ultimate:** Craft a railgun (2 bullets) — straight-line shots that pierce everything in the line

## Open Design Decisions

Not yet specified in the design doc. Do not implement guesses without confirming.

- Charge gained per point of damage
- Energy costs for summoning, fusion, and specials; starting energy and cap
- Fusion rules
- Interrupt Card effects (idea in progress). The prototype uses three no-effect "Test Card" placeholders, one use each per match.
- Whether summons are limited (energy, piece count)

## Prototype Test Setup

- Five black dummy pieces (Pawn E3, Knight G3, Bishop C4, Rook I4, Queen F5) with their normal health. They don't act. Configured in `MatchConfig.TEST_DUMMIES`.
