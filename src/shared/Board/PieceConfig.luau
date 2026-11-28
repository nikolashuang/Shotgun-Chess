local PieceConfig = {
    Health = {
        King = 15,
        Pawn = 3,
        Knight = 5,
        Bishop = 5,
        Rook = 7,
        Queen = 9,
        -- Gravehollow Regional Encounter: fought once, then fights beside the King for the rest of the Expedition
        FallenKnight = 10,
        -- Guard the Fallen Knight's throne; fight like normal pawns
        FallenPawn = 4,
        -- Gravehollow Rook variant, already scaled for Act III
        Necromancer = 12,
        -- Regional Encounters: Deadman Walking's snipers can't be hurt, only stunned; Dangerous Payload's cart;
        -- Haunted Mansion's undead
        SniperBishop = 5,
        Payload = 30,
        Ghost = 4,
        Zombie = 8,
    },

    -- Damage a summoned piece deals when commanded onto an enemy
    Damage = {
        Pawn = 1,
        Knight = 3,
        Bishop = 3,
        Rook = 4,
        Queen = 5,
        FallenKnight = 4,
        FallenPawn = 1,
        Necromancer = 3,
        Ghost = 3,
        Zombie = 4,
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

    -- Necromancers raise a fallen ally within RANGE tiles instead of acting, back on its death tile at HEALTH_SHARE
    -- of its max health (rounded up); each piece is raised once per battle
    Necromancer = {
        RANGE = 3,
        COOLDOWN = 3,
        MAX_RAISES = 2,
        HEALTH_SHARE = 0.5,
        NO_RAISE = {King = true, Queen = true, Necromancer = true},
    },

    -- Pieces without their own sprite yet borrow another piece's, tinted
    SpriteStandIns = {
        Necromancer = {Sprite = "Rook", Tint = Color3.fromHex("8FD18A")},
        SniperBishop = {Sprite = "Bishop", Tint = Color3.fromHex("C8644F")},
        Payload = {Sprite = "Rook", Tint = Color3.fromHex("D4A85A")},
        Ghost = {Sprite = "Pawn", Tint = Color3.fromHex("BFE8FF")},
        Zombie = {Sprite = "Pawn", Tint = Color3.fromHex("8FB86A")},
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
