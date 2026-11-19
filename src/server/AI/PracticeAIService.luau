local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)
local BoardRules = require(ReplicatedStorage.Shared.Board.BoardRules)
local PieceConfig = require(ReplicatedStorage.Shared.Board.PieceConfig)
local PieceRules = require(ReplicatedStorage.Shared.Board.PieceRules)
local ShotgunRules = require(ReplicatedStorage.Shared.Combat.ShotgunRules)
local CombatConfig = require(ReplicatedStorage.Shared.Combat.CombatConfig)
local AIConfig = require(ServerScriptService.AI.AIConfig)

local ActionCost = CombatConfig.ActionCost

-- Seconds before the AI starts its turn, and between its actions (actions follow the player's speed setting)
local THINK_TIME = 0.8
local ACTION_TIME = 0.9

-- Hits on the enemy King count this much more than hits on pieces
local KING_VALUE = 2
local KILL_BONUS = 3

-- A simple AI that plays a whole duel turn like a player: move, then one of shoot / attack with a piece,
-- then summon when it has saved up for the piece it wants. Smarter techniques can replace each step later.
local PracticeAIService = {}

local function GetRating(side)
    return AIConfig.Ratings[side.AIRating] or AIConfig.Ratings[1000]
end

local function IsMistake(match, side)
    local rating = GetRating(side)
    if rating.MaxMistakes and match.AIMistakes >= rating.MaxMistakes then return false end
    if match.Random:NextNumber() >= rating.MistakeChance then return false end

    match.AIMistakes += 1

    return true
end

local function GetValue(side, unit, damage)
    local value = math.min(damage, unit.Health)

    if damage >= unit.Health then
        value += KILL_BONUS
    end

    if unit == side.Match:GetOpponent(side).King then
        value *= KING_VALUE
    end

    return value
end

local function GetEnemies(match, side)
    local enemies = {}

    for _, piece in pairs(match.Pieces) do
        if piece.Team == side.EnemyTeam then
            table.insert(enemies, piece)
        end
    end

    return enemies
end

-- Best aim from a tile: aims straight at each enemy in range and keeps the most valuable shot
local function GetBestShot(match, side, column, row)
    local weapon = side.King.Shotgun
    local best = nil

    local function IsEnemyTile(tileColumn, tileRow)
        local piece = match:GetPieceAt(tileColumn, tileRow)
        return piece ~= nil and piece.Team == side.EnemyTeam
    end

    for _, enemy in ipairs(GetEnemies(match, side)) do
        if BoardRules.GetDistance(column, row, enemy.Column, enemy.Row) <= weapon.MaxRange then
            local aimX, aimY = enemy.Column - 0.5, enemy.Row - 0.5
            local _, hitTiles, shotType = ShotgunRules.GetFireResult(column, row, aimX, aimY, weapon, "Normal", IsEnemyTile)

            if hitTiles then
                local value = 0

                for _, tile in pairs(hitTiles) do
                    local target = match:GetPieceAt(tile.Column, tile.Row)

                    local hitChance = match:GetShotHitChance(tile.Column, tile.Row, side)

                    if target and target.Team == side.EnemyTeam and hitChance > 0 then
                        local distance = BoardRules.GetDistance(column, row, tile.Column, tile.Row)
                        value += GetValue(side, target, ShotgunRules.GetHitDamage(weapon, shotType, distance)) * hitChance
                    end
                end

                if value > 0 and (not best or value > best.Value) then
                    best = {X = aimX, Y = aimY, Value = value}
                end
            end
        end
    end

    return best
end

-- Every tile the king could end the move on, including staying put
local function GetKingTiles(match, side)
    local king = side.King
    local tiles = {{Column = king.Column, Row = king.Row}}

    if side.HasMoved or king:IsStunned() then return tiles end

    for columnStep = -1, 1 do
        for rowStep = -1, 1 do
            local column, row = king.Column + columnStep, king.Row + rowStep

            if BoardRules.IsOnBoard(column, row) and not match:IsOccupied(column, row) then
                table.insert(tiles, {Column = column, Row = row})
            end
        end
    end

    return tiles
end

-- Moves where the king can shoot best; with no shot anywhere, walks toward the enemy King
local function PlanMove(match, side)
    local canFire = side.King:CanFire("Normal") and match:CanAct(side, ActionCost.Fire, "Fire")
    local enemyKing = match:GetOpponent(side).King
    local options = {}

    for _, tile in ipairs(GetKingTiles(match, side)) do
        -- The king's own tile reads as occupied while it is checked from somewhere else, which is fine for aiming
        local shot = canFire and GetBestShot(match, side, tile.Column, tile.Row)
        local distance = BoardRules.GetDistance(tile.Column, tile.Row, enemyKing.Column, enemyKing.Row)
        local score = shot and shot.Value * 10 or 0

        -- Close in to shotgun range but no closer than needed
        score -= math.abs(distance - side.King.Shotgun.MaxRange)

        table.insert(options, {Column = tile.Column, Row = tile.Row, Shot = shot, Score = score})
    end

    table.sort(options, function(a, b)
        return a.Score > b.Score
    end)

    if #options > 1 and IsMistake(match, side) then
        return options[match.Random:NextInteger(2, #options)]
    end

    return options[1]
end

-- Best attack any of its pieces can make this turn
local function PlanAttack(match, side)
    local best = nil

    local function IsBlocked(column, row)
        return match:IsOccupied(column, row)
    end

    local function IsEnemy(column, row)
        local piece = match:GetPieceAt(column, row)
        return piece ~= nil and piece.Team == side.EnemyTeam
    end

    for _, piece in pairs(match.Pieces) do
        if piece.Team == side.Team and piece.Type ~= "King" and not piece:IsStunned() then
            for _, tile in ipairs(PieceRules.GetAttacks(piece.Type, piece.Team, piece.Column, piece.Row, IsBlocked, IsEnemy)) do
                local target = match:GetPieceAt(tile.Column, tile.Row)

                if not match:IsProtected(tile.Column, tile.Row, side) then
                    local value = GetValue(side, target, PieceConfig.Damage[piece.Type])

                    if not best or value > best.Value then
                        best = {PieceId = piece.Id, Column = tile.Column, Row = tile.Row, Value = value}
                    end
                end
            end
        end
    end

    return best
end

-- Moves the piece that gets closest to the enemy King
local function PlanAdvance(match, side)
    local enemyKing = match:GetOpponent(side).King
    local best = nil

    local function IsBlocked(column, row)
        return match:IsOccupied(column, row)
    end

    for _, piece in pairs(match.Pieces) do
        if piece.Team == side.Team and piece.Type ~= "King" and not piece:IsStunned() then
            local current = BoardRules.GetDistance(piece.Column, piece.Row, enemyKing.Column, enemyKing.Row)

            for _, tile in ipairs(PieceRules.GetMoves(piece.Type, piece.Team, piece.Column, piece.Row, IsBlocked)) do
                local gain = current - BoardRules.GetDistance(tile.Column, tile.Row, enemyKing.Column, enemyKing.Row)

                if gain > 0 and (not best or gain > best.Gain) then
                    best = {PieceId = piece.Id, Column = tile.Column, Row = tile.Row, Gain = gain}
                end
            end
        end
    end

    return best
end

-- Saves up for a randomly picked piece, then summons it on the free tile nearest the enemy King
local function PickSummonGoal(match, side)
    local types = {}

    for _, pieceType in ipairs(PieceConfig.SUMMONABLE) do
        local maxActive = PieceConfig.MaxActive[pieceType]

        if not maxActive or match:CountPieces(pieceType, side.Team) < maxActive then
            table.insert(types, pieceType)
        end
    end

    side.AISummonGoal = types[match.Random:NextInteger(1, #types)]
end

local function TrySummon(match, side)
    if not side.AISummonGoal then
        PickSummonGoal(match, side)
    end

    local pieceType = side.AISummonGoal
    if not match:CanAct(side, PieceConfig.Cost[pieceType], "Summon") then return false end

    local king = side.King
    local enemyKing = match:GetOpponent(side).King
    local best = nil
    local range = BoardConfig.SUMMON_RANGE

    for column = king.Column - range, king.Column + range do
        for row = king.Row - range, king.Row + range do
            if BoardRules.IsOnBoard(column, row) and not match:IsOccupied(column, row) then
                local distance = BoardRules.GetDistance(column, row, enemyKing.Column, enemyKing.Row)

                if not best or distance < best.Distance then
                    best = {Column = column, Row = row, Distance = distance}
                end
            end
        end
    end

    if not best then return false end

    match:Summon(side, pieceType, best.Column, best.Row)
    PickSummonGoal(match, side)

    return true
end

function PracticeAIService.TakeTurn(match, side)
    local turn = match.Turn
    local speed = match:GetOpponent(side).Player:GetAttribute("GameSpeed") or 1

    -- False once the match ended or the turn moved on, which stops the AI
    local function Pause(seconds)
        task.wait(seconds)

        return match.isActive and match.Turn == turn and not match.isSkipping
    end

    task.spawn(function()
        if not Pause(THINK_TIME) then return end

        local move = PlanMove(match, side)
        local king = side.King

        if move.Column ~= king.Column or move.Row ~= king.Row then
            match:Move(side, move.Column, move.Row)
            if not Pause(ACTION_TIME / speed) then return end
        end

        if move.Shot then
            match:Fire(side, move.Shot.X, move.Shot.Y, "Normal")
            if not Pause(ACTION_TIME / speed) then return end
        else
            local attack = PlanAttack(match, side)

            if attack and match:CanAct(side, ActionCost.Command, "Command") then
                match:Command(side, attack.PieceId, attack.Column, attack.Row)
                if not Pause(ACTION_TIME / speed) then return end
            end
        end

        if king.Ammo < king.Shotgun.AmmoPerShot and match:CanAct(side, ActionCost.Reload, "Reload") then
            match:Reload(side)
            if not Pause(ACTION_TIME / speed) then return end
        end

        if TrySummon(match, side) then
            if not Pause(ACTION_TIME / speed) then return end
        end

        -- Spare energy beyond the next summon moves a piece forward
        local goalCost = PieceConfig.Cost[side.AISummonGoal] or 0
        local advance = PlanAdvance(match, side)

        if advance and side.Energy - ActionCost.Command >= goalCost and match:CanAct(side, ActionCost.Command, "Command") then
            match:Command(side, advance.PieceId, advance.Column, advance.Row)
            if not Pause(ACTION_TIME / speed) then return end
        end

        match:EndTurn(side)
    end)
end

return PracticeAIService
