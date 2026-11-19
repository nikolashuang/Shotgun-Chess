local DuelConfig = {
    -- Seconds on each player's chess clock; running out loses the duel
    CLOCK = 300,

    -- Seconds a challenge can be accepted for
    CHALLENGE_TIMEOUT = 30,

    -- Placeholder rewards until duel economy is designed; forfeiting pays nothing
    WIN_REWARD = {Gold = 150, Exp = 100},
    LOSS_REWARD = {Gold = 50, Exp = 30},

    -- Practice AI ratings the difficulty picker steps through; each must be a key of AIConfig.Ratings
    PRACTICE_RATINGS = {500, 1000, 1500, 2000, 2500},
    PRACTICE_DEFAULT_RATING = 1000,
}

return DuelConfig
