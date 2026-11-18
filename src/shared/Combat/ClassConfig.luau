local ClassConfig = {
    -- Kings start with no class; classes are unlocked by defeating regional Kings
    STARTER = nil,
    ORDER = {"Reaper", "Hunter", "Gunslinger", "Outlaw"},

    -- Text is display only; ability numbers sit beside the text of implemented abilities
    Classes = {
        Reaper = {
            DisplayName = "Reaper",
            Passive = "Reap: Dead enemies become souls. Queens don't drop souls.",
            Special = "Assimilate: Harvest souls to use their abilities for one turn, or turn them into energy.",
            Ultimate = "Unbound: Move like a Queen for one turn.",
        },

        Hunter = {
            DisplayName = "Hunter",
            Passive = "Collector: Dead enemies drop scrap on the field.",
            Special = "Trap Layout: Lay invisible bear traps.",
            Ultimate = "Hunting Strike: Throw bolas in a 5 tile radius, stunning enemies for 3 turns.",
        },

        Gunslinger = {
            DisplayName = "Gunslinger",
            Passive = "Deadeye: Shotgun cones shrink and shoot slightly further.",
            Special = "Fan the Hammer: Fire 6 revolver shots down a 3 tile line. Each shot has a 50% chance to hit.",
            Ultimate = "High Noon's Bounty: Mark 2 enemies, gain energy for killing both.",

            FanTheHammer = {
                Shots = 6,
                Range = 3,
                HitChance = 0.5,
                Damage = 1,
            },
        },

        Outlaw = {
            DisplayName = "Outlaw",
            Passive = "Opportunist: +1 damage to isolated pieces.",
            Special = "Conceal: 3x3 smoke for two turns. Enemies can't attack or shoot into it.",
            Ultimate = "Ambush: Move to any square at least 1 tile from an enemy. +2 damage on your next shot.",
        },
    },
}

return ClassConfig
