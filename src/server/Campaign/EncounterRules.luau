local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)
local CampaignConfig = require(ReplicatedStorage.Shared.Campaign.CampaignConfig)

local EncounterConfig = CampaignConfig.Encounter
local Points = EncounterConfig.Points

-- Rolls a fresh enemy army from a point budget, different every battle
local EncounterRules = {}

-- nodeType is "Combat", "Queen" or "King"; returns a list of {Type, Column, Row}
function EncounterRules.Generate(points, nodeType, random)
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

    if pawns == EncounterConfig.MAX_PAWNS then
        for column = 1, BoardConfig.SIZE do
            Place("Pawn", column, EncounterConfig.FIRST_ROW)
        end

        pawns = 0
    end

    local free = {}

    for row = EncounterConfig.FIRST_ROW, BoardConfig.SIZE do
        for column = 1, BoardConfig.SIZE do
            if not taken[column .. "," .. row] then
                table.insert(free, {column, row})
            end
        end
    end

    random:Shuffle(free)

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

        tile = tile or TakeTile()
        if not tile then break end

        Place(pieceType, tile[1], tile[2])
    end

    for _ = 1, pawns do
        local tile = TakeTile()
        if not tile then break end

        Place("Pawn", tile[1], tile[2])
    end

    return enemies
end

return EncounterRules
