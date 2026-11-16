local MatchConfig = {
    -- Seconds the enemy turn lasts while the enemy has no AI
    ENEMY_TURN_TIME = 5,

    TEST_DUMMIES = {
        {Type = "Pawn", Column = 5, Row = 3},
        {Type = "Knight", Column = 7, Row = 3},
        {Type = "Bishop", Column = 3, Row = 4},
        {Type = "Rook", Column = 9, Row = 4},
        {Type = "Queen", Column = 6, Row = 5},
    },
}

return MatchConfig
