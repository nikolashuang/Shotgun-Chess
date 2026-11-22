local DuelConfig = {
    -- Seconds on each player's chess clock; running out loses the duel
    CLOCK = 300,

    -- Seconds a challenge can be accepted for
    CHALLENGE_TIMEOUT = 30,

    -- Winners get WIN_REWARD, losers get the small LOSS_REWARD; forfeiting pays nothing
    WIN_REWARD = {Gold = 150, Exp = 100},
    LOSS_REWARD = {Gold = 50, Exp = 30},

    -- 2v2 win reward multipliers: the rivals surrendered after a teammate disconnected,
    -- or the winner fought on alone after their own teammate disconnected (taking their share)
    DISCONNECT_SURRENDER_SCALE = 0.1,
    SOLO_WIN_SCALE = 2,

    -- 2v2 lobby positions the host fills by invite
    LOBBY_POSITIONS = {"Teammate", "Rival1", "Rival2"},

    -- Global duels run in reserved servers of the duel place, then send players back to the main game
    MAIN_PLACE_ID = 120635777023691,
    DUEL_PLACE_ID = 109780390106651,

    -- Seconds: the coordinator's lease (it lapses on its own if its server stops renewing it),
    -- how often servers match and check for assignments, and how long queue entries and assignments live
    LEASE_TIME = 10,
    MATCH_INTERVAL = 2,
    QUEUE_ENTRY_TIME = 60,
    -- A claim the coordinator never finished (its server went down) is dropped after this long
    CLAIM_TIMEOUT = 30,
    ASSIGNMENT_TIME = 120,

    -- Seconds the duel place waits for every matched player, counts down before the clocks start,
    -- and shows the result before sending everyone back
    ARRIVAL_TIMEOUT = 45,
    COUNTDOWN = 3,
    RETURN_DELAY = 6,

    -- Practice AI ratings the difficulty picker steps through; each must be a key of AIConfig.Ratings
    PRACTICE_RATINGS = {500, 1000, 1500, 2000, 2500},
    PRACTICE_DEFAULT_RATING = 1000,
}

return DuelConfig
