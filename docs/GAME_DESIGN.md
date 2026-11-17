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

Shotguns are bought in the Shop with gold and equipped in the Armory. Only the Pump is owned at the start; unowned shotguns show as LOCKED. Numbers marked *placeholder* are not in the design doc.

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

Chosen in the Armory alongside the shotgun. Replaces the old Necro/Spark/WindCharge/Forge shotgun classes. *Abilities not implemented yet.*

- The king starts with **no class**: normal turns and normal summons only. Special and Ultimate are hidden in the HUD while no class is equipped.
- Each class is unlocked by defeating the regional King who uses it (see Campaign). Clicking the equipped class in the Armory unequips it.

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

## Campaign

World map, bottom to top: **King's Training** (tutorial) → **Hunter Forest** (Hunter King) → **Cliffside** (Outlaw King) → **Outskirts** (Gunslinger King) → **Gravehollow** (Reaper King). Each region needs the one before it.

- The Campaign button opens its own screen. The world map scrolls vertically: King's Training at the bottom, Gravehollow at the top. It opens scrolled to the newest unlocked region.
- Each region is a floating pixel-art island that bobs gently, joined by dotted paths. Locked islands are gray, wrapped in two chains with a padlock.
- When a region unlocks, the map scrolls to it, the padlock shakes and drops, the chains slide off, the island fades into color and the path to it lights up.
- Clicking a region opens its area map: the region's painting behind a branching route of 11–13 nodes to the King. Nodes have no names; a legend of the five node icons sits in the info bar.
- All map data lives in `CampaignConfig`; art asset ids live in `CampaignArt`.
- Art pipeline: `art/tools/build_islands.py` (run inside Blender with the sprite file open) builds the islands, chains and padlock from primitives and renders them to `art/campaign/islands/`, saving the scene as `art/CampaignIslands.blend`. `art/tools/build_campaign_art.py` then outlines them, makes the gray versions and packs `Islands.png`, plus the node icons, area backgrounds and logo cut from `art/reference/`.
- Node types (from the reference legend): **Battle**, **Rest Site**, **Treasure Hunt**, **Queen Fight** (the elite), **Boss Fight** (King).
- A node opens once any node linking to it is cleared. Taking one branch doesn't lock the others.
- Every region ends Queen → King, and nothing else links to the King. `CampaignRules.Validate` errors at server start if this is broken.
- Rest and Treasure nodes clear as soon as they're entered and can't be revisited. Rest sites currently do nothing, because health doesn't carry between battles yet.
- Defeating a King completes the region and permanently unlocks its class (King's Training unlocks no class).
- Losing or leaving a battle returns to the area map; cleared nodes are kept.
- **Win condition in campaign:** armies with a King are beaten by killing the King, armies without one by clearing every enemy piece.

### Rewards

Base rewards, multiplied by the region's `RewardScale` (Training 0.5, Forest 1, Cliffside 1.5, Outskirts 2, Gravehollow 2.5):

| Node | Gold | XP |
|---|---|---|
| Battle | 100 | 50 |
| Treasure Hunt | 150 | 25 |
| Rest Site | 0 | 0 |
| Queen Fight | 400 | 200 |
| Boss Fight | 750 | 350 |

First clears pay in full. Battle replays pay `REPLAY_REWARD_SCALE` (20%). Clearing every node in the campaign once gives about 16,100 Gold and 7,185 XP (level 12); Duels at level 20 still needs replays. Nodes can override rewards with their own `Reward` table.

### Progression

- Gold buys shotguns. XP raises the account level. Each level needs 100 more XP than the last: 100 for level 2, 200 for level 3, and so on (`ProgressionRules.GetExpToLevel`).
- **Duels unlock at level 20** (`ProgressionConfig.DUELS_UNLOCK_LEVEL`, 19,000 total XP), checked on the server.
- Back steps out one level at a time: area map → world map → main menu.
- **Dev panel:** a Developer button on the main menu, shown only to the accounts in `DevConfig.USER_IDS` (Snoothe3rd). It can unlock everything (all shotguns, classes, campaign nodes and level 20), add 1000 Gold, or reset the profile. The server checks the account on every request.
- Saved in a DataStore (`PlayerProfile_v1`): gold, XP, owned shotguns, unlocked classes, cleared nodes and equipped loadout. If the profile can't load (e.g. Studio API access off), a temporary profile is used and never saved.

## Visual Style

- Palette: `#332A35` (panels), `#9C574B` (borders, dark tiles), `#D49A77` (secondary text, light tiles), `#F1D4AC` (highlights), `#E9E3D6` (text). Derived shades: `#271F29` and `#1E1820` for backgrounds, `#C8644F` for warnings and enemy text, `#4A3D48` for empty bars.
- Font: Grenze Gotisch Bold, the closest built-in Roblox font to the logo lettering (Roblox can't load custom fonts). UI text is Title Case because blackletter is hard to read in all caps.
- The menu uses the logo image (`CampaignArt.LOGO`) instead of text.

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
- Class numbers: soul abilities, trap damage, Quickdraw damage, what counts as an "isolated" piece, bounty energy reward
- Enemy AI: enemies still don't act, so campaign battles can't be lost yet
- Encounter armies (current ones are placeholders in `CampaignConfig.Armies`)
- Regional King and Queen boss abilities (need the class abilities first)
- What Rest Sites do (no carried-over health yet)
- What Treasure Hunts find beyond gold and XP (items, upgrades)
- The replay reward fraction (20% placeholder)
- Exact ranges/arcs for Double Barrel and Long Barrel

## Prototype Test Setup

- Five black dummy pieces (Pawn E3, Knight G3, Bishop C4, Rook I4, Queen F5) with their normal health. They don't act. Configured in `MatchConfig.TEST_DUMMIES`.
