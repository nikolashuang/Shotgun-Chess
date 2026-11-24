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
local CompanionAIService = require(ServerScriptService.AI.CompanionAIService)

-- Each class's passive, special and ultimate live in its own component
local ClassComponents = {
    Reaper = require(script.Parent.Classes.ReaperClass),
    Hunter = require(script.Parent.Classes.HunterClass),
    Gunslinger = require(script.Parent.Classes.GunslingerClass),
    Outlaw = require(script.Parent.Classes.OutlawClass),
    Monarch = require(script.Parent.Classes.MonarchClass),
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

    -- Campaign Fallen Knight: {Type, Column, Row, Health} set before Start; Companion is the piece once placed
    self.CompanionStart = nil
    self.Companion = nil

    self.Pieces = {}
    self.NextPieceId = 1
    -- Reaper souls, numbered across both sides so the rival's never clash with your own
    self.NextSoulId = 1

    self.Sides = {}

    -- Phase is "PlayerTurn" while ActiveTeam's player acts, "EnemyTurn" while the AI acts, "Countdown" before a
    -- duel place match begins, or "Over"
    self.Phase = "PlayerTurn"
    self.ActiveTeam = "White"
    self.Turn = 1
    self.TurnStartedAt = 0
    -- Seconds left before the clocks start, during the "Countdown" phase
    self.CountdownLeft = nil

    self.Random = Random.new()

    self.AIRating = aiRating
    self.AIMistakes = 0

    self.isDuel = false
    self.isTeamDuel = false
    self.isActive = true

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
        self:AddDuelKing(side)
    end

    return self
end

-- 2v2: whites and blacks are each two {Player, Shotgun, Class}; teammates start side by side on their back row
-- Both players on a team act during the team's turn, each with their own king, energy and clock
function MatchClass.newTeamDuel(whites, blacks)
    local white, black = whites[1], blacks[1]
    local self = MatchClass.newDuel(white.Player, white.Shotgun, white.Class, black.Player, black.Shotgun, black.Class)

    self.isTeamDuel = true

    local column = BoardConfig.KING_START_COLUMN + 1
    local row = BoardConfig.KING_START_ROW
    local secondWhite = self:AddSide(whites[2].Player, "White", column, row, whites[2].Shotgun, whites[2].Class, "White2")
    local secondBlack = self:AddSide(blacks[2].Player, "Black", MirrorRules.Tile(column), MirrorRules.Tile(row), blacks[2].Shotgun, blacks[2].Class, "Black2")

    self:AddDuelKing(secondWhite)
    self:AddDuelKing(secondBlack)

    return self
end

-- Duel kings are board pieces too, so shots, commands and traps can reach them
function MatchClass:AddDuelKing(side)
    side.Clock = DuelConfig.CLOCK

    side.King.Id = self.NextPieceId
    self.NextPieceId += 1
    self.Pieces[side.King.Id] = side.King
end

-- key defaults to the team; the second player on a 2v2 team gets its own key
function MatchClass:AddSide(player, team, column, row, shotgunName, className, key)
    local king = KingClass.new(player, column, row, shotgunName, className, team)
    local side = SideClass.new(self, player, team, king, className)

    local component = ClassComponents[className]
    side.Ability = component and component.new(side)

    side.Key = key or team
    self.Sides[side.Key] = side

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

-- Every side on the team, still playing or not
function MatchClass:GetTeamSides(team)
    local sides = {}

    for _, side in pairs(self.Sides) do
        if side.Team == team then
            table.insert(sides, side)
        end
    end

    return sides
end

function MatchClass:GetOpponents(side)
    return self:GetTeamSides(side.EnemyTeam)
end

-- nil outside 2v2
function MatchClass:GetTeammate(side)
    for _, other in pairs(self.Sides) do
        if other ~= side and other.Team == side.Team then return other end
    end

    return nil
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
    if side.isDisconnected or not side.Player.Parent then return end

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

function MatchClass:SendOthers(exceptSide, action, ...)
    for _, side in pairs(self.Sides) do
        if side ~= exceptSide then
            self:SendTo(side, action, ...)
        end
    end
end

-- Each player sees their own king through King events and the other king as a piece
function MatchClass:SendKingMoved(side, ownAction)
    local king = side.King

    side:Send(ownAction, king.Column, king.Row)
    self:SendOthers(side, "PieceMoved", king.Id, king.Column, king.Row)
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
    if side.isSkipping then return side.Clock end

    return math.max(side.Clock - (time() - self.TurnStartedAt), 0)
end

function MatchClass:GetTurnState(side)
    local phase = "EnemyTurn"

    if self.Phase == "Over" or self.Phase == "Countdown" then
        phase = self.Phase
    elseif self:IsSideTurn(side) and side.isSkipping then
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
        DamageBonus = side.King.DamageBonus,
        Ability = self:CallAbility(side, "GetState"),
        Clock = self:GetClock(side),
        EnemyClock = self:GetRivalClock(side),
        TeamDuel = self.isTeamDuel,
        IsOut = side.isOut,
        Countdown = self.CountdownLeft,
    }
