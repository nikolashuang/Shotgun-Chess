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
   - **Summon a piece** — placed up to two tiles from the king (costs energy)
   - **Command a piece** — move one of your pieces using its normal chess movement
   - **Appoint an Interrupt Card** to one of your pieces
   - **Use ultimate**

### Energy

- Each player gains 1 energy per turn.
- Energy is spent to summon pieces, fuse pieces, and use specials.

### Ultimate Charge

- Built by damaging enemy pieces.
- 100 charge required to use an ultimate.

## Shotgun (Fire Action)

- Range: up to 3 tiles from the king (Chebyshev distance, so diagonals count as 1).
- Spread grows with aim distance: 1 tile away = 1x1, 2 away = 2x2, 3 away = 3x3.
- 3x3 is centered on the aimed tile. 2x2 includes the aimed tile and extends away from the king (when aiming straight along a row or column, it extends toward the higher column/row). *Assumption — confirm.*
- The king's own tile is never hit.
- Damage per pellet/tile is still undecided.

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
- Shotgun damage
- Energy costs for summoning, fusion, and specials; starting energy and cap
- Fusion rules
- Interrupt Card effects (idea in progress)
