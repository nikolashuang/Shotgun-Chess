local PieceConfig = {
    Health = {
        King = 15,
        Pawn = 3,
        Knight = 5,
        Bishop = 5,
        Rook = 7,
        Queen = 9,
    },

    -- Energy cost to summon
    Cost = {
        Pawn = 1,
        Knight = 3,
        Bishop = 3,
        Rook = 5,
        Queen = 7,
    },

    -- Most of a piece type a king can have active at once
    MaxActive = {
        Queen = 1,
    },

    SUMMONABLE = {"Pawn", "Knight", "Bishop", "Rook", "Queen"},
}

return PieceConfig
