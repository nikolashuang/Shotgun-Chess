-- Checks for values the client sends inside ability payloads
local ArgumentRules = {}

function ArgumentRules.IsFiniteNumber(value)
    return typeof(value) == "number" and value == value and math.abs(value) < 1e6
end

function ArgumentRules.IsWholeNumber(value)
    return ArgumentRules.IsFiniteNumber(value) and value % 1 == 0
end

function ArgumentRules.IsTile(column, row)
    return ArgumentRules.IsWholeNumber(column) and ArgumentRules.IsWholeNumber(row)
end

return ArgumentRules
