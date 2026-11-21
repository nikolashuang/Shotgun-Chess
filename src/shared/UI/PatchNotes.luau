-- Game version shown in the corner of every screen, and the patch notes on the main menu
-- One release per day: bump the last number each day, and the middle one (resetting the last) only for a huge update
local PatchNotes = {
    VERSION = "0.4.1",

    -- Newest first
    Releases = {
        {
            Version = "0.4.1",
            Date = "Nov 21",
            Title = "Mystery Encounters",
            Notes = {
                "New Mystery nodes on every region map. One road is full of them, one is all battles, the rest mix both.",
                "Wandering Gunsmith: pay from your pouch to upgrade your shotgun, or gamble on it.",
                "Fallen Knight: beat him and he fights beside you for the rest of the run. He moves like a King and a Knight, acts on his own, and keeps his wounds between battles.",
                "Ambush: take the hit or fight your way out.",
                "Queen's Altar: trade health for max health or shotgun damage.",
                "Rest Sites now have their own screen: your King rests by a campfire with his party, or with the Fallen Knight once he joins, and you pick Rest, Train or Upgrade Shotgun from illustrated cards.",
                "Leaving in the middle of a region now saves your run exactly where you were.",
                "Rest Sites, Treasure Hunts and Mystery encounters now give XP too.",
            },
        },
        {
            Version = "0.4.0",
            Date = "Nov 20",
            Title = "Campaign Rework",
            Notes = {
                "Each region is now a run: health carries over between battles and routes only move forward.",
                "Rest Sites are checkpoints. Pick Rest (full heal), Train (+2 max health) or Gun Maintenance (+1 shotgun damage).",
                "Dying sends you back to your last Rest Site. With none reached, the region starts over.",
                "Enemy armies are rolled fresh every battle from a point budget that grows through the region.",
                "Treasure Hunt: dig a 12x12 board with 5 digs. Find the treasure early for more gold.",
                "Gold and XP collect in a pouch, shown on the run map, and pay out when you beat the region's King. Completed regions can be replayed for reduced rewards.",
                "Gunslinger: Deadly Rounds now loses 2 damage for every enemy a blast passes through (was 0.5).",
                "Menu and Settings buttons now sit in the same spot at the bottom right of every screen.",
                "The Armory and Shop show your player card. Campaign, Singleplayer and Multiplayer no longer show level and gold.",
                "New Armory drawings for Deadly Rounds and Fan the Hammer.",
                "Added these patch notes and the game version in the corner of the screen.",
            },
        },
        {
            Version = "0.3.0",
            Date = "Nov 19",
            Title = "Multiplayer",
            Notes = {
                "Duels unlock at level 10: quick-match Queue or Challenge a player directly. Both sides start with only their King.",
                "Each player has a 5-minute chess clock. Kill the rival King or run out their clock to win. Leaving forfeits.",
                "Hunting Strike bolas stun the rival King. A stunned King skips its whole turn and is clearly told so. The rival King shows the shotgun it's using.",
                "Practice: duel an AI from the Singleplayer screen, choosing its rating (500-2500), shotgun and class.",
                "New Game Speed setting: Fast speeds up enemy and ally animations, never the enemy's thinking time.",
                "Keybinds now save between sessions.",
                "Reaper: souls drop from any piece that dies, allies included. Assimilate is a bonus move you can use after moving. A rival Reaper's souls burn red.",
                "Hunter: Hunting Strike uses the Pump's 3-tile cone.",
                "Gunslinger: new passive Deadly Rounds. Shots pass through everything, losing damage for each enemy passed. Deadeye removed.",
                "Outlaw: Conceal lasts 1 turn. Shots into smoke hit half the time; enemy pieces still can't attack into it.",
                "Double Barrel holds one shot (2 shells). Long Barrel deals 5 up close down to 1 at max range. Knife Shotty slashes for 5 plus 3 turns of bleed.",
                "End Turn moved below the board; its old spot now shows your King's health.",
            },
        },
        {
            Version = "0.2.0",
            Date = "Nov 18",
            Title = "Classes and New Menus",
            Notes = {
                "The Reaper, Hunter, Gunslinger and Outlaw classes now have their passives, abilities and ultimates.",
                "Buck Barrel knocks enemies back a tile. Long Barrel range lowered to 4.",
                "Fixed how bear traps work and redrew the bear trap.",
                "Enemy Kings carry a Pump shotgun, enemy pieces attack using chess capture rules, and every Boss Fight fields a Queen.",
                "Campaign is now on the Singleplayer screen, next to Siege (coming soon).",
                "The Armory and Shop have their own pages, with a drawing for every class ability.",
                "Settings is an overlay you can open from anywhere, with a new CRT filter. Settings now save.",
                "In matches, the Menu button lets you resume, open Settings or go back to the menu.",
                "The Campaign opens its own world map of floating islands, starting at King's Training.",
                "Every choice on the board has a border, Command shows which pieces you can pick, and health bars show a tick per point of health.",
                "Main menu buttons open a gold ribbon on hover. Summoning a Queen now costs 6 energy.",
            },
        },
        {
            Version = "0.1.1",
            Date = "Nov 17",
            Title = "Enemy AI and Energy",
            Notes = {
                "Enemies now think for themselves: they defend their King, dodge your shots, close off your escape and work together.",
                "Turns now run on energy: shooting, commanding and reloading cost 1, specials 2, and summons the piece's cost. Ultimates are free once charged.",
                "New Knight art and updated in-match and campaign screens.",
                "Main menu refresh.",
            },
        },
        {
            Version = "0.1.0",
            Date = "Nov 16",
            Title = "First Playable",
            Notes = {
                "Main menu, a King that moves one tile in any direction, and the first sprites.",
                "Summon pieces next to your King and command them to move and attack.",
                "Added 5 shotguns: Pump, Double Barrel, Buck Barrel, Long Barrel and Knife Shotty, with magazines and reloading.",
                "The Reaper, Hunter, Gunslinger and Outlaw classes can be picked in the Armory.",
                "Added the campaign: King's Training, Hunter Forest, Cliffside, Outskirts and Gravehollow, with area maps drawn on parchment.",
                "Battles pay Gold and XP, and shotguns are bought with Gold in the Shop.",
                "Keybinds can be changed in Settings, and matches have a Leave option.",
                "Warmer color palette and a new menu title.",
            },
        },
    },
}

return PatchNotes
