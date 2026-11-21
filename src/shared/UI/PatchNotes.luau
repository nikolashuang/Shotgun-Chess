-- Game version shown in the corner of every screen, and the patch notes on the main menu
local PatchNotes = {
    VERSION = "0.1.0",

    -- Newest first
    Releases = {
        {
            Version = "0.1.0",
            Title = "Campaign Rework",
            Notes = {
                "Each region is now a run: health carries over between battles and routes only move forward.",
                "Rest Sites are checkpoints. Pick Rest (full heal), Train (+2 max health) or Gun Maintenance (+1 shotgun damage).",
                "Dying sends you back to your last Rest Site. With none reached, the region starts over.",
                "Enemy armies are rolled fresh every battle from a point budget that grows through the region.",
                "Treasure Hunt: dig a 12x12 board with 5 digs. Find the treasure early for more gold.",
                "Gold and XP collect in a pouch and pay out when you beat the region's King.",
                "Menu and Settings buttons now sit at the bottom right of every screen.",
                "The Armory and Shop show your player card.",
            },
        },
    },
}

return PatchNotes