end

-- 2v2 shows the lowest clock still running on the other team; once they're all out, the last one's clock
function MatchClass:GetRivalClock(side)
    local lowest = nil
    local last = nil

    for _, opponent in ipairs(self:GetOpponents(side)) do
        local clock = self:GetClock(opponent)
        last = clock or last

        if clock and not opponent.isOut and (not lowest or clock < lowest) then
            lowest = clock
        end
    end

    return lowest or last
end

function MatchClass:SendTurnState()
    for _, side in pairs(self.Sides) do
        side:Send("TurnState", self:GetTurnState(side))
    end
end

--SETUP--

-- countdown (seconds) shows the board first and only starts the turns and clocks once it runs out
function MatchClass:Start(countdown)
    self:Setup()

    if not countdown then
        self:Begin()
        return
    end

    self.Phase = "Countdown"

    task.spawn(function()
        for left = countdown, 1, -1 do
            if not self.isActive then return end

            self.CountdownLeft = left
            self:SendTurnState()
            task.wait(1)
        end

        if not self.isActive then return end

        self.CountdownLeft = nil
        self.Phase = "PlayerTurn"
        self:Begin()
    end)
end

function MatchClass:Setup()
    self:SendAll("MatchStarted")

    for _, side in pairs(self.Sides) do
        local king = side.King
        side:Send("KingMoved", king.Column, king.Row)

        -- Other Kings come with their shotgun so everyone can see what they are running
        self:SendOthers(side, "PieceAdded", king.Id, king.Type, king.Team, king.Column, king.Row, king.Health, king.MaxHealth, king.ShotgunName)
    end

    for _, enemy in ipairs(self.Enemies) do
        self:AddPiece(enemy.Type, "Black", enemy.Column, enemy.Row)
    end

    self.HasEnemyKing = self:CountPieces("King", "Black") > 0

    local ally = self.CompanionStart
    if ally and not self:IsOccupied(ally.Column, ally.Row) then
        self.Companion = self:AddPiece(ally.Type, "White", ally.Column, ally.Row, ally.Health)
        self.Companion.isCompanion = true
    end
end

function MatchClass:Begin()
    local whites = self:GetTeamSides("White")

    for _, side in ipairs(whites) do
        side:GainEnergy()
    end

    self.TurnStartedAt = time()
    self:SendTurnState()

    if not self.isDuel then return end

    for _, side in ipairs(whites) do
        self:StartClock(side)
        self:StartAITurn(side)
    end
end

function MatchClass:Destroy()
    self.isActive = false
end

-- Leaving a duel early forfeits it; in 2v2 the teammate fights on alone or surrenders
function MatchClass:Leave(player)
    local side = self:GetSide(player)

    if self.isTeamDuel and self.isActive and side then
        self:Disconnect(side)
        return
    end

    if self.isDuel and self.isActive and side then
        self:EndDuel(self:GetOpponent(side), "Forfeit")
    end

    self:Destroy()
end

-- A 2v2 player who leaves is out for good; a team that loses both players forfeits
function MatchClass:Disconnect(side)
    if side.isDisconnected then return end

    side.isDisconnected = true
    self:KnockOut(side)

    if self:CheckDuelOver("Forfeit") then return end

    local teammate = self:GetTeammate(side)
    if teammate and not teammate.isOut then
        teammate:Send("TeammateLeft")
    end

    self:CheckTeamTurnDone()
