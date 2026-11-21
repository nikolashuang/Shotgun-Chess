local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)
local BoardRules = require(ReplicatedStorage.Shared.Board.BoardRules)
local PieceConfig = require(ReplicatedStorage.Shared.Board.PieceConfig)
local PieceRules = require(ReplicatedStorage.Shared.Board.PieceRules)
local ShotgunRules = require(ReplicatedStorage.Shared.Combat.ShotgunRules)
local ShotgunConfig = require(ReplicatedStorage.Shared.Combat.ShotgunConfig)
local CombatConfig = require(ReplicatedStorage.Shared.Combat.CombatConfig)
local DuelConfig = require(ReplicatedStorage.Shared.Duel.DuelConfig)
local MatchConfig = require(script.Parent.MatchConfig)
local MirrorRules = require(script.Parent.MirrorRules)
local KingClass = require(script.Parent.KingClass)
local PieceClass = require(script.Parent.PieceClass)
local SideClass = require(script.Parent.SideClass)
local EnemyAIService = require(ServerScriptService.AI.EnemyAIService)
local PracticeAIService = require(ServerScriptService.AI.PracticeAIService)

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

    self.Enemies = enemies or MatchConfig.TEST_DUMMIES

    -- Set by whoever owns the match to be told the result; campaign matches without it never end
    self.OnEnd = nil
    self.HasEnemyKing = false

    self.Pieces = {}
    self.NextPieceId = 1
    -- Reaper souls, numbered across both sides so the rival's never clash with your own
    self.NextSoulId = 1

    self.Sides = {}

    -- Phase is "PlayerTurn" while ActiveTeam's player acts, "EnemyTurn" while the AI acts, or "Over"
    self.Phase = "PlayerTurn"
    self.ActiveTeam = "White"
    self.Turn = 1
    self.TurnStartedAt = 0

    self.Random = Random.new()

    self.AIRating = aiRating
    self.AIMistakes = 0

    self.isDuel = false
    self.isActive = true
    -- A stunned duel King's turn is being skipped
    self.isSkipping = false

    local side = self:AddSide(player, "White", BoardConfig.KING_START_COLUMN, BoardConfig.KING_START_ROW, shotgunName, className)

    -- The enemy AI reads the player and their king straight off the match
    self.Player = player
    self.King = side.King

    return self
end

-- Black starts on the White king's tile turned 180 degrees, so both see the same opening
-- A side with no player (Practice) is played by PracticeAIService
function MatchClass.newDuel(whitePlayer, whiteShotgun, whiteClass, blackPlayer, blackShotgun, blackClass)
    local self = MatchClass.new(whitePlayer, whiteShotgun, whiteClass, {})

    self.isDuel = true

    local column = MirrorRules.Tile(BoardConfig.KING_START_COLUMN)
    local row = MirrorRules.Tile(BoardConfig.KING_START_ROW)
    self:AddSide(blackPlayer, "Black", column, row, blackShotgun, blackClass)

    for _, side in pairs(self.Sides) do
        side.Clock = DuelConfig.CLOCK

        -- Duel kings are board pieces too, so shots, commands and traps can reach them
        side.King.Id = self.NextPieceId
        self.NextPieceId += 1
        self.Pieces[side.King.Id] = side.King
    end

    return self
end

function MatchClass:AddSide(player, team, column, row, shotgunName, className)
    local king = KingClass.new(player, column, row, shotgunName, className, team)
    local side = SideClass.new(self, player, team, king, className)

    local component = ClassComponents[className]
    side.Ability = component and component.new(side)

    self.Sides[team] = side

    return side
end

function MatchClass:GetSide(player)
    for _, side in pairs(self.Sides) do
        if side.Player == player then return side end
    end

    return nil
end

-- nil in campaign matches, where the other team is the AI
function MatchClass:GetOpponent(side)
    return self.Sides[side.EnemyTeam]
end

-- The side whose class reacts to things happening to this team (its traps, its bleeds)
function MatchClass:GetDefender(team)
    return self.Sides[team == "White" and "Black" or "White"]
end

-- Calls an optional hook on a side's class component; returns nil when there is no class or no hook
function MatchClass:CallAbility(side, method, ...)
    local ability = side and side.Ability
    if not ability or not ability[method] then return nil end

    return ability[method](ability, ...)
