local PieceRigClass = require(script.Parent.Parent.UI.PieceRigClass)

local board = nil
local pieces = {}

local PieceController = {}

function PieceController.Add(id, pieceType, team, column, row)
    local rig = PieceRigClass.new(board, pieceType, team)
    rig:SetTile(column, row)
    rig.Sprite:Play("Hop")

    pieces[id] = {
        Id = id,
        Type = pieceType,
        Team = team,
        Rig = rig,
    }
end

function PieceController.Move(id, column, row)
    local piece = pieces[id]
    if not piece then return end

    piece.Rig:HopTo(column, row)
end

function PieceController.ApplyDamage(id, health)
    local piece = pieces[id]
    if not piece then return end

    if health > 0 then
        piece.Rig.Sprite:Play("Hit")
        return
    end

    pieces[id] = nil
    piece.Rig:Die()
end

function PieceController.Get(id)
    return pieces[id]
end

function PieceController.GetAt(column, row)
    for _, piece in pairs(pieces) do
        if piece.Rig.Column == column and piece.Rig.Row == row then return piece end
    end

    return nil
end

function PieceController.GetTeamPieces(team)
    local teamPieces = {}

    for _, piece in pairs(pieces) do
        if piece.Team == team then
            table.insert(teamPieces, piece)
        end
    end

    return teamPieces
end

function PieceController.Clear()
    for _, piece in pairs(pieces) do
        piece.Rig:Destroy()
    end

    pieces = {}
end

local init = false
function PieceController.Init(boardFrame)
    if init then return end
    init = true

    board = boardFrame
end

return PieceController
