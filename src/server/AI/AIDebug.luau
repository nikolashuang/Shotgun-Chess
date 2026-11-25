local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardRules = require(ReplicatedStorage.Shared.Board.BoardRules)
local AIConfig = require(script.Parent.AIConfig)

local DIRECTIVES = {"Defend", "Attack", "Evade", "Position", "Teamwork", "Advance"}
local PARTS = {"Defend", "Attack", "Evade", "Position", "Teamwork", "Advance", "Risk"}

-- Prints the enemy AI's reasoning to the output while balancing
local AIDebug = {}

function AIDebug.IsOn()
    return AIConfig.DEBUG or workspace:GetAttribute("AIDebug") == true
end

local function DescribeOption(option)
    if option.Type == "Attack" then
        return "Attack " .. BoardRules.GetTileName(option.TargetColumn, option.TargetRow)
    elseif option.Type == "Shoot" then
        return "Shoot " .. BoardRules.GetTileName(math.floor(option.AimX) + 1, math.floor(option.AimY) + 1)
    end

    return option.Type .. " " .. BoardRules.GetTileName(option.Column, option.Row)
end

local function DescribeParts(parts)
    local text = {}

    for _, name in ipairs(PARTS) do
        local value = parts[name]

        if value and math.abs(value) >= 0.5 then
            table.insert(text, string.format("%s %.0f", name, value))
        end
    end

    return table.concat(text, ", ")
end

-- The two parts that pushed the option up the most
local function GetReasons(parts)
    local reasons = {}

    for name, value in pairs(parts) do
        if value > 0 then
            table.insert(reasons, {Name = name, Value = value})
        end
    end

    table.sort(reasons, function(a, b)
        return a.Value > b.Value
    end)

    local names = {}

    for i = 1, math.min(2, #reasons) do
        table.insert(names, reasons[i].Name)
    end

    return #names > 0 and table.concat(names, " + ") or "least bad option"
end

function AIDebug.LogTurn(context)
    local actions = context.PlayerActions

    print(string.format("[AI] ===== Enemy turn %d | player king %s, %d HP, next turn %d energy, %s =====",
        context.Match.Turn,
        BoardRules.GetTileName(context.PlayerKing.Column, context.PlayerKing.Row),
        context.PlayerHealth,
        actions.Energy,
        actions.ShotCost and "can shoot" or "can't shoot"))
end

function AIDebug.LogPiece(context, piece, weights, options, choice, isMistake)
    local weightText = {}

    for _, name in ipairs(DIRECTIVES) do
        table.insert(weightText, string.format("%s %.0f", name, weights[name]))
    end

    local lines = {
        string.format("[AI] %s %d at %s (%d/%d HP) | %s | %d options",
            piece.Type, piece.Id, BoardRules.GetTileName(piece.Column, piece.Row), piece.Health, piece.MaxHealth,
            table.concat(weightText, " "), #options),
    }

    for i = 1, math.min(AIConfig.DEBUG_OPTIONS, #options) do
        local option = options[i]
        local marker = option == choice and ">" or " "

        table.insert(lines, string.format("   %s %-12s %8.1f   %s", marker, DescribeOption(option), option.Score, DescribeParts(option.Parts)))
    end

    if isMistake then
        table.insert(lines, string.format("   Picked %s: rating mistake", DescribeOption(choice)))
    else
        table.insert(lines, string.format("   Picked %s: %s", DescribeOption(choice), GetReasons(choice.Parts)))
    end

    print(table.concat(lines, "\n"))
end

function AIDebug.LogBoss(boss, decision)
    local used = {}

    for _, kind in ipairs({"Special", "Ultimate"}) do
        if decision[kind] then
            table.insert(used, kind)
        end
    end

    print(string.format("[AI] Boss %s uses: %s", boss.ClassName, #used > 0 and table.concat(used, ", ") or "nothing this turn"))
end

return AIDebug
