local AIConfig = {
    -- Prints every enemy piece's options and score parts to the output; can also be turned on in a running game with
    -- workspace:SetAttribute("AIDebug", true)
    DEBUG = false,
    -- Options shown per piece in the debug output, best first
    DEBUG_OPTIONS = 5,

    -- Chance per acting piece to take a random option instead of the best one
    -- MaxMistakes caps the mistakes in a whole match
    Ratings = {
        [500] = {MistakeChance = 0.4},
        [1000] = {MistakeChance = 0.25},
        [1500] = {MistakeChance = 0.1},
        [2000] = {MistakeChance = 0.05},
        [2500] = {MistakeChance = 0.01, MaxMistakes = 2},
    },

    -- Directive weights before the board adjusts them; every score part is roughly 0 to 1 before weighting
    Weights = {
        Default = {Defend = 600, Attack = 500, Evade = 400, Position = 300, Teamwork = 200, Advance = 100},
        -- Swapped to Default once only the King and Queen are left
        Queen = {Attack = 600, Defend = 500, Evade = 400, Position = 300, Teamwork = 200, Advance = 100},
        -- Cut off escape routes with straight lines
        Rook = {Defend = 600, Attack = 450, Evade = 400, Position = 400, Teamwork = 250, Advance = 100},
        -- Hold diagonals from a distance
        Bishop = {Defend = 600, Attack = 450, Evade = 400, Position = 350, Teamwork = 250, Advance = 100},
        -- Flank and strike from angles the sliders can't reach
        Knight = {Defend = 550, Attack = 550, Evade = 400, Position = 300, Teamwork = 300, Advance = 150},
        King = {Evade = 600, Attack = 500, Teamwork = 300, Position = 200, Advance = 100, Defend = 0},
        -- Pawns march for promotion first and only strike when they can't step forward (Fallen Pawns too)
        Pawn = {Advance = 600, Attack = 500, Defend = 0, Evade = 0, Position = 0, Teamwork = 0},
        -- Stay behind the army and keep raising it; Advance walks toward the fallen while a raise is ready
        Necromancer = {Evade = 600, Defend = 300, Attack = 400, Position = 300, Teamwork = 400, Advance = 350},
    },

    -- How much each piece is worth to its side: what losing it costs, and what killing it is worth
    PieceValue = {
        Pawn = 1,
        FallenPawn = 1,
        Knight = 3,
        Bishop = 3,
        Rook = 5,
        FallenKnight = 4,
        Necromancer = 7,
        Queen = 9,
        King = 20,
    },

    --RISK--

    -- Expected damage times this, over max health, is how risky a tile is (capped at 1)
    RISK_SCALE = 2,
    -- Every option except piece attacks loses this much at full risk, even for healthy pieces (avoiding a bad move)
    RISK_WEIGHT = 100,
    -- Plus this much per point of the piece's value, times its chance of dying there
    LOSS_WEIGHT = 120,
    -- Attacking a cheaper summoned piece is weighed as a trade (health lost instead of death chance), times this,
    -- so pieces don't walk into pawns the player plants next to their King for a point blank blast
    BAIT_MULTIPLIER = 1.5,
    -- Each other ally the player's king could also hit cuts a piece's non-lethal risk by this share of itself
    SHARED_TARGET = 0.5,
    -- Taken off each option per ally within 1 tile of its tile that the player could also hit (one blast, many hits)
    CLUSTER_PENALTY = 40,

    --EVADE--

    -- Pieces press the attack until their health falls below this share of max health, then start evading
    EVADE_HEALTH = {Default = 0.3, King = 0.5, Necromancer = 0.6},
    -- Furthest an evading Rook or Bishop will slide to get away, so the player isn't chasing it from side to side
    -- Attacks and normal moves still use the full slide
    SLIDE_CAP = {Rook = 4, Bishop = 4, Necromancer = 4},
    -- Hurt sliders lose range on every move: at or below each health share they slide at most Range tiles
    -- Attacks keep the full slide; pawns and knights are never affected
    LOW_HEALTH_SLIDERS = {Rook = true, Bishop = true, Queen = true, Necromancer = true},
    LOW_HEALTH_RANGE = {
        {Health = 0.33, Range = 1},
        {Health = 0.66, Range = 3},
    },
    -- Evade grows from 1x at the threshold to this at 0 health
    EVADE_MAX_URGENCY = 2,

    -- An enemy King with no allies left loses this share of Evade for every turn in a row it spent backing off,
    -- and gains Attack, so it comes back and fights instead of running forever
    KING_FATIGUE = 0.35,
    ISOLATED_KING_ATTACK = 1.25,

    --ATTACK--

    -- Extra attack value for hitting the player's king
    KING_TARGET_BONUS = 0.25,
    -- Extra attack value for hitting Dangerous Payload's cart, enough to beat any other target
    PRIORITY_TARGET_VALUE = 3,
    -- Ending a move where a hunter can hit the payload next turn, worth more than hitting the player's king
    HUNT_LINE_VALUE = 1.5,
    -- Killing the player's king wins the fight
    KING_KILL_SCORE = 10000,
    -- Extra attack value per point of a killed piece's value
    KILL_VALUE = 0.1,
    -- Attack grows by up to this share as the player's king loses health
    LOW_KING_ATTACK = 0.5,

    --DEFEND--

    -- Defend grows by up to this share when the allied King's tile is dangerous
    KING_DANGER_DEFEND = 1,
    -- Defend values: killing a threat, stepping into its line, standing next to the King on its side
    DEFEND_KILL = 1,
    DEFEND_BLOCK = 0.8,
    DEFEND_GUARD = 0.4,

    --POSITION--

    -- Share of Position that comes from lining up an attack on the king's tile (the rest is blocking its escape tiles)
    KING_LINE_VALUE = 0.5,
    -- Extra Position share for standing at the piece's preferred distance from the player's king
    PREFERRED_RANGE = {Bishop = {Min = 3, Max = 5, Value = 0.25}},

    --TEAMWORK--

    -- Allies within this many tiles count as nearby for Teamwork
    TEAMWORK_RANGE = 2,
    -- Teamwork values: hitting a target an ally already hit this turn, closing in from a side no ally holds,
    -- and threatening a white piece that threatens an ally
    FOCUS_VALUE = 0.5,
    FLANK_VALUE = 0.3,
    PROTECT_VALUE = 0.4,
    -- Pieces this close to the player's king count for flanking
    FLANK_RANGE = 3,

    --ADVANCE--

    -- Tiles of distance closed that count as a full Advance
    ADVANCE_STEP = 3,
    -- Advance grows by this share for every turn in a row a piece hasn't moved or attacked, up to IDLE_TURNS_MAX turns
    IDLE_ADVANCE = 0.75,
    IDLE_TURNS_MAX = 4,
    -- Taken off for stepping straight back to the tile the piece left last turn
    BACKTRACK_PENALTY = 80,

    -- Expedition boss Kings using their class: special every SPECIAL_COOLDOWN enemy turns, ultimate once per fight
    -- after dropping to ULTIMATE_HEALTH of max health
    Boss = {
        SPECIAL_COOLDOWN = 3,
        ULTIMATE_HEALTH = 0.5,
        -- Monarch shields once at least this many allies end the turn where the player can hit them
        MONARCH_SHIELD_MIN = 1,

        -- Reaper: Assimilate away once it cuts the danger on the King by this much damage
        REAPER_RETREAT_MIN = 2,
        -- Reaper's High once (souls healed for) + (souls of extra damage on this turn's shot) reaches this
        REAPERS_HIGH_MIN = 2,

        -- Hunter: traps prefer tiles nearer the player's king, plus this for tiles a white piece could step onto
        TRAP_PATH_VALUE = 0.5,
        -- Hunting Strike counts each piece caught as 1 and the player's king as this, and is thrown at this many
        BOLAS_KING_VALUE = 3,
        BOLAS_MIN = 2,
        -- Boss trap ids start here so they never clash with the player's own Hunter traps on the client
        TRAP_ID_START = 100000,

        -- Bandit: Conceal once the smoke would cover this much (risk x piece value, halved by the 50/50)
        CONCEAL_MIN = 1.5,
        -- Ambush next to the player's king when the point blank shot kills, or deals this much without the King
        -- landing where it would die
        AMBUSH_MIN_DAMAGE = 6,

        -- Gunslinger: Fan the Hammer once its expected hits are worth this (share of each target's health),
        -- plus this for every line that reaches the player's king
        FAN_MIN = 0.5,
        FAN_KING_VALUE = 0.5,
    },
}

return AIConfig
