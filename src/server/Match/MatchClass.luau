local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)
local BoardRules = require(ReplicatedStorage.Shared.Board.BoardRules)
local PieceConfig = require(ReplicatedStorage.Shared.Board.PieceConfig)
local PieceRules = require(ReplicatedStorage.Shared.Board.PieceRules)
local ShotgunRules = require(ReplicatedStorage.Shared.Combat.ShotgunRules)
local CombatConfig = require(ReplicatedStorage.Shared.Combat.CombatConfig)
local MatchConfig = require(script.Parent.MatchConfig)
local KingClass = require(script.Parent.KingClass)
local PieceClass = require(script.Parent.PieceClass)

local BoardRemote = ReplicatedStorage.Remotes.BoardRemote

local EnergyConfig = CombatConfig.Energy
local UltimateConfig = CombatConfig.Ultimate

local MatchClass = {}

MatchClass.__index = MatchClass

-- enemies is a list of {Type, Column, Row}; without one the match uses the test dummies
function MatchClass.new(player, shotgunName, className, enemies)
    local self = setmetatable({}, MatchClass)

    self.Player = player
    self.King = KingClass.new(player, BoardConfig.KING_START_COLUMN, BoardConfig.KING_START_ROW, shotgunName)
    self.ClassName = className
    self.Enemies = enemies or MatchConfig.TEST_DUMMIES

    -- Set by whoever owns the match (campaign) to be told the result; matches without it never end
    self.OnEnd = nil
    self.HasEnemyKing = false

    self.Pieces = {}
    self.NextPieceId = 1

    self.Phase = "PlayerTurn"
    self.Turn = 1
    self.HasMoved = false
    self.HasActed = false

    self.Energy = EnergyConfig.START_ENERGY
    self.UltimateCharge = 0

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
        Class = self.ClassName,
        Shotgun = self.King.ShotgunName,
        Ammo = self.King.Ammo,
        MaxAmmo = self.King.Shotgun.MaxAmmo,
        Energy = self.Energy,
        MaxEnergy = EnergyConfig.MAX_ENERGY,
        UltimateCharge = self.UltimateCharge,
        MaxUltimateCharge = UltimateConfig.MAX_CHARGE,
    })
end

function MatchClass:Start()
    self:Send("MatchStarted")
    self:Send("KingMoved", self.King.Column, self.King.Row)

    for _, enemy in ipairs(self.Enemies) do
        self:AddPiece(enemy.Type, "Black", enemy.Column, enemy.Row)
    end

    self.HasEnemyKing = self:CountPieces("King", "Black") > 0

    self:GainEnergy()
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

    self:Send("PieceAdded", piece.Id, piece.Type, piece.Team, piece.Column, piece.Row, piece.Health, piece.MaxHealth)

    return piece
end

function MatchClass:CountPieces(pieceType, team)
    local count = 0

    for _, piece in pairs(self.Pieces) do
        if piece.Type == pieceType and piece.Team == team then
            count += 1
        end
    end

    return count
end

function MatchClass:GainEnergy()
    self.Energy = math.min(self.Energy + EnergyConfig.ENERGY_PER_TURN, EnergyConfig.MAX_ENERGY)
end

-- Damage to enemy pieces builds ultimate charge; returns true when the piece dies
function MatchClass:DamagePiece(piece, amount)
    local dealt = piece:TakeDamage(amount)

    if piece.Team ~= "White" then
        self.UltimateCharge = math.min(self.UltimateCharge + dealt * UltimateConfig.CHARGE_PER_DAMAGE, UltimateConfig.MAX_CHARGE)
    end

    if piece:IsAlive() then return false end

    self.Pieces[piece.Id] = nil

    return true
end

function MatchClass:CanAct()
    if self.Phase ~= "PlayerTurn" then return false end
    if self.HasActed then return false end

    return true
end

-- Armies with a King are beaten by killing it, armies without one by clearing the board
function MatchClass:CheckVictory()
    if not self.OnEnd then return false end

    local isWon = false

    if self.HasEnemyKing then
        isWon = self:CountPieces("King", "Black") == 0
    else
        isWon = self:CountTeam("Black") == 0
    end

    if not isWon then return false end

    self:End("Victory")

    return true
end

function MatchClass:CountTeam(team)
    local count = 0

    for _, piece in pairs(self.Pieces) do
        if piece.Team == team then
            count += 1
        end
    end

    return count
end

