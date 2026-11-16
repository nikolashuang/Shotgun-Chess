local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)

local BoardRules = {}

function BoardRules.IsOnBoard(column, row)
    return column >= 1 and column <= BoardConfig.SIZE and row >= 1 and row <= BoardConfig.SIZE
end

function BoardRules.GetDistance(fromColumn, fromRow, toColumn, toRow)
    return math.max(math.abs(toColumn - fromColumn), math.abs(toRow - fromRow))
end

function BoardRules.GetTileName(column, row)
    return BoardConfig.COLUMNS:sub(column, column) .. row
end

function BoardRules.IsValidKingMove(fromColumn, fromRow, toColumn, toRow)
    if not BoardRules.IsOnBoard(toColumn, toRow) then return false end

    return BoardRules.GetDistance(fromColumn, fromRow, toColumn, toRow) == 1
end

return BoardRules