end

--MESSAGES--

-- The Black player gets every event turned around so their own king is at the bottom as White
function MatchClass:SendTo(side, action, ...)
    if not side or not side.Player then return end

    if side.Team == "Black" then
        BoardRemote:FireClient(side.Player, action, MirrorRules.Event(action, table.pack(...)))
    else
        BoardRemote:FireClient(side.Player, action, ...)
    end
end

function MatchClass:SendAll(action, ...)
    for _, side in pairs(self.Sides) do
        self:SendTo(side, action, ...)
    end
end

-- Each player sees their own king through King events and the other king as a piece
function MatchClass:SendKingMoved(side, ownAction)
    local king = side.King

    side:Send(ownAction, king.Column, king.Row)

    local opponent = self:GetOpponent(side)
    if opponent then
        self:SendTo(opponent, "PieceMoved", king.Id, king.Column, king.Row)
    end
end

-- Health updates for everyone except exceptSide, who already saw the hit through their own event
function MatchClass:ShowDamage(unit, exceptSide)
    for _, side in pairs(self.Sides) do
        if side == exceptSide then continue end

        if unit == side.King then
            side:Send("KingAttacked", 0, unit.Health)
        else
            self:SendTo(side, "PieceDamaged", unit.Id, unit.Health)
        end
    end
end

function MatchClass:SendAttack(piece, target, isCapture)
    for _, side in pairs(self.Sides) do
        if target == side.King then
            side:Send("KingAttacked", piece.Id, target.Health)
        else
            self:SendTo(side, "PieceAttacked", piece.Id, target.Id, target.Health, isCapture)
        end
    end
end

-- Seconds left on a side's clock, counting the turn in progress
function MatchClass:GetClock(side)
    if not side or not side.Clock then return nil end
    if not self:IsSideTurn(side) then return side.Clock end
    if self.isSkipping then return side.Clock end

    return math.max(side.Clock - (time() - self.TurnStartedAt), 0)
end

function MatchClass:GetTurnState(side)
    local phase = "EnemyTurn"

    if self.Phase == "Over" then
        phase = "Over"
    elseif self:IsSideTurn(side) and self.isSkipping then
        phase = "Stunned"
    elseif self:IsSideTurn(side) then
        phase = "PlayerTurn"
    end

    return {
        Phase = phase,
        -- Duel turns count once both players have gone
        Turn = self.isDuel and math.ceil(self.Turn / 2) or self.Turn,
        HasMoved = side.HasMoved,
        UsedActions = side.UsedActions,
        Class = side.ClassName,
        Shotgun = side.King.ShotgunName,
        Ammo = side.King.Ammo,
        MaxAmmo = side.King.Shotgun.MaxAmmo,
        Energy = side.Energy,
        MaxEnergy = EnergyConfig.MAX_ENERGY,
        UltimateCharge = side.UltimateCharge,
        MaxUltimateCharge = UltimateConfig.MAX_CHARGE,
        KingHealth = side.King.Health,
        KingMaxHealth = side.King.MaxHealth,
        KingStunned = side.King:IsStunned(),
        NextShotBonus = side.NextShotBonus,
        Ability = self:CallAbility(side, "GetState"),
        Clock = self:GetClock(side),
        EnemyClock = self:GetClock(self:GetOpponent(side)),
    }
end

function MatchClass:SendTurnState()
    for _, side in pairs(self.Sides) do
        side:Send("TurnState", self:GetTurnState(side))
    end
end

--SETUP--

function MatchClass:Start()
    self:SendAll("MatchStarted")

    for _, side in pairs(self.Sides) do
        local king = side.King
        side:Send("KingMoved", king.Column, king.Row)

        -- The rival King comes with its shotgun so the other player can see what it is running
        local opponent = self:GetOpponent(side)
        if opponent then
            self:SendTo(opponent, "PieceAdded", king.Id, king.Type, king.Team, king.Column, king.Row, king.Health, king.MaxHealth, king.ShotgunName)
        end
    end

    for _, enemy in ipairs(self.Enemies) do
        self:AddPiece(enemy.Type, "Black", enemy.Column, enemy.Row)
    end

    self.HasEnemyKing = self:CountPieces("King", "Black") > 0

    local white = self.Sides.White
    white:GainEnergy()

    self.TurnStartedAt = time()
    self:SendTurnState()

    if self.isDuel then
        self:StartClock(white)
        self:StartAITurn(white)
    end
