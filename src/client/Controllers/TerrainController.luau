local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)
local BoardRules = require(ReplicatedStorage.Shared.Board.BoardRules)

-- How each kind of tile looks, laid over the board skin under the move highlights
local TILE_LOOKS = {
    -- Deadman Walking's drop on either side of the path
    Cliff = {Color = Color3.fromHex("120E14"), Transparency = 0.2},
    -- Haunted Mansion's walls
    Wall = {Color = Color3.fromHex("2A2230"), Transparency = 0, Stroke = Color3.fromHex("4A3E52")},
    -- Where the King (or the payload) has to get to
    Goal = {Color = Color3.fromHex("D4A85A"), Transparency = 0.5},
    -- Dangerous Payload's route
    Track = {Color = Color3.fromHex("9C574B"), Transparency = 0.65},
    Gold = {Color = Color3.fromHex("D4A85A"), Chest = true},
    Artifact = {Color = Color3.fromHex("8E6FD1"), Chest = true},
}

local CHEST_SIZE = 0.38
local CHEST_OUTLINE = Color3.fromHex("332A35")

-- Sniper marks pulse red over the tiles about to be shelled
local MARK_COLOR = Color3.fromHex("C8644F")
local MARK_TRANSPARENCY = {0.35, 0.65}
local MARK_PULSE = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

