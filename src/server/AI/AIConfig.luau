local AIConfig = {
    -- Chance per acting piece to take a random option instead of the best one
    -- MaxMistakes caps the mistakes in a whole match
    Ratings = {
        [500] = {MistakeChance = 0.4},
        [1000] = {MistakeChance = 0.25},
        [1500] = {MistakeChance = 0.1},
        [2000] = {MistakeChance = 0.05},
        [2500] = {MistakeChance = 0.01, MaxMistakes = 2},
    },

    -- Priority weights, highest acts first; every score part is roughly 0 to 1 before weighting
    Weights = {
        Default = {Defend = 600, Attack = 500, Evade = 400, Position = 300, Teamwork = 200, Advance = 100},
        -- Swapped to Default once only the King and Queen are left
        Queen = {Attack = 600, Defend = 500, Evade = 400, Position = 300, Teamwork = 200, Advance = 100},
        King = {Evade = 600, Attack = 500, Teamwork = 300, Position = 200, Advance = 100, Defend = 0},
    },

    -- Pieces whose Evade outranks Attack won't attack from a tile the player can hit
    EVADE_BEFORE_ATTACK = {King = true},

    -- Expected damage times this, over max health, is how risky a tile is (capped at 1)
    RISK_SCALE = 2,
    -- Share of Position that comes from lining up an attack on the king's tile (the rest is blocking its escape tiles)
    KING_LINE_VALUE = 0.5,
    -- Extra attack value for hitting the player's king
    KING_TARGET_BONUS = 0.25,
    -- Allies within this many tiles count as nearby for Teamwork
    TEAMWORK_RANGE = 2,
    -- Tiles of distance closed that count as a full Advance
    ADVANCE_STEP = 3,

    -- Enemy Kings fire this shotgun (no ammo tracking)
    KING_SHOTGUN = "Pump",
}

return AIConfig
