local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)

local SIZE = BoardConfig.SIZE

-- Duels turn the board 180 degrees for the Black player, so both players see themselves
-- at the bottom as White and the client never needs to know which side it is on
local MirrorRules = {}

local TILE_KEYS = {Column = true, Row = true, KnockColumn = true, KnockRow = true}
local POINT_KEYS = {X = true, Y = true}

-- Index of the first of each event's tile arguments (column, then row)
local EVENT_TILES = {
    KingMoved = 1,
    KingAmbushed = 1,
    EnergyDropped = 1,
    SmokeChanged = 1,
    PieceMoved = 2,
    SoulAdded = 3,
    PieceAdded = 4,
}

-- Index of each event's team argument
local EVENT_TEAMS = {
    PieceAdded = 3,
}

function MirrorRules.Tile(value)
    return SIZE + 1 - value
end

-- Board positions run from 0 to SIZE, with tile N covering N - 1 to N
function MirrorRules.Point(value)
    return SIZE - value
end

function MirrorRules.Team(team)
    if team == "White" then return "Black" end
    if team == "Black" then return "White" end

    return team
end

-- Copies a table, mirroring every tile and point field at any depth
function MirrorRules.Table(value)
    local copy = {}

    for key, field in pairs(value) do
        if typeof(field) == "number" and TILE_KEYS[key] then
            copy[key] = MirrorRules.Tile(field)
        elseif typeof(field) == "number" and POINT_KEYS[key] then
            copy[key] = MirrorRules.Point(field)
        elseif typeof(field) == "table" then
            copy[key] = MirrorRules.Table(field)
        else
            copy[key] = field
        end
    end

    return copy
end

-- args is a table.pack of an event's arguments; returns them mirrored
function MirrorRules.Event(action, args)
    local mirrored = table.clone(args)

    for i = 1, args.n do
        if typeof(args[i]) == "table" then
            mirrored[i] = MirrorRules.Table(args[i])
        end
    end

    local tileIndex = EVENT_TILES[action]

    if tileIndex and typeof(args[tileIndex]) == "number" then
        mirrored[tileIndex] = MirrorRules.Tile(args[tileIndex])
        mirrored[tileIndex + 1] = MirrorRules.Tile(args[tileIndex + 1])
    end

    local teamIndex = EVENT_TEAMS[action]

    if teamIndex then
        mirrored[teamIndex] = MirrorRules.Team(args[teamIndex])
    end

    return table.unpack(mirrored, 1, args.n)
end

return MirrorRules
