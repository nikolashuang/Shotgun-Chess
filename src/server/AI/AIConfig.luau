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
        -- Pawns march for promotion first and only strike when they can't step forward (Fallen Pawns too)
        Pawn = {Advance = 600, Attack = 500, Defend = 0, Evade = 0, Position = 0, Teamwork = 0},
    },

    -- Campaign boss Kings using their class: special every SPECIAL_COOLDOWN enemy turns, ultimate once per fight
    -- after dropping to ULTIMATE_HEALTH of max health
    Boss = {
        SPECIAL_COOLDOWN = 3,
        ULTIMATE_HEALTH = 0.5,
        -- Monarch shields once at least this many allies end the turn where the player can hit them
        MONARCH_SHIELD_MIN = 1,
    },

    -- Pieces whose Evade outranks Attack won't attack from a tile the player can hit
    EVADE_BEFORE_ATTACK = {King = true},

    -- Pieces press the attack until their health falls below this share of max health, then start evading
    EVADE_HEALTH = {Default = 0.3, King = 0.5},
    -- Attacking a summoned piece from a tile the player can hit loses this much of the attack's weight at full risk,
    -- so pieces don't walk into pawns the player plants next to their King for a point blank blast
    BAIT_PENALTY = 0.8,
    -- Furthest an evading Rook or Bishop will slide to get away, so the player isn't chasing it from side to side
    -- Attacks and normal moves still use the full slide
    SLIDE_CAP = {Rook = 4, Bishop = 4},

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
}

return AIConfig
