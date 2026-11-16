# Shotgun Chess — Game Design

Source: [Shotgun Chess design doc](https://docs.google.com/document/d/1gA-xHbcUpENdVX3_O49R_yyCUCjF6f7sPg0P0JDFYTQ/edit)

A reimagining of *Shotgun King: The Final Checkmate*. Players control an armed king, command summoned chess pieces, and wield fantasy shotguns that define their combat style. Supports single-player campaign (PvE) and multiplayer duels (PvP).

## Win Condition

Kill the enemy king.

## Board

- 12x12 board (columns A–L, rows 1–12). The player's king starts at F1.
- Co-op matches use a 16x16 board (not implemented).

## Turn System

The game is fully turn-based. All durations (stuns, souls, crafted weapons, etc.) are measured in turns.

Each player turn has two events:

1. **Movement Event** — the king moves like a chess king: one tile in any of the 8 directions.
2. **Action Event** — one of:
   - **Fire shotgun**
   - **Use special** (costs energy)
   - **Summon a piece** — placed on an empty tile within one tile of the king (costs energy)
   - **Command a piece** — move one of your pieces using its normal chess movement
   - **Use ultimate**
   - **Reload** — refills the shotgun's magazine

The turn ends automatically once both events are used, or early with **End Turn**.

### Enemy Turn

- *Prototype:* test dummies don't act, so the enemy turn is a fixed 5-second window (`MatchConfig.ENEMY_TURN_TIME`).

### Commanding Pieces

- Pieces move with normal chess movement and can't move onto an occupied tile. Sliding pieces are blocked by any piece.
- Pawns move one tile forward (toward the enemy side).
- **Attacking:** commanding a piece onto an enemy attacks it instead of moving. Targets follow chess capture rules: pawns attack diagonally forward, knights jump, sliding pieces hit the first piece in each line (friendly pieces block). The attacker hops to the enemy and returns to its own square. Survivors flash white like any hit; killed pieces fall over and crumble.
- Summon damage builds ultimate charge like any other damage to enemy pieces.

### Energy

- Each player gains 1 energy at the start of every turn (including the first), up to 8.
- Starting energy is 0. *(Assumption — confirm.)*
- Costs: Pawn 1, Knight 3, Bishop 3, Rook 5, Queen 7, Special 1.
- Only one active Queen per king.
- Energy is also spent on fusion (cost undecided).

### Ultimate Charge

- Built by damaging enemy pieces: 10 charge per point of damage actually dealt (overkill doesn't count), including bleed.
- 100 charge required to use an ultimate.

## Shotgun (Fire Action)

Every shotgun has a magazine. Firing spends ammo; you can't fire without enough. **Reload** uses the Action event and refills the magazine.

Aiming follows the Shotgun King style: a curved arc centered on the king.

- The arc sits at the cursor's distance from the center of the king's tile, clamped between 1 and 3 tiles.
- The arc's angle is fixed (64°), so aiming closer draws a narrow arc and aiming farther draws a wide one.
- The shot is deterministic: the same aim always gives the same result, and the hit tiles are previewed while aiming.
- Every tile inside the cone between the king and the arc is hit.
- 5 pellets are spread evenly across the arc. They keep travelling past the arc along their line out to max range (3), hitting every tile they pass through. They stop at the board edge.
- **Point blank:** if an enemy is on the adjacent tile the shot points into (aim snapped to the nearest of 8 directions, or the cursor directly on an adjacent enemy), only that tile is hit and every pellet lands in it. Otherwise the normal cone fires.
- Shots don't pierce: each pellet, and each line of the cone, stops at the first enemy piece it hits. Enemies also shield what's behind them: a tile is only hit if the straight line from the king to that tile's center doesn't pass through an enemy tile (`ShotgunRules.HasLineOfSight`). Friendly pieces don't block. Only the Buck Barrel's precise shot pierces.
- Range, arc angle, pellet count and damage are per-shotgun tuning values in `ShotgunConfig.Shotguns`.
- Damage depends on the enemy's tile distance from the king, falling off linearly from `MaxDamage` at 1 tile to `MinDamage` at the shotgun's max range. Decimal damage is allowed. Each enemy takes damage once per shot.
- Friendly pieces aren't damaged. Undecided: friendly fire, and whether friendly pieces should block shots.
- Open question: because pellets always continue to max range, close and far aims currently cover nearly the same tiles.

## Shotguns

Shotguns are chosen in the Armory and bought in the Shop (everything is unlocked until gold exists). Numbers marked *placeholder* are not in the design doc.

| Shotgun | Price | Ammo | Range | Arc | Damage | Notes |
|---|---|---|---|---|---|---|
| Pump (starter) | — | 5 | 3 | 64° | 5→2 | Basic shotgun |
| Double Barrel | 2000 | 4 | 2 *(placeholder)* | 64° | 5→3.5, x2 | Every shot fires both barrels: 2 shells, double damage |
| Buck Barrel | 2100 | 3 | 3 | 64° | 5→2 | Alt mode: precise shot |
| Long Barrel | 3500 | 4 | 5 | 24° *(placeholder)* | 5→2 | Very tight cone |
| Knife Shotty | 2400 | 5 | 3 | 64° | 5→2 | Alt mode: knife swing |

**Alt modes** — right click while aiming switches between normal and alt; left click fires.

- **Precise shot (Buck Barrel):** a 3-tile straight line snapped to the nearest of the 8 chess directions. Pierces every enemy in the line for max damage. Uses the Action and needs all 3 shells.
- **Knife swing (Knife Shotty):** hits 2 adjacent tiles — the tile it points at plus its neighbor on the cursor's side. Needs an enemy in one of them. 6 damage and bleed (1 damage per turn for 2 turns, ticking at the start of the bleeding piece's turn; reapplying refreshes it). Uses the Action, costs no ammo, so it works at 0 ammo.
- Point blank applies to normal shots of every shotgun.

## Classes

Chosen in the Armory alongside the shotgun. Replaces the old Necro/Spark/WindCharge/Forge shotgun classes. *Selectable but not implemented yet.*

### Reaper
- **Passive [Reap]:** Dead enemies become souls. Queens don't drop souls.
- **Special [Assimilate]:** Harvest dead souls and use their abilities for one turn, or turn them into energy stacks.
- **Ultimate [Unbound]:** Move like a Queen for one turn.

### Hunter
- **Passive [Collector]:** Dead enemies drop scrap on the field.
- **Special [Trap Layout]:** Lay invisible bear traps that enemies can't see.
- **Ultimate [Hunting Strike]:** Throw bolas in a 5-tile radius, stunning enemies for 3 turns.

### Gunslinger
- **Passive [Deadeye]:** All shotgun cones shrink and shoot slightly further.
- **Special [Quickdraw]:** Fire a weaker shot without using the Action event (once per turn).
- **Ultimate [High Noon's Bounty]:** Mark 2 enemies; gain energy for killing both.

### Outlaw
- **Passive [Opportunist]:** +1 damage to isolated pieces.
- **Special [Conceal]:** Smoke bomb covering 3x3 for two turns; enemies can't attack or shoot into it.
- **Ultimate [Ambush]:** Move to any square at least 1 tile from an enemy; +2 damage on the next shot.

## Pieces

| Piece  | Health | Attack Damage |
|--------|--------|---------------|
| King   | 15     | —             |
| Pawn   | 3      | 1             |
| Bishop | 5      | 2             |
| Knight | 5      | 2             |
| Rook   | 7      | 2             |
| Queen  | 9      | 4             |

## Controls

Default keybinds, rebindable in **Settings** (session only until settings are saved to a profile):

| Action | Key |
|---|---|
| Fire shotgun | 1 |
| Special | E |
| Ultimate | 3 |
| Summon | 4 |
| Command | 5 |
| Reload | R |
| End turn | X |

Right click toggles a shotgun's alt mode while aiming.

## Removed Mechanics

- **Interrupt Cards / defensive interrupts** — discarded entirely (Nov 2026).

## Open Design Decisions

Not yet specified in the design doc. Do not implement guesses without confirming.

- Fusion rules and cost
- Starting energy (prototype uses 0)
- Starter class (prototype uses Reaper)
- Class numbers: soul abilities, trap damage, Quickdraw damage, what counts as an "isolated" piece, bounty energy reward
- Gold economy and how shotguns are purchased
- Exact ranges/arcs for Double Barrel and Long Barrel

## Prototype Test Setup

- Five black dummy pieces (Pawn E3, Knight G3, Bishop C4, Rook I4, Queen F5) with their normal health. They don't act. Configured in `MatchConfig.TEST_DUMMIES`.