end

function MatchClass:Destroy()
    self.isActive = false
end

-- Leaving a duel early forfeits it
function MatchClass:Leave(player)
    local side = self:GetSide(player)

    if self.isDuel and self.isActive and side then
        self:EndDuel(self:GetOpponent(side), "Forfeit")
    end

    self:Destroy()
end

--BOARD--

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

function MatchClass:IsSideTurn(side)
    return self.Phase == "PlayerTurn" and self.ActiveTeam == side.Team
end

function MatchClass:AddPiece(pieceType, team, column, row)
    local piece = PieceClass.new(self.NextPieceId, pieceType, team, column, row)
    self.NextPieceId += 1
    self.Pieces[piece.Id] = piece

    self:SendAll("PieceAdded", piece.Id, piece.Type, piece.Team, piece.Column, piece.Row, piece.Health, piece.MaxHealth)

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

-- attacker is the side dealing the damage, if any; hurting the other team builds its ultimate charge
-- Returns true when the piece dies
function MatchClass:DamagePiece(piece, amount, attacker)
    local dealt = piece:TakeDamage(amount)
    local isEnemy = attacker ~= nil and piece.Team ~= attacker.Team

    if isEnemy then
        attacker.UltimateCharge = math.min(attacker.UltimateCharge + dealt * UltimateConfig.CHARGE_PER_DAMAGE, UltimateConfig.MAX_CHARGE)
    end

    if piece:IsAlive() then return false end

    self.Pieces[piece.Id] = nil

    if isEnemy then
        self:CallAbility(attacker, "OnEnemyKilled", piece)
    end

    for _, side in pairs(self.Sides) do
        self:CallAbility(side, "OnPieceKilled", piece)
    end

    return true
end

function MatchClass:CanAct(side, cost, action)
    if not self:IsSideTurn(side) then return false end
    if self.isSkipping then return false end
    if side.UsedActions[action] then return false end
    if side.Energy < cost then return false end

    return true
end

function MatchClass:SpendEnergy(side, cost, action)
    side.Energy -= cost
    side.UsedActions[action] = true
end

-- Smoke belongs to the side being attacked; AI attacks (no attacker) are against White
function MatchClass:IsProtected(column, row, attacker)
    local defender = attacker and self:GetOpponent(attacker) or self.Sides.White

    return self:CallAbility(defender, "IsProtected", column, row) == true
end

-- Chance a shotgun blast lands on the tile; lower inside the Outlaw's smoke
function MatchClass:GetShotHitChance(column, row, attacker)
    local defender = attacker and self:GetOpponent(attacker) or self.Sides.White

    return self:CallAbility(defender, "GetShotHitChance", column, row) or 1
end

-- Called whenever a piece or king ends up on a new tile; the other team's traps can catch it
function MatchClass:OnUnitMoved(piece)
    self:CallAbility(self:GetDefender(piece.Team), "OnEnemyMoved", piece)
end

-- kind is the look of the stun ("Stars" or "Bolas"); bolas are only thrown on the attacker's screen
function MatchClass:StunPiece(piece, turns, kind, attacker)
    piece:Stun(turns)
    piece.isStunShown = true
    -- A stun landed on its own side's turn (walking into a trap) starts counting from the next one
    piece.StunnedOnTurn = self.Turn

    for _, side in pairs(self.Sides) do
        -- A player sees their own stunned King through its own event, since it isn't one of their pieces
        if piece == side.King then
            side:Send("KingStunned", true, kind or "Stars")
            continue
        end

        local look = kind or "Stars"
        if look == "Bolas" and side ~= attacker then
            look = "Stars"
        end

        self:SendTo(side, "PieceStunned", piece.Id, true, look)
    end
end

-- Stun stars come off once the stun has run out
function MatchClass:ClearEndedStuns()
    for _, piece in pairs(self.Pieces) do
        if piece.isStunShown and not piece:IsStunned() then
            piece.isStunShown = false

            for _, side in pairs(self.Sides) do
                if piece == side.King then
                    side:Send("KingStunned", false)
                else
                    self:SendTo(side, "PieceStunned", piece.Id, false)
                end
            end
        end
    end
end

--RESULTS--