-- The Haunted Mansion is dark past the King's light: the edge of it is dim, beyond is near black
local DARK_COLOR = Color3.fromHex("08060A")
local EDGE_TRANSPARENCY = 0.55
local DARK_TRANSPARENCY = 0
-- Above pieces (which stack up to the board's size by row) and their health bars, so whatever is out in the dark
-- stays hidden
local DARK_Z = 20
local MARK_Z = 2

local board = nil
local terrain = {}
-- Tile key -> kind
local tileKinds = {}
local tileFrames = {}
local markLayer = nil
local darkLayer = nil
local darkFrames = {}
local kingColumn, kingRow = nil, nil

-- Regional Encounter boards: cliffs, walls, goals, chests, sniper marks and darkness
local TerrainController = {}

local function GetKey(column, row)
    return column * 100 + row
end

local function ToBoardPosition(column, row)
    return UDim2.fromScale((column - 0.5) / BoardConfig.SIZE, 1 - (row - 0.5) / BoardConfig.SIZE)
end

local function NewLayer(name, zIndex)
    local layer = Instance.new("Frame")
    layer.Name = name
    layer.BackgroundTransparency = 1
    layer.Size = UDim2.fromScale(1, 1)
    layer.ZIndex = zIndex
    layer.Interactable = false
    layer.Parent = board

    return layer
end

local function NewTileFrame(parent, column, row, zIndex)
    local frame = Instance.new("Frame")
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = ToBoardPosition(column, row)
    frame.Size = UDim2.fromScale(1 / BoardConfig.SIZE, 1 / BoardConfig.SIZE)
    frame.BorderSizePixel = 0
    frame.ZIndex = zIndex
    frame.Interactable = false
    frame.Parent = parent

    return frame
end

-- Tile looks sit inside the tile itself, under its highlight overlay
local function DrawTile(column, row, kind)
    local look = TILE_LOOKS[kind]
    local tile = board:FindFirstChild(BoardRules.GetTileName(column, row))
    if not look or not tile then return end

    local frame = Instance.new("Frame")
    frame.Name = "Terrain"
    frame.Size = UDim2.fromScale(1, 1)
    frame.BorderSizePixel = 0
    frame.ZIndex = 1
    frame.Interactable = false
    frame.BackgroundTransparency = 1
    frame.Parent = tile

    if look.Chest then
        local chest = Instance.new("Frame")
        chest.AnchorPoint = Vector2.new(0.5, 0.5)
        chest.Position = UDim2.fromScale(0.5, 0.55)
        chest.Size = UDim2.fromScale(CHEST_SIZE, CHEST_SIZE * 0.8)
        chest.BackgroundColor3 = look.Color
        chest.BorderSizePixel = 0
        chest.ZIndex = 1
        chest.Parent = frame

        local stroke = Instance.new("UIStroke")
        stroke.Color = CHEST_OUTLINE
        stroke.Thickness = 2
        stroke.Parent = chest

        local lid = Instance.new("Frame")
        lid.Position = UDim2.fromScale(0, 0.35)
        lid.Size = UDim2.new(1, 0, 0, 2)
        lid.BackgroundColor3 = CHEST_OUTLINE
        lid.BorderSizePixel = 0
        lid.ZIndex = 1
        lid.Parent = chest
    else
        frame.BackgroundColor3 = look.Color
        frame.BackgroundTransparency = look.Transparency

        if look.Stroke then
            local stroke = Instance.new("UIStroke")
            stroke.Color = look.Stroke
            stroke.Thickness = 2
            stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            stroke.Parent = frame
        end
    end

    table.insert(tileFrames, frame)
end

local function DrawMarks()
    markLayer:ClearAllChildren()

    for _, mark in ipairs(terrain.Marks or {}) do
        local frame = NewTileFrame(markLayer, mark[1], mark[2], MARK_Z)
        frame.BackgroundColor3 = MARK_COLOR
        frame.BackgroundTransparency = MARK_TRANSPARENCY[1]

        local stroke = Instance.new("UIStroke")
        stroke.Color = MARK_COLOR
        stroke.Thickness = 2
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Parent = frame

        -- A crosshair over the tile
        for _, size in ipairs({UDim2.new(0.6, 0, 0, 2), UDim2.new(0, 2, 0.6, 0)}) do
            local line = Instance.new("Frame")
            line.AnchorPoint = Vector2.new(0.5, 0.5)
            line.Position = UDim2.fromScale(0.5, 0.5)
            line.Size = size
            line.BackgroundColor3 = MARK_COLOR
            line.BorderSizePixel = 0
            line.ZIndex = MARK_Z
            line.Parent = frame
        end

        TweenService:Create(frame, MARK_PULSE, {BackgroundTransparency = MARK_TRANSPARENCY[2]}):Play()
    end
end

local function UpdateDarkness()
    local range = terrain.LightRange

    for key, frame in pairs(darkFrames) do
        local column, row = key // 100, key % 100
        local distance = kingColumn and BoardRules.GetDistance(kingColumn, kingRow, column, row) or math.huge

        -- The way out always glows, so the player knows where to head
        if not range or distance < range or tileKinds[key] == "Goal" then
            frame.Visible = false
        else
            frame.Visible = true
            frame.BackgroundTransparency = distance == range and EDGE_TRANSPARENCY or DARK_TRANSPARENCY
        end
    end
end

function TerrainController.Clear()
    TerrainController.Set({})
end

function TerrainController.Set(newTerrain)
    terrain = newTerrain or {}
    tileKinds = {}

    for _, frame in ipairs(tileFrames) do
        frame:Destroy()
    end

    tileFrames = {}

    for _, tile in ipairs(terrain.Tiles or {}) do
        tileKinds[GetKey(tile[1], tile[2])] = tile[3]
        DrawTile(tile[1], tile[2], tile[3])
    end

    DrawMarks()
    UpdateDarkness()
end

function TerrainController.SetKingTile(column, row)
    kingColumn, kingRow = column, row
    UpdateDarkness()
end

function TerrainController.IsWall(column, row)
    return tileKinds[GetKey(column, row)] == "Wall"
end

-- Cliffs and walls keep the King out; in the Haunted Mansion he can't squeeze diagonally between two walls
function TerrainController.CanKingEnter(fromColumn, fromRow, column, row)
    local kind = tileKinds[GetKey(column, row)]
    if kind == "Cliff" or kind == "Wall" then return false end

    if terrain.NoCornerCutting and column ~= fromColumn and row ~= fromRow then
        if TerrainController.IsWall(column, fromRow) and TerrainController.IsWall(fromColumn, row) then return false end
    end

    return true
end

-- Piece types this fight allows summoning, or nil for all
function TerrainController.GetSummonable()
    return terrain.Summonable
end

function TerrainController.Init(boardFrame)
    board = boardFrame
    markLayer = NewLayer("Marks", MARK_Z)
    darkLayer = NewLayer("Darkness", DARK_Z)

    for column = 1, BoardConfig.SIZE do
        for row = 1, BoardConfig.SIZE do
            local frame = NewTileFrame(darkLayer, column, row, DARK_Z)
            frame.BackgroundColor3 = DARK_COLOR
            frame.Visible = false
            darkFrames[GetKey(column, row)] = frame
        end
    end
end

return TerrainController
