local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)
local ShotgunConfig = require(ReplicatedStorage.Shared.Combat.ShotgunConfig)

local BoardRules = {}

local function Direction(value)
    if value < 0 then return -1 end
    return 1
end

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

function BoardRules.GetShotgunArea(kingColumn, kingRow, targetColumn, targetRow)
    if not BoardRules.IsOnBoard(targetColumn, targetRow) then return nil end

    local distance = BoardRules.GetDistance(kingColumn, kingRow, targetColumn, targetRow)
    if distance < 1 or distance > ShotgunConfig.MAX_RANGE then return nil end

    local spread = ShotgunConfig.SPREAD_BY_DISTANCE[distance]
    local columnStep = Direction(targetColumn - kingColumn)
    local rowStep = Direction(targetRow - kingRow)

    -- Odd spreads center on the target, even spreads grow away from the king
    local offset = math.floor((spread - 1) / 2)

    local tiles = {}

    for i = 0, spread - 1 do
        for j = 0, spread - 1 do
            local column = targetColumn + (i - offset) * columnStep
            local row = targetRow + (j - offset) * rowStep

            if BoardRules.IsOnBoard(column, row) and not (column == kingColumn and row == kingRow) then
                table.insert(tiles, {Column = column, Row = row})
            end
        end
    end

    return tiles
end

return BoardRules
