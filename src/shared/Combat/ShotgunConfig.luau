local ShotgunConfig = {
    STARTER = "Pump",
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
            DisplayName = "PUMP",
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
            DisplayName = "DOUBLE BARREL",
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
            DisplayName = "BUCK BARREL",
            Description = "Right click for a precise shot: 3 tile line that pierces for max damage. Needs all 3 shells.",
            Price = 2100,

            MaxAmmo = 3,
            AmmoPerShot = 1,
            Blasts = 1,

            MaxRange = 3,
            ArcDegrees = 64,
            PelletCount = 5,
            MaxDamage = 5,
            MinDamage = 2,

            AltMode = "Precise",
            Precise = {
                Range = 3,
                AmmoCost = 3,
            },
        },

        LongBarrel = {
            DisplayName = "LONG BARREL",
            Description = "5 tile range with a very tight spread.",
            Price = 3500,

            MaxAmmo = 4,
            AmmoPerShot = 1,
            Blasts = 1,

            MaxRange = 5,
            ArcDegrees = 24,
            PelletCount = 5,
            MaxDamage = 5,
            MinDamage = 2,
        },

        KnifeShotty = {
            DisplayName = "KNIFE SHOTTY",
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