-- Armies with a King are beaten by killing it, armies without one by clearing the board
function MatchClass:CheckVictory()
    if self.isDuel then return self:CheckDuelOver() end
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

function MatchClass:CheckDuelOver()
    for _, side in pairs(self.Sides) do
        if not side.King:IsAlive() then
            self:EndDuel(self:GetOpponent(side), "KingKilled")
            return true
        end
    end

    return false
end

-- reason is "KingKilled", "Timeout" or "Forfeit"
function MatchClass:EndDuel(winner, reason)
    if not self.isActive then return end

    self.isActive = false
    self.Phase = "Over"
    self:SendTurnState()

    if self.OnEnd then
        self.OnEnd(winner, reason)
    end
end

-- Actions are limited by energy and once per turn each, so the turn ends through End Turn
function MatchClass:FinishEvent()
    if self:CheckVictory() then return end
    -- A King that walks into a trap loses the rest of this turn (and the next one, see EndDuelTurn)
    if self:CheckStunSkip(self.Sides[self.ActiveTeam]) then return end

    self:SendTurnState()
end

-- A stunned duel King loses its turn: it shows as stunned for a moment, then play passes on
-- Its clock stops while the turn is skipped
function MatchClass:CheckStunSkip(side)
    if not self.isDuel then return false end
    if self.isSkipping then return true end
    if not side.King:IsStunned() then return false end

    side.Clock = self:GetClock(side)
    self.isSkipping = true
    self:SendTurnState()

    local turn = self.Turn

    task.delay(MatchConfig.STUN_SKIP_TIME, function()
        if not self.isActive then return end
        if self.Turn ~= turn then return end

        self:EndDuelTurn(side)
    end)

    return true
end

--MOVEMENT EVENT--

-- Assimilate (Reaper) gives a bonus move with another piece's movement; it doesn't use up the turn's move
function MatchClass:Move(side, column, row)
    if not self:IsSideTurn(side) then return end
    if side.King:IsStunned() then return end
    if self:IsOccupied(column, row) then return end

    local king = side.King
    local moveType = self:CallAbility(side, "GetMoveType")
    if side.HasMoved and not moveType then return end

    if moveType then
        local function IsBlocked(blockColumn, blockRow)
            return self:IsOccupied(blockColumn, blockRow)
        end

        if not PieceRules.IsValidMove(moveType, side.Team, king.Column, king.Row, column, row, IsBlocked) then return end

        king:SetTile(column, row)
    elseif not king:MoveTo(column, row) then
        return
    end

    if not moveType then
        side.HasMoved = true
    end

    self:CallAbility(side, "OnKingMoved")
    self:SendKingMoved(side, "KingMoved")
    self:OnUnitMoved(king)
    self:FinishEvent()
end

--ACTION EVENTS--

