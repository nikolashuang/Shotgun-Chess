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

    -- Positions are scale coordinates inside the area map
    -- Requires lists regions that must be completed first; completing a region means beating its King
    -- Every region ends Queen -> King, and nothing else may link to the King
    -- Battle nodes (Combat, Queen, King) need an Army; Rest and Treasure nodes resolve without a fight
    Regions = {
        Training = {
            DisplayName = "King's Training",
            Subtitle = "Tutorial / Practice Grounds",
            Requires = {},
            RewardScale = 0.5,
            Start = "Gate",
            Final = "King",

            Nodes = {
                Gate = {Type = "Combat", Army = "TutorialPawns", Position = {0.06, 0.5}, Links = {"Yard"}},
                Yard = {Type = "Combat", Army = "TutorialPawns", Position = {0.16, 0.5}, Links = {"Armory", "Targets"}},
                Armory = {Type = "Treasure", Position = {0.27, 0.25}, Links = {"Board"}},
                Targets = {Type = "Combat", Army = "TutorialMixed", Position = {0.27, 0.75}, Links = {"Board"}},
                Board = {Type = "Combat", Army = "TutorialMixed", Position = {0.38, 0.5}, Links = {"Barracks"}},
                Barracks = {Type = "Rest", Position = {0.49, 0.5}, Links = {"Dummies", "Banners"}},
                Dummies = {Type = "Combat", Army = "Patrol", Position = {0.6, 0.27}, Links = {"Drill"}},
                Banners = {Type = "Combat", Army = "Patrol", Position = {0.6, 0.73}, Links = {"Drill"}},
                Drill = {Type = "Combat", Army = "Skirmish", Position = {0.71, 0.5}, Links = {"Queen"}},
                Queen = {Type = "Queen", Army = "TutorialQueen", Position = {0.82, 0.5}, Links = {"King"}},
                King = {Type = "King", Army = "TutorialKing", Position = {0.93, 0.5}, Links = {}},
            },
        },

        Forest = {
            DisplayName = "Hunter Forest",
            Subtitle = "Hunter King",
            Requires = {"Training"},
            Class = "Hunter",
            RewardScale = 1,
            Start = "Edge",
            Final = "King",

            Nodes = {
                Edge = {Type = "Combat", Army = "Patrol", Position = {0.05, 0.5}, Links = {"Trail", "Thicket"}},
                Trail = {Type = "Combat", Army = "Patrol", Position = {0.16, 0.25}, Links = {"Cache"}},
                Thicket = {Type = "Combat", Army = "Skirmish", Position = {0.16, 0.75}, Links = {"Camp"}},
                Cache = {Type = "Treasure", Position = {0.28, 0.18}, Links = {"Ridge"}},
                Camp = {Type = "Rest", Position = {0.28, 0.82}, Links = {"Hollow"}},
                Ridge = {Type = "Combat", Army = "Skirmish", Position = {0.4, 0.25}, Links = {"Den"}},
                Hollow = {Type = "Combat", Army = "Skirmish", Position = {0.4, 0.75}, Links = {"Den"}},
                Den = {Type = "Combat", Army = "Warband", Position = {0.52, 0.5}, Links = {"Falls", "Bridge"}},
                Falls = {Type = "Rest", Position = {0.65, 0.27}, Links = {"Queen"}},
                Bridge = {Type = "Combat", Army = "Warband", Position = {0.65, 0.73}, Links = {"Queen"}},
                Queen = {Type = "Queen", Army = "QueenGuard", Position = {0.8, 0.5}, Links = {"King"}},
                King = {Type = "King", Army = "KingGuard", Position = {0.93, 0.5}, Links = {}},
            },
        },

        Cliffside = {
            DisplayName = "Cliffside",
            Subtitle = "Outlaw King",
            Requires = {"Forest"},
            Class = "Outlaw",
            RewardScale = 1.5,
            Start = "Pass",
            Final = "King",

            Nodes = {
                Pass = {Type = "Combat", Army = "Patrol", Position = {0.05, 0.5}, Links = {"Ledge"}},
                Ledge = {Type = "Combat", Army = "Skirmish", Position = {0.15, 0.5}, Links = {"Rope", "Mine", "Ravine"}},
                Rope = {Type = "Combat", Army = "Skirmish", Position = {0.27, 0.2}, Links = {"Lookout"}},
                Mine = {Type = "Treasure", Position = {0.27, 0.5}, Links = {"Lookout", "Shack"}},
                Ravine = {Type = "Combat", Army = "Warband", Position = {0.27, 0.8}, Links = {"Shack"}},
                Lookout = {Type = "Combat", Army = "Warband", Position = {0.4, 0.27}, Links = {"Waterfall"}},
                Shack = {Type = "Combat", Army = "Warband", Position = {0.4, 0.73}, Links = {"Waterfall", "Hideout"}},
                Waterfall = {Type = "Rest", Position = {0.53, 0.35}, Links = {"Summit"}},
                Hideout = {Type = "Treasure", Position = {0.53, 0.78}, Links = {"Summit"}},
                Summit = {Type = "Combat", Army = "Warband", Position = {0.66, 0.5}, Links = {"Queen"}},
                Queen = {Type = "Queen", Army = "QueenGuard", Position = {0.8, 0.5}, Links = {"King"}},
                King = {Type = "King", Army = "KingGuard", Position = {0.93, 0.5}, Links = {}},
            },
        },

        Outskirts = {
            DisplayName = "Outskirts",
            Subtitle = "Gunslinger King",
            Requires = {"Cliffside"},
            Class = "Gunslinger",
            RewardScale = 2,
            Start = "Road",
            Final = "King",

            Nodes = {
                Road = {Type = "Combat", Army = "Skirmish", Position = {0.05, 0.5}, Links = {"Windmill", "Fence"}},
                Windmill = {Type = "Combat", Army = "Skirmish", Position = {0.15, 0.28}, Links = {"Tower", "Saloon"}},
                Fence = {Type = "Combat", Army = "Patrol", Position = {0.15, 0.72}, Links = {"Saloon", "Stables"}},
                Tower = {Type = "Treasure", Position = {0.27, 0.15}, Links = {"Street"}},
                Saloon = {Type = "Rest", Position = {0.28, 0.5}, Links = {"Street", "Corral"}},
                Stables = {Type = "Combat", Army = "Warband", Position = {0.27, 0.85}, Links = {"Corral"}},
                Street = {Type = "Combat", Army = "Warband", Position = {0.41, 0.27}, Links = {"Bank"}},
                Corral = {Type = "Combat", Army = "Warband", Position = {0.41, 0.73}, Links = {"Gallows"}},
                Bank = {Type = "Treasure", Position = {0.54, 0.25}, Links = {"Sheriff"}},
                Gallows = {Type = "Combat", Army = "Warband", Position = {0.54, 0.75}, Links = {"Sheriff"}},
                Sheriff = {Type = "Combat", Army = "QueenGuard", Position = {0.67, 0.5}, Links = {"Queen"}},
                Queen = {Type = "Queen", Army = "QueenGuard", Position = {0.8, 0.5}, Links = {"King"}},
                King = {Type = "King", Army = "KingGuard", Position = {0.93, 0.5}, Links = {}},
            },
        },

        Gravehollow = {
            DisplayName = "Gravehollow",
            Subtitle = "Reaper King",
            Requires = {"Outskirts"},
            Class = "Reaper",
            RewardScale = 2.5,
            Start = "Gate",
            Final = "King",

            Nodes = {
                Gate = {Type = "Combat", Army = "Warband", Position = {0.05, 0.5}, Links = {"Graves"}},
                Graves = {Type = "Combat", Army = "Warband", Position = {0.15, 0.5}, Links = {"Crypt", "Statue"}},
                Crypt = {Type = "Combat", Army = "Warband", Position = {0.27, 0.22}, Links = {"Ossuary", "Chapel"}},
                Statue = {Type = "Treasure", Position = {0.27, 0.78}, Links = {"Chapel", "Mausoleum"}},
                Ossuary = {Type = "Combat", Army = "QueenGuard", Position = {0.4, 0.15}, Links = {"Bells"}},
                Chapel = {Type = "Rest", Position = {0.41, 0.5}, Links = {"Bells", "Fog"}},
                Mausoleum = {Type = "Combat", Army = "Warband", Position = {0.4, 0.85}, Links = {"Fog"}},
                Bells = {Type = "Combat", Army = "QueenGuard", Position = {0.54, 0.27}, Links = {"Steps"}},
                Fog = {Type = "Treasure", Position = {0.54, 0.73}, Links = {"Steps"}},
                Steps = {Type = "Combat", Army = "QueenGuard", Position = {0.67, 0.5}, Links = {"Queen"}},
                Queen = {Type = "Queen", Army = "QueenGuard", Position = {0.8, 0.5}, Links = {"King"}},
                King = {Type = "King", Army = "KingGuard", Position = {0.93, 0.5}, Links = {}},
            },
        },
    },
}

return CampaignConfig
