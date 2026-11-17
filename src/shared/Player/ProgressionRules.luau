local ProgressionConfig = require(script.Parent.ProgressionConfig)

local ProgressionRules = {}

-- Exp needed to go from this level to the next
function ProgressionRules.GetExpToLevel(level)
    return ProgressionConfig.EXP_PER_LEVEL + (level - ProgressionConfig.START_LEVEL) * ProgressionConfig.EXP_INCREASE_PER_LEVEL
end

-- Returns the level and the exp earned inside that level
function ProgressionRules.GetLevel(totalExp)
    local level = ProgressionConfig.START_LEVEL
    local exp = totalExp

    while exp >= ProgressionRules.GetExpToLevel(level) do
        exp -= ProgressionRules.GetExpToLevel(level)
        level += 1
    end

    return level, exp
end

return ProgressionRules
