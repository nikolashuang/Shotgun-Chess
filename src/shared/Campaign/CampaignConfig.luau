local CampaignMap = require(script.Parent.CampaignMap)

local CampaignConfig = {
    -- Bottom to top on the world map
    ORDER = {"Training", "Forest", "Cliffside", "Outskirts", "Gravehollow"},

    -- Replaying a region that was already completed pays this fraction of its pouch
    REPLAY_REWARD_SCALE = 0.2,

    -- Base rewards per node type, multiplied by the region's RewardScale and collected in the run's pouch
    -- A node's own Reward table replaces the base reward; Treasure gold comes from Treasure.Rewards instead
    Rewards = {
        Combat = {Gold = 100, Exp = 50},
        Treasure = {Gold = 0, Exp = 20},
        Rest = {Gold = 0, Exp = 20},
        Mystery = {Gold = 0, Exp = 25},
        Queen = {Gold = 400, Exp = 200},
        King = {Gold = 750, Exp = 350},
    },

    TypeNames = {
        Combat = "Battle",
        Treasure = "Treasure Hunt",
        Rest = "Rest Site",
        Mystery = "Mystery",
        Queen = "Queen Fight",
        King = "Boss Fight",
    },

    -- Enemy AI rating for every campaign battle (a key of AIConfig.Ratings); elite scaling comes later
    AI_RATING = 1000,

    -- Enemy armies are rolled from a point budget every battle
    Encounter = {
        Points = {Pawn = 1, Knight = 3, Bishop = 3, Rook = 5, Queen = 9},
        -- Picked at random to spend the budget before pawns fill what's left
        MAJORS = {"Rook", "Knight", "Bishop"},

        -- Each normal battle along a route adds this to the region's StartPoints
        POINTS_PER_FIGHT = 3,
        -- Queen battle = last normal battle + QUEEN_BONUS, King battle = Queen battle + KING_BONUS
        QUEEN_BONUS = 9,
        KING_BONUS = 6,

        RESERVED_PAWNS = 2,
        MAX_PAWNS = 12,

        -- Enemies spawn on rows FIRST_ROW to the back row; 12 pawns form a wall on FIRST_ROW
        FIRST_ROW = 9,
        QUEEN_TILE = {6, 12},
        KING_TILE = {7, 12},
    },

    Rest = {
        TRAIN_HEALTH = 2,
        -- Added to every shotgun hit, fall-off damage included
        MAINTENANCE_DAMAGE = 1,
    },

    Treasure = {
        DIGS = 5,
        -- Each dig uncovers a DIG_SIZE x DIG_SIZE square centered on the picked tile
        DIG_SIZE = 3,
        -- Gold for finding the treasure on dig 1, 2, 3...
        Rewards = {200, 175, 150, 125, 100},
        CONSOLATION = 25,
    },

    -- Mystery nodes roll one of these on arrival (never the same one twice in a row)
    Mystery = {
        ENCOUNTERS = {"Gunsmith", "FallenKnight", "Ambush", "Altar"},

        -- Costs come out of the run's pouch; damage goes on every shotgun hit, fall-off included
        Gunsmith = {UPGRADE_COST = 50, UPGRADE_DAMAGE = 1, GAMBLE_COST = 25, GAMBLE_DAMAGE = 1},

        -- Taking the hit is locked at DAMAGE health or less; fighting rolls an army from the region's points
        Ambush = {
            DAMAGE = 3,
            Points = {Training = 6, Forest = 7, Cliffside = 8, Outskirts = 8, Gravehollow = 9, Dev = 6},
        },

        -- Each offering needs more health than it costs
        Altar = {BLOOD_COST = 4, BLOOD_HEALTH = 2, ROYAL_COST = 6, ROYAL_DAMAGE = 2},

        -- The Knight waits alone on his throne tile; beat him and he joins the run
        -- Three Fallen Pawns guard the steps in front of his throne
        FallenKnight = {TILE = {6, 12}, PAWN_TILES = {{5, 11}, {6, 11}, {7, 11}}},
    },

    -- The Fallen Knight companion starts each battle this many columns right of the King
    COMPANION_OFFSET = 1,

    -- Requires lists regions that must be completed first; completing a region means beating its King
    -- Nodes are built from Map by CampaignMap: Lanes across, Seed picks the layout (changing it reshuffles the map)
    -- StartPoints is the first battle's point budget
    Regions = {
        Training = {
            DisplayName = "King's Training",
            Subtitle = "Tutorial / Practice Grounds",
            Requires = {},
            RewardScale = 0.5,
            StartPoints = 6,
            Start = "Start",
            Final = "King",
            Map = {Lanes = 3, Seed = 11},
        },

        Forest = {
            DisplayName = "Hunter Forest",
            Subtitle = "Hunter King",
            Requires = {"Training"},
            Class = "Hunter",
            RewardScale = 1,
            StartPoints = 8,
            Start = "Start",
            Final = "King",
            Map = {Lanes = 4, Seed = 23},
        },

        Cliffside = {
            DisplayName = "Cliffside",
            Subtitle = "Outlaw King",
            Requires = {"Forest"},
            Class = "Outlaw",
            RewardScale = 1.5,
            StartPoints = 10,
            Start = "Start",
            Final = "King",
            Map = {Lanes = 4, Seed = 37},
        },

        Outskirts = {
            DisplayName = "Outskirts",
            Subtitle = "Gunslinger King",
            Requires = {"Cliffside"},
            Class = "Gunslinger",
            RewardScale = 2,
            StartPoints = 12,
            Start = "Start",
            Final = "King",
            Map = {Lanes = 4, Seed = 41},
        },

        Gravehollow = {
            DisplayName = "Gravehollow",
            Subtitle = "Reaper King",
            Requires = {"Outskirts"},
            Class = "Reaper",
            RewardScale = 2.5,
            StartPoints = 14,
            Start = "Start",
            Final = "King",
            Map = {Lanes = 4, Seed = 53},
        },

        -- Developer testing ground, left out of ORDER so it never shows on the world map
        -- Every node stays open, each Mystery node is pinned to one encounter, and finishing it pays nothing
        Dev = {
            DisplayName = "Dev Campaign",
            Subtitle = "Developers only: every node stays open",
            Requires = {},
            DevOnly = true,
            AllNodesOpen = true,
            RewardScale = 1,
            StartPoints = 6,
            Start = "Start",
            Final = "King",
            Nodes = {
                Start = {Type = "Combat", Fight = 1, Position = {0.06, 0.5}, Links = {"Battle", "Rest", "Treasure", "Gunsmith", "FallenKnight", "Ambush", "Altar"}},
                Battle = {Type = "Combat", Fight = 6, Position = {0.24, 0.2}, Links = {"Queen"}},
                Rest = {Type = "Rest", Position = {0.24, 0.5}, Links = {"Queen"}},
                Treasure = {Type = "Treasure", Position = {0.24, 0.8}, Links = {"Queen"}},
                Gunsmith = {Type = "Mystery", Encounter = "Gunsmith", Position = {0.48, 0.17}, Links = {"Queen"}},
                FallenKnight = {Type = "Mystery", Encounter = "FallenKnight", Position = {0.48, 0.39}, Links = {"Queen"}},
                Ambush = {Type = "Mystery", Encounter = "Ambush", Position = {0.48, 0.61}, Links = {"Queen"}},
                Altar = {Type = "Mystery", Encounter = "Altar", Position = {0.48, 0.83}, Links = {"Queen"}},
                Queen = {Type = "Queen", Position = {0.72, 0.5}, Links = {"King"}},
                King = {Type = "King", Position = {0.9, 0.5}, Links = {}},
            },
        },
    },
}

for _, region in pairs(CampaignConfig.Regions) do
    region.Nodes = region.Nodes or CampaignMap.Build(region.Map)
end

return CampaignConfig