end

-- A 2v2 player is out once their king dies, their clock runs out or they leave; a king still standing is taken off
-- The out player's summons go to their teammate
function MatchClass:KnockOut(side)
    if side.isOut then return end

    side.isOut = true

    local king = side.King
    if self.Pieces[king.Id] then
        self.Pieces[king.Id] = nil
        king.Health = 0
        self:SendOthers(side, "PieceDamaged", king.Id, 0)
    end

    local teammate = self:GetTeammate(side)
    if teammate then
        teammate:Send("TeammatePiecesFreed")
    end
end

-- A 1v1 surrender ends the duel at once; a 2v2 team surrenders once every player still in agrees
-- A player left alone by a disconnect surrenders on their own, for a smaller reward to the winners
function MatchClass:Surrender(side)
    if not self.isDuel or not self.isActive then return end
    if side.isOut then return end

    if not self.isTeamDuel then
        self:EndDuel(self:GetOpponent(side), "Surrender")
        return
    end

    side.wantsSurrender = true

    local teammate = self:GetTeammate(side)
    local winner = self:GetOpponents(side)[1]

    if teammate.isDisconnected then
        self:EndDuel(winner, "DisconnectSurrender")
    elseif teammate.isOut or teammate.wantsSurrender then
        self:EndDuel(winner, "Surrender")
    else
        teammate:Send("SurrenderVote")
    end
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

-- In 2v2 both teammates act during their team's turn until each ends theirs
function MatchClass:IsSideTurn(side)
    if side.isOut or side.hasEndedTurn then return false end

    return self.Phase == "PlayerTurn" and self.ActiveTeam == side.Team
end

-- health starts the piece hurt (a companion carrying its health between battles)
-- owner is the side that summoned it; a 2v2 teammate is told the piece isn't theirs to command
function MatchClass:AddPiece(pieceType, team, column, row, health, owner)
    local piece = PieceClass.new(self.NextPieceId, pieceType, team, column, row)
    piece.Health = health or piece.Health
    piece.Owner = owner
    self.NextPieceId += 1
    self.Pieces[piece.Id] = piece

    for _, side in pairs(self.Sides) do
        local isTeammates = owner ~= nil and owner ~= side and owner.Team == side.Team
        self:SendTo(side, "PieceAdded", piece.Id, piece.Type, piece.Team, piece.Column, piece.Row, piece.Health, piece.MaxHealth, nil, isTeammates)
    end

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
    -- A Morale shield soaks up damage before health
    if (piece.Shield or 0) > 0 and amount > 0 then
        local absorbed = math.min(piece.Shield, amount)
        piece.Shield -= absorbed
        amount -= absorbed
        self:SendAll("PieceShielded", piece.Id, piece.Shield)
    end

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
    if side.isSkipping then return false end
    if side.UsedActions[action] then return false end
    if side.Energy < cost then return false end

    return true
end

function MatchClass:SpendEnergy(side, cost, action)
    side.Energy -= cost
    side.UsedActions[action] = true
end

-- Smoke belongs to the side being attacked; AI attacks (no attacker) are against White
-- Chance any attack (shot pellet, knife swing or piece attack) lands on the tile; lower inside the Bandit's smoke
function MatchClass:GetHitChance(column, row, attacker)
    local defenders = attacker and self:GetOpponents(attacker) or {self.Sides.White}
    local chance = 1

    for _, defender in ipairs(defenders) do
        chance = math.min(chance, self:CallAbility(defender, "GetHitChance", column, row) or 1)
    end

    return chance
end

function MatchClass:RollHit(column, row, attacker)
    return self.Random:NextNumber() < self:GetHitChance(column, row, attacker)
end

-- Called whenever a piece or king ends up on a new tile; the other team's traps can catch it
function MatchClass:OnUnitMoved(piece)
    for _, side in pairs(self.Sides) do
        if side.Team ~= piece.Team then
            self:CallAbility(side, "OnEnemyMoved", piece)
        end
    end
end

