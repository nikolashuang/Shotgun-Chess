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

Turns are energy-based:

- **Movement** — the king gets 1 free move per turn, like a chess king: one tile in any of the 8 directions.
- **Actions** — each action can be used **once per turn**, in any order, as long as there's energy to pay for it (prevents spam; used actions fade out in the action panel):
   - **Fire shotgun** — 1 energy
   - **Command a piece** — 1 energy (move or attack with one of your pieces using its normal chess movement)
   - **Reload** — 1 energy, refills the shotgun's magazine
   - **Use special** — 2 energy
   - **Summon a piece** — the piece's cost (see Energy); placed on an empty tile within one tile of the king. Opening the summon menu is free.
   - **Use ultimate** — free once fully charged

The turn ends with **End Turn**.

### Enemy Turn

Campaign battles run the enemy AI (`ServerScriptService.AI.EnemyAIService`, tuning in `AIConfig`). Matches without an AI rating (the Duel test dummies) still use a fixed 5-second wait (`MatchConfig.ENEMY_TURN_TIME`).

- Every enemy piece may move OR attack on every enemy turn. *(The Active/Passive cycle from the design doc was removed in Nov 2026: too easy.)*
- **Stuns:** a stunned piece skips its enemy turns until the stun runs out. `MatchClass:StunPiece` applies one and shows stars circling the piece's head until it wears off (nothing applies stuns yet).
- **Rotating priority:** acting pieces plan in Id order, rotated by one each enemy turn. Earlier pieces reserve their destination tiles first.
- **Simultaneous execution:** every plan is made against the same board snapshot, then all attacks resolve and all moves happen together.
- **Priorities** (weights in `AIConfig.Weights`): Defend > Attack > Evade > Position > Teamwork > Advance. Queens put Attack above Defend until only their King and Queen are left. Enemy Kings: Evade > Attack > Teamwork > Position > Advance.
   - Defend: attack whatever threatens the enemy King, or stand next to it on the threat's side.
   - Evade: avoid tiles the player's king could shoot after one step, or that a white piece could hit.
   - Position: line up an attack on the player's king and cover the tiles it could step to.
   - Teamwork: near an ally, cover escape tiles no ally covers yet.
   - Advance: close distance to the player's king.
- **Enemy pieces** attack with chess capture rules and their normal damage, against the player's king or summoned pieces. Killing a summoned piece moves the attacker onto its square, and the AI scores that capture square (Position, Teamwork, Advance) as where the piece ends up.
- **Enemy Kings** hold and fire a Pump shotgun (`ShotgunConfig.ENEMY_KING`) with the same rules as the player's, aimed straight at a target. The gun points at the player's king until they fire, then at their last shot. They don't track ammo (assumption).
- **Ratings** set how often a piece takes a random option instead of its best one: 500 → 40%, 1000 → 25%, 1500 → 10%, 2000 → 5%, 2500 → 1% (max 2 per match). Campaign battles use 1000 (`CampaignConfig.AI_RATING`).
- **Defeat:** the player's king dying ends the match as a Defeat.

### Commanding Pieces

- Pieces move with normal chess movement and can't move onto an occupied tile. Sliding pieces are blocked by any piece.
- Pawns move one tile forward (toward the enemy side).
- Every highlighted choice on the board (moves, summon tiles, command targets) has a border, and the one under the cursor gets a thicker yellow border.
- Choosing Command outlines every piece you can choose in yellow; the chosen piece gets a spinning yellow arrow bobbing above it.
- **Attacking:** commanding a piece onto an enemy attacks it instead of moving. Targets follow chess capture rules: pawns attack diagonally forward, knights jump, sliding pieces hit the first piece in each line (friendly pieces block). The attacker hops to the enemy; if the hit kills it, the attacker takes the enemy's square like a chess capture, otherwise it returns to its own square. Enemy pieces capture the same way when they kill a summoned piece (attacks on the player's king never move the attacker). Survivors flash white like any hit; killed pieces fall over and crumble.
- Summon damage builds ultimate charge like any other damage to enemy pieces.

