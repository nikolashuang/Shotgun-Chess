-- Expedition: a replayable three-Act run. One region is rolled from each Act's pool when the run starts
local ExpeditionConfig = {
    MODES = {"Normal", "Elite"},

    Acts = {
        {Pool = {"KingsThrone", "Overgrowth"}, StartPoints = 6},
        {Pool = {"Cliffside", "Outskirts"}, StartPoints = 12},
        {Pool = {"Gravehollow"}, StartPoints = 18},
    },

    Elite = {
        -- Added to every Act's starting point allocation
        START_POINTS_BONUS = 5,
    },

    --MAP--

    -- A full grid like the old Campaign map: WIDTH lanes, a node on every layer of each (40 nodes plus the Boss)
    Map = {
        LAYERS = 10,
        WIDTH = 4,
        -- Chance a node also links into a neighboring lane, and that the branch replaces its straight link
        BRANCH_CHANCE = 0.4,
        MERGE_CHANCE = 0.35,
        -- At least this many links cross between the two middle lanes, so the map never splits down the middle
        MIN_CENTER_LINKS = 3,

        -- Generation weights, not guaranteed counts; the first layer is always Battle and the Boss is added on top
        Weights = {
            Battle = 25,
            -- Includes the 20% that was Regional: Regional Encounters are rolled from the Mystery pool
            Mystery = 45,
            Elite = 15,
            Shop = 10,
            Rest = 5,
        },

        -- Never back to back with the same type along a path
        NO_REPEAT = {Rest = true, Elite = true},
        -- Every Act gets at least one of each
        REQUIRED = {"Rest", "Shop"},
    },

    TypeNames = {
        Battle = "Battle",
        Elite = "Elite Battle",
        Boss = "Boss Battle",
        Mystery = "Mystery",
        Shop = "Shop",
        Rest = "Rest Site",
    },

    --REWARDS--

    -- Gold and XP go in the pouch and are paid out when Act III is beaten; Silver is spent during the run
    Rewards = {
        Battle = {Gold = 100, Exp = 50, Silver = 15},
        Elite = {Gold = 200, Exp = 100, Silver = 30},
        Boss = {Gold = 500, Exp = 250, Silver = 50},
        -- Fights started by Mystery encounters
        EncounterFight = {Gold = 100, Exp = 50, Silver = 10},
        Encounter = {Gold = 0, Exp = 25, Silver = 0},
        Rest = {Gold = 0, Exp = 20, Silver = 0},
        Shop = {Gold = 0, Exp = 0, Silver = 0},
    },
    -- Pouch Gold and XP multiplied by the Act it was earned in, 1x / 1.5x / 2x
    ACT_REWARD_SCALE = {1, 1.5, 2},

    --ENEMIES--

    Enemies = {
        Points = {Pawn = 1, Knight = 3, Bishop = 3, Rook = 5, Queen = 9, King = 0, Necromancer = 7},

        ELITE_BONUS = 6,
        BOSS_BONUS = 12,
        -- Winning a Normal or Elite Battle raises the allocation; encounter fights don't
        POINTS_PER_BATTLE = 3,

        RESERVED_PAWNS = 2,
        MAX_PAWNS = 5,
        -- Rooks are picked more often as the budget grows: weight 1 + points / ROOK_PRIORITY_POINTS
        ROOK_PRIORITY_POINTS = 12,

        -- Enemies spawn from FIRST_ROW to the back row
        FIRST_ROW = 7,
        QUEEN_TILE = {5, 10},
        KING_TILE = {6, 10},

        -- Most of a unique piece one encounter can field
        MaxCount = {Queen = 1, Necromancer = 2},
    },

    -- Enemies get stronger every Act; Act I uses the base stats
    Scaling = {
        -- Compounded per Act from the base, rounded up
        HEALTH_PER_ACT = 0.25,
        DamagePerAct = {Pawn = 1, Knight = 2, Bishop = 2, Rook = 2, Queen = 2, King = 0},
        -- Variants with their own stats are never scaled
        FIXED = {Necromancer = true, FallenKnight = true},
    },

    -- Enemy AI rating for every Expedition battle (a key of AIConfig.Ratings)
    AI_RATING = 1000,

    --UPGRADES--

    Rest = {
        -- Share of missing health restored
        HEAL_MISSING = 0.7,
        AMMO = 1,
        -- The Double Barrel gets this instead of AMMO
        AmmoByShotgun = {DoubleBarrel = 2},
    },

    Artifacts = {
        MAX = 5,
        -- Artifact designs and prices are still to be made; name -> {DisplayName, Description, Price}
        Pool = {},
    },

    Shop = {
        INVENTORY_SIZE = 3,
    },

    -- Mystery encounters, rolled on entry and never the same one twice in a row
    -- The current region's Regional Encounters join this pool, each at most once per run
    Mystery = {
        ENCOUNTERS = {"Gunsmith", "Ambush", "Altar", "Treasure", "Barracks", "Doctor", "HolyRook", "Gambler"},

        Gunsmith = {COST = 50, DAMAGE = 1},
        Ambush = {
            DAMAGE = 3,
            KING_TILE = {5, 5},
            RING_MIN = 2,
            RING_MAX = 3,
        },
        Altar = {BLOOD_COST = 4, BLOOD_HEALTH = 2, ROYAL_COST = 6, ROYAL_DAMAGE = 2},
        Treasure = {
            SIZE = 12,
            DIGS = 5,
            DIG_SIZE = 3,
            -- Silver for finding it on dig 1, 2, 3...
            Rewards = {60, 50, 40, 30, 20},
            CONSOLATION = 5,
        },
        Barracks = {HEALTH = 1, DAMAGE = 1},
        Doctor = {VITALITY = 2},
        HolyRook = {POWER_CHARGE = 25, POWER_HEALTH = 2, VITALITY_HEAL = 2, VITALITY_ENERGY = 1},
        Gambler = {WAGERS = {25, 50, 100}, WIN_CHANCE = 0.5},
    },

    --REGIONS--

    -- Exclusives are the region's Regional Encounters: Mysteries that can only roll in that region
    -- Enabled = false keeps an encounter out of the pool until its content is designed
    Exclusives = {
        DeadmanWalking = {Region = "Cliffside", Enabled = false},
        DangerousPayload = {Region = "Outskirts", Enabled = false},
        FallenKnight = {
            Region = "Gravehollow",
            Enabled = true,
            -- He takes a Knight's share of the allocation; the rest buys his supporting army
            POINTS = 3,
            TILE = {5, 10},
            ArmyBonus = {Health = 2, Damage = 1},
            -- No Kings or Queens in his army
            POOL = {"Pawn", "Knight", "Bishop", "Rook"},
        },
        HauntedMansion = {Region = "Gravehollow", Enabled = false},
    },

    -- AIWeights multiply the enemy AI's directive weights; Risk scales how much pieces fear losing health
    Regions = {
        KingsThrone = {
            DisplayName = "King's Throne",
            Act = 1,
            BossClass = "Monarch",
            EnemyPool = {"Pawn", "Knight", "Bishop", "Rook"},
            Exclusives = {},
            AIWeights = {Defend = 1.3, Teamwork = 1.15, Attack = 0.9},
            Risk = 1.25,
        },

        Overgrowth = {
            DisplayName = "Thorned Forest",
            Act = 1,
            BossClass = "Hunter",
            EnemyPool = {"Pawn", "Knight", "Bishop", "Rook"},
            Exclusives = {},
            AIWeights = {Position = 1.4, Teamwork = 1.4},
            Risk = 1,
        },

        Cliffside = {
            DisplayName = "Cliffside",
            Act = 2,
            BossClass = "Outlaw",
            EnemyPool = {"Pawn", "Knight", "Bishop", "Rook"},
            Exclusives = {"DeadmanWalking"},
            AIWeights = {Position = 1.5, Advance = 1.2, Attack = 0.9},
            Risk = 1,
        },

        Outskirts = {
            DisplayName = "Outskirts",
            Act = 2,
            BossClass = "Gunslinger",
            EnemyPool = {"Pawn", "Knight", "Bishop", "Rook"},
            Exclusives = {"DangerousPayload"},
            AIWeights = {Attack = 1.4, Evade = 0.7, Defend = 0.8},
            Risk = 0.7,
        },

        Gravehollow = {
            DisplayName = "Gravehollow",
            Act = 3,
            BossClass = "Reaper",
            EnemyPool = {"Pawn", "Knight", "Bishop", "Rook", "Necromancer"},
            Exclusives = {"FallenKnight", "HauntedMansion"},
            AIWeights = {Defend = 1.2, Attack = 1.1},
            Risk = 0.85,
        },
    },

    -- The Fallen Knight companion starts each battle this many columns right of the King
    COMPANION_OFFSET = 1,
}

return ExpeditionConfig
