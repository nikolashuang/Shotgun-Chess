local ShotgunConfig = {
    STARTER = "Pump",
    -- Enemy Kings hold and fire this shotgun (no ammo tracking)
    ENEMY_KING = "Pump",
    -- Sorted by price for the shop and armory
    ORDER = {"Pump", "DoubleBarrel", "BuckBarrel", "KnifeShotty", "LongBarrel"},

    -- Distances are in tiles, measured from the center of the king's tile
    MIN_RANGE = 1,

    -- Sideways gap between pellets landing in a point blank tile
    POINT_BLANK_SPREAD = 0.12,

    TRACE_STEP = 0.05,
    COVERAGE_SPACING = 0.1,

    -- Lines of sight that only touch an enemy tile's edge or corner within this many tiles aren't blocked
    LINE_OF_SIGHT_MARGIN = 0.02,

    -- Damage falls off linearly from MaxDamage at MIN_RANGE to MinDamage at MaxRange (tile distance)
    -- Blasts multiplies the damage of every hit, AmmoPerShot is spent per normal shot
    -- Ranges, arcs and damage are placeholders until the design doc gives numbers
    Shotguns = {
        Pump = {
            DisplayName = "Pump",
            Description = "Starter shotgun. Medium range, medium damage.",
            Price = 0,

            MaxAmmo = 5,
            AmmoPerShot = 1,
            Blasts = 1,

            MaxRange = 3,
            ArcDegrees = 64,
            PelletCount = 5,
            MaxDamage = 5,
            MinDamage = 2,
        },

        DoubleBarrel = {
            DisplayName = "Double Barrel",
            Description = "Fires both barrels: double damage, uses 2 shells. Shorter range.",
            Price = 2000,

            MaxAmmo = 4,
            AmmoPerShot = 2,
            Blasts = 2,

            MaxRange = 2,
            ArcDegrees = 64,
            PelletCount = 5,
            MaxDamage = 5,
            MinDamage = 3.5,
        },

        BuckBarrel = {
            DisplayName = "Buck Barrel",
            Description = "Knocks enemies back a tile. Hits harder at long range.",
            Price = 2100,

            MaxAmmo = 4,
            AmmoPerShot = 1,
            Blasts = 1,

            MaxRange = 3,
            ArcDegrees = 64,
            PelletCount = 5,
            MaxDamage = 5,
            MinDamage = 3,

            -- Tiles every enemy hit (except Kings) is pushed straight away from the king, if the tile is free
            Knockback = 1,
        },

        LongBarrel = {
            DisplayName = "Long Barrel",
            Description = "5 tile range with a very tight spread.",
            Price = 3500,

            MaxAmmo = 4,
            AmmoPerShot = 1,
            Blasts = 1,

            MaxRange = 4,
            ArcDegrees = 24,
            PelletCount = 5,
            MaxDamage = 5,
            MinDamage = 2,
        },

        KnifeShotty = {
            DisplayName = "Knife Shotty",
            Description = "Right click to swing at adjacent enemies: 6 damage and bleed. Works with no ammo.",
            Price = 2400,

            MaxAmmo = 5,
            AmmoPerShot = 1,
            Blasts = 1,

            MaxRange = 3,
            ArcDegrees = 64,
            PelletCount = 5,
            MaxDamage = 5,
            MinDamage = 2,

            AltMode = "Knife",
            Knife = {
                Damage = 6,
                BleedDamage = 1,
                BleedTurns = 2,
            },
        },
    },
}

return ShotgunConfig
