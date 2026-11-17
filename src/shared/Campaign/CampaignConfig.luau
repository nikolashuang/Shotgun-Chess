local CampaignMap = require(script.Parent.CampaignMap)

local CampaignConfig = {
    -- Bottom to top on the world map
    ORDER = {"Training", "Forest", "Cliffside", "Outskirts", "Gravehollow"},

    -- First clears pay the full reward, replays pay this fraction of it
    REPLAY_REWARD_SCALE = 0.2,

    -- Base rewards per node type, multiplied by the region's RewardScale
    -- A node's own Reward table replaces the base reward
    Rewards = {
        Combat = {Gold = 100, Exp = 50},
        Treasure = {Gold = 150, Exp = 25},
        Rest = {Gold = 0, Exp = 0},
        Queen = {Gold = 400, Exp = 200},
        King = {Gold = 750, Exp = 350},
    },

    TypeNames = {
        Combat = "Battle",
        Treasure = "Treasure Hunt",
        Rest = "Rest Site",
        Queen = "Queen Fight",
        King = "Boss Fight",
    },

    -- Armies are pushed toward the far end so their closest piece starts on this row
    ARMY_FRONT_ROW = 8,

    -- Placeholder enemy layouts (black pieces) until encounters are designed
    -- An army with a King is won by killing the King, otherwise by clearing the board
    Armies = {
        TutorialPawns = {
            {Type = "Pawn", Column = 5, Row = 4},
            {Type = "Pawn", Column = 7, Row = 4},
        },

        TutorialMixed = {
            {Type = "Pawn", Column = 5, Row = 3},
            {Type = "Knight", Column = 7, Row = 3},
            {Type = "Bishop", Column = 3, Row = 4},
            {Type = "Rook", Column = 9, Row = 4},
        },

        TutorialQueen = {
            {Type = "Pawn", Column = 5, Row = 5},
            {Type = "Pawn", Column = 7, Row = 5},
            {Type = "Queen", Column = 6, Row = 7},
        },

        TutorialKing = {
            {Type = "Pawn", Column = 5, Row = 5},
            {Type = "Pawn", Column = 7, Row = 5},
            {Type = "Knight", Column = 4, Row = 7},
            {Type = "King", Column = 6, Row = 8},
        },

        Patrol = {
            {Type = "Pawn", Column = 4, Row = 4},
            {Type = "Pawn", Column = 6, Row = 5},
            {Type = "Pawn", Column = 8, Row = 4},
            {Type = "Knight", Column = 6, Row = 7},
        },

        Skirmish = {
            {Type = "Pawn", Column = 5, Row = 4},
            {Type = "Pawn", Column = 7, Row = 4},
            {Type = "Bishop", Column = 3, Row = 6},
            {Type = "Bishop", Column = 9, Row = 6},
        },

        Warband = {
            {Type = "Pawn", Column = 5, Row = 4},
            {Type = "Pawn", Column = 7, Row = 4},
            {Type = "Knight", Column = 4, Row = 6},
            {Type = "Knight", Column = 8, Row = 6},
            {Type = "Rook", Column = 6, Row = 8},
        },

        QueenGuard = {
            {Type = "Pawn", Column = 5, Row = 5},
            {Type = "Pawn", Column = 7, Row = 5},
            {Type = "Rook", Column = 3, Row = 7},
            {Type = "Rook", Column = 9, Row = 7},
            {Type = "Queen", Column = 6, Row = 8},
        },

        KingGuard = {
            {Type = "Pawn", Column = 4, Row = 5},
            {Type = "Pawn", Column = 6, Row = 5},
            {Type = "Pawn", Column = 8, Row = 5},
            {Type = "Knight", Column = 5, Row = 7},
            {Type = "Bishop", Column = 7, Row = 7},
            {Type = "Rook", Column = 3, Row = 9},
            {Type = "Rook", Column = 9, Row = 9},
            {Type = "King", Column = 6, Row = 10},
        },
    },

    -- Requires lists regions that must be completed first; completing a region means beating its King
    -- Nodes are built from Map by CampaignMap: Lanes across, Seed picks the layout (changing it reshuffles saved progress)
    -- Armies lists the army for each fight column, Start first
    Regions = {
        Training = {
            DisplayName = "King's Training",
            Subtitle = "Tutorial / Practice Grounds",
            Requires = {},
            RewardScale = 0.5,
            Start = "Start",
            Final = "King",

            Map = {
                Lanes = 3,
                Seed = 11,
                Armies = {"TutorialPawns", "TutorialPawns", "TutorialPawns", "TutorialMixed", "TutorialMixed", "Patrol"},
                QueenArmy = "TutorialQueen",
                KingArmy = "TutorialKing",
            },
        },

        Forest = {
            DisplayName = "Hunter Forest",
            Subtitle = "Hunter King",
            Requires = {"Training"},
            Class = "Hunter",
            RewardScale = 1,
            Start = "Start",
            Final = "King",

            Map = {
                Lanes = 4,
                Seed = 23,
                Armies = {"Patrol", "Patrol", "Patrol", "Skirmish", "Skirmish", "Warband"},
                QueenArmy = "QueenGuard",
                KingArmy = "KingGuard",
            },
        },

        Cliffside = {
            DisplayName = "Cliffside",
            Subtitle = "Outlaw King",
            Requires = {"Forest"},
            Class = "Outlaw",
            RewardScale = 1.5,
            Start = "Start",
            Final = "King",

            Map = {
                Lanes = 4,
                Seed = 37,
                Armies = {"Patrol", "Skirmish", "Skirmish", "Warband", "Warband", "Warband"},
                QueenArmy = "QueenGuard",
                KingArmy = "KingGuard",
            },
        },

        Outskirts = {
            DisplayName = "Outskirts",
            Subtitle = "Gunslinger King",
            Requires = {"Cliffside"},
            Class = "Gunslinger",
            RewardScale = 2,
            Start = "Start",
            Final = "King",

            Map = {
                Lanes = 4,
                Seed = 41,
                Armies = {"Skirmish", "Skirmish", "Warband", "Warband", "Warband", "QueenGuard"},
                QueenArmy = "QueenGuard",
                KingArmy = "KingGuard",
            },
        },

        Gravehollow = {
            DisplayName = "Gravehollow",
            Subtitle = "Reaper King",
            Requires = {"Outskirts"},
            Class = "Reaper",
            RewardScale = 2.5,
            Start = "Start",
            Final = "King",

            Map = {
                Lanes = 4,
                Seed = 53,
                Armies = {"Warband", "Warband", "Warband", "QueenGuard", "QueenGuard", "QueenGuard"},
                QueenArmy = "QueenGuard",
                KingArmy = "KingGuard",
            },
        },
    },
}

for _, region in pairs(CampaignConfig.Regions) do
    region.Nodes = CampaignMap.Build(region.Map)
end

return CampaignConfig
