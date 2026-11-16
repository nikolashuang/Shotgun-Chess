local ShotgunConfig = {
    -- Distances are in tiles, measured from the center of the king's tile
    MIN_RANGE = 1,
    MAX_RANGE = 3,

    ARC_DEGREES = 64,
    PELLET_COUNT = 5,

    -- Damage at MIN_RANGE falls off linearly to MIN_DAMAGE at MAX_RANGE (tile distance)
    MAX_DAMAGE = 5,
    MIN_DAMAGE = 2,

    -- Sideways gap between pellets landing in a point blank tile
    POINT_BLANK_SPREAD = 0.12,

    TRACE_STEP = 0.05,
    COVERAGE_SPACING = 0.1,
}

return ShotgunConfig
