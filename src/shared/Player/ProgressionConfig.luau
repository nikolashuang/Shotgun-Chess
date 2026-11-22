local ProgressionConfig = {
    START_LEVEL = 1,
    -- Exp for the first level up; every level after needs EXP_INCREASE_PER_LEVEL more than the last
    EXP_PER_LEVEL = 100,
    EXP_INCREASE_PER_LEVEL = 100,

    START_GOLD = 0,

    -- The Multiplayer screen opens after Hunter Forest (about level 5); Duels inside it open later
    MULTIPLAYER_UNLOCK_LEVEL = 5,
    DUELS_UNLOCK_LEVEL = 10,
}

return ProgressionConfig
