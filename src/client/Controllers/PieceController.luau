local PieceRigClass = require(script.Parent.Parent.UI.PieceRigClass)

local board = nil
local pieces = {}

local PieceController = {}

function PieceController.Add(id, pieceType, team, column, row, health, maxHealth)
    local rig = PieceRigClass.new(board, pieceType, team)
    rig:SetTile(column, row)
    rig:SetHealth(health, maxHealth)
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

    piece.Rig:SetHealth(health)

    if health > 0 then
        piece.Rig.Sprite:Play("Hit")
        piece.Rig:ShowHealth()
        piece.Rig:HideHealth()
        return
    end

    pieces[id] = nil
    piece.Rig:Die()
end

-- The attacker lunges at the target and returns to its tile
-- Survivors flash like any hit, killed pieces are knocked over and crumble
-- isCapture: the attacker takes the killed piece's square instead of returning (summoned pieces)
function PieceController.Attack(attackerId, targetId, health, isCapture)
    local attacker = pieces[attackerId]
    local target = pieces[targetId]

    if not attacker or not target then
        PieceController.ApplyDamage(targetId, health)
        return
    end

    if health > 0 then
        attacker.Rig:Lunge(target.Rig.Column, target.Rig.Row, function()
            PieceController.ApplyDamage(targetId, health)
        end)
        return
    end

    pieces[targetId] = nil

    local direction = target.Rig.Column < attacker.Rig.Column and -1 or 1

    local targetColumn, targetRow = target.Rig.Column, target.Rig.Row

    attacker.Rig:Lunge(targetColumn, targetRow, function()
        target.Rig:SetHealth(health)
        target.Rig:KnockOver(direction)

        -- Lunge hops back to the rig's tile, so changing it lands the attacker on the captured square
        if isCapture then
            attacker.Rig.Column = targetColumn
            attacker.Rig.Row = targetRow
        end
    end)
end

function PieceController.SetStunned(id, isStunned, kind)
    local piece = pieces[id]
    if not piece then return end

    piece.Rig:SetStunned(isStunned, kind)
end

function PieceController.SetMarked(id, isMarked)
    local piece = pieces[id]
    if not piece then return end

    piece.Rig:SetMarked(isMarked)
end

-- Only one piece shows the command arrow at a time; nil hides it
local arrowPieceId = nil

function PieceController.SetArrow(id)
    if id == arrowPieceId then return end

    local previous = pieces[arrowPieceId]
    if previous then
        previous.Rig:SetArrow(false)
    end

    arrowPieceId = id

    local piece = pieces[id]
    if piece then
        piece.Rig:SetArrow(true)
    end
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
    arrowPieceId = nil
end

local init = false
function PieceController.Init(boardFrame)
    if init then return end
    init = true

    board = boardFrame
end

return PieceController
