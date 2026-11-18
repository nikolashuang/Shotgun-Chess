local CombatConfig = {
    Energy = {
        -- Energy is gained at the start of every player turn, including the first
        START_ENERGY = 0,
        ENERGY_PER_TURN = 1,
        MAX_ENERGY = 8,
    },

    -- Energy each action costs; summon costs live in PieceConfig.Cost
    ActionCost = {
        Fire = 1,
        Command = 1,
        Reload = 1,
        Special = 2,
        Ultimate = 0,
    },

    Ultimate = {
        MAX_CHARGE = 100,
        -- Charge per point of damage actually dealt to enemy pieces (overkill doesn't count)
        CHARGE_PER_DAMAGE = 10,
    },
}

return CombatConfig
