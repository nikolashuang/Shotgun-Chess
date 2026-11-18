local ClassConfig = {
    -- Kings start with no class; classes are unlocked by defeating regional Kings
    STARTER = nil,
    ORDER = {"Reaper", "Hunter", "Gunslinger", "Outlaw"},

    -- Text is display only; the numbers each ability uses sit beside its text
    -- Distances are in tiles (chess king distance), durations in enemy turns
    Classes = {
        Reaper = {
            DisplayName = "Reaper",
            Passive = "Reap: Dead enemies leave souls on the board.",
            Special = "Assimilate: Use up a soul to move like its piece this turn.",
            Ultimate = "Reaper's High: Absorb every soul. Heal 2 per soul and +1 damage per soul on your next shot.",

            -- Kings end the match when they die, so they never leave a soul
            NO_SOUL = {King = true},

            ReapersHigh = {
                HealPerSoul = 2,
                DamagePerSoul = 1,
            },
        },

        Hunter = {
            DisplayName = "Hunter",
            Passive = "Collector: Dead enemies have a 25% chance to drop 1 energy.",
            Special = "Trap Layout: Lay 3 bear traps enemies can't see. 3 damage and a 1 turn stun.",
            Ultimate = "Hunting Strike: Throw bolas in a Double Barrel spread. Every enemy hit is stunned for 3 turns. Kings are immune.",

            Collector = {
                Chance = 0.25,
                Energy = 1,
            },

            Traps = {
                Count = 3,
                Range = 2,
                Damage = 3,
                StunTurns = 1,
            },

            -- Thrown with this shotgun's aim and hitbox (cone, range, line of sight, point blank); deals no damage
            HuntingStrike = {
                Weapon = "DoubleBarrel",
                StunTurns = 3,
            },
        },

        Gunslinger = {
            DisplayName = "Gunslinger",
            Passive = "Deadeye: Shotgun cones are narrower and reach 1 tile further.",
            Special = "Fan the Hammer: Fire 6 revolver shots down a 3 tile line. 60% to hit, 1.5 damage each.",
            Ultimate = "High Noon's Bounty: Mark 2 enemies. Gain 2 energy when each one dies.",

            -- Placeholder numbers; the doc only says narrower and slightly further
            Deadeye = {
                ArcScale = 0.75,
                RangeBonus = 1,
            },

            FanTheHammer = {
                Shots = 6,
                Range = 3,
                HitChance = 0.6,
                Damage = 1.5,
            },

            Bounty = {
                Marks = 2,
                Energy = 2,
            },
        },

        Outlaw = {
            DisplayName = "Outlaw",
            Passive = "Opportunist: +1 damage to enemies with no ally next to them.",
            Special = "Conceal: Throw a 3x3 smoke bomb up to 3 tiles away. Enemies can't attack into it for 2 turns.",
            Ultimate = "Ambush: Jump to any empty tile next to an enemy. +2 damage on your next shot.",

            Opportunist = {
                Damage = 1,
            },

            Conceal = {
                Range = 3,
                -- Tiles from the center, so 1 makes a 3x3 cloud
                Radius = 1,
                Turns = 2,
            },

            Ambush = {
                -- The landing tile must be within this many tiles of at least one enemy
                MaxEnemyDistance = 1,
                Damage = 2,
            },
        },
    },
}

return ClassConfig
