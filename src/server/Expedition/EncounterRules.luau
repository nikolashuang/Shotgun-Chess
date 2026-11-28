local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)
local ExpeditionConfig = require(ReplicatedStorage.Shared.Expedition.ExpeditionConfig)

local EnemyConfig = ExpeditionConfig.Enemies
local Points = EnemyConfig.Points

-- Rolls a fresh enemy army from a point budget, different every battle
local EncounterRules = {}

local function GetKey(column, row)
    return column .. "," .. row
end

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

-- Rooks get likelier as the budget grows; everything else is even
local function PickMajor(random, options, points)
    local total = 0
    local weights = {}

    for i, pieceType in ipairs(options) do
        weights[i] = pieceType == "Rook" and 1 + points / EnemyConfig.ROOK_PRIORITY_POINTS or 1
        total += weights[i]
    end

    local roll = random:NextNumber() * total

    for i, pieceType in ipairs(options) do
        roll -= weights[i]
        if roll <= 0 then return pieceType end
    end

    return options[#options]
end

-- kind is "Battle", "Elite" or "Boss"; returns a list of {Type, Column, Row}
-- settings: Pool (piece types the region fields), Ambush (Mystery.Ambush: the army surrounds the King instead of
-- lining the back rows), Taken (tiles already used, as {column, row})
function EncounterRules.Generate(points, kind, random, settings)
    random = random or Random.new()
    settings = settings or {}

    local pool = settings.Pool or {"Pawn", "Knight", "Bishop", "Rook"}
    local ambush = settings.Ambush

    local enemies = {}
    local taken = {}
    local counts = {}

    for _, tile in ipairs(settings.Taken or {}) do
        taken[GetKey(tile[1], tile[2])] = true
    end

    local function Place(pieceType, column, row)
        table.insert(enemies, {Type = pieceType, Column = column, Row = row})
        taken[GetKey(column, row)] = true
    end

    -- Elites and Bosses always field the Queen on her own tile, paid from the budget; the Boss King is free
    if kind == "Elite" or kind == "Boss" then
        Place("Queen", EnemyConfig.QUEEN_TILE[1], EnemyConfig.QUEEN_TILE[2])
        points -= Points.Queen
    end

    if kind == "Boss" then
        Place("King", EnemyConfig.KING_TILE[1], EnemyConfig.KING_TILE[2])
    end

    -- Hold back a couple of pawns, spend most of the rest on the region's majors, then fill with pawns
    local hasPawns = table.find(pool, "Pawn") ~= nil
    local reserved = hasPawns and EnemyConfig.RESERVED_PAWNS or 0
    local spend = math.max(points - reserved, 0)
    local majors = {}

    while true do
        local options = {}

        for _, pieceType in ipairs(pool) do
            local cost = Points[pieceType]
            local cap = EnemyConfig.MaxCount[pieceType]
            local isMajor = pieceType ~= "Pawn" and pieceType ~= "Queen" and pieceType ~= "King"

            if isMajor and cost <= spend and (not cap or (counts[pieceType] or 0) < cap) then
                table.insert(options, pieceType)
            end
        end

        if #options == 0 then break end

        local pick = PickMajor(random, options, points)
        table.insert(majors, pick)
        counts[pick] = (counts[pick] or 0) + 1
        spend -= Points[pick]
    end

    local pawns = hasPawns and math.clamp(spend + reserved, 0, EnemyConfig.MAX_PAWNS) or 0

    local free = {}

    if ambush then
        for _, tile in ipairs(GetAmbushTiles(ambush, random)) do
            if not taken[GetKey(tile[1], tile[2])] then
                table.insert(free, tile)
            end
        end
    else
        for row = EnemyConfig.FIRST_ROW, BoardConfig.SIZE do
            for column = 1, BoardConfig.SIZE do
                if not taken[GetKey(column, row)] then
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

    -- Bishops alternate square colors so neither color is safe from them
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