function MatchClass:Fire(side, targetX, targetY, mode)
    if not self:CanAct(side, ActionCost.Fire, "Fire") then return end

    local king = side.King
    if not king:CanFire(mode) then return end

    local function IsEnemyTile(column, row)
        local piece = self:GetPieceAt(column, row)
        return piece ~= nil and piece.Team ~= side.Team
    end

    local pellets, hitTiles, shotType = king:GetShot(targetX, targetY, mode, IsEnemyTile)
    if not pellets then return end

    local targets = {}

    -- Knife swings can't reach into smoke; shotgun blasts into it roll to hit for each target
    local function IsHit(column, row)
        if shotType == "Knife" then return not self:IsProtected(column, row, side) end

        return self.Random:NextNumber() < self:GetShotHitChance(column, row, side)
    end

    for _, tile in pairs(hitTiles) do
        if IsEnemyTile(tile.Column, tile.Row) and IsHit(tile.Column, tile.Row) then
            table.insert(targets, self:GetPieceAt(tile.Column, tile.Row))
        end
    end

    if shotType == "Knife" and #targets == 0 then return end

    local weapon = king.Shotgun
    local damaged = {}
    -- What the other player sees: hits keyed by the tile each target stood on
    local enemyDamaged = {}
    local opponent = self:GetOpponent(side)

    -- Farthest first, so a knocked back enemy never blocks one behind it that is also being pushed
    table.sort(targets, function(a, b)
        return BoardRules.GetDistance(king.Column, king.Row, a.Column, a.Row) > BoardRules.GetDistance(king.Column, king.Row, b.Column, b.Row)
    end)

    -- Bonuses are worked out before anyone is hit, so a kill can't change whether a neighbor counts as isolated
    local bonuses = {}
    local originX, originY = ShotgunRules.GetKingOrigin(king.Column, king.Row)

    for _, piece in ipairs(targets) do
        bonuses[piece] = side.NextShotBonus + (self:CallAbility(side, "GetHitBonus", piece) or 0)

        -- Gun Maintenance adds to each blast, so a Double Barrel gets it twice
        bonuses[piece] += king.DamageBonus * (shotType == "Knife" and 1 or weapon.Blasts)

        -- Piercing blasts (Deadly Rounds) lose damage for every enemy they pass through on the way
        if weapon.Pierces and shotType ~= "Knife" then
            bonuses[piece] -= ShotgunRules.CountBlockers(originX, originY, piece.Column, piece.Row, IsEnemyTile) * weapon.PierceDamageLoss
        end
    end

    side.NextShotBonus = 0

    for _, piece in ipairs(targets) do
        local column, row = piece.Column, piece.Row
        local distance = BoardRules.GetDistance(king.Column, king.Row, column, row)
        self:DamagePiece(piece, math.max(ShotgunRules.GetHitDamage(weapon, shotType, distance) + bonuses[piece], 0), side)

        if shotType == "Knife" and piece:IsAlive() then
            piece:ApplyBleed(weapon.Knife.BleedDamage, weapon.Knife.BleedTurns)
        end

        local result = {Id = piece.Id, Health = piece.Health}

        if weapon.Knockback and piece:IsAlive() then
            result.KnockColumn, result.KnockRow = self:KnockBack(piece, weapon.Knockback, king)
        end

        table.insert(damaged, result)

        -- The other player's own king is hit with no Id
        local isOpponentKing = opponent ~= nil and piece == opponent.King
        table.insert(enemyDamaged, {Id = not isOpponentKing and piece.Id or nil, Column = column, Row = row, Health = piece.Health})
    end

    king:SpendAmmo(mode)
    self:SpendEnergy(side, ActionCost.Fire, "Fire")

    side:Send("ShotFired", pellets, hitTiles, damaged, shotType)

    if opponent then
        self:SendTo(opponent, "EnemyShotFired", king.Id, pellets, hitTiles, enemyDamaged)
    end

    -- Knocked back enemies can land in traps
    for _, result in ipairs(damaged) do
        local piece = self.Pieces[result.Id]

        if piece and result.KnockColumn then
            if opponent then
                self:SendTo(opponent, "PieceMoved", piece.Id, piece.Column, piece.Row)
            end

            self:OnUnitMoved(piece)
        end
    end

    self:FinishEvent()
end

-- Pushes the piece away from the shooting king
function MatchClass:KnockBack(piece, tiles, fromKing)
    if piece.Type == "King" then return nil end

    local stepColumn = math.sign(piece.Column - fromKing.Column)
    local stepRow = math.sign(piece.Row - fromKing.Row)
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

function MatchClass:Reload(side)
    if not self:CanAct(side, ActionCost.Reload, "Reload") then return end
    if not side.King:Reload() then return end

    self:SpendEnergy(side, ActionCost.Reload, "Reload")
    side:Send("Reloaded")
    self:FinishEvent()
end

--CLASS ABILITIES--

-- payload is a table whose fields depend on the class; the class component validates it
function MatchClass:Special(side, payload)
    if not self:CanAct(side, ActionCost.Special, "Special") then return end
    if not self:CallAbility(side, "Special", payload) then return end

    self:SpendEnergy(side, ActionCost.Special, "Special")
    self:FinishEvent()
end

-- Free once fully charged, once per turn, and spends the whole charge
function MatchClass:Ultimate(side, payload)
    if not self:CanAct(side, ActionCost.Ultimate, "Ultimate") then return end
    if side.UltimateCharge < UltimateConfig.MAX_CHARGE then return end
    if not self:CallAbility(side, "Ultimate", payload) then return end

    side.UltimateCharge = 0
    self:SpendEnergy(side, ActionCost.Ultimate, "Ultimate")
    self:FinishEvent()
end

