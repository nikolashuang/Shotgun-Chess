local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardRules = require(ReplicatedStorage.Shared.Board.BoardRules)
local PieceConfig = require(ReplicatedStorage.Shared.Board.PieceConfig)
local PieceRules = require(ReplicatedStorage.Shared.Board.PieceRules)

-- Attack first: finishing a piece beats chipping one, and the enemy King beats anything
local KILL_VALUE = 100
local KING_VALUE = 50

-- Moving: close the distance to the nearest enemy, but each enemy that could hit the tile weighs this many tiles
local DANGER_WEIGHT = 2
-- Enemy Kings shoot, so tiles this close to one count as dangerous
local KING_DANGER_RANGE = 3

-- Plans the campaign Fallen Knight's action for the player's side: the same priorities as the enemy pieces
-- (attack, then evade and advance), from the other side of the board
local CompanionAIService = {}

local function GetEnemies(match, piece)
    local enemies = {}

    for _, other in pairs(match.Pieces) do
        if other.Team ~= piece.Team and other:IsAlive() then
            table.insert(enemies, other)
        end
    end

    return enemies
end

-- How many enemies could hit the tile on their turn
local function GetDanger(match, enemies, column, row)
    local danger = 0

    local function IsBlocked(blockColumn, blockRow)
        return match:IsOccupied(blockColumn, blockRow)
    end

    local function IsTile(targetColumn, targetRow)
        return targetColumn == column and targetRow == row
    end

    for _, enemy in ipairs(enemies) do
        if enemy.Type == "King" then
            if BoardRules.GetDistance(enemy.Column, enemy.Row, column, row) <= KING_DANGER_RANGE then
                danger += 1
            end
        elseif PieceRules.IsValidAttack(enemy.Type, enemy.Team, enemy.Column, enemy.Row, column, row, IsBlocked, IsTile) then
            danger += 1
        end
    end

    return danger
end

local function GetNearestDistance(enemies, column, row)
    local nearest = math.huge

    for _, enemy in ipairs(enemies) do
        nearest = math.min(nearest, BoardRules.GetDistance(enemy.Column, enemy.Row, column, row))
    end

    return nearest
end

-- Returns {Type = "Attack" or "Move", Column, Row}, or nil to stay put
function CompanionAIService.Plan(match, piece)
    local enemies = GetEnemies(match, piece)
    if #enemies == 0 then return nil end

    local function IsBlocked(column, row)
        return match:IsOccupied(column, row)
    end

    local function IsEnemy(column, row)
        local target = match:GetPieceAt(column, row)
        return target ~= nil and target.Team ~= piece.Team and not match:IsProtected(column, row, match.Sides.White)
    end

    local damage = PieceConfig.Damage[piece.Type]
    local bestAttack, bestValue = nil, -math.huge

    for _, attack in pairs(PieceRules.GetAttacks(piece.Type, piece.Team, piece.Column, piece.Row, IsBlocked, IsEnemy)) do
        local target = match:GetPieceAt(attack.Column, attack.Row)
        local value = -target.Health

        if target.Health <= damage then
            value += KILL_VALUE
        end

        if target.Type == "King" then
            value += KING_VALUE
        end

        if value > bestValue then
            bestAttack, bestValue = attack, value
        end
    end

    if bestAttack then
        return {Type = "Attack", Column = bestAttack.Column, Row = bestAttack.Row}
    end

    local stayScore = -GetNearestDistance(enemies, piece.Column, piece.Row) - GetDanger(match, enemies, piece.Column, piece.Row) * DANGER_WEIGHT
    local bestMove, bestScore = nil, stayScore

    for _, move in pairs(PieceRules.GetMoves(piece.Type, piece.Team, piece.Column, piece.Row, IsBlocked)) do
        local score = -GetNearestDistance(enemies, move.Column, move.Row) - GetDanger(match, enemies, move.Column, move.Row) * DANGER_WEIGHT

        if score > bestScore then
            bestMove, bestScore = move, score
        end
    end

    if not bestMove then return nil end

    return {Type = "Move", Column = bestMove.Column, Row = bestMove.Row}
end

return CompanionAIService
