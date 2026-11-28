local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)
local PieceConfig = require(ReplicatedStorage.Shared.Board.PieceConfig)
local ExpeditionConfig = require(ReplicatedStorage.Shared.Expedition.ExpeditionConfig)

local Config = ExpeditionConfig.Exclusives.HauntedMansion

local UNDEAD = {G = "Ghost", Z = "Zombie"}
local CHESTS = {["$"] = "Gold", A = "Artifact"}

-- Gravehollow Regional Encounter: a dark maze of walls with Ghosts (drift through walls) and Zombies (shamble every
-- other turn). Chests along the way hold Gold or an Artifact, paid out if the King makes it to the exit
local HauntedMansion = {}
HauntedMansion.__index = HauntedMansion

local function GetKey(column, row)
    return column * 100 + row
end

-- Calls back with every tile of the layout and its symbol; the first string is the top row
local function ForEachTile(callback)
    for index, line in ipairs(Config.LAYOUT) do
        local row = BoardConfig.SIZE - index + 1

        for column = 1, BoardConfig.SIZE do
            callback(column, row, line:sub(column, column))
        end
    end
end

function HauntedMansion.GetEnemies()
    local enemies = {}

    ForEachTile(function(column, row, symbol)
        local pieceType = UNDEAD[symbol]
        if not pieceType then return end

        table.insert(enemies, {
            Type = pieceType,
            Column = column,
            Row = row,
            MaxHealth = PieceConfig.Health[pieceType],
            DamageBonus = 0,
        })
    end)

    return enemies
end

function HauntedMansion.new()
    local self = setmetatable({}, HauntedMansion)

    self.KingTile = Config.KING_TILE
    self.Walls = {}
    -- Tile key -> "Gold" or "Artifact", until the King picks it up
    self.Chests = {}
    -- What the King has picked up, paid out on reaching the exit
    self.Collected = {}
    self.Match = nil

    ForEachTile(function(column, row, symbol)
        if symbol == "#" then
            self.Walls[GetKey(column, row)] = true
        elseif CHESTS[symbol] then
            self.Chests[GetKey(column, row)] = CHESTS[symbol]
        end
    end)

    return self
end

-- A diagonal step can't squeeze between two walls touching at the corner
function HauntedMansion:CanKingEnter(match, column, row)
    local king = match.King
    local columnStep = column - king.Column
    local rowStep = row - king.Row

    if columnStep ~= 0 and rowStep ~= 0 then
        local isSideWall = self.Walls[GetKey(king.Column + columnStep, king.Row)]
        local isOtherWall = self.Walls[GetKey(king.Column, king.Row + rowStep)]

        if isSideWall and isOtherWall then return false end
    end

    return true
end

function HauntedMansion:Setup(match)
    self.Match = match
end

function HauntedMansion:OnKingMoved(match)
    local key = GetKey(match.King.Column, match.King.Row)
    local chest = self.Chests[key]
    if not chest then return end

    self.Chests[key] = nil
    table.insert(self.Collected, chest)
    match:SendTerrain()
end

-- Zombies only act every other turn
function HauntedMansion:OnEnemyTurn(match)
    for _, piece in pairs(match.Pieces) do
        if piece.Type == "Zombie" and match.Turn % 2 == 0 then
            piece.isResting = true
        end
    end
end

function HauntedMansion:CheckResult(match)
    local king = match.King

    for _, exit in ipairs(Config.EXITS) do
        if king.Column == exit[1] and king.Row == exit[2] then return "Victory" end
    end

    return nil
end

function HauntedMansion:GetTerrain()
    local tiles = {}

    for key in pairs(self.Walls) do
        table.insert(tiles, {key // 100, key % 100, "Wall"})
    end

    for key, chest in pairs(self.Chests) do
        table.insert(tiles, {key // 100, key % 100, chest})
    end

    for _, exit in ipairs(Config.EXITS) do
        table.insert(tiles, {exit[1], exit[2], "Goal"})
    end

    return {
        Tiles = tiles,
        LightRange = Config.LIGHT_RANGE,
        NoCornerCutting = true,
    }
end

return HauntedMansion
