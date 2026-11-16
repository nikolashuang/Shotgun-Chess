local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)
local BoardRules = require(ReplicatedStorage.Shared.Board.BoardRules)
local PieceConfig = require(ReplicatedStorage.Shared.Board.PieceConfig)
local PieceRules = require(ReplicatedStorage.Shared.Board.PieceRules)
local ShotgunRules = require(ReplicatedStorage.Shared.Combat.ShotgunRules)
local MatchConfig = require(script.Parent.MatchConfig)
local KingClass = require(script.Parent.KingClass)
local PieceClass = require(script.Parent.PieceClass)

local BoardRemote = ReplicatedStorage.Remotes.BoardRemote

local MatchClass = {}

MatchClass.__index = MatchClass

function MatchClass.new(player)
    local self = setmetatable({}, MatchClass)

    self.Player = player
    self.King = KingClass.new(player, BoardConfig.KING_START_COLUMN, BoardConfig.KING_START_ROW)

    self.Pieces = {}
    self.NextPieceId = 1

    self.Phase = "PlayerTurn"
    self.Turn = 1
    self.HasMoved = false
    self.HasActed = false

    self.InterruptCards = table.clone(MatchConfig.INTERRUPT_CARDS)
    self.InterruptUsed = false

    self.isActive = true

    return self
end

function MatchClass:Send(action, ...)
    BoardRemote:FireClient(self.Player, action, ...)
end

function MatchClass:SendTurnState()
    self:Send("TurnState", {
        Phase = self.Phase,
        Turn = self.Turn,
        HasMoved = self.HasMoved,
        HasActed = self.HasActed,
        InterruptCards = self.InterruptCards,
        CanInterrupt = self.Phase == "EnemyTurn" and not self.InterruptUsed,
    })
end

function MatchClass:Start()
    self:Send("MatchStarted")
    self:Send("KingMoved", self.King.Column, self.King.Row)

    for _, dummy in ipairs(MatchConfig.TEST_DUMMIES) do
        self:AddPiece(dummy.Type, "Black", dummy.Column, dummy.Row)
    end

    self:SendTurnState()
end

function MatchClass:Destroy()
    self.isActive = false
end

function MatchClass:GetPieceAt(column, row)
    for _, piece in pairs(self.Pieces) do
        if piece.Column == column and piece.Row == row then return piece end
    end

    return nil
end

function MatchClass:IsOccupied(column, row)
    if self.King.Column == column and self.King.Row == row then return true end

    return self:GetPieceAt(column, row) ~= nil
end

function MatchClass:AddPiece(pieceType, team, column, row)
    local piece = PieceClass.new(self.NextPieceId, pieceType, team, column, row)
    self.NextPieceId += 1
    self.Pieces[piece.Id] = piece

    self:Send("PieceAdded", piece.Id, piece.Type, piece.Team, piece.Column, piece.Row)

    return piece
end

function MatchClass:CanAct()
    if self.Phase ~= "PlayerTurn" then return false end
    if self.HasActed then return false end

    return true
end

-- Ends the turn once both the movement and action events are used
function MatchClass:FinishEvent()
    if self.HasMoved and self.HasActed then
        self:StartEnemyTurn()
    else
        self:SendTurnState()
    end
end

--MOVEMENT EVENT--

function MatchClass:Move(column, row)
    if self.Phase ~= "PlayerTurn" then return end
    if self.HasMoved then return end
    if self:IsOccupied(column, row) then return end
    if not self.King:MoveTo(column, row) then return end

    self.HasMoved = true
    self:Send("KingMoved", column, row)
    self:FinishEvent()
end

--ACTION EVENTS--

function MatchClass:Fire(targetX, targetY)
    if not self:CanAct() then return end

    local function IsEnemyTile(column, row)
        local piece = self:GetPieceAt(column, row)
        return piece ~= nil and piece.Team ~= "White"
    end

    local pellets, hitTiles = self.King:Fire(targetX, targetY, IsEnemyTile)
    if not pellets then return end

    local damaged = {}

    for _, tile in pairs(hitTiles) do
        local piece = self:GetPieceAt(tile.Column, tile.Row)

        if piece and piece.Team ~= "White" then
            local distance = BoardRules.GetDistance(self.King.Column, self.King.Row, piece.Column, piece.Row)
            piece:TakeDamage(ShotgunRules.GetDamage(distance))
            table.insert(damaged, {Id = piece.Id, Health = piece.Health})

            if not piece:IsAlive() then
                self.Pieces[piece.Id] = nil
            end
        end
    end

    self.HasActed = true
    self:Send("ShotFired", pellets, hitTiles, damaged)
    self:FinishEvent()
end

function MatchClass:Summon(pieceType, column, row)
    if not self:CanAct() then return end
    if not table.find(PieceConfig.SUMMONABLE, pieceType) then return end
    if not BoardRules.IsOnBoard(column, row) then return end
    if BoardRules.GetDistance(self.King.Column, self.King.Row, column, row) > BoardConfig.SUMMON_RANGE then return end
    if self:IsOccupied(column, row) then return end

    self:AddPiece(pieceType, "White", column, row)

    self.HasActed = true
    self:FinishEvent()
end

function MatchClass:Command(pieceId, column, row)
    if not self:CanAct() then return end

    local piece = self.Pieces[pieceId]
    if not piece then return end
    if piece.Team ~= "White" then return end

    local function IsBlocked(blockColumn, blockRow)
        return self:IsOccupied(blockColumn, blockRow)
    end

    if not PieceRules.IsValidMove(piece.Type, piece.Team, piece.Column, piece.Row, column, row, IsBlocked) then return end

    piece.Column = column
    piece.Row = row

    self.HasActed = true
    self:Send("PieceMoved", piece.Id, column, row)
    self:FinishEvent()
end

--TURNS--

function MatchClass:EndTurn()
    if self.Phase ~= "PlayerTurn" then return end

    self:StartEnemyTurn()
end

function MatchClass:StartEnemyTurn()
    self.Phase = "EnemyTurn"
    self.InterruptUsed = false
    self:SendTurnState()

    -- Dummies don't act, so the enemy turn only opens the interrupt window
    local turn = self.Turn

    task.delay(MatchConfig.ENEMY_TURN_TIME, function()
        if not self.isActive then return end
        if self.Turn ~= turn then return end

        self:StartPlayerTurn()
    end)
end

function MatchClass:StartPlayerTurn()
    self.Phase = "PlayerTurn"
    self.Turn += 1
    self.HasMoved = false
    self.HasActed = false
    self:SendTurnState()
end

function MatchClass:UseInterrupt(slot)
    if self.Phase ~= "EnemyTurn" then return end
    if self.InterruptUsed then return end

    local card = self.InterruptCards[slot]
    if not card then return end

    self.InterruptCards[slot] = false
    self.InterruptUsed = true

    self:Send("InterruptUsed", slot, card)
    self:SendTurnState()
end

return MatchClass
