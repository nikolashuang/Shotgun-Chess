-- Expedition: a replayable three-Act run. One region is rolled from each Act's pool when the run starts
local ExpeditionConfig = {
    MODES = {"Normal", "Elite"},

    Acts = {
        {Pool = {"KingsThrone", "ThornedForest"}, StartPoints = 6},
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
        FIXED = {Necromancer = true, FallenKnight = true, SniperBishop = true, Ghost = true, Zombie = true},
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
            SIZE = 10,
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
    -- Tiles are {column, row}; Rows and Columns are inclusive ranges
    Exclusives = {
        -- Cross a 2 wide cliff path to the far end while two Sniper Bishops on the board's edges shell it
        DeadmanWalking = {
            Region = "Cliffside",
            Enabled = true,
            -- The only columns the King can stand on; he starts at the near end and wins at the far one
            PATH_COLUMNS = {5, 6},
            KING_TILE = {5, 1},
            SNIPER_TILES = {{1, 6}, {10, 4}},
            -- Each sniper marks this many path tiles every enemy turn and fires on them the next one
            MARKS_PER_SNIPER = 2,
            -- Marks land on path rows from this far behind the King to this far ahead
            MARK_BEHIND = 1,
            MARK_AHEAD = 2,
            SNIPER_DAMAGE = 3,
            -- A sniper hit by a summoned piece skips this many turns instead of taking damage
            STUN_TURNS = 1,
            SUMMONABLE = {"Rook", "Queen"},
        },
        -- Escort a payload up the board while Rooks and Bishops throw themselves at it
        DangerousPayload = {
            Region = "Outskirts",
            Enabled = true,
            PAYLOAD_TILE = {5, 1},
            KING_TILE = {4, 1},
            -- It rolls one row every ROLL_TURNS enemy turns and is delivered on the roll after reaching the far row
            ROLL_TURNS = 2,
            -- The army is only Rooks and Bishops, bought with the allocation; a fresh wave worth WAVE_SHARE of it
            -- arrives on the back rows every WAVE_TURNS enemy turns
            POOL = {"Rook", "Bishop"},
            WAVE_SHARE = 0.5,
            WAVE_TURNS = 3,
            HUNTERS = {Rook = true, Bishop = true},
        },
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
        -- A dark maze of walls haunted by Ghosts and Zombies, with chests of Gold along the way
        HauntedMansion = {
            Region = "Gravehollow",
            Enabled = true,
            KING_TILE = {1, 1},
            -- The King wins by stepping onto any of these
            EXITS = {{10, 10}},
            -- Rows of the maze from row 10 at the top down to row 1; # is a wall, G a Ghost, Z a Zombie,
            -- $ a chest of Gold, A an Artifact chest, . empty
            LAYOUT = {
                "..#...Z#..",
                ".G#.##.#.#",
                ".##..#...#",
                "...#.#.#G.",
                "$#.#...#.#",
                ".#..##Z#..",
                ".##..#..#A",
                "..Z#.G.##.",
                "#.##.#....",
                "....$#.##.",
            },
            -- Pouch Gold in a $ chest; an A chest gives an Artifact, or ARTIFACT_SILVER when none are left to find
            CHEST_GOLD = 50,
            ARTIFACT_SILVER = 30,
            -- Tiles further than this from the King are dark
            LIGHT_RANGE = 2,
        },
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

        ThornedForest = {
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
