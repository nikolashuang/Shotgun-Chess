local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local BoardRules = require(ReplicatedStorage.Shared.Board.BoardRules)
local PieceSprites = require(ReplicatedStorage.Shared.Board.PieceSprites)
local PixelSprite = require(script.Parent.Parent.UI.PixelSprite)

local BoardRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BoardRemote")

local MOVE_COLOR = Color3.fromHex("354867")
local AIM_COLOR = Color3.fromHex("E6C47C")
local SHOT_COLOR = Color3.fromHex("D9544D")

local KING_PALETTE = {
    o = Color3.fromHex("171D32"),
    x = Color3.fromHex("F0E9D8"),
    g = Color3.fromHex("E6C47C"),
}

local board = nil
local actionPanel = nil
local kingSprite = nil
local kingColumn = nil
local kingRow = nil
local hoveredColumn = nil
local hoveredRow = nil
local previewTiles = {}

local BoardController = {}

local function GetTile(column, row)
    return board:FindFirstChild(BoardRules.GetTileName(column, row))
end

local function SetOverlay(tile, color, transparency)
    local overlay = tile:FindFirstChild("Overlay")
    if not overlay then return end

    overlay.Visible = color ~= nil

    if color then
        overlay.BackgroundColor3 = color
        overlay.BackgroundTransparency = transparency
    end
end

local function ClearPreview()
    for _, tile in pairs(previewTiles) do
        SetOverlay(tile, nil)
    end

    previewTiles = {}
end

local function MarkPreview(column, row, color, transparency)
    local tile = GetTile(column, row)
    if not tile then return end

    SetOverlay(tile, color, transparency)
    table.insert(previewTiles, tile)
end

function BoardController.RefreshPreview()
    ClearPreview()
    if not kingColumn then return end

    local selectedAction = actionPanel.SelectedAction

    if selectedAction == "Fire" then
        if not hoveredColumn then return end

        local tiles = BoardRules.GetShotgunArea(kingColumn, kingRow, hoveredColumn, hoveredRow)
        if not tiles then return end

        for _, target in pairs(tiles) do
            MarkPreview(target.Column, target.Row, AIM_COLOR, 0.35)
        end
    elseif selectedAction == nil then
        for columnOffset = -1, 1 do
            for rowOffset = -1, 1 do
                local column = kingColumn + columnOffset
                local row = kingRow + rowOffset

                if BoardRules.IsValidKingMove(kingColumn, kingRow, column, row) then
                    MarkPreview(column, row, MOVE_COLOR, 0.45)
                end
            end
        end
    end
end

local function OnTileClicked(column, row)
    if not kingColumn then return end

    local selectedAction = actionPanel.SelectedAction

    if selectedAction == "Fire" then
        if not BoardRules.GetShotgunArea(kingColumn, kingRow, column, row) then return end

        BoardRemote:FireServer("Fire", column, row)
        actionPanel.ClearSelection()
    elseif selectedAction == nil then
        if not BoardRules.IsValidKingMove(kingColumn, kingRow, column, row) then return end

        BoardRemote:FireServer("Move", column, row)
    end
end

local function BindTile(tile)
    local column = tile:GetAttribute("Column")
    local row = tile:GetAttribute("Row")
    if not column or not row then return end

    tile.MouseEnter:Connect(function()
        hoveredColumn = column
        hoveredRow = row
        BoardController.RefreshPreview()
    end)

    tile.MouseLeave:Connect(function()
        if hoveredColumn ~= column or hoveredRow ~= row then return end

        hoveredColumn = nil
        hoveredRow = nil
        BoardController.RefreshPreview()
    end)

    tile.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

        OnTileClicked(column, row)
    end)
end

local function PlaceKing(column, row)
    kingColumn = column
    kingRow = row

    if not kingSprite then
        kingSprite = Instance.new("Frame")
        kingSprite.Name = "KingSprite"
        kingSprite.BackgroundTransparency = 1
        kingSprite.AnchorPoint = Vector2.new(0.5, 0.5)
        kingSprite.Position = UDim2.fromScale(0.5, 0.5)
        kingSprite.Size = UDim2.fromScale(0.85, 0.85)
        kingSprite.ZIndex = 3
        PixelSprite.Draw(kingSprite, PieceSprites.KingShotgun, KING_PALETTE)
    end

    kingSprite.Parent = GetTile(column, row)
    BoardController.RefreshPreview()
end

local function ShowShot(tiles)
    ClearPreview()

    local hitTiles = {}
    for _, target in pairs(tiles) do
        local tile = GetTile(target.Column, target.Row)
        if tile then
            SetOverlay(tile, SHOT_COLOR, 0.2)
            table.insert(hitTiles, tile)
        end
    end

    task.delay(0.3, function()
        for _, tile in pairs(hitTiles) do
            SetOverlay(tile, nil)
        end

        BoardController.RefreshPreview()
    end)
end

local init = false
function BoardController.Init(actionPanelController)
    if init then return end
    init = true

    actionPanel = actionPanelController
    actionPanel.OnSelectionChanged = BoardController.RefreshPreview

    local hud = Players.LocalPlayer.PlayerGui:WaitForChild("GameHUD")
    board = hud:WaitForChild("Root"):WaitForChild("BoardFrame"):WaitForChild("Board")

    for _, tile in pairs(board:GetChildren()) do
        BindTile(tile)
    end

    BoardRemote.OnClientEvent:Connect(function(action, ...)
        if action == "KingMoved" then
            PlaceKing(...)
        elseif action == "ShotFired" then
            ShowShot(...)
        end
    end)
end

function BoardController.StartMatch()
    BoardRemote:FireServer("StartMatch")
end

return BoardController
