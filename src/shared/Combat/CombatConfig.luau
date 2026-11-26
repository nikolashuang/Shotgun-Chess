local CombatConfig = {
    Energy = {
        -- Energy is gained at the start of every player turn, including the first
        START_ENERGY = 0,
        ENERGY_PER_TURN = 2,
        MAX_ENERGY = 8,
    },

    -- Energy each action costs; summon costs live in PieceConfig.Cost
    ActionCost = {
        -- The King's one step per turn; Assimilate's bonus moves are free
        Move = 1,
        Fire = 1,
        Command = 1,
        Reload = 1,
        Special = 2,
        Ultimate = 0,
    },

    -- Commands cost one energy per this many tiles the piece travels (rounded up), never less than ActionCost.Command
    COMMAND_TILES_PER_ENERGY = 2,

    Ultimate = {
        MAX_CHARGE = 100,
        -- Charge per point of damage the King's own weapons actually deal to enemy pieces (overkill doesn't count);
        -- summoned pieces, companions and traps don't build it
        CHARGE_PER_DAMAGE = 5,
    },
}

return CombatConfig