### Energy

- Each player gains 1 energy at the start of every turn (including the first), up to 8.
- Starting energy is 0. *(Assumption — confirm.)*
- Summon costs: Pawn 1, Knight 2, Bishop 2, Rook 3, Queen 6 (raised from 4 in Nov 2026 so the Queen is harder to get).
- Action costs: Fire 1, Command 1, Reload 1, Special 2, Ultimate 0.
- Only one active Queen per king.
- Energy is also spent on fusion (cost undecided).

### Ultimate Charge

- Built by damaging enemy pieces: 10 charge per point of damage actually dealt (overkill doesn't count), including bleed.
- 100 charge required to use an ultimate.

## Shotgun (Fire Action)

Every shotgun has a magazine. Firing spends ammo; you can't fire without enough. **Reload** costs 1 energy and refills the magazine.

Aiming follows the Shotgun King style: a curved arc centered on the king.

- The arc sits at the cursor's distance from the center of the king's tile, clamped between 1 and 3 tiles.
- The arc's angle is fixed (64°), so aiming closer draws a narrow arc and aiming farther draws a wide one.
- The shot is deterministic: the same aim always gives the same result, and the hit tiles are previewed while aiming.
- Every tile inside the cone between the king and the arc is hit.
- 5 pellets are spread evenly across the arc. They keep travelling past the arc along their line out to max range (3), hitting every tile they pass through. They stop at the board edge.
- **Point blank:** if an enemy is on the adjacent tile the shot points into (aim snapped to the nearest of 8 directions, or the cursor directly on an adjacent enemy), only that tile is hit and every pellet lands in it. Otherwise the normal cone fires.
- Shots don't pierce: each pellet, and each line of the cone, stops at the first enemy piece it hits. Enemies also shield what's behind them: a tile is only hit if the straight line from the king to that tile's center doesn't pass through an enemy tile (`ShotgunRules.HasLineOfSight`). Friendly pieces don't block. No shot pierces.
- Range, arc angle, pellet count and damage are per-shotgun tuning values in `ShotgunConfig.Shotguns`.
- Damage depends on the enemy's tile distance from the king, falling off linearly from `MaxDamage` at 1 tile to `MinDamage` at the shotgun's max range. Decimal damage is allowed. Each enemy takes damage once per shot.
- Friendly pieces aren't damaged. Undecided: friendly fire, and whether friendly pieces should block shots.
- Open question: because pellets always continue to max range, close and far aims currently cover nearly the same tiles.

## Shotguns

Shotguns are bought in the Shop with gold and equipped in the Armory. Only the Pump is owned at the start; unowned shotguns show as LOCKED. Numbers marked *placeholder* are not in the design doc.

| Shotgun | Price | Ammo | Range | Arc | Damage | Notes |
|---|---|---|---|---|---|---|
| Pump (starter) | — | 5 | 3 | 64° | 5→2 | Basic shotgun |
| Double Barrel | 2000 | 2 | 2 *(placeholder)* | 64° | 5→3.5, x2 | Every shot fires both barrels: 2 shells, double damage. Holds one shot, so it reloads after every blast (Nov 2026) |
| Buck Barrel | 2100 | 4 | 3 | 64° | 5→3 | Knockback 1 tile |
| Long Barrel | 3500 | 4 | 4 | 24° *(placeholder)* | 5→1 | Very tight cone; falloff nerfed to 1 at max range (Nov 2026) |
| Knife Shotty | 2400 | 5 | 3 | 64° | 5→2 | Alt mode: knife swing |

**Knockback (Buck Barrel):** every enemy the shot hits and doesn't kill is pushed 1 tile straight away from the king (one of the 8 directions). If the tile is off the board or occupied, it stays put with no extra damage. Kings can't be knocked back. Enemies farther from the king are pushed first, so a line of enemies all move back together. The precise shot was removed (Nov 2026).

**Alt modes** — right click while aiming switches between normal and alt; left click fires.

- **Knife swing (Knife Shotty):** hits 2 adjacent tiles — the tile it points at plus its neighbor on the cursor's side. Needs an enemy in one of them. 5 damage and bleed (1 damage per turn for 3 turns, ticking at the start of the bleeding piece's turn; reapplying refreshes it). Costs 1 energy like any shot but no ammo, so it works at 0 ammo.
- Point blank applies to normal shots of every shotgun.

