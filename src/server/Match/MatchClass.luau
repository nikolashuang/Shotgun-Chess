local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)
local BoardRules = require(ReplicatedStorage.Shared.Board.BoardRules)
local PieceConfig = require(ReplicatedStorage.Shared.Board.PieceConfig)
local PieceRules = require(ReplicatedStorage.Shared.Board.PieceRules)
local ShotgunRules = require(ReplicatedStorage.Shared.Combat.ShotgunRules)
local ClassConfig = require(ReplicatedStorage.Shared.Combat.ClassConfig)
local CombatConfig = require(ReplicatedStorage.Shared.Combat.CombatConfig)
local MatchConfig = require(script.Parent.MatchConfig)
local AIConfig = require(ServerScriptService.AI.AIConfig)
local KingClass = require(script.Parent.KingClass)
local PieceClass = require(script.Parent.PieceClass)
local EnemyAIService = require(ServerScriptService.AI.EnemyAIService)

local BoardRemote = ReplicatedStorage.Remotes.BoardRemote

local EnergyConfig = CombatConfig.Energy
local UltimateConfig = CombatConfig.Ultimate
local ActionCost = CombatConfig.ActionCost

local MatchClass = {}

MatchClass.__index = MatchClass

-- enemies is a list of {Type, Column, Row}; without one the match uses the test dummies
-- aiRating is a key of AIConfig.Ratings; without one the enemies never act
function MatchClass.new(player, shotgunName, className, enemies, aiRating)
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
    -- Each action can be used once per turn
    self.UsedActions = {}

    self.Energy = EnergyConfig.START_ENERGY
    self.UltimateCharge = 0

    self.Random = Random.new()

    self.AIRating = aiRating
    self.AIMistakes = 0

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
        UsedActions = self.UsedActions,
        Class = self.ClassName,
        Shotgun = self.King.ShotgunName,
        Ammo = self.King.Ammo,
        MaxAmmo = self.King.Shotgun.MaxAmmo,
        Energy = self.Energy,
        MaxEnergy = EnergyConfig.MAX_ENERGY,
        UltimateCharge = self.UltimateCharge,
        MaxUltimateCharge = UltimateConfig.MAX_CHARGE,
        KingHealth = self.King.Health,
        KingMaxHealth = self.King.MaxHealth,
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

function MatchClass:CanAct(cost, action)
    if self.Phase ~= "PlayerTurn" then return false end
    if self.UsedActions[action] then return false end
    if self.Energy < cost then return false end

    return true
end

function MatchClass:SpendEnergy(cost, action)
    self.Energy -= cost
    self.UsedActions[action] = true
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

    if self.OnEnd then
        self.OnEnd(result)
    end
end

function MatchClass:CheckDefeat()
    if self.King:IsAlive() then return false end

    self:End("Defeat")

    return true
end

-- Actions are limited by energy and once per turn each, so the turn ends through End Turn
function MatchClass:FinishEvent()
    if self:CheckVictory() then return end

    self:SendTurnState()
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
    if not self:CanAct(ActionCost.Fire, "Fire") then return end
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
    self:SpendEnergy(ActionCost.Fire, "Fire")

    self:Send("ShotFired", pellets, hitTiles, damaged, shotType)
    self:FinishEvent()
end

function MatchClass:Reload()
    if not self:CanAct(ActionCost.Reload, "Reload") then return end
    if not self.King:Reload() then return end

    self:SpendEnergy(ActionCost.Reload, "Reload")
    self:Send("Reloaded")
    self:FinishEvent()
end

--SPECIALS--

function MatchClass:Special(targetX, targetY)
    if self.ClassName == "Gunslinger" then
        self:FanTheHammer(targetX, targetY)
    end
end

