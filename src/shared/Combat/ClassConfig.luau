local ClassConfig = {
    -- Kings start with no class; classes are unlocked by defeating regional Kings
    STARTER = nil,
    ORDER = {"Monarch", "Reaper", "Hunter", "Gunslinger", "Outlaw"},

    -- Text is display only; the numbers each ability uses sit beside its text
    -- Distances are in tiles (chess king distance), durations in enemy turns
    Classes = {
        Monarch = {
            DisplayName = "Monarch",
            Passive = "Loyalty: Your first Queen each match costs 4 energy.",
            Special = "Morale: All your pieces gain a 1 health shield until your next turn.",
            Ultimate = "Unyielding: All your pieces deal +2 damage this turn.",

            Loyalty = {
                QueenCost = 4,
            },

            -- The shield soaks up damage before health and is gone at the start of your next turn
            Morale = {
                Shield = 1,
            },

            Unyielding = {
                Damage = 2,
            },
        },

        Reaper = {
            DisplayName = "Reaper",
            Passive = "Reap: Every piece that dies leaves a soul on the board, allies included.",
            Special = "Assimilate: Use up a soul for a bonus move like its piece. Works even after the king has moved.",
            Ultimate = "Reaper's High: Absorb every soul. Heal 2 per soul (up to 8) and +1 damage per soul on your next shot.",

            -- Kings end the match when they die, so they never leave a soul
            NO_SOUL = {King = true},

            ReapersHigh = {
                HealPerSoul = 2,
                -- Most health one Reaper's High can restore
                MaxHeal = 8,
                DamagePerSoul = 1,
            },
        },

        Hunter = {
            DisplayName = "Hunter",
            Passive = "Collector: Dead enemies have a 25% chance to drop 1 energy.",
            Special = "Trap Layout: Lay 2 bear traps enemies can't see. 1 damage and a 1 turn stun. Knights jump over them.",
            Ultimate = "Hunting Strike: Throw bolas in a Pump spread (3 tiles). Every enemy hit is stunned for 3 turns, Kings for 1.",

            Collector = {
                Chance = 0.25,
                Energy = 1,
            },

            Traps = {
                Count = 2,
                Range = 2,
                Damage = 1,
                StunTurns = 1,
            },

            -- Thrown with this shotgun's aim and hitbox (cone, range, line of sight, point blank); deals no damage
            HuntingStrike = {
                Weapon = "Pump",
                StunTurns = 3,
                KingStunTurns = 1,
            },
        },

        Gunslinger = {
            DisplayName = "Gunslinger",
            Passive = "Deadly Rounds: Shotgun blasts pass through everything. -2 damage for every enemy passed through.",
            Special = "Fan the Hammer: Fire 6 revolver shots down a 4 tile line. 60% to hit, 1.5 damage each.",
            Ultimate = "High Noon's Bounty: Mark 2 enemies. Gain 2 energy when each one dies.",

            -- Blasts aren't stopped by anything; each enemy passed on the way to a target costs this much damage
            DeadlyRounds = {
                DamageLossPerEnemy = 2,
            },

            FanTheHammer = {
                Shots = 6,
                Range = 4,
                HitChance = 0.6,
                Damage = 1.5,
            },

            Bounty = {
                Marks = 2,
                Energy = 2,
            },
        },

        -- Shown to players as the Bandit; the key stays Outlaw so saved unlocks and loadouts still match
        Outlaw = {
            DisplayName = "Bandit",
            Passive = "Opportunist: +2 damage to enemies with no ally next to them.",
            Special = "Conceal: Throw a 3x3 smoke bomb up to 3 tiles away for 1 turn. Enemy attacks and shots into it only hit half the time.",
            Ultimate = "Ambush: Jump to any empty tile next to an enemy.",

            Opportunist = {
                Damage = 2,
            },

            Conceal = {
                Range = 3,
                -- Tiles from the center, so 1 makes a 3x3 cloud
                Radius = 1,
                Turns = 1,
                -- Every enemy attack, knife swing or shotgun hit on a target inside the cloud rolls this separately
                HitChance = 0.5,
            },

            Ambush = {
                -- The landing tile must be within this many tiles of at least one enemy
                MaxEnemyDistance = 1,
            },
        },
    },
}

return ClassConfig
