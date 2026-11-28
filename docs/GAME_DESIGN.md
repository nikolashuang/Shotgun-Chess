# Shotgun Chess — Game Design

Source: [Shotgun Chess design doc](https://docs.google.com/document/d/1gA-xHbcUpENdVX3_O49R_yyCUCjF6f7sPg0P0JDFYTQ/edit)

A reimagining of *Shotgun King: The Final Checkmate*. Players control an armed king, command summoned chess pieces, and wield fantasy shotguns that define their combat style. Supports single-player campaign (PvE) and multiplayer duels (PvP).

## Win Condition

Kill the enemy king.

## Board

- 10x10 board (columns A–J, rows 1–10). The player's king starts at E1.
- Co-op matches use a 16x16 board (not implemented).

## Turn System

The game is fully turn-based. All durations (stuns, souls, crafted weapons, etc.) are measured in turns.

Turns are energy-based:

- **Movement** — the king can move once per turn for **1 energy** (Nov 26 2026: was free), like a chess king: one tile in any of the 8 directions. It has its own Move button (default key W; Summon is S, End Turn is Space) at the top of the action panel; the king's steps only show, and a click only moves him, while Move is selected (same for Assimilate's bonus moves). Assimilate's bonus moves stay free.
- **Actions** — each action can be used **once per turn**, in any order, as long as there's energy to pay for it (prevents spam; used actions fade out in the action panel):
   - **Fire shotgun** — 1 energy
   - **Command a piece** — 1 energy per 2 tiles the piece travels, rounded up (min 1; a knight's jump counts as 2) — move or attack with one of your pieces using its normal chess movement
   - **Reload** — 1 energy, refills the shotgun's magazine
   - **Use special** — 2 energy
   - **Summon a piece** — the piece's cost (see Energy); placed on an empty tile within one tile of the king. Opening the summon menu is free.
   - **Use ultimate** — free once fully charged

The turn ends with **End Turn**.

### Enemy Turn

Campaign battles run the enemy AI (`ServerScriptService.AI.EnemyAIService`, tuning in `AIConfig`). Matches without an AI rating (the Duel test dummies) still use a fixed 5-second wait (`MatchConfig.ENEMY_TURN_TIME`).

- Every enemy piece may move OR attack on every enemy turn. *(The Active/Passive cycle from the design doc was removed in Nov 2026: too easy.)*
- **Stuns:** a stunned piece skips its enemy turns until the stun runs out. `MatchClass:StunPiece` applies one and shows stars circling the piece's head until it wears off.
- **Rotating priority:** acting pieces plan in Id order, rotated by one each enemy turn.
- **Planning (Nov 25 2026 revamp):** pieces plan one at a time on a shared board (`AI/AIBoard`). Each committed plan frees the piece's old tile and claims its new one, so later pieces see the lines it opens and the tiles it takes. Attacks then resolve first (checked against the board at the start of the turn) and moves run in plan order.
- **Utility scoring:** every option is scored against every directive at once: the sum of directive weight × how well the option serves it, minus risk. Weights start from `AIConfig.Weights` and shift with the board: Defend grows when the enemy King is in danger, Attack grows as the player's king loses health. Profiles: Default Defend > Attack > Evade > Position > Teamwork > Advance; Queens put Attack above Defend until only their King and Queen are left; Rooks lean on Position, Bishops on Position at 3–5 tiles from the player's king, Knights on Attack and Teamwork. Enemy Kings: Evade > Attack > Ability > Teamwork > Position > Advance. Pawns and Fallen Pawns: Advance > Attack, where Advance means stepping toward the promotion row; they keep marching even into danger.
   - Danger: only what the player can see. The player's king can step once (1 energy) and then blast (line of sight: non-piercing pellets never reach a tile behind an enemy piece) or slash with the Knife Shotty; it needs ammo, or energy to reload first, from next turn's energy. Only one white piece can be commanded per turn. Player class abilities aren't counted yet.
   - Risk: every option except a piece attack loses points for the damage the tile could take plus the piece's value (`AIConfig.PieceValue`) times its chance of dying there, and for allies within 1 tile the same blast could hit. Non-lethal risk is shared when several pieces are in reach, since the player's king only blasts one target a turn. Position, Teamwork and Advance only count as much as the piece is likely to survive the tile.
   - Defend: kill whatever threatens the enemy King, step into its line, or stand next to the King on the threat's side.
   - Evade: pieces press the attack until they're hurt: they only start actively retreating below 30% health, Kings below 50% (`AIConfig.EVADE_HEALTH`), and the pull grows as health drops. Above that they still avoid bad tiles through the risk cost. An evading Rook or Bishop slides at most 4 tiles (`AIConfig.SLIDE_CAP`, number is an assumption); attacks and normal moves use the full slide.
   - Bait check: attacking a cheaper summoned piece is priced as a trade (share of health lost × the attacker's value, × 1.5), so a Rook won't take a pawn planted next to the player's King for a point blank blast, while pawns still will, and anyone will when the player can't shoot next turn. Kills on valuable targets (a summoned Queen) can still be worth a sacrifice.
   - Position: line up an attack on the player's king and cover the tiles it could step to.
   - Teamwork: cover escape tiles no ally covers yet, finish targets an ally already hit this turn, close in from a side no ally holds, and threaten white pieces that threaten an ally.
   - Advance: close distance to the player's king. Stepping straight back to last turn's tile is scored down, and a piece that hasn't moved or attacked for a few turns is pushed forward.
   - A lone enemy King gets tired of running: every turn in a row it backs off cuts its Evade and its Attack goes up.
- **Enemy pieces** attack with chess capture rules and their normal damage, against the player's king or summoned pieces. Killing a summoned piece moves the attacker onto its square, and the AI scores that capture square (Position, Teamwork, Advance) as where the piece ends up.
- **Enemy Kings** hold and fire a Pump shotgun (`ShotgunConfig.ENEMY_KING`) with the same rules as the player's, aimed straight at a target. The gun points at the player's king until they fire, then at their last shot. They don't track ammo (assumption).
- **Ratings** set how often a piece takes a random option instead of its best one: 500 → 40%, 1000 → 25%, 1500 → 10%, 2000 → 5%, 2500 → 1% (max 2 per match). Campaign battles use 1000 (`CampaignConfig.AI_RATING`).
- **Debug:** `AIConfig.DEBUG = true`, or `workspace:SetAttribute("AIDebug", true)` during a playtest, prints every piece's weights, best options with their score per directive, and why it picked one.
- **Promotion (singleplayer only):** an enemy Pawn that reaches row 1 (moving or capturing) becomes a Knight (40%), Bishop (40%) or Rook (20%) at the new piece's full health (`PieceConfig.PROMOTIONS`). The player's pawns, Fallen Pawns and Practice AI pawns never promote.
- **Defeat:** the player's king dying ends the match as a Defeat.
- **Boss abilities (Nov 25 2026):** campaign boss Kings use their class (`AI/BossAbilityService`, rules in `AIConfig.Boss`, numbers from `ClassConfig` like the player's version). They have no energy or charge: the special comes back every 3 enemy turns, the ultimate can be used once per fight after dropping to half health. Using one doesn't cost the King his move or shot, and the board shows its name ("Morale!"). A stunned boss uses neither.
   - Monarch: Morale whenever at least one ally ends the turn where the player can hit it; Unyielding on a turn where allies attack.
   - Reaper: Reap drops a soul (red flame) for every piece that dies, allies included. Assimilate after shooting (or standing) to move like a soul's piece to the safest tile, when that cuts the danger by 2+. Reaper's High when the heal plus the extra damage on this turn's shot is worth 2+ souls.
   - Hunter: Trap Layout from the first turn: 2 hidden traps within 2 tiles of the King, nearest the player and on tiles white pieces could step onto. The player sees a trap only when it snaps (1 damage, 1 turn stun; knights jump them). Hunting Strike throws Pump-cone bolas when they catch the player's king (stunned 1 turn) or 2+ pieces (3 turns).
   - Bandit: Opportunist (+2 on shots at targets with no ally next to them). Conceal smokes the spot where the most value is in danger (the King counts most), and the player's attacks into it hit 50/50 until the next enemy turn. Ambush, before the turn is planned, jumps next to the player's king when the point blank shot from there kills, or deals 6+ without landing where the King would die.
   - Gunslinger: Deadly Rounds (his Pump pierces, -2 per unit passed). Fan the Hammer goes off after his shotgun blast, down the line where six shots do the most, so it finishes what the blast leaves. High Noon's Bounty marks the 2 white pieces closest to dying.
   - **Player king stuns (campaign):** a boss trap or bolas skips the player's turns like in duels. A trap stepped on during your own turn costs the rest of that turn and the next.
   - The Dev Campaign King fights as `CampaignConfig.Regions.Dev.BossClass` so each boss can be tested.
- **Open design decisions (enemy AI):**
   - Bounty for bosses: bosses have no energy, so a marked piece dying makes Fan the Hammer ready again instead of giving energy. Confirm or change.
   - Visuals reused as placeholders: Reaper's High healing plays the boss's hit animation; the boss's six Fan the Hammer shots play as one burst; with the player and boss both Bandit, only one smoke cloud shows at a time.

### Commanding Pieces

- Pieces move with normal chess movement and can't move onto an occupied tile. Sliding pieces are blocked by any piece.
- Pawns move one tile forward (toward the enemy side).
- Every highlighted choice on the board (moves, summon tiles, command targets) has a border, and the one under the cursor gets a thicker yellow border.
- Choosing Command outlines every piece you can choose in yellow; the chosen piece gets a spinning yellow arrow bobbing above it.
- **Attacking:** commanding a piece onto an enemy attacks it instead of moving. Targets follow chess capture rules: pawns attack diagonally forward, knights jump, sliding pieces hit the first piece in each line (friendly pieces block). The attacker hops to the enemy; if the hit kills it, the attacker takes the enemy's square like a chess capture, otherwise it returns to its own square. Enemy pieces capture the same way when they kill a summoned piece (attacks on the player's king never move the attacker). Survivors flash white like any hit; killed pieces fall over and crumble.
- Summon damage builds ultimate charge like any other damage to enemy pieces.

### Energy

- Each player gains 2 energy at the start of every turn (including the first), up to 8 (Nov 26 2026: was 1).
- Starting energy is 0. *(Assumption — confirm.)*
- Summon costs: Pawn 1, Knight 2, Bishop 2, Rook 3, Queen 6 (raised from 4 in Nov 2026 so the Queen is harder to get).
- Action costs: Move 1, Fire 1, Command 1+ (tiles ÷ 2, rounded up; `CombatConfig.COMMAND_TILES_PER_ENERGY`), Reload 1, Special 2, Ultimate 0. Only command tiles the player can afford are highlighted.
- Hovering an action button, or having an action selected, makes the energy it will spend flash between red and the empty-bar color on the energy bar; for a command, the hovered target sets the cost.
- Only one active Queen per king.
- Energy is also spent on fusion (cost undecided).

### Ultimate Charge

- Only the King builds it (Nov 24 2026): 5 charge (was 10) per point of damage his own weapons actually deal to enemies (overkill doesn't count). That's shotgun and knife hits, Knife Shotty bleed and Fan the Hammer's revolver. Damage from commanded pieces, the Fallen Knight and Hunter traps doesn't charge it.
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

Shotguns are bought in the Shop with gold and equipped in the Armory. Only the Pump is owned at the start; unowned shotguns show as LOCKED. Prices were raised by 5,000 each (Nov 22 2026) when gold became buyable with Robux. Numbers marked *placeholder* are not in the design doc.

| Shotgun | Price | Ammo | Range | Arc | Damage | Notes |
|---|---|---|---|---|---|---|
| Pump (starter) | — | 5 | 3 | 64° | 5→2 | Basic shotgun |
| Double Barrel | 7000 | 2 | 2 *(placeholder)* | 64° | 3.5→2.5, x2 | Every shot fires both barrels: 2 shells, double damage. Holds one shot, so it reloads after every blast (Nov 2026) |
| Buck Barrel | 7100 | 4 | 3 | 64° | 5→3 | Knockback 1 tile |
| Long Barrel | 8500 | 4 | 4 | 24° *(placeholder)* | 3→1 | Very tight cone; falloff nerfed to 1 at max range (Nov 2026) |
| Knife Shotty | 7400 | 5 | 3 | 64° | 5→2 | Alt mode: knife swing |

**Knockback (Buck Barrel):** every enemy the shot hits and doesn't kill is pushed 1 tile straight away from the king (one of the 8 directions). If the tile is off the board or occupied, it stays put with no extra damage. Kings can't be knocked back. Enemies farther from the king are pushed first, so a line of enemies all move back together. The precise shot was removed (Nov 2026).

**Alt modes** — right click while aiming switches between normal and alt; left click fires.

- **Knife swing (Knife Shotty):** hits 2 adjacent tiles — the tile it points at plus its neighbor on the cursor's side. Needs an enemy in one of them. 5 damage and bleed (1 damage per turn for 3 turns, ticking at the start of the bleeding piece's turn; reapplying refreshes it). Costs 1 energy like any shot but no ammo, so it works at 0 ammo.
- Point blank applies to normal shots of every shotgun.

## Classes

Chosen in the Armory alongside the shotgun. All numbers live in `ClassConfig`; each class's logic is a component in `ServerScriptService.Match.Classes` (`MonarchClass`, `ReaperClass`, `HunterClass`, `GunslingerClass`, `OutlawClass`) that `MatchClass` calls into.

- The king starts with **no class**: normal turns and normal summons only. Special and Ultimate are hidden in the HUD while no class is equipped.
- Each class is unlocked by defeating a region's King (see Campaign): King's Training → Monarch, Hunter Forest → Hunter, Cliffside → Bandit, Outskirts → Gunslinger, Gravehollow → Reaper. Profiles that already cleared a region get its class when they load (this is how existing players got Monarch). Clicking the equipped class in the Armory unequips it.
- **Special:** 2 energy, once per turn. **Ultimate:** needs 100 charge, costs no energy, once per turn, spends the whole charge.
- Reaper's High and both of Monarch's abilities have no target and fire as soon as they're selected; the rest wait for an aim or clicks on the board.
- Numbers marked *placeholder* aren't in the design doc.
- **Class outfits (Nov 24 2026):** equipping a class dresses the King in that class's outfit; with no class he's the classic King. Rival Kings in duels wear their class's outfit, and campaign boss Kings wear the class their region unlocks. The Armory has a "Your King" panel beside the abilities showing the King idling in the equipped outfit. Each outfit is drawn once in `art/tools/class_outfits.py` (stills and a preview sheet in `art/skins/pieces/`); `art/tools/build_class_kings.py` maps it onto every King animation frame (squash, stretch, death rubble), sways the cloth (each class's `FABRIC` colors) while rigid items like weapons and hats stay put, and packs both teams into `art/ClassKingAtlas.png` with `ClassKingConfig.luau`. The King keeps his classic cream body, with the class shown through clothing:
  - **Monarch:** royal-red cloak fastened round his neck that wraps round him: the lighter front drapes over his shoulders and sides and ends mid-body with a gold hem, and the darker back hangs lower behind him, just past the top of the base; white ermine collar round the neck (flecks only at the sides); gold chain draped across the chest to a clasp in the front; crown and classic body unchanged.
  - **Hunter:** heavy shaggy fur coat hanging open behind him (down to the top of the base), fur collar behind the shoulders, bone-fang necklace.
  - **Bandit:** gray cloth mask over the lower face (no eyes), layered tattered scarves round the neck and shoulders, dark leather vest with crossed straps, belt with pouches and a pocket knife on his right side drawn at an angle pushing back behind him (shaded brass end cap facing the viewer, wooden handle and crossguard, blade narrowing and darkening as it recedes behind the base; handle outlined dark), ragged cloth flaps hanging from the belt.
  - **Gunslinger:** cowboy hat with the gold crown pinned to the band, red fringed poncho, bandolier of brass rounds, belt and buckle, and a leather holster high on the right hip, just under the poncho, with a revolver in it (outlined dark).
  - **Reaper:** wrapped in a dark cloak from the neck down ending in ragged tendrils, crown and bare head, scythe slung across his back.
  - These are class defaults, not crate skins, so Epic skins still need their own designs.

### Monarch (added Nov 24 2026)
- **Passive [Loyalty]:** your first Queen each match costs 4 energy instead of 6. The Queen summon card shows the lower cost until one is summoned.
- **Special [Morale]:** every one of your pieces (not the King) gets a 1 health shield that soaks up damage before health. It lasts until the start of your next turn and shows as a light-blue border on the piece's health bar. Needs at least one piece.
- **Ultimate [Unyielding]:** every one of your pieces deals +2 damage for the rest of the turn (commanded attacks, and the Fallen Knight's attack at the end of the turn). The command damage preview includes it. Needs at least one piece.
- Armory drawings: Loyalty is the King's gold crown, Morale a silver heater shield, Unyielding the King's red banner rippling in the wind with his crown on it.

### Reaper
- **Passive [Reap]:** every piece that dies leaves a soul on its tile, allies included (Nov 2026): a black orb in greenish-blue flame with a faint ghost of its piece. Queens leave souls too. Kings end the match, so they never do. When your rival is a Reaper, you see their souls in red flame; your own stay blue.
- **Special [Assimilate]:** pick a soul; it's used up and the king's move this turn uses that piece's movement (Knight jumps, Rook/Bishop/Queen slides, Pawn steps forward). It's a bonus move that doesn't count as the king's movement, so it works after the king has already moved (Nov 2026); unused, it expires at the end of the turn.
- **Ultimate [Reaper's High]:** absorb every soul on the board. Heal 2 HP per soul, at most 8 HP per use (Nov 24 2026), and +1 damage per soul on every hit of the next shot. Needs at least one soul.

### Hunter
- **Passive [Collector]:** each enemy death has a 25% chance to give +1 energy, shown as a lightning bolt floating up. *(+1 is a placeholder.)*
- **Special [Trap Layout]:** place 2 bear traps (Nov 24 2026: was 3) on empty tiles within 2 of the king; click 2 tiles (fewer if there aren't 2 free). Only the player sees them. An enemy that moves or is knocked onto one takes 1 damage (Nov 24 2026: was 3) and is stunned 1 turn. Any move or attack whose line crosses a trap stops on the trap's square and springs it, cancelling the rest of the move or attack, so traps also shield the king and allies. Knights jump over traps they cross and are only caught by landing on one; enemy Kings are affected. The trap clamps shut over the piece, floats up and fades.
- **Ultimate [Hunting Strike]:** aimed and thrown exactly like a Pump shot (Nov 2026: was Double Barrel): same 3-tile cone, range, line of sight and point blank (`HuntingStrike.Weapon`), previewed with the same arc. Every enemy in the hit tiles is stunned for 3 turns and deals no damage; Kings, rival and campaign boss alike, are stunned for 1 turn (Nov 24 2026: boss Kings were immune, duel Kings took 3). A bolas flies to each one and stays wrapped around it while it's stunned. Only throws if it would catch at least one enemy, so the charge isn't wasted. (Replaced the old 5-tile radius in Nov 2026.)

### Gunslinger
- **Passive [Deadly Rounds]** (Nov 2026, replaced Deadeye): no body blocking for any shotgun; blasts pass through every piece. Each target takes -2 damage for every enemy the blast passed through on the way to it (nerfed from -0.5, Nov 2026). Point blank shots go through the adjacent enemy and on in a straight line to max range. Applied to the weapon itself (`ShotgunRules.GetWeapon(name, "Gunslinger")` sets `Pierces`), so the aim preview matches.
- **Special [Fan the Hammer]:** the king pulls out a revolver (shown while aiming and firing) and fires 6 shots down a 4-tile straight line (Nov 24 2026: was 3) (snapped to the 8 chess directions). Each shot has a 60% chance to hit and deals 1.5 damage. Shots don't pierce: each hits the first living enemy in the line, so once that enemy dies the remaining shots go to the next one. A target inside enemy smoke also rolls the smoke's 50%.
- **Ultimate [High Noon's Bounty]:** click 2 enemies (Kings allowed; 1 if only one is left) to mark them with a red X. Each marked enemy pays 2 energy when it dies, however it dies. Marks last until the enemy dies.

### Bandit

*Shown in game as the Bandit (renamed from Outlaw, Nov 2026). Code still uses the `Outlaw` key and `OutlawClass`, so saved unlocks and loadouts keep working.*
- **Passive [Opportunist]:** +2 damage (Nov 24 2026: was +1) on shotgun hits against an isolated enemy, meaning one with no allied piece (its own King included) within 1 tile.
- **Special [Conceal]:** throw a smoke bomb at any tile up to 3 away; a 3x3 cloud centers there for 1 enemy turn (Nov 2026: was 2). Every enemy attack into it has a 50% chance to hit, rolled separately for each target: piece attacks, knife swings, shotgun blasts and Fan the Hammer shots (Nov 24 2026: enemy pieces used to be unable to attack into it at all). A piece that misses still lunges but deals no damage. Pellets still stop on it. Hovering previews the cloud.
- **Ultimate [Ambush]:** jump the king to any empty tile next to an enemy (`Ambush.MaxEnemyDistance`, 1). Doesn't use the turn's move. (Nov 24 2026: the +2 damage on the next shot was removed.)

### Health Bars

Every health bar (pieces and kings) has a divider between each point of health, like the energy bar, so players can count the hits left.

## Story Mode

The old Campaign becomes Story Mode. Its card on the Singleplayer screen is locked ("Coming Soon") until the story is written.

## Expedition (Nov 27 2026)

A replayable roguelike run, separate from Story Mode. Spec: the Expedition design doc pasted Nov 27 2026. Tuning lives in `ExpeditionConfig`, rules in `ExpeditionRules`, map generation in `ExpeditionMap`, the server in `ExpeditionService`, armies in `Expedition/EncounterRules`, the screen in `ExpeditionController`, art ids in `ExpeditionArt`.

### Structure

- Three Acts. When a run starts, one region is rolled from each Act's pool: Act I **King's Throne** or **Thorned Forest**, Act II **Cliffside** or **Outskirts**, Act III **Gravehollow**. More regions are added by putting them in a pool.
- Each Act is a branching map laid out like the old Campaign map: 4 lanes with a node on every one of 10 layers (40 nodes) plus the Boss. Each node links straight up, 40% of the time also into a neighboring lane, and 35% of those branches replace the straight link when the node above still has another way in. Routes can cross, and at least 3 links cross between the two middle lanes so the map never splits down the middle. Every lane ends at the Act's Boss. The map is built from a seed kept in the run, so the server, the client and a restored checkpoint all get the same map.
- One node per layer; only nodes linked from the current one can be entered. Skipped nodes stay behind.
- Generation weights: Battle 25, Mystery 45 (the spec's 20% Regional is folded in), Elite 15, Shop 10, Rest 5. Layer 1 is always Battle. Rest Sites and Elites never sit next to their own kind on a route. Every Act gets at least one Rest Site and one Shop.
- **Regional Encounters are Mysteries** (Nov 27 2026): there is no separate Regional node. A Mystery node rolls from the universal Mysteries plus the current region's Regional Encounters not yet met this run, so those can only appear in their own region. Mystery nodes show only the "?" badge; the encounter is rolled on entry and kept in the run so it can't be rerolled.
- Beating the Boss opens the next Act. Beating Act III completes the Expedition. 33 encounters including the 3 Bosses.

### The Map Screen

- Portrait paper map in a scroll frame that opens at the bottom (layer 1) and follows the King up. The legend is a paper slip on the right, the run panel (health, Silver, upgrades, Artifacts, pouch, Abandon) on the left, the node info and Fight/Enter button under the legend. The run panel shows the King's portrait beside his health and a bar with one segment per max health, Silver on its own highlighted row, the run's 5 Artifact slots, and the pouch. Battles show their Gold, Silver and XP rewards as icons on the play card. Currency icons are Nikolas's paintings (`art/expedition/currency_icons_source.png`), cut by `art/tools/build_currency_icons.py`.
- Every map and the legend sit on Nikolas's painted parchment (`art/expedition/parchment_source.png`, cut by `art/tools/build_parchment.py`). On the map it's a tall sheet (the page with its middle stretch repeated) that scrolls with the routes: a run opens on the bottom of the paper, and the top edge only comes into view when scrolled up to the Boss. About a quarter of the sheet shows at once. Each region lays its own trim over the parchment's edges, drawn in Blender by `art/tools/build_expedition_art.py` (Nov 28 2026): King's Throne gold wire laced through eyelets with garnet clasps on the corners, Thorned Forest twisting vines, Cliffside boulders, Outskirts plain parchment, Gravehollow a ring of purple graveyard mist. Each region also has its own ink and route color (Gravehollow's walked route is a ghostly green); all Expedition text uses the game font (Nov 28 2026).
- Encounter badges are Nikolas's painted pixel badges (`art/expedition/encounter_badges_source.png`), cut and packed by `art/tools/build_encounter_badges.py` into `encounter_badges.png`: crossed sword and shotgun (Battle), Queen with laurels (Elite), King between banners (Boss), question mark in mist (Mystery), market stall (Shop), campfire camp (Rest). Locked nodes are faded, visited ones dimmed with a check. (The earlier single-ink Blender icons are kept in `art/expedition/expedition_encounter_icons.*` but unused.)

### Progression Inside a Run

- **Silver** is the run's currency for every purchase. Battles pay Silver (Battle 15, Elite 30, Boss 50, encounter fights 10) and Treasure Hunts pay 5–60. It carries between Acts and is lost when the run ends.
- **Gold and XP** collect in the pouch (Battle 100/50, Elite 200/100, Boss 500/250, encounter fights 100/50, other encounters 25 XP, Rest 20 XP; x1 / x1.5 / x2 by Act) and are only paid out when Act III is beaten. Abandoning forfeits them.
- **Upgrades** last for the run only and never touch Campaign, PvP or the profile: King max health, shotgun damage, ammo capacity (Gun Maintenance), summon health and damage, starting Ultimate charge, heal after battles, max energy.
- **Artifacts:** up to 5, no duplicates. Elites drop one, Shops sell them for Silver. Holding 5, a new one replaces a chosen slot or is left behind. Artifact designs and prices are not made yet (`ExpeditionConfig.Artifacts.Pool` is empty), so Elites drop nothing and Shops are empty for now.

### Health, Checkpoints and Failure

- King health (current and max) carries between every encounter and Act.
- **Rest Sites** (Normal only) save a checkpoint just before the choice: Rest (heal 70% of missing health; the Fallen Knight heals the same share) or Gun Maintenance (+1 ammo capacity, +2 on the Double Barrel). Dying restores the last checkpoint: same maps, same encounters, same Shop stock, and the Rest choice can be made again. Dying before any checkpoint ends the run.
- **Battles** lost: Normal restores the checkpoint; Elite Expeditions end the run.
- **Encounter penalties** that kill the King follow the same defeat rules.
- Leaving mid-run saves it exactly where the player left.

### Enemies

- Point budgets: Act starting allocation 6 / 12 / 18 (Elite mode +5: 11 / 17 / 23). Normal Battle = allocation, Elite = +6, Boss = +12. Winning a Normal or Elite Battle raises the allocation by 3; encounter fights use it without raising it. A new Act resets it to that Act's start.
- Costs: Pawn 1, Knight 3, Bishop 3, Rook 5, Queen 9, King 0, Necromancer 7. Elites and Bosses always field one Queen (her 9 comes out of the budget); Bosses add the region's King on his fixed tile (Queen column 5, King column 6 of the back row). 2 points are kept for Pawns, Knights/Bishops/Rooks (and Necromancers in Gravehollow) spend most of the rest with Rooks likelier as the budget grows, then Pawns fill (max 5). Max 1 Queen, 2 Necromancers. Bishops alternate square colors.
- Enemies spawn on rows 7–10 (the back of the 10×10 board).
- Armies with a King are beaten by killing the King, armies without one by clearing every enemy piece.
- **Act scaling:** max health x1.25 per Act, compounded and rounded up; damage +1 per Act for Pawns, +2 for Knights, Bishops, Rooks and Queens. Enemy Kings get the health scaling only. The Necromancer and Fallen Knight keep their own stats. Player summons don't scale with Acts. Promoted pawns take the Act's stats for their new piece.
- **Boss Kings** fight with their region's class: King's Throne Monarch, Thorned Forest Hunter, Cliffside Bandit, Outskirts Gunslinger, Gravehollow Reaper.
- **Regional AI:** every region uses the same AI with its own directive multipliers and risk tolerance (`ExpeditionConfig.Regions[...].AIWeights` / `Risk`): King's Throne defends and avoids bad trades, Thorned Forest weights position (blocking escape tiles) and teamwork, Cliffside position and advance (confinement), Outskirts attack with low risk aversion, Gravehollow defends its Necromancers and trades freely.

### Necromancer (Gravehollow)

Rook variant: 12 health, 3 damage, 7 points, Rook movement. Before planning, a Necromancer whose raise is ready spends its action raising the most valuable fallen ally within 3 tiles onto its free death tile at half its max health (rounded up), with its Act-scaled damage; the raised piece can't act until the next enemy turn. 3-turn cooldown, 2 raises each. Can't raise Kings, Queens or Necromancers; a piece is raised once per battle; raised pieces drop no Reaper souls. The AI keeps it back (high Evade) and walks it toward fallen allies while a raise is ready. Until it has its own sprite it uses the Rook's, tinted green (`PieceConfig.SpriteStandIns`).

### Universal Mystery Encounters

Rolled on entry, never the same one twice in a row (`ExpeditionConfig.Mystery`):
- **Wandering Gunsmith:** 50 Silver for +1 shotgun damage (fall-off included), or leave.
- **Ambush:** take 3 damage at once, then fight the current allocation with the King surrounded in the middle of the board.
- **Queen's Altar:** Blood Offering (-4 health, +2 max health), Royal Sacrifice (-6 health, +2 shotgun damage), or leave. Neither can kill.
- **Treasure Hunt:** 12×12 board in the region's colors, 5 digs, each uncovers 3×3. Silver 60/50/40/30/20 by dig, 5 if never found.
- **Abandoned Barracks:** Reinforced Armor (+1 max health for summoned pieces) or Weapons Training (+1 damage for summoned pieces).
- **Wandering Doctor:** Treatment (heal to full) or Vitality (+2 max health, +2 health).
- **Statue of a Holy Rook:** Blessing of Power (start battles with 25 Ultimate charge, -2 max health) or Blessing of Vitality (heal 2 after each battle, -1 max energy).
- **Gambler:** wager 25, 50 or 100 Silver on a 50/50 to double it, or leave.

Barracks, Doctor, Holy Rook, Gambler and Treasure Hunt use the camp background until they get their own art.

### Regional Encounters (rolled from the Mystery pool, only in their region)

- **Gravehollow — Fallen Knight:** fight him (10 health, King + Knight movement, his 3 points out of the allocation) and a supporting army bought with the rest (no Kings or Queens; +2 health, +1 damage on top of Act scaling), or keep walking. Win and he joins as a companion for the rest of the run: starts right of the King, acts on his own, health carries over, gone for good if he dies (unless a checkpoint brings him back).
- **Cliffside — Deadman Walking**, **Outskirts — Dangerous Payload**, **Gravehollow — Haunted Mansion:** specified but not built yet (they need new board rules: a restricted 2×10 path with Sniper Bishops, an escorted payload, a maze with Ghost and Zombie pieces). They're in `ExpeditionConfig.Exclusives` with `Enabled = false`, so they stay out of the Mystery pool until they're made.

### Elite Expedition

Same structure, +5 to every Act's starting allocation, Rest Sites keep their choices but save no checkpoint, and any defeat ends the run (upgrades, Artifacts, companion and pouch are lost). Chosen when starting a run.

### Developer Tools

Dev accounts can send `ExpeditionRemote` `DevEncounter <name>` (pins the next Mystery roll, Regional Encounters included) and `DevAct <1-3>` (jumps to an Act's map) for testing. The Expedition screen also has a dev-only **Dev Maps** button: it shows any region's map from a fresh random seed without touching the real run (◀ ▶ change region, New Map rerolls, Exit returns to the run). Nodes can be inspected but not entered.

### Progression

- Gold buys shotguns. XP raises the account level. Each level needs 100 more XP than the last: 100 for level 2, 200 for level 3, and so on (`ProgressionRules.GetExpToLevel`).
- **Multiplayer opens at level 5** (`ProgressionConfig.MULTIPLAYER_UNLOCK_LEVEL`, 1,000 total XP), so players can play co-op with friends sooner.
- **Duels unlock at level 10** (`ProgressionConfig.DUELS_UNLOCK_LEVEL`, 4,500 total XP), checked on the server. Below that the Duels card shows "Duels [Lv 10]" and can't be opened.
- Every class is unlocked from the start (Nov 27 2026; they used to come from beating Campaign Kings).
- **Dev panel:** a Developer button on the main menu, shown only to the accounts in `DevConfig.USER_IDS` (Snoothe3rd). It can unlock everything (all shotguns, classes and the Multiplayer unlock level), add 1000 Gold, or reset the profile. The server checks the account on every request.
- Saved in a DataStore (`PlayerProfile_v1`): gold, XP, owned shotguns, unlocked classes, the Expedition in progress, equipped loadout, settings and keybinds. If the profile can't load (e.g. Studio API access off), a temporary profile is used and never saved.

## Multiplayer (PvP Duels)

Unlocks at level 10 (the Multiplayer screen itself opens at level 5). Uses the same rules as the campaign (`MatchClass`), with two human sides instead of the AI.

- **Screens:** Multiplayer opens on a **Duels** card (room for more multiplayer modes beside it). Duels opens two cards: **Queue** (searches in place, click again to cancel; pairs the two players who have waited longest) and **Challenge** (the player list on its own screen). Back steps out one screen at a time. Card drawings come from `art/tools/build_armory_icons.py` (sheet in `ArmoryArt`).
- **Practice** (the last card on the **Singleplayer** screen, after Campaign and Siege; no level needed): Choose Difficulty picks the AI rating (500–2500 in steps of 500, `DuelConfig.PRACTICE_RATINGS`) and the AI king's shotgun and class. It's a normal duel (coin flip for White, 5:00 clock) against `PracticeAIService`, with no rewards.
- **Practice AI (simple for now):** each turn it moves the king to the tile with the best shot (or toward your King), then shoots; with no shot it attacks with a piece if it can. It reloads when empty, saves energy for a randomly picked piece and summons it near its king, and uses spare energy to push a piece forward. The rating is its chance of picking a worse move (`AIConfig.Ratings`). It doesn't use class specials or ultimates yet. Smarter player techniques get added over time.
- **Challenges:** a challenge shows the target an Accept/Decline popup on any menu screen for 30 seconds (`DuelConfig.CHALLENGE_TIMEOUT`). Players already in a match show as Busy.
- **Setup:** kings only, no starting pieces. A coin flip picks White, who moves first from E1; Black starts on the mirrored tile (F10). Each player brings their equipped shotgun and class.
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

### Low-Health Movement (enemy AI)
Hurt enemy Rooks, Bishops, Queens and Necromancers lose movement range so the player isn't chasing them across the board (`AIConfig.LOW_HEALTH_RANGE`). Applies to AI-controlled pieces only (singleplayer and Practice); the player's summons and human rivals' pieces keep full range. Pawns, Knights and Kings are unaffected.

| Health | Max slide |
|---|---|
| Above 66% | Full |
| 34–66% | 3 tiles |
| 33% or less | 1 tile |

Moves only — attacks still reach the first piece down a line at any distance. Stacks with the evade cap (`AIConfig.SLIDE_CAP`); the shorter cap wins.

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

## Shop

One scrolling page (`ShopController`, prices in `ShopConfig`), top to bottom:

1. **Featured Skins** (placeholder) and **Skin Crates** (see Skins). Featured Mythical skins will get boosted crate rates.
2. **Shotguns** — bought with gold (see Shotguns).
3. **Gold** (Robux): 1,000 for 50, 10,000 for 400, 50,000 for 1,400 ("Best Value!!!", tag pulses), 100,000 for 3,000.
4. **Boosts** (Robux): 2x Gold or 2x XP, 50 Robux for 1 hour of **play time** each (only counts down while in a server, either place). Buying again adds another hour. Doubles what's earned from campaign payouts (applied when the pouch pays out) and duel rewards; bought gold is never doubled.
5. **Donations** (Robux): 500, 1,000, 1,500, 2,000. Grant nothing.

Robux items are Developer Products (ids in `ShopConfig`, icons in `art/shop`). `PurchaseService` grants each purchase once: the purchase id is saved with the profile before the receipt is marked granted, and both places take receipts.

### Gold Economy (Nov 22 2026)

First clear of each region, from the real maps (low end: lanes heavy on Mysteries; high end: battle lanes with good Treasure Hunts):

| Region | Gold |
|---|---|
| King's Training | 525–1,275 |
| Hunter Forest | 1,200–2,150 |
| Cliffside | 1,875–3,025 |
| Outskirts | 2,550–3,900 |
| Gravehollow | 3,225–4,775 |
| **Campaign** | **~9,400–15,100** |

- Afterwards: replays pay 20% (~950 per Gravehollow run), duels 150 per win / 50 per loss.
- All four buyable shotguns cost 30,000; a full first clear buys about 2. The rest is ~17 Gravehollow replays or ~107 duel wins.
- Gold per Robux: 20 (1k pack), 25 (10k), 35.7 (50k, best value), 33.3 (100k). One shotgun ≈ 350–425 Robux at the base rate; the whole campaign's gold ≈ 730 Robux.

## Skins

Cosmetic only. They come only from Shop crates and are equipped in the Armory's Skins tab. Config in `SkinConfig`, rolls on the server in `CrateService`.

| Rarity | Style | Drop rate |
|---|---|---|
| Common | Plain recolors, no extra detail | 80% |
| Rare | Richer palettes and pairings, thin accent border on every tile | 15% |
| Epic | Detailed themed redesigns, mostly static | 4.5% |
| Legendary | Animated (design pending) | 0.5% |

- A rarity a crate has no skins for drops the next rarity down, so Legendary rolls give an Epic for now.
- **Crates:** Gameboard Crate, Gun Skin Crate, Piece Skin Crate, each 1,000 Gold or 10 for 8,000. Only the Gameboard Crate opens for now; the gun and piece crates say Coming Soon.
- **Duplicates** refund 10% of the gold paid for that crate (100 from a single, 80 each from a 10-pack). No pity system for now.
- **Board skins:** Classic (default, owned by everyone, never drops). Common: Crimson, Azure, Onyx, Moss. Rare: Black & Gold, Ivory & Crimson, Royal Buckshot (Shotgun King-inspired palette). Epic: Ruined Chessboard (cracked stone slabs), Abandoned Castle.
- Epic boards are one 192x192 pixel image of the whole board (16 px per tile), rendered by `art/tools/build_board_skins.py` into `art/skins/boards`, so cracks and rubble run across tiles.
- Each player sees their own equipped board, in the campaign and in duels.

## Open Design Decisions

Not yet specified in the design doc. Do not implement guesses without confirming.

- Fusion rules and cost
- Starting energy (prototype uses 0)
- Class placeholders: Collector energy amount, trap placement range, Deadeye cone/range numbers, what counts as an "isolated" piece
- Enemy King shotgun ammo, and whether bosses use their class abilities
- Regional King and Queen boss abilities (the class abilities now exist for them to use)
- Expedition: Artifact designs and prices, Shop stock size and prices, King's Throne and Thorned Forest Regional Encounters, Ghost and Zombie pieces, Deadman Walking and Dangerous Payload failure penalties and rewards, how often Treasure Hunts find Artifacts, Silver amounts (placeholders), whether Elite Expedition needs unlocking, whether Rest heals the Fallen Knight (currently the same 70%)
- Exact ranges/arcs for Double Barrel and Long Barrel
- Duel reward amounts and ranked play; whether bolas should skip 3 King turns or fewer
- Duels with two Outlaws show only the most recent smoke cloud on each screen
- Skins: Legendary (animated) board design, Mythical rarity and how much featured skins boost crate rates, gun and piece skin designs

## Prototype Test Setup

- Five black dummy pieces (Pawn E3, Knight G3, Bishop C4, Rook I4, Queen F5) with their normal health. They don't act. Configured in `MatchConfig.TEST_DUMMIES`.