-- Every shot travels the line and hits the first enemy still standing in it, or misses
function MatchClass:FanTheHammer(targetX, targetY)
    if not self:CanAct(ActionCost.Special, "Special") then return end

    local fan = ClassConfig.Classes.Gunslinger.FanTheHammer
    local _, lineTiles = ShotgunRules.GetPreciseShot(self.King.Column, self.King.Row, targetX, targetY, fan.Range)
    if not lineTiles then return end

    local lastTile = lineTiles[#lineTiles]
    local shots = {}

    for _ = 1, fan.Shots do
        local target = nil

        for _, tile in ipairs(lineTiles) do
            local piece = self:GetPieceAt(tile.Column, tile.Row)

            if piece and piece.Team ~= "White" then
                target = piece
                break
            end
        end

        if target and self.Random:NextNumber() < fan.HitChance then
            local column, row = target.Column, target.Row
            self:DamagePiece(target, fan.Damage)

            table.insert(shots, {Column = column, Row = row, Id = target.Id, Health = target.Health})
        else
            table.insert(shots, {Column = lastTile.Column, Row = lastTile.Row})
        end
    end

    self:SpendEnergy(ActionCost.Special, "Special")
    self:Send("FanFired", shots)
    self:FinishEvent()
end

function MatchClass:Summon(pieceType, column, row)
    if not table.find(PieceConfig.SUMMONABLE, pieceType) then return end

    local cost = PieceConfig.Cost[pieceType]
    if not self:CanAct(cost, "Summon") then return end

    if not BoardRules.IsOnBoard(column, row) then return end
    if BoardRules.GetDistance(self.King.Column, self.King.Row, column, row) > BoardConfig.SUMMON_RANGE then return end
    if self:IsOccupied(column, row) then return end

    local maxActive = PieceConfig.MaxActive[pieceType]
    if maxActive and self:CountPieces(pieceType, "White") >= maxActive then return end

    self:SpendEnergy(cost, "Summon")
    self:AddPiece(pieceType, "White", column, row)

    self:FinishEvent()
end

function MatchClass:Command(pieceId, column, row)
    if not self:CanAct(ActionCost.Command, "Command") then return end

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

        self:SpendEnergy(ActionCost.Command, "Command")
        self:Send("PieceAttacked", piece.Id, target.Id, target.Health)
        self:FinishEvent()
        return
    end

    if not PieceRules.IsValidMove(piece.Type, piece.Team, piece.Column, piece.Row, column, row, IsBlocked) then return end

    piece.Column = column
    piece.Row = row

    self:SpendEnergy(ActionCost.Command, "Command")
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

    local turn = self.Turn

    -- Without an AI rating the enemies are test dummies, so the enemy turn is just a timed wait
    if not self.AIRating then
        task.delay(MatchConfig.ENEMY_TURN_TIME, function()
            if not self.isActive then return end
            if self.Turn ~= turn then return end

            self:StartPlayerTurn()
        end)
        return
    end

    local plans = EnemyAIService.PlanTurn(self)

    task.delay(MatchConfig.ENEMY_THINK_TIME, function()
        if not self.isActive then return end
        if self.Turn ~= turn then return end

        self:RunEnemyPlans(plans)
        if self:CheckDefeat() then return end

        self:SendTurnState()

        task.delay(MatchConfig.ENEMY_ACTION_TIME, function()
            if not self.isActive then return end
            if self.Turn ~= turn then return end

            self:StartPlayerTurn()
        end)
    end)
end

--ENEMY ACTIONS--

-- Every plan was made against the same board, so attacks resolve first and then everyone moves at once
function MatchClass:RunEnemyPlans(plans)
    for _, plan in ipairs(plans) do
        local piece = self.Pieces[plan.PieceId]

        if piece and plan.Type == "Attack" then
            self:EnemyAttack(piece, plan.TargetColumn, plan.TargetRow)
        elseif piece and plan.Type == "Shoot" then
            self:EnemyShoot(piece, plan.AimX, plan.AimY)
        end
    end

    for _, plan in ipairs(plans) do
        local piece = self.Pieces[plan.PieceId]

        if piece and plan.Type == "Move" and not self:IsOccupied(plan.Column, plan.Row) then
            piece.Column = plan.Column
            piece.Row = plan.Row

            self:Send("PieceMoved", piece.Id, plan.Column, plan.Row)
        end
    end

    -- Stun stars come off once the stun has run out
    for _, piece in pairs(self.Pieces) do
        if piece.isStunShown and not piece:IsStunned() then
            piece.isStunShown = false
            self:Send("PieceStunned", piece.Id, false)
        end
    end
end

-- Nothing stuns yet; abilities like Hunting Strike will call this
function MatchClass:StunPiece(piece, turns)
    piece:Stun(turns)
    piece.isStunShown = true

    self:Send("PieceStunned", piece.Id, true)
end

-- Damages the player's king or a white piece on the tile; returns the health left, or nil if nothing was there
function MatchClass:DamageWhiteTile(column, row, amount)
    if self.King.Column == column and self.King.Row == row then
        self.King:TakeDamage(amount)
        return self.King.Health, nil
    end

    local target = self:GetPieceAt(column, row)
    if not target or target.Team ~= "White" then return nil end

    self:DamagePiece(target, amount)

    return target.Health, target.Id
end

function MatchClass:EnemyAttack(piece, column, row)
    if not self.King:IsAlive() then return end

    local health, targetId = self:DamageWhiteTile(column, row, PieceConfig.Damage[piece.Type])
    if not health then return end

    if targetId then
        self:Send("PieceAttacked", piece.Id, targetId, health)
    else
        self:Send("KingAttacked", piece.Id, health)
    end
end

function MatchClass:EnemyShoot(piece, aimX, aimY)
    if not self.King:IsAlive() then return end

    local weapon = ShotgunRules.GetWeapon(AIConfig.KING_SHOTGUN)

    local function IsWhiteTile(column, row)
        if self.King.Column == column and self.King.Row == row then return true end

        local target = self:GetPieceAt(column, row)
        return target ~= nil and target.Team == "White"
    end

    local pellets, hitTiles, shotType = ShotgunRules.GetFireResult(piece.Column, piece.Row, aimX, aimY, weapon, "Normal", IsWhiteTile)
    if not pellets then return end

    local damaged = {}

    for _, tile in pairs(hitTiles) do
        if IsWhiteTile(tile.Column, tile.Row) then
            local distance = BoardRules.GetDistance(piece.Column, piece.Row, tile.Column, tile.Row)
            local health, targetId = self:DamageWhiteTile(tile.Column, tile.Row, ShotgunRules.GetHitDamage(weapon, shotType, distance))

            table.insert(damaged, {Id = targetId, Column = tile.Column, Row = tile.Row, Health = health})
        end
    end

    self:Send("EnemyShotFired", piece.Id, pellets, hitTiles, damaged)
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
    self.UsedActions = {}

    self:GainEnergy()
    self:TickBleed("White")
    self:SendTurnState()
end

return MatchClass
