local PieceConfig = {
    Health = {
        King = 15,
        Pawn = 3,
        Knight = 5,
        Bishop = 5,
        Rook = 7,
        Queen = 9,
    },

    -- Damage a summoned piece deals when commanded onto an enemy
    Damage = {
        Pawn = 1,
        Knight = 2,
        Bishop = 2,
        Rook = 2,
        Queen = 4,
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
}

return PieceConfig