function MatchClass:End(result)
    self.isActive = false
    self.Phase = "Over"
    self:SendTurnState()

    self.OnEnd(result)
end

-- Ends the turn once both the movement and action events are used
function MatchClass:FinishEvent()
    if self:CheckVictory() then return end

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

function MatchClass:Fire(targetX, targetY, mode)
    if not self:CanAct() then return end
    if not self.King:CanFire(mode) then return end

    local function IsEnemyTile(column, row)
        local piece = self:GetPieceAt(column, row)
        return piece ~= nil and piece.Team ~= "White"
    end

    local pellets, hitTiles, shotType = self.King:GetShot(targetX, targetY, mode, IsEnemyTile)
    if not pellets then return end

    local targets = {}

    for _, tile in pairs(hitTiles) do
        if IsEnemyTile(tile.Column, tile.Row) then
            table.insert(targets, self:GetPieceAt(tile.Column, tile.Row))
        end
    end

    -- The knife can only be swung at an adjacent enemy
    if shotType == "Knife" and #targets == 0 then return end

    local weapon = self.King.Shotgun
    local damaged = {}

    for _, piece in pairs(targets) do
        local distance = BoardRules.GetDistance(self.King.Column, self.King.Row, piece.Column, piece.Row)
        self:DamagePiece(piece, ShotgunRules.GetHitDamage(weapon, shotType, distance))

        if shotType == "Knife" and piece:IsAlive() then
            piece:ApplyBleed(weapon.Knife.BleedDamage, weapon.Knife.BleedTurns)
        end

        table.insert(damaged, {Id = piece.Id, Health = piece.Health})
    end

    self.King:SpendAmmo(mode)

    self.HasActed = true
    self:Send("ShotFired", pellets, hitTiles, damaged, shotType)
    self:FinishEvent()
end

function MatchClass:Reload()
    if not self:CanAct() then return end
    if not self.King:Reload() then return end

    self.HasActed = true
    self:Send("Reloaded")
    self:FinishEvent()
end

function MatchClass:Summon(pieceType, column, row)
    if not self:CanAct() then return end
    if not table.find(PieceConfig.SUMMONABLE, pieceType) then return end
    if not BoardRules.IsOnBoard(column, row) then return end
    if BoardRules.GetDistance(self.King.Column, self.King.Row, column, row) > BoardConfig.SUMMON_RANGE then return end
    if self:IsOccupied(column, row) then return end

    local cost = PieceConfig.Cost[pieceType]
    if self.Energy < cost then return end

    local maxActive = PieceConfig.MaxActive[pieceType]
    if maxActive and self:CountPieces(pieceType, "White") >= maxActive then return end

    self.Energy -= cost
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

    -- Commanding onto an enemy attacks it; the attacker stays on its own square
    local target = self:GetPieceAt(column, row)
    if target then
        if target.Team == piece.Team then return end

        local function IsEnemy(enemyColumn, enemyRow)
            local enemy = self:GetPieceAt(enemyColumn, enemyRow)
            return enemy ~= nil and enemy.Team ~= piece.Team
        end

        if not PieceRules.IsValidAttack(piece.Type, piece.Team, piece.Column, piece.Row, column, row, IsBlocked, IsEnemy) then return end

        self:DamagePiece(target, PieceConfig.Damage[piece.Type])

        self.HasActed = true
        self:Send("PieceAttacked", piece.Id, target.Id, target.Health)
        self:FinishEvent()
        return
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

    self:TickBleed("Black")
    if self:CheckVictory() then return end

    self:SendTurnState()

    -- Dummies don't act, so the enemy turn is just a timed wait
    local turn = self.Turn

    task.delay(MatchConfig.ENEMY_TURN_TIME, function()
        if not self.isActive then return end
        if self.Turn ~= turn then return end

        self:StartPlayerTurn()
    end)
end

-- Bleeding pieces lose health at the start of their team's turn
function MatchClass:TickBleed(team)
    for _, piece in pairs(self.Pieces) do
        if piece.Team == team and piece:IsBleeding() then
            self:DamagePiece(piece, piece:TickBleed())
            self:Send("PieceDamaged", piece.Id, piece.Health)
        end
    end
end

function MatchClass:StartPlayerTurn()
    self.Phase = "PlayerTurn"
    self.Turn += 1
    self.HasMoved = false
    self.HasActed = false

    self:GainEnergy()
    self:TickBleed("White")
    self:SendTurnState()
end

return MatchClass