-- The other team's traps on the way stop a commanded piece
function MatchClass:InterceptPath(side, piece, column, row)
    for _, opponent in ipairs(self:GetOpponents(side)) do
        if self:CallAbility(opponent, "InterceptPath", piece, column, row) then return true end
    end

    return false
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

-- A dead king puts its player out; a team with every player out loses (in 1v1 that's its only king)
function MatchClass:CheckDuelOver(reason)
    for _, side in pairs(self.Sides) do
        if not side.King:IsAlive() then
            self:KnockOut(side)
        end
    end

    for _, team in ipairs({"White", "Black"}) do
        local isBeaten = true

        for _, side in ipairs(self:GetTeamSides(team)) do
            if not side.isOut then
                isBeaten = false
            end
        end

        if isBeaten then
            local winner = self:GetTeamSides(team == "White" and "Black" or "White")[1]
            self:EndDuel(winner, reason or "KingKilled")
            return true
        end
    end

    return false
end

-- reason is "KingKilled", "Timeout", "Forfeit", or in 2v2 "Surrender" or "DisconnectSurrender"
-- winner is any side on the winning team
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
    if self:CheckTeamTurnDone() then return end

    -- A King that walks into a trap loses the rest of this turn (and the next one, see EndTeamTurn)
    for _, side in ipairs(self:GetTeamSides(self.ActiveTeam)) do
        self:CheckStunSkip(side)
    end

    self:SendTurnState()
end

-- A stunned duel King loses its turn: it shows as stunned for a moment, then play passes on
-- Its clock stops while the turn is skipped
function MatchClass:CheckStunSkip(side)
    if not self.isDuel then return false end
    if side.isSkipping then return true end
    if not self:IsSideTurn(side) then return false end
    if not side.King:IsStunned() then return false end

    side.Clock = self:GetClock(side)
    side.isSkipping = true
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

    -- Knife swings and shotgun blasts into smoke roll to hit for each target
    local function IsHit(column, row)
        return self:RollHit(column, row, side)
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
        table.insert(enemyDamaged, {Piece = piece, Column = column, Row = row, Health = piece.Health})
    end

    king:SpendAmmo(mode)
    self:SpendEnergy(side, ActionCost.Fire, "Fire")

    side:Send("ShotFired", pellets, hitTiles, damaged, shotType)

    -- Everyone else sees the shot; each player's own king is hit with no Id
    for _, other in pairs(self.Sides) do
        if other == side then continue end

        local seen = {}

        for _, hit in ipairs(enemyDamaged) do
            table.insert(seen, {Id = hit.Piece ~= other.King and hit.Piece.Id or nil, Column = hit.Column, Row = hit.Row, Health = hit.Health})
        end

        self:SendTo(other, "EnemyShotFired", king.Id, pellets, hitTiles, seen)
    end

    -- Knocked back enemies can land in traps
    for _, result in ipairs(damaged) do
        local piece = self.Pieces[result.Id]

        if piece and result.KnockColumn then
            self:SendOthers(side, "PieceMoved", piece.Id, piece.Column, piece.Row)
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

    local cost = self:CallAbility(side, "GetSummonCost", pieceType) or PieceConfig.Cost[pieceType]
    if not self:CanAct(side, cost, "Summon") then return end

    local king = side.King
    if not BoardRules.IsOnBoard(column, row) then return end
    if BoardRules.GetDistance(king.Column, king.Row, column, row) > BoardConfig.SUMMON_RANGE then return end
    if self:IsOccupied(column, row) then return end

    local maxActive = PieceConfig.MaxActive[pieceType]
    if maxActive and self:CountPieces(pieceType, side.Team) >= maxActive then return end

    self:SpendEnergy(side, cost, "Summon")
    self:AddPiece(pieceType, side.Team, column, row, nil, side)
    self:CallAbility(side, "OnSummoned", pieceType)

    self:FinishEvent()
end

function MatchClass:Command(side, pieceId, column, row)
    if not self:CanAct(side, ActionCost.Command, "Command") then return end

    local piece = self.Pieces[pieceId]
    if not piece then return end
    if piece.Team ~= side.Team then return end
    if piece.Type == "King" then return end
    -- 2v2: each player commands their own summons, and their teammate's once that teammate is out
    if piece.Owner and piece.Owner ~= side and not piece.Owner.isOut then return end
    -- The Fallen Knight acts on his own
    if piece.isCompanion then return end
    if piece:IsStunned() then return end

    local function IsBlocked(blockColumn, blockRow)
        return self:IsOccupied(blockColumn, blockRow)
    end

    local cost = BoardRules.GetCommandCost(piece.Column, piece.Row, column, row)

    -- Commanding onto an enemy attacks it; like a chess capture, a kill moves the attacker onto the enemy's square,
    -- otherwise it stays on its own
    local target = self:GetPieceAt(column, row)
    if target then
        if target.Team == piece.Team then return end

        local function IsEnemy(enemyColumn, enemyRow)
            local enemy = self:GetPieceAt(enemyColumn, enemyRow)
            return enemy ~= nil and enemy.Team ~= piece.Team
        end

        if not PieceRules.IsValidAttack(piece.Type, piece.Team, piece.Column, piece.Row, column, row, IsBlocked, IsEnemy) then return end
        if side.Energy < cost then return end

        self:SpendEnergy(side, cost, "Command")

        -- The other team's traps on the way stop the attack
        if self:InterceptPath(side, piece, column, row) then
            self:FinishEvent()
            return
        end

        -- Attacks into smoke can miss: the piece still lunges, but the target takes nothing
        if not self:RollHit(column, row, side) then
            self:SendAttack(piece, target, false)
            self:FinishEvent()
            return
        end

        local damage = PieceConfig.Damage[piece.Type] + (self:CallAbility(side, "GetAllyDamageBonus", piece) or 0)
        local isCapture = self:DamagePiece(target, damage, side)

        if isCapture then
            piece.Column = column
            piece.Row = row
        end

        self:SendAttack(piece, target, isCapture)
        self:FinishEvent()
        return
    end

    if not PieceRules.IsValidMove(piece.Type, piece.Team, piece.Column, piece.Row, column, row, IsBlocked) then return end
    if side.Energy < cost then return end

    self:SpendEnergy(side, cost, "Command")

    if self:InterceptPath(side, piece, column, row) then
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
    if side.isSkipping then return end

    if self.isDuel then
        self:EndDuelTurn(side)
    else
        self:StartEnemyTurn()
    end
end

--DUEL TURNS--

-- Each player's clock only runs on their own turn; in 2v2 the team's turn ends once both players have ended theirs
function MatchClass:EndDuelTurn(side)
    side.Clock = self:GetClock(side)
    side.isSkipping = false
    side.hasEndedTurn = true

    if self:CheckTeamTurnDone() then return end

    self:SendTurnState()
end

-- Ends the team's turn once nobody on it can still act; returns true if it did
function MatchClass:CheckTeamTurnDone()
    if not self.isDuel or not self.isActive or self.Phase ~= "PlayerTurn" then return false end

    for _, side in ipairs(self:GetTeamSides(self.ActiveTeam)) do
        if self:IsSideTurn(side) or side.isSkipping then return false end
    end

    self:EndTeamTurn()

    return true
end

function MatchClass:EndTeamTurn()
    local team = self.ActiveTeam
    local enemyTeam = team == "White" and "Black" or "White"

    -- A stun lasts through its piece's own turns, not counting the turn it was stunned on
    for _, piece in pairs(self.Pieces) do
        if piece.Team == team and piece.StunnedOnTurn ~= self.Turn then
            piece:TickStun()
        end
    end

    self:ClearEndedStuns()

    for _, opponent in ipairs(self:GetTeamSides(enemyTeam)) do
        self:CallAbility(opponent, "OnEnemyTurnEnd")
    end

    self:StartTeamTurn(enemyTeam)
end

function MatchClass:StartTeamTurn(team)
    self.ActiveTeam = team
    self.Turn += 1

    local sides = self:GetTeamSides(team)

    for _, side in ipairs(sides) do
        side.HasMoved = false
        side.UsedActions = {}
        side.hasEndedTurn = false

        if not side.isOut then
            self:CallAbility(side, "OnPlayerTurnStart")
            side:GainEnergy()
        end
    end

    self:TickBleed(team)
    if self:CheckDuelOver() then return end

    self.TurnStartedAt = time()

    for _, side in ipairs(sides) do
        self:CheckStunSkip(side)
    end

    self:SendTurnState()

    for _, side in ipairs(sides) do
        if self:IsSideTurn(side) and not side.isSkipping then
            self:StartClock(side)
            self:StartAITurn(side)
        end
    end
end

function MatchClass:StartAITurn(side)
    if side.Player then return end

    PracticeAIService.TakeTurn(self, side)
end

-- Running out of time loses a 1v1; in 2v2 it only puts that player out
function MatchClass:StartClock(side)
    local turn = self.Turn

    task.delay(side.Clock, function()
        if not self.isActive then return end
        if self.Turn ~= turn then return end
        if side.isSkipping or side.hasEndedTurn then return end

        side.Clock = 0

        if not self.isTeamDuel then
            self:EndDuel(self:GetOpponent(side), "Timeout")
            return
        end

        self:KnockOut(side)
        if self:CheckDuelOver("Timeout") then return end
        if self:CheckTeamTurnDone() then return end

        self:SendTurnState()
    end)
end

--CAMPAIGN TURNS--

function MatchClass:StartEnemyTurn()
    self.Phase = "EnemyTurn"

    self:TickBleed("Black")
    if self:CheckVictory() then return end

    -- The Fallen Knight moves at the end of the player's turn, before the enemies plan
    self:RunCompanion()
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

--COMPANION--

function MatchClass:RunCompanion()
    local piece = self.Companion
    if not piece or not self.Pieces[piece.Id] then return end
    if piece:IsStunned() then return end

    local plan = CompanionAIService.Plan(self, piece)
    if not plan then return end

    if plan.Type == "Attack" then
        local target = self:GetPieceAt(plan.Column, plan.Row)
        if not target or target.Team == piece.Team then return end

        local damage = PieceConfig.Damage[piece.Type] + (self:CallAbility(self.Sides.White, "GetAllyDamageBonus", piece) or 0)
        local isCapture = self:DamagePiece(target, damage, self.Sides.White)

        if isCapture then
            piece.Column = plan.Column
            piece.Row = plan.Row
        end

        self:SendAttack(piece, target, isCapture)
        return
    end

    if self:IsOccupied(plan.Column, plan.Row) then return end

    piece.Column = plan.Column
    piece.Row = plan.Row

    self:SendAll("PieceMoved", piece.Id, plan.Column, plan.Row)
    self:OnUnitMoved(piece)
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
            self:TryPromote(piece)
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
    if self:CallAbility(self.Sides.White, "InterceptPath", piece, column, row) then return end

    -- Attacks into smoke can miss: the piece lunges but nothing is hurt
    if not self:RollHit(column, row) then
        if self.King.Column == column and self.King.Row == row then
            self:SendAll("KingAttacked", piece.Id, self.King.Health)
        else
            local target = self:GetPieceAt(column, row)
            if target and target.Team == "White" then
                self:SendAll("PieceAttacked", piece.Id, target.Id, target.Health, false)
            end
        end
        return
    end

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
        self:TryPromote(piece)
    end
end

-- Enemy pawns reaching the player's back row are promoted at full health; the player's own pawns never are
function MatchClass:TryPromote(piece)
    if piece.Type ~= "Pawn" or piece.Team ~= "Black" then return end
    if piece.Row ~= 1 then return end
    if not self.Pieces[piece.Id] then return end

    local total = 0

    for _, option in ipairs(PieceConfig.PROMOTIONS) do
        total += option.Weight
    end

    local roll = self.Random:NextNumber() * total
    local pieceType = PieceConfig.PROMOTIONS[#PieceConfig.PROMOTIONS].Type

    for _, option in ipairs(PieceConfig.PROMOTIONS) do
        roll -= option.Weight

        if roll < 0 then
            pieceType = option.Type
            break
        end
    end

    piece.Type = pieceType
    piece.MaxHealth = PieceConfig.Health[pieceType]
    piece.Health = piece.MaxHealth

    self:SendAll("PiecePromoted", piece.Id, pieceType, piece.Health, piece.MaxHealth)
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
        if IsWhiteTile(tile.Column, tile.Row) and self:RollHit(tile.Column, tile.Row) then
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
