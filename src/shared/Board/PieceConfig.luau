local PieceConfig = {
    Health = {
        King = 15,
        Pawn = 3,
        Knight = 5,
        Bishop = 5,
        Rook = 7,
        Queen = 9,
        -- Campaign mystery encounter: fought once, then fights beside the King for the rest of the run
        FallenKnight = 10,
        -- Guard the Fallen Knight's throne; fight like normal pawns
        FallenPawn = 4,
    },

    -- Damage a summoned piece deals when commanded onto an enemy
    Damage = {
        Pawn = 1,
        Knight = 2,
        Bishop = 2,
        Rook = 3,
        Queen = 4,
        FallenKnight = 4,
        FallenPawn = 1,
    },

    -- Energy cost to summon
    Cost = {
        Pawn = 1,
        Knight = 2,
        Bishop = 2,
        Rook = 3,
        Queen = 6,
    },

    -- Most of a piece type a king can have active at once
    MaxActive = {
        Queen = 1,
    },

    SUMMONABLE = {"Pawn", "Knight", "Bishop", "Rook", "Queen"},

    -- Singleplayer enemy pawns that reach the player's back row become one of these, by weight
    PROMOTIONS = {
        {Type = "Knight", Weight = 40},
        {Type = "Bishop", Weight = 40},
        {Type = "Rook", Weight = 20},
    },
}

return PieceConfig
