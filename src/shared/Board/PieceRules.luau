local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardRules = require(ReplicatedStorage.Shared.Board.BoardRules)

local ORTHOGONAL = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
local DIAGONAL = {{1, 1}, {1, -1}, {-1, 1}, {-1, -1}}
local KNIGHT = {{1, 2}, {2, 1}, {2, -1}, {1, -2}, {-1, -2}, {-2, -1}, {-2, 1}, {-1, 2}}
local KING = table.move(DIAGONAL, 1, #DIAGONAL, #ORTHOGONAL + 1, table.clone(ORTHOGONAL))

local SLIDES = {
    Rook = ORTHOGONAL,
    -- Gravehollow's Rook variant
    Necromancer = ORTHOGONAL,
    Bishop = DIAGONAL,
    Queen = table.move(DIAGONAL, 1, #DIAGONAL, #ORTHOGONAL + 1, table.clone(ORTHOGONAL)),
}

local PieceRules = {}

function PieceRules.GetForward(team)
    return team == "White" and 1 or -1
end

-- isBlocked(column, row) returns true for any occupied tile
function PieceRules.GetMoves(pieceType, team, column, row, isBlocked)
    local moves = {}

    local function TryAdd(toColumn, toRow)
        if not BoardRules.IsOnBoard(toColumn, toRow) then return false end
        if isBlocked(toColumn, toRow) then return false end

        table.insert(moves, {Column = toColumn, Row = toRow})
        return true
    end

    if pieceType == "Pawn" or pieceType == "FallenPawn" then
        TryAdd(column, row + PieceRules.GetForward(team))
    elseif pieceType == "Knight" then
        for _, offset in pairs(KNIGHT) do
            TryAdd(column + offset[1], row + offset[2])
        end
    elseif pieceType == "FallenKnight" then
        for _, offset in pairs(KNIGHT) do
            TryAdd(column + offset[1], row + offset[2])
        end

        for _, offset in pairs(KING) do
            TryAdd(column + offset[1], row + offset[2])
        end
    elseif pieceType == "King" then
        for _, offset in pairs(KING) do
            TryAdd(column + offset[1], row + offset[2])
        end
    elseif SLIDES[pieceType] then
        for _, direction in pairs(SLIDES[pieceType]) do
            local toColumn = column + direction[1]
            local toRow = row + direction[2]

            while TryAdd(toColumn, toRow) do
                toColumn += direction[1]
                toRow += direction[2]
            end
        end
    end

    return moves
end

-- Enemy tiles a piece can attack, using chess capture rules
-- isEnemy(column, row) returns true for tiles holding an enemy piece
function PieceRules.GetAttacks(pieceType, team, column, row, isBlocked, isEnemy)
    local attacks = {}

    local function TryAttack(toColumn, toRow)
        if not BoardRules.IsOnBoard(toColumn, toRow) then return end
        if not isEnemy(toColumn, toRow) then return end

        table.insert(attacks, {Column = toColumn, Row = toRow})
    end

    if pieceType == "Pawn" or pieceType == "FallenPawn" then
        local forward = PieceRules.GetForward(team)
        TryAttack(column - 1, row + forward)
        TryAttack(column + 1, row + forward)
    elseif pieceType == "Knight" then
        for _, offset in pairs(KNIGHT) do
            TryAttack(column + offset[1], row + offset[2])
        end
    elseif pieceType == "FallenKnight" then
        for _, offset in pairs(KNIGHT) do
            TryAttack(column + offset[1], row + offset[2])
        end

        for _, offset in pairs(KING) do
            TryAttack(column + offset[1], row + offset[2])
        end
    elseif SLIDES[pieceType] then
        -- Sliding pieces can only hit the first piece in each direction
        for _, direction in pairs(SLIDES[pieceType]) do
            local toColumn = column + direction[1]
            local toRow = row + direction[2]

            while BoardRules.IsOnBoard(toColumn, toRow) and not isBlocked(toColumn, toRow) do
                toColumn += direction[1]
                toRow += direction[2]
            end

            TryAttack(toColumn, toRow)
        end
    end

    return attacks
end

function PieceRules.IsValidAttack(pieceType, team, column, row, toColumn, toRow, isBlocked, isEnemy)
    for _, attack in pairs(PieceRules.GetAttacks(pieceType, team, column, row, isBlocked, isEnemy)) do
        if attack.Column == toColumn and attack.Row == toRow then return true end
    end

    return false
end

function PieceRules.IsValidMove(pieceType, team, column, row, toColumn, toRow, isBlocked)
    for _, move in pairs(PieceRules.GetMoves(pieceType, team, column, row, isBlocked)) do
        if move.Column == toColumn and move.Row == toRow then return true end
    end

    return false
end

return PieceRules