function MatchClass:Summon(side, pieceType, column, row)
    if not table.find(PieceConfig.SUMMONABLE, pieceType) then return end

    local cost = PieceConfig.Cost[pieceType]
    if not self:CanAct(side, cost, "Summon") then return end

    local king = side.King
    if not BoardRules.IsOnBoard(column, row) then return end
    if BoardRules.GetDistance(king.Column, king.Row, column, row) > BoardConfig.SUMMON_RANGE then return end
    if self:IsOccupied(column, row) then return end

    local maxActive = PieceConfig.MaxActive[pieceType]
    if maxActive and self:CountPieces(pieceType, side.Team) >= maxActive then return end

    self:SpendEnergy(side, cost, "Summon")
    self:AddPiece(pieceType, side.Team, column, row)

    self:FinishEvent()
end

function MatchClass:Command(side, pieceId, column, row)
    if not self:CanAct(side, ActionCost.Command, "Command") then return end

    local piece = self.Pieces[pieceId]
    if not piece then return end
    if piece.Team ~= side.Team then return end
    if piece.Type == "King" then return end
    if piece:IsStunned() then return end

    local function IsBlocked(blockColumn, blockRow)
        return self:IsOccupied(blockColumn, blockRow)
    end

    local opponent = self:GetOpponent(side)

    -- Commanding onto an enemy attacks it; like a chess capture, a kill moves the attacker onto the enemy's square,
    -- otherwise it stays on its own
    local target = self:GetPieceAt(column, row)
    if target then
        if target.Team == piece.Team then return end
        if self:IsProtected(column, row, side) then return end

        local function IsEnemy(enemyColumn, enemyRow)
            local enemy = self:GetPieceAt(enemyColumn, enemyRow)
            return enemy ~= nil and enemy.Team ~= piece.Team
        end

        if not PieceRules.IsValidAttack(piece.Type, piece.Team, piece.Column, piece.Row, column, row, IsBlocked, IsEnemy) then return end

        self:SpendEnergy(side, ActionCost.Command, "Command")

        -- The other player's traps on the way stop the attack
        if self:CallAbility(opponent, "InterceptPath", piece, column, row) then
            self:FinishEvent()
            return
        end

        local isCapture = self:DamagePiece(target, PieceConfig.Damage[piece.Type], side)

        if isCapture then
            piece.Column = column
            piece.Row = row
        end

        self:SendAttack(piece, target, isCapture)
        self:FinishEvent()
        return
    end

    if not PieceRules.IsValidMove(piece.Type, piece.Team, piece.Column, piece.Row, column, row, IsBlocked) then return end

    self:SpendEnergy(side, ActionCost.Command, "Command")

    if self:CallAbility(opponent, "InterceptPath", piece, column, row) then
        self:FinishEvent()
        return
    end

    piece.Column = column
    piece.Row = row

    self:SendAll("PieceMoved", piece.Id, column, row)
    self:OnUnitMoved(piece)
    self:FinishEvent()
end

--TURNS--

function MatchClass:EndTurn(side)
    if not self:IsSideTurn(side) then return end
    if self.isSkipping then return end

    if self.isDuel then
        self:EndDuelTurn(side)
    else
        self:StartEnemyTurn()
    end
end

--DUEL TURNS--

-- Each player's clock only runs on their own turn
function MatchClass:EndDuelTurn(side)
    side.Clock = self:GetClock(side)
    self.isSkipping = false

    -- A stun lasts through its piece's own turns, not counting the turn it was stunned on
    for _, piece in pairs(self.Pieces) do
        if piece.Team == side.Team and piece.StunnedOnTurn ~= self.Turn then
            piece:TickStun()
        end
    end

    self:ClearEndedStuns()

    local opponent = self:GetOpponent(side)
    self:CallAbility(opponent, "OnEnemyTurnEnd")
    self:StartDuelTurn(opponent)
end

function MatchClass:StartDuelTurn(side)
    self.ActiveTeam = side.Team
    self.Turn += 1
    side.HasMoved = false
    side.UsedActions = {}

    self:CallAbility(side, "OnPlayerTurnStart")

    side:GainEnergy()
    self:TickBleed(side.Team)
    if self:CheckDuelOver() then return end

    self.TurnStartedAt = time()
    if self:CheckStunSkip(side) then return end

    self:SendTurnState()
    self:StartClock(side)
    self:StartAITurn(side)
