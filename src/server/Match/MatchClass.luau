local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)
local BoardRules = require(ReplicatedStorage.Shared.Board.BoardRules)
local PieceConfig = require(ReplicatedStorage.Shared.Board.PieceConfig)
local PieceRules = require(ReplicatedStorage.Shared.Board.PieceRules)
local ShotgunRules = require(ReplicatedStorage.Shared.Combat.ShotgunRules)
local CombatConfig = require(ReplicatedStorage.Shared.Combat.CombatConfig)
local MatchConfig = require(script.Parent.MatchConfig)
local AIConfig = require(ServerScriptService.AI.AIConfig)
local KingClass = require(script.Parent.KingClass)
local PieceClass = require(script.Parent.PieceClass)
local EnemyAIService = require(ServerScriptService.AI.EnemyAIService)

-- Each class's passive, special and ultimate live in its own component
local ClassComponents = {
    Reaper = require(script.Parent.Classes.ReaperClass),
    Hunter = require(script.Parent.Classes.HunterClass),
    Gunslinger = require(script.Parent.Classes.GunslingerClass),
    Outlaw = require(script.Parent.Classes.OutlawClass),
}

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
    self.King = KingClass.new(player, BoardConfig.KING_START_COLUMN, BoardConfig.KING_START_ROW, shotgunName, className)
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
    -- Extra damage on every hit of the next shot (Reaper's High, Ambush)
    self.NextShotBonus = 0

    self.Random = Random.new()

    self.AIRating = aiRating
    self.AIMistakes = 0

    self.isActive = true

    local component = ClassComponents[className]
    self.Ability = component and component.new(self)

    return self
end

-- Calls an optional hook on the class component; returns nil when there is no class or no hook
function MatchClass:CallAbility(method, ...)
    local ability = self.Ability
    if not ability or not ability[method] then return nil end

    return ability[method](ability, ...)
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
        NextShotBonus = self.NextShotBonus,
        Ability = self:CallAbility("GetState"),
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
    self:AddEnergy(EnergyConfig.ENERGY_PER_TURN)
end

function MatchClass:AddEnergy(amount)
    self.Energy = math.min(self.Energy + amount, EnergyConfig.MAX_ENERGY)
end

-- Damage to enemy pieces builds ultimate charge; returns true when the piece dies
function MatchClass:DamagePiece(piece, amount)
    local dealt = piece:TakeDamage(amount)

    if piece.Team ~= "White" then
        self.UltimateCharge = math.min(self.UltimateCharge + dealt * UltimateConfig.CHARGE_PER_DAMAGE, UltimateConfig.MAX_CHARGE)
    end

    if piece:IsAlive() then return false end

    self.Pieces[piece.Id] = nil

    if piece.Team ~= "White" then
        self:CallAbility("OnEnemyKilled", piece)
    end

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

-- Assimilate (Reaper) swaps the king's step for another piece's movement for this move
function MatchClass:Move(column, row)
    if self.Phase ~= "PlayerTurn" then return end
    if self.HasMoved then return end
    if self:IsOccupied(column, row) then return end

    local moveType = self:CallAbility("GetMoveType")

    if moveType then
        local function IsBlocked(blockColumn, blockRow)
            return self:IsOccupied(blockColumn, blockRow)
        end

        local king = self.King
        if not PieceRules.IsValidMove(moveType, "White", king.Column, king.Row, column, row, IsBlocked) then return end

        king:SetTile(column, row)
    elseif not self.King:MoveTo(column, row) then
        return
    end

    self.HasMoved = true
    self:CallAbility("OnKingMoved")
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

    -- Farthest first, so a knocked back enemy never blocks one behind it that is also being pushed
    table.sort(targets, function(a, b)
        return BoardRules.GetDistance(self.King.Column, self.King.Row, a.Column, a.Row) > BoardRules.GetDistance(self.King.Column, self.King.Row, b.Column, b.Row)
    end)

    -- Bonuses are worked out before anyone is hit, so a kill can't change whether a neighbor counts as isolated
    local bonuses = {}

    for _, piece in ipairs(targets) do
        bonuses[piece] = self.NextShotBonus + (self:CallAbility("GetHitBonus", piece) or 0)
    end

    self.NextShotBonus = 0

    for _, piece in ipairs(targets) do
        local distance = BoardRules.GetDistance(self.King.Column, self.King.Row, piece.Column, piece.Row)
        self:DamagePiece(piece, ShotgunRules.GetHitDamage(weapon, shotType, distance) + bonuses[piece])

        if shotType == "Knife" and piece:IsAlive() then
            piece:ApplyBleed(weapon.Knife.BleedDamage, weapon.Knife.BleedTurns)
        end

        local result = {Id = piece.Id, Health = piece.Health}

        if weapon.Knockback and piece:IsAlive() then
            result.KnockColumn, result.KnockRow = self:KnockBack(piece, weapon.Knockback)
        end

        table.insert(damaged, result)
    end

    self.King:SpendAmmo(mode)
    self:SpendEnergy(ActionCost.Fire, "Fire")

    self:Send("ShotFired", pellets, hitTiles, damaged, shotType)

    -- Knocked back enemies can land in traps
    for _, result in ipairs(damaged) do
        local piece = self.Pieces[result.Id]

        if piece and result.KnockColumn then
            self:OnEnemyMoved(piece)
        end
    end

    self:FinishEvent()
end

-- Pushes a piece straight away from the king, stopping at anything in the way; Kings can't be moved
-- Returns the new tile, or nil if the piece didn't move
function MatchClass:KnockBack(piece, tiles)
    if piece.Type == "King" then return nil end

    local stepColumn = math.sign(piece.Column - self.King.Column)
    local stepRow = math.sign(piece.Row - self.King.Row)
    local column, row = piece.Column, piece.Row

    for _ = 1, tiles do
        local nextColumn = column + stepColumn
        local nextRow = row + stepRow

        if not BoardRules.IsOnBoard(nextColumn, nextRow) then break end
        if self:IsOccupied(nextColumn, nextRow) then break end

        column, row = nextColumn, nextRow
    end

    if column == piece.Column and row == piece.Row then return nil end

    piece.Column = column
    piece.Row = row

    return column, row
end

-- Called whenever an enemy ends up on a new tile (its own move or a knockback)
function MatchClass:OnEnemyMoved(piece)
    self:CallAbility("OnEnemyMoved", piece)
end

function MatchClass:Reload()
    if not self:CanAct(ActionCost.Reload, "Reload") then return end
    if not self.King:Reload() then return end

    self:SpendEnergy(ActionCost.Reload, "Reload")
    self:Send("Reloaded")
    self:FinishEvent()
end

--CLASS ABILITIES--

-- payload is a table whose fields depend on the class; the class component validates it
function MatchClass:Special(payload)
    if not self:CanAct(ActionCost.Special, "Special") then return end
    if not self:CallAbility("Special", payload) then return end

    self:SpendEnergy(ActionCost.Special, "Special")
    self:FinishEvent()
end

-- Free once fully charged, once per turn, and spends the whole charge
function MatchClass:Ultimate(payload)
    if not self:CanAct(ActionCost.Ultimate, "Ultimate") then return end
    if self.UltimateCharge < UltimateConfig.MAX_CHARGE then return end
    if not self:CallAbility("Ultimate", payload) then return end

    self.UltimateCharge = 0
    self:SpendEnergy(ActionCost.Ultimate, "Ultimate")
    self:FinishEvent()
end

-- kind is the look of the stun ("Stars" or "Bolas")
function MatchClass:StunPiece(piece, turns, kind)
    piece:Stun(turns)
    piece.isStunShown = true

    self:Send("PieceStunned", piece.Id, true, kind or "Stars")
end

function MatchClass:IsProtected(column, row)
    return self:CallAbility("IsProtected", column, row) == true
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
        -- Traps can kill enemies on their own turn
        if self:CheckVictory() then return end

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
            self:OnEnemyMoved(piece)
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
    if self:IsProtected(column, row) then return end

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
        if IsWhiteTile(tile.Column, tile.Row) and not self:IsProtected(tile.Column, tile.Row) then
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
    self:CallAbility("OnEnemyTurnEnd")

    self.Phase = "PlayerTurn"
    self.Turn += 1
    self.HasMoved = false
    self.UsedActions = {}

    self:CallAbility("OnPlayerTurnStart")

    self:GainEnergy()
    self:TickBleed("White")
    self:SendTurnState()
end

return MatchClass
