local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)
local CampaignConfig = require(ReplicatedStorage.Shared.Campaign.CampaignConfig)

local EncounterConfig = CampaignConfig.Encounter
local Points = EncounterConfig.Points

-- Rolls a fresh enemy army from a point budget, different every battle
local EncounterRules = {}

-- Tiles RING_MIN to RING_MAX steps from the King (counting diagonals as one), nearest ring first, each ring shuffled
local function GetAmbushTiles(ambush, random)
    local king = ambush.KING_TILE
    local tiles = {}

    for distance = ambush.RING_MIN, ambush.RING_MAX do
        local ring = {}

        for column = king[1] - distance, king[1] + distance do
            for row = king[2] - distance, king[2] + distance do
                local isOnRing = math.max(math.abs(column - king[1]), math.abs(row - king[2])) == distance
                local isOnBoard = column >= 1 and column <= BoardConfig.SIZE and row >= 1 and row <= BoardConfig.SIZE

                if isOnRing and isOnBoard then
                    table.insert(ring, {column, row})
                end
            end
        end

        random:Shuffle(ring)
        table.move(ring, 1, #ring, #tiles + 1, tiles)
    end

    return tiles
end

-- nodeType is "Combat", "Queen" or "King"; returns a list of {Type, Column, Row}
-- With ambush (CampaignConfig.Mystery.Ambush) the same army surrounds the King instead of lining the back rows
function EncounterRules.Generate(points, nodeType, random, ambush)
    random = random or Random.new()

    local enemies = {}
    local taken = {}

    local function Place(pieceType, column, row)
        table.insert(enemies, {Type = pieceType, Column = column, Row = row})
        taken[column .. "," .. row] = true
    end

    -- Boss battles always field the Queen on her own tile; her points come out of the budget, the King is free
    if nodeType == "Queen" or nodeType == "King" then
        Place("Queen", EncounterConfig.QUEEN_TILE[1], EncounterConfig.QUEEN_TILE[2])
        points -= Points.Queen
    end

    if nodeType == "King" then
        Place("King", EncounterConfig.KING_TILE[1], EncounterConfig.KING_TILE[2])
    end

    -- Keep a couple of pawns back, spend the rest on Rooks, Knights and Bishops, then fill with pawns
    local spend = points - EncounterConfig.RESERVED_PAWNS
    local majors = {}

    while true do
        local options = {}

        for _, pieceType in ipairs(EncounterConfig.MAJORS) do
            if Points[pieceType] <= spend then
                table.insert(options, pieceType)
            end
        end

        if #options == 0 then break end

        local pick = options[random:NextInteger(1, #options)]
        table.insert(majors, pick)
        spend -= Points[pick]
    end

    local pawns = math.clamp(spend + EncounterConfig.RESERVED_PAWNS, 0, EncounterConfig.MAX_PAWNS)

    if pawns == EncounterConfig.MAX_PAWNS and not ambush then
        for column = 1, BoardConfig.SIZE do
            Place("Pawn", column, EncounterConfig.FIRST_ROW)
        end

        pawns = 0
    end

    local free = {}

    if ambush then
        free = GetAmbushTiles(ambush, random)
    else
        for row = EncounterConfig.FIRST_ROW, BoardConfig.SIZE do
            for column = 1, BoardConfig.SIZE do
                if not taken[column .. "," .. row] then
                    table.insert(free, {column, row})
                end
            end
        end

        random:Shuffle(free)
    end

    -- Takes the first free tile that passes the check
    local function TakeTile(check)
        for i, tile in ipairs(free) do
            if not check or check(tile) then
                table.remove(free, i)
                return tile
            end
        end

        return nil
    end

    -- In an ambush the pawns take the tiles above the King, where their forward attacks reach him
    local function IsAboveKing(candidate)
        return ambush ~= nil and candidate[2] > ambush.KING_TILE[2]
    end

    -- Bishops alternate square colors so no color is safe from them
    local bishops = 0

    for _, pieceType in ipairs(majors) do
        local tile = nil

        if pieceType == "Bishop" then
            local color = bishops % 2
            tile = TakeTile(function(candidate)
                return (candidate[1] + candidate[2]) % 2 == color
            end)
            bishops += 1
        end

        tile = tile or TakeTile(function(candidate)
            return not IsAboveKing(candidate)
        end) or TakeTile()
        if not tile then break end

        Place(pieceType, tile[1], tile[2])
    end

    for _ = 1, pawns do
        local tile = ambush and TakeTile(IsAboveKing) or TakeTile()
        if not tile then break end

        Place("Pawn", tile[1], tile[2])
    end

    return enemies
end

return EncounterRules