end

function MatchClass:StartAITurn(side)
    if side.Player then return end

    PracticeAIService.TakeTurn(self, side)
end

function MatchClass:StartClock(side)
    local turn = self.Turn

    task.delay(side.Clock, function()
        if not self.isActive then return end
        if self.Turn ~= turn then return end
        if self.isSkipping then return end

        side.Clock = 0
        self:EndDuel(self:GetOpponent(side), "Timeout")
    end)
end

--CAMPAIGN TURNS--

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

        -- Only the wait for animations follows the player's speed setting, not the think time
        local speed = self.Player:GetAttribute("GameSpeed") or 1

        task.delay(MatchConfig.ENEMY_ACTION_TIME / speed, function()
            if not self.isActive then return end
            if self.Turn ~= turn then return end

            self:StartPlayerTurn()
        end)
    end)
end

--ENEMY ACTIONS--

-- Every plan was made against the same board, so attacks resolve first and then everyone moves at once
function MatchClass:RunEnemyPlans(plans)
    local white = self.Sides.White

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

        if piece and plan.Type == "Move" and not self:IsOccupied(plan.Column, plan.Row)
            and not self:CallAbility(white, "InterceptPath", piece, plan.Column, plan.Row) then
            piece.Column = plan.Column
            piece.Row = plan.Row

            self:SendAll("PieceMoved", piece.Id, plan.Column, plan.Row)
            self:OnUnitMoved(piece)
        end
    end

    self:ClearEndedStuns()
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
    if self:CallAbility(self.Sides.White, "InterceptPath", piece, column, row) then return end

    local health, targetId = self:DamageWhiteTile(column, row, PieceConfig.Damage[piece.Type])
    if not health then return end

    if not targetId then
        self:SendAll("KingAttacked", piece.Id, health)
        return
    end

    -- Killing a summoned piece captures its square, like the player's own captures
    local isCapture = health <= 0

    if isCapture then
        piece.Column = column
        piece.Row = row
    end

    self:SendAll("PieceAttacked", piece.Id, targetId, health, isCapture)

    if isCapture then
        self:OnUnitMoved(piece)
    end
end

function MatchClass:EnemyShoot(piece, aimX, aimY)
    if not self.King:IsAlive() then return end

    local weapon = ShotgunRules.GetWeapon(ShotgunConfig.ENEMY_KING)

    local function IsWhiteTile(column, row)
        if self.King.Column == column and self.King.Row == row then return true end

        local target = self:GetPieceAt(column, row)
        return target ~= nil and target.Team == "White"
    end

    local pellets, hitTiles, shotType = ShotgunRules.GetFireResult(piece.Column, piece.Row, aimX, aimY, weapon, "Normal", IsWhiteTile)
    if not pellets then return end

    local damaged = {}

    for _, tile in pairs(hitTiles) do
        if IsWhiteTile(tile.Column, tile.Row) and self.Random:NextNumber() < self:GetShotHitChance(tile.Column, tile.Row) then
            local distance = BoardRules.GetDistance(piece.Column, piece.Row, tile.Column, tile.Row)
            local health, targetId = self:DamageWhiteTile(tile.Column, tile.Row, ShotgunRules.GetHitDamage(weapon, shotType, distance))

            table.insert(damaged, {Id = targetId, Column = tile.Column, Row = tile.Row, Health = health})
        end
    end

    self:SendAll("EnemyShotFired", piece.Id, pellets, hitTiles, damaged)
end

-- Bleeding pieces lose health at the start of their team's turn; it counts as the other side's damage
function MatchClass:TickBleed(team)
    local attacker = self:GetDefender(team)

    for _, piece in pairs(self.Pieces) do
        if piece.Team == team and piece:IsBleeding() then
            self:DamagePiece(piece, piece:TickBleed(), attacker)
            self:ShowDamage(piece)
        end
    end
end

function MatchClass:StartPlayerTurn()
    local white = self.Sides.White

    self:CallAbility(white, "OnEnemyTurnEnd")

    self.Phase = "PlayerTurn"
    self.Turn += 1
    white.HasMoved = false
    white.UsedActions = {}

    self:CallAbility(white, "OnPlayerTurnStart")

    white:GainEnergy()
    self:TickBleed("White")
    self:SendTurnState()
end

return MatchClass
