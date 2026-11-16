local ClassConfig = {
    STARTER = "Reaper",
    ORDER = {"Reaper", "Hunter", "Gunslinger", "Outlaw"},

    -- Display only until class abilities are implemented
    Classes = {
        Reaper = {
            DisplayName = "REAPER",
            Passive = "REAP: Dead enemies become souls. Queens don't drop souls.",
            Special = "ASSIMILATE: Harvest souls to use their abilities for one turn, or turn them into energy.",
            Ultimate = "UNBOUND: Move like a Queen for one turn.",
        },

        Hunter = {
            DisplayName = "HUNTER",
            Passive = "COLLECTOR: Dead enemies drop scrap on the field.",
            Special = "TRAP LAYOUT: Lay invisible bear traps.",
            Ultimate = "HUNTING STRIKE: Throw bolas in a 5 tile radius, stunning enemies for 3 turns.",
        },

        Gunslinger = {
            DisplayName = "GUNSLINGER",
            Passive = "DEADEYE: Shotgun cones shrink and shoot slightly further.",
            Special = "QUICKDRAW: Fire a weaker shot without using your action. Once per turn.",
            Ultimate = "HIGH NOON'S BOUNTY: Mark 2 enemies, gain energy for killing both.",
        },

        Outlaw = {
            DisplayName = "OUTLAW",
            Passive = "OPPORTUNIST: +1 damage to isolated pieces.",
            Special = "CONCEAL: 3x3 smoke for two turns. Enemies can't attack or shoot into it.",
            Ultimate = "AMBUSH: Move to any square at least 1 tile from an enemy. +2 damage on your next shot.",
        },
    },
}

return ClassConfig