## Classes

Chosen in the Armory alongside the shotgun. All numbers live in `ClassConfig`; each class's logic is a component in `ServerScriptService.Match.Classes` (`ReaperClass`, `HunterClass`, `GunslingerClass`, `OutlawClass`) that `MatchClass` calls into.

- The king starts with **no class**: normal turns and normal summons only. Special and Ultimate are hidden in the HUD while no class is equipped.
- Each class is unlocked by defeating the regional King who uses it (see Campaign). Clicking the equipped class in the Armory unequips it.
- **Special:** 2 energy, once per turn. **Ultimate:** needs 100 charge, costs no energy, once per turn, spends the whole charge.
- Reaper's High has no target and fires as soon as it's selected; the other ultimates wait for an aim or clicks on the board.
- Numbers marked *placeholder* aren't in the design doc.

### Reaper
- **Passive [Reap]:** every piece that dies leaves a soul on its tile, allies included (Nov 2026): a black orb in greenish-blue flame with a faint ghost of its piece. Queens leave souls too. Kings end the match, so they never do. When your rival is a Reaper, you see their souls in red flame; your own stay blue.
- **Special [Assimilate]:** pick a soul; it's used up and the king's move this turn uses that piece's movement (Knight jumps, Rook/Bishop/Queen slides, Pawn steps forward). It's a bonus move that doesn't count as the king's movement, so it works after the king has already moved (Nov 2026); unused, it expires at the end of the turn.
- **Ultimate [Reaper's High]:** absorb every soul on the board. Heal 2 HP per soul (up to 15) and +1 damage per soul on every hit of the next shot. Needs at least one soul.

### Hunter
- **Passive [Collector]:** each enemy death has a 25% chance to give +1 energy, shown as a lightning bolt floating up. *(+1 is a placeholder.)*
- **Special [Trap Layout]:** place 3 bear traps on empty tiles within 2 of the king *(range placeholder)*; click 3 tiles (fewer if there aren't 3 free). Only the player sees them. An enemy that moves or is knocked onto one takes 3 damage and is stunned 1 turn. Any move or attack whose line crosses a trap stops on the trap's square and springs it, cancelling the rest of the move or attack, so traps also shield the king and allies. Knights jump over traps they cross and are only caught by landing on one; enemy Kings are affected. The trap clamps shut over the piece, floats up and fades.
- **Ultimate [Hunting Strike]:** aimed and thrown exactly like a Pump shot (Nov 2026: was Double Barrel): same 3-tile cone, range, line of sight and point blank (`HuntingStrike.Weapon`), previewed with the same arc. Every non-King enemy in the hit tiles is stunned for 3 turns and deals no damage; a bolas flies to each one and stays wrapped around it while it's stunned. Kings are immune. Only throws if it would catch at least one non-King enemy, so the charge isn't wasted. (Replaced the old 5-tile radius in Nov 2026.)

### Gunslinger
- **Passive [Deadly Rounds]** (Nov 2026, replaced Deadeye): no body blocking for any shotgun; blasts pass through every piece. Each target takes -2 damage for every enemy the blast passed through on the way to it (nerfed from -0.5, Nov 2026). Point blank shots go through the adjacent enemy and on in a straight line to max range. Applied to the weapon itself (`ShotgunRules.GetWeapon(name, "Gunslinger")` sets `Pierces`), so the aim preview matches.
- **Special [Fan the Hammer]:** the king pulls out a revolver (shown while aiming and firing) and fires 6 shots down a 3-tile straight line (snapped to the 8 chess directions). Each shot has a 60% chance to hit and deals 1.5 damage. Shots don't pierce: each hits the first living enemy in the line, so once that enemy dies the remaining shots go to the next one.
- **Ultimate [High Noon's Bounty]:** click 2 enemies (Kings allowed; 1 if only one is left) to mark them with a red X. Each marked enemy pays 2 energy when it dies, however it dies. Marks last until the enemy dies.

### Outlaw
- **Passive [Opportunist]:** +1 damage on shotgun hits against an enemy with no other enemy next to it *(definition of "isolated" is a placeholder)*.
- **Special [Conceal]:** throw a smoke bomb at any tile up to 3 away; a 3x3 cloud centers there for 1 enemy turn (Nov 2026: was 2). Enemy pieces can't attack anything inside it, the player's king included. Shotgun blasts into it have a 50% chance to hit, rolled separately for each target (pellets still stop on it). Hovering previews the cloud.
- **Ultimate [Ambush]:** jump the king to any empty tile next to an enemy (`Ambush.MaxEnemyDistance`, 1). Doesn't use the turn's move. +2 damage on every hit of the next shot.

### Health Bars

Every health bar (pieces and kings) has a divider between each point of health, like the energy bar, so players can count the hits left.

## Campaign

World map, bottom to top: **King's Training** (tutorial) → **Hunter Forest** (Hunter King) → **Cliffside** (Outlaw King) → **Outskirts** (Gunslinger King) → **Gravehollow** (Reaper King). Each region needs the one before it.

- The Campaign button opens its own screen. The world map scrolls vertically: King's Training at the bottom, Gravehollow at the top. It always opens scrolled to the bottom (King's Training) so players see where the campaign starts.
- Each region is a floating pixel-art island that bobs gently, joined by dotted paths. Locked islands are gray, wrapped in two chains with a padlock.
- When a region unlocks, the map scrolls to it, the padlock shakes and drops, the chains slide off, the island fades into color and the path to it lights up.
- Clicking a region opens its area map: a branching route of 11–13 nodes to the King, inked on a torn parchment sheet. Nodes have no names; a legend of the five node icons sits in the info bar.
- All map data lives in `CampaignConfig`; art asset ids live in `CampaignArt`.
- Waterfalls (Forest, Cliffside) run from a stream on top over the island's front rim and down the rock face into a puff of mist.
- Art pipeline: `art/tools/build_islands.py` (run inside Blender with the sprite file open) builds the islands, chains and padlock from primitives and renders them to `art/campaign/islands/`, saving the scene as `art/CampaignIslands.blend`. `art/tools/build_campaign_art.py` then outlines them, makes the gray versions and packs `Islands.png`, draws the parchment (`Paper.png`), and cuts the node icons and logo from `art/reference/`.
- Node types (from the reference legend): **Battle**, **Rest Site**, **Treasure Hunt**, **Queen Fight** (the elite), **Boss Fight** (King).
- Every route is 3 Battles → Rest Site and Treasure Hunt → 3 Battles → Rest Site and Treasure Hunt → Queen → King, so each run fights exactly 6 normal battles (`CampaignMap.FIGHTS`).
- Every region ends Queen → King, and nothing else links to the King. `CampaignRules.Validate` errors at server start if this is broken.

### Region Runs

- Each region is played as a **run**: the route only moves forward from the last node cleared, like Slay the Spire. Runs are saved per region in the profile (`Runs`).
- **Health carries over** between battles. The King starts each run at 15/15.
- **Rest Sites are checkpoints** with three choices: **Rest** (heal to full), **Train** (+2 max and current health), **Gun Maintenance** (+1 to every shotgun hit, fall-off included; a Double Barrel's two blasts get +1 each). Upgrades last for the region only.
- **Dying** sends the run back to its last Rest Site, where the choice can be made again. Everything after it is lost. With no Rest Site reached yet, the run ends and the region starts over.
- **Leaving mid-region** keeps the run exactly as it was: every finished node is saved to the DataStore a few seconds later, and again when the player leaves. A battle left unfinished just has to be fought again; a rolled Treasure Hunt or mystery encounter stays the same.
- **The pouch:** Gold and XP from nodes collect in the run's pouch and are only paid when the region's King falls. Defeating a King completes the region and permanently unlocks its class (King's Training unlocks no class).
- Completed regions can be replayed as a fresh run; the pouch then pays `REPLAY_REWARD_SCALE` (20%).

### Encounters

Enemy armies are rolled fresh every battle from a point budget (`CampaignConfig.Encounter`, generated by `EncounterRules`): Pawn 1, Knight/Bishop 3, Rook 5, Queen 9.

| Encounter | Training | Forest | Cliffside | Outskirts | Gravehollow |
|---|---|---|---|---|---|
| Normal 1 | 6 | 8 | 10 | 12 | 14 |
| Normal 2–6 | +3 each | +3 each | +3 each | +3 each | +3 each |
| Queen Battle | 30 | 32 | 34 | 36 | 38 |
| King Battle | 36 | 38 | 40 | 42 | 44 |

- Queen battle = Normal 6 + 9, King battle = Queen battle + 6. Both always include the Queen (her 9 points come out of the budget, the King is free). Only one Queen.
- 2 points are reserved for Pawns; Rooks, Knights and Bishops are picked at random to spend the rest, then Pawns fill what's left (max 12). Exactly 12 Pawns form a wall across row 9.
- Everything is placed randomly on rows 9–12. In boss battles the Queen starts on column 6 and the King on column 7 of row 12.
- Bishops alternate square colors, so neither color is safe.

### Mystery Encounters

Some fight columns hold **Mystery** nodes instead of battles (`CampaignMap.MYSTERY_PLANS`). Each region deals the lane plans in its own order: one lane gets four mysteries (two early, two late), one lane is straight battles, and the others get one early and one late, so routes feel different and players branch out.

Arriving rolls one of four encounters on the server (never the same one twice in a row, and no Fallen Knight once he has joined); it's kept in the run, so leaving can't reroll it. Numbers live in `CampaignConfig.Mystery`.

- **Wandering Gunsmith:** pay 50 Gold from the pouch for +1 shotgun damage (fall-off included), pay 25 to gamble (+1 or -1), or leave. Locked when the pouch can't cover it.
- **Fallen Knight:** challenge him (a battle against him alone) or keep walking. Beating him makes him a companion for the rest of the run.
- **Ambush:** take 3 damage (locked at 3 health or less) or fight an army rolled from the region's points (Training 6, Forest 7, Cliffside 8, Outskirts 8, Gravehollow 9) for a normal battle's reward.
- **Queen's Altar:** Blood Offering (-4 health, +2 max health), Royal Sacrifice (-6 health, +2 shotgun damage), or walk away. Each needs more health than it costs.

### Fallen Knight

- 7 health, deals 2, moves and attacks like a King and a Knight combined (`PieceRules`). Dark teal armour, glowing blue eyes and a flickering blue-green aura (`Aura` effect behind his sprite).
- As a companion he starts every battle one tile right of the King, acts on his own at the end of the player's turn (`CompanionAIService`: attack first, finishing pieces and the enemy King; otherwise close in while avoiding tiles enemies can hit) and can't be commanded.
- His health carries between battles like the King's; Rest heals him too. If he dies he's gone for the run.

### Rest Site Scene

The Rest Site panel shows `art/campaign/RestCamp.png` with an animated campfire layer on top: the King on the right log and either his party (two pawns, a knight and a bishop) or the Fallen Knight on the left log. Rendered in Blender by `art/tools/build_rest_camp.py`, packed by `build_rest_art.py`.

### Treasure Hunt

A 12×12 board in the region's colors with 5 digs; each dig uncovers a 3×3 square. The treasure's tile is rolled on the server when the hunt starts and kept in the run. Finding it on dig 1–5 pays 200 / 175 / 150 / 125 / 100 Gold to the pouch; not finding it pays 25.
- **Win condition in campaign:** armies with a King are beaten by killing the King, armies without one by clearing every enemy piece.

### Rewards

Base rewards go into the pouch, multiplied by the region's `RewardScale` (Training 0.5, Forest 1, Cliffside 1.5, Outskirts 2, Gravehollow 2.5):

| Node | Gold | XP |
|---|---|---|
| Battle | 100 | 50 |
| Treasure Hunt | 25–200 (see above, not scaled) | 0 |
| Rest Site | 0 | 0 |
| Queen Fight | 400 | 200 |
| Boss Fight | 750 | 350 |

A first completion pays the whole pouch; replays of a completed region pay 20%. Nodes can override rewards with their own `Reward` table.

### Progression

- Gold buys shotguns. XP raises the account level. Each level needs 100 more XP than the last: 100 for level 2, 200 for level 3, and so on (`ProgressionRules.GetExpToLevel`).
- **Duels unlock at level 10** (`ProgressionConfig.DUELS_UNLOCK_LEVEL`, 4,500 total XP), checked on the server.
- Back steps out one level at a time: area map → world map → main menu.
- **Dev panel:** a Developer button on the main menu, shown only to the accounts in `DevConfig.USER_IDS` (Snoothe3rd). It can unlock everything (all shotguns, classes, campaign nodes and level 10), add 1000 Gold, or reset the profile. The server checks the account on every request.
- Saved in a DataStore (`PlayerProfile_v1`): gold, XP, owned shotguns, unlocked classes, completed regions, region runs, equipped loadout, settings and keybinds. If the profile can't load (e.g. Studio API access off), a temporary profile is used and never saved.

## Multiplayer (PvP Duels)

Unlocks at level 10. Uses the same rules as the campaign (`MatchClass`), with two human sides instead of the AI.

- **Screens:** Multiplayer opens on a **Duels** card (room for more multiplayer modes beside it). Duels opens two cards: **Queue** (searches in place, click again to cancel; pairs the two players who have waited longest) and **Challenge** (the player list on its own screen). Back steps out one screen at a time. Card drawings come from `art/tools/build_armory_icons.py` (sheet in `ArmoryArt`).
- **Practice** (the last card on the **Singleplayer** screen, after Campaign and Siege; no level needed): Choose Difficulty picks the AI rating (500–2500 in steps of 500, `DuelConfig.PRACTICE_RATINGS`) and the AI king's shotgun and class. It's a normal duel (coin flip for White, 5:00 clock) against `PracticeAIService`, with no rewards.
- **Practice AI (simple for now):** each turn it moves the king to the tile with the best shot (or toward your King), then shoots; with no shot it attacks with a piece if it can. It reloads when empty, saves energy for a randomly picked piece and summons it near its king, and uses spare energy to push a piece forward. The rating is its chance of picking a worse move (`AIConfig.Ratings`). It doesn't use class specials or ultimates yet. Smarter player techniques get added over time.
- **Challenges:** a challenge shows the target an Accept/Decline popup on any menu screen for 30 seconds (`DuelConfig.CHALLENGE_TIMEOUT`). Players already in a match show as Busy.
- **Setup:** kings only, no starting pieces. A coin flip picks White, who moves first from F1; Black starts on the mirrored tile (G12). Each player brings their equipped shotgun and class.
- **View:** the server turns the board 180° for Black, so both players see themselves at the bottom as White.
- **Chess clock:** 5:00 per player (`DuelConfig.CLOCK`), running only on that player's turn. Shown next to End Turn.
- **Winning:** kill the enemy King, or the enemy's clock reaches 0. Leaving the match (Back to Menu or quitting) forfeits.
- **Kings on the board:** in duels each king is a target for the other side's shots, commands, traps, bleed and stuns. Kings still can't be knocked back. Hunting Strike's bolas stun the rival King in duels (campaign boss Kings are immune). **A stunned King skips its whole turn:** it shows as "Stunned - Turn Skipped" for a moment (`MatchConfig.STUN_SKIP_TIME`), its clock doesn't run, and play passes on. A King that walks into a trap loses the rest of that turn and the whole next one; bolas (3 turns) skip three.
- **Stuns** count the stunned piece's own turns, not including the turn it was stunned on, and wear off at the end of the last one. Smoke protects its owner's units from the other player's shots and commands.
- **Rewards (placeholder):** win 150 Gold + 100 XP, loss 50 Gold + 30 XP, forfeit nothing (`DuelConfig`).

## Visual Style

- Board effects (stun stars, command arrow) are built and rendered in Blender by `art/tools/build_effects.py` (run with `art/ShotgunChessSprites.blend` open), then packed into the sprite atlas by `art/tools/build_atlas.py` as `SpriteConfig.Effects`.

- Palette: `#332A35` (panels), `#9C574B` (borders, dark tiles), `#D49A77` (secondary text, light tiles), `#F1D4AC` (highlights), `#E9E3D6` (text). Derived shades: `#271F29` and `#1E1820` for backgrounds, `#C8644F` for warnings and enemy text, `#4A3D48` for empty bars.
- Font: Grenze Gotisch Bold, the closest built-in Roblox font to the logo lettering (Roblox can't load custom fonts). UI text is Title Case because blackletter is hard to read in all caps.
- The menu uses the logo image (`CampaignArt.LOGO`) instead of text.
- Hovering a main menu button opens a gold ribbon behind its label from the middle outward and turns the label dark. The ribbon is built in Blender by `art/tools/build_ribbon.py`; `art/tools/build_menu_art.py` outlines it and generates the CRT textures. Asset ids live in `MenuArt`.

## Pieces

| Piece  | Health | Attack Damage |
|--------|--------|---------------|
| King   | 15     | —             |
| Pawn   | 3      | 1             |
| Bishop | 5      | 2             |
| Knight | 5      | 2             |
| Rook   | 7      | 2             |
| Queen  | 9      | 4             |

## Settings

- **CRT filter** (on by default): scanlines, a vignette and a soft band rolling down the screen, drawn over every screen. Toggled with the CRT Filter button in Settings (main menu and pause menu) and saved in the profile (`Settings.CRT`, defaults in `SettingsConfig`).

## Controls

Default keybinds, rebindable in **Settings** and saved in the profile (`Keybinds`, only the actions moved off their default key):

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

- **Enemy Active/Passive cycle** — enemies act every turn instead (Nov 2026).

- **Interrupt Cards / defensive interrupts** — discarded entirely (Nov 2026).

## Open Design Decisions

Not yet specified in the design doc. Do not implement guesses without confirming.

- Fusion rules and cost
- Starting energy (prototype uses 0)
- Class placeholders: Collector energy amount, trap placement range, Deadeye cone/range numbers, what counts as an "isolated" piece
- Enemy King shotgun ammo, and whether bosses use their class abilities
- Pawn promotion: enemy pawns that reach row 1 just stop
- Regional King and Queen boss abilities (the class abilities now exist for them to use)
- What Treasure Hunts find beyond gold (items, upgrades); Treasure Hunt board art per region (colors only for now)
- Elite campaign: +5 to the starting budget, AI 1500–2000, death restarts the region (not implemented)
- The replay reward fraction (20% placeholder)
- Exact ranges/arcs for Double Barrel and Long Barrel
- Duel reward amounts and ranked play; whether bolas should skip 3 King turns or fewer
- Duels with two Outlaws show only the most recent smoke cloud on each screen

## Prototype Test Setup

- Five black dummy pieces (Pawn E3, Knight G3, Bishop C4, Rook I4, Queen F5) with their normal health. They don't act. Configured in `MatchConfig.TEST_DUMMIES`.
