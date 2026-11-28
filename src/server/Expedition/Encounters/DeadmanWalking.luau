local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)
local BoardRules = require(ReplicatedStorage.Shared.Board.BoardRules)
local PieceConfig = require(ReplicatedStorage.Shared.Board.PieceConfig)
local ExpeditionConfig = require(ReplicatedStorage.Shared.Expedition.ExpeditionConfig)

local Config = ExpeditionConfig.Exclusives.DeadmanWalking

-- Cliffside Regional Encounter: the King crosses a narrow cliff path to the far end while two Sniper Bishops on the
-- board's edges mark path tiles each enemy turn and fire on them the next. Summoned Rooks and Queens can stun them
local DeadmanWalking = {}
DeadmanWalking.__index = DeadmanWalking

local function IsPath(column)
    return table.find(Config.PATH_COLUMNS, column) ~= nil
end

function DeadmanWalking.GetEnemies()
    local enemies = {}

    for _, tile in ipairs(Config.SNIPER_TILES) do
        table.insert(enemies, {
            Type = "SniperBishop",
            Column = tile[1],
            Row = tile[2],
            MaxHealth = PieceConfig.Health.SniperBishop,
            DamageBonus = 0,
        })
    end

    return enemies
end

function DeadmanWalking.new()
    local self = setmetatable({}, DeadmanWalking)

    self.KingTile = Config.KING_TILE
    self.Summonable = Config.SUMMONABLE
    -- Path tiles the snipers will fire on next enemy turn, as {Column, Row, SniperId}
    self.Marks = {}
    self.Match = nil
    self.Random = Random.new()

    return self
end

function DeadmanWalking:CanKingEnter(_, column)
    return IsPath(column)
end

function DeadmanWalking:GetSnipers(match)
    local snipers = {}

    for _, piece in pairs(match.Pieces) do
        if piece.Type == "SniperBishop" then
            table.insert(snipers, piece)
        end
    end

    table.sort(snipers, function(a, b)
        return a.Id < b.Id
    end)

    return snipers
end

function DeadmanWalking:Setup(match)
    self.Match = match

    for _, sniper in ipairs(self:GetSnipers(match)) do
        sniper.isStatic = true
        sniper.isImmune = true
        sniper.StunOnHit = Config.STUN_TURNS
    end

    self:Aim(match)
end

local function HasMark(marks, column, row)
    for _, mark in ipairs(marks) do
        if mark.Column == column and mark.Row == row then return true end
    end

    return false
end

-- Each sniper that isn't stunned marks path tiles near the King: the first always marks where he stands, the
-- other the rows ahead, so standing still or walking straight in is punished. At least one tile he can step to (or
-- his own) is always left safe
function DeadmanWalking:Aim(match)
    local king = match.King
    local marks = {}
    local near = {}
    local ahead = {}

    for row = king.Row - Config.MARK_BEHIND, king.Row + Config.MARK_AHEAD do
        for _, column in ipairs(Config.PATH_COLUMNS) do
            if BoardRules.IsOnBoard(column, row) then
                local tile = {Column = column, Row = row}
                table.insert(row > king.Row and ahead or near, tile)
            end
        end
    end

    self.Random:Shuffle(near)
    self.Random:Shuffle(ahead)

    local function Take(list, sniper)
        for i, tile in ipairs(list) do
            if not HasMark(marks, tile.Column, tile.Row) then
                table.remove(list, i)
                table.insert(marks, {Column = tile.Column, Row = tile.Row, SniperId = sniper.Id})
                return
            end
        end
    end

    for index, sniper in ipairs(self:GetSnipers(match)) do
        if not sniper:IsStunned() then
            for shot = 1, Config.MARKS_PER_SNIPER do
                if index == 1 and shot == 1 then
                    table.insert(marks, {Column = king.Column, Row = king.Row, SniperId = sniper.Id})
                else
                    Take(index == 1 and near or ahead, sniper)
                end
            end
        end
    end

    -- Tiles the King can reach next turn: his own and the free path tiles around him
    local reach = {{Column = king.Column, Row = king.Row}}

    for columnOffset = -1, 1 do
        for rowOffset = -1, 1 do
            local column, row = king.Column + columnOffset, king.Row + rowOffset

            if (columnOffset ~= 0 or rowOffset ~= 0) and BoardRules.IsOnBoard(column, row) and IsPath(column)
                and not match:IsOccupied(column, row) then
                table.insert(reach, {Column = column, Row = row})
            end
        end
    end

    local isSafe = false

    for _, tile in ipairs(reach) do
        if not HasMark(marks, tile.Column, tile.Row) then
            isSafe = true
        end
    end

    -- Every escape covered: lift the mark from one tile he can reach, never his own
    if not isSafe then
        for i = #marks, 1, -1 do
            local mark = marks[i]
            local isOwn = mark.Column == king.Column and mark.Row == king.Row

            if not isOwn and HasMark(reach, mark.Column, mark.Row) then
                table.remove(marks, i)
                break
            end
        end
    end

    self.Marks = marks
end

-- A sniper stunned since it took aim drops its marks
function DeadmanWalking:IsLive(match, mark)
    local sniper = match.Pieces[mark.SniperId]

    return sniper ~= nil and not sniper:IsStunned()
end

-- The marked tiles from last turn are shelled: whatever white unit stands there is hit, each sniper's shot drawn
-- from its own tile
function DeadmanWalking:Fire(match)
    local shots = {}

    for _, mark in ipairs(self.Marks) do
        if not self:IsLive(match, mark) then continue end

        local sniper = match.Pieces[mark.SniperId]
        shots[sniper] = shots[sniper] or {Pellets = {}, Tiles = {}, Damaged = {}}

        local shot = shots[sniper]
        table.insert(shot.Pellets, {X = mark.Column - 0.5, Y = mark.Row - 0.5})
        table.insert(shot.Tiles, {Column = mark.Column, Row = mark.Row})

        local health, targetId = match:DamageWhiteTile(mark.Column, mark.Row, Config.SNIPER_DAMAGE)

        if health then
            table.insert(shot.Damaged, {Id = targetId, Column = mark.Column, Row = mark.Row, Health = health})
        end
    end

    for sniper, shot in pairs(shots) do
        match:SendAll("EnemyShotFired", sniper.Id, shot.Pellets, shot.Tiles, shot.Damaged)
    end
end

-- Snipers stunned during the player's turn are still stunned here, so they skip this volley and the next aim
function DeadmanWalking:OnEnemyTurn(match)
    self:Fire(match)
    self:Aim(match)
    match:SendTerrain()
end

function DeadmanWalking:CheckResult(match)
    if match.King.Row >= BoardConfig.SIZE then return "Victory" end

    return nil
end

function DeadmanWalking:GetTerrain()
    local tiles = {}

    for row = 1, BoardConfig.SIZE do
        for column = 1, BoardConfig.SIZE do
            if not IsPath(column) then
                table.insert(tiles, {column, row, "Cliff"})
            elseif row == BoardConfig.SIZE then
                table.insert(tiles, {column, row, "Goal"})
            end
        end
    end

    local marks = {}

    for _, mark in ipairs(self.Marks) do
        if self:IsLive(self.Match, mark) then
            table.insert(marks, {mark.Column, mark.Row})
        end
    end

    return {
        Tiles = tiles,
        Marks = marks,
        Summonable = self.Summonable,
    }
end

return DeadmanWalking
