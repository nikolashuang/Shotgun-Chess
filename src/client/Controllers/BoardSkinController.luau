local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local SkinConfig = require(ReplicatedStorage.Shared.Skins.SkinConfig)
local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)

local ACCENT_THICKNESS = 2
local PREVIEW_TILES = 6
local PREVIEW_ACCENT_THICKNESS = 1
-- The board's own colors, built in Studio
local CLASSIC_LIGHT = Color3.fromHex("D49A77")
local CLASSIC_DARK = Color3.fromHex("9C574B")

local player = Players.LocalPlayer

-- Paints the game board with the equipped board skin; Classic keeps the colors the board was built with
-- Tiles are dark where column + row is even (A1 is dark, like a real chessboard)
local BoardSkinController = {}

function BoardSkinController.IsDark(column, row)
    return (column + row) % 2 == 0
end

-- Works on any tile with Column and Row attributes, so the Armory preview reuses it
function BoardSkinController.PaintTile(tile, skinName)
    local skin = SkinConfig.Skins.Board[skinName] or SkinConfig.Skins.Board[SkinConfig.DEFAULT_BOARD]
    local isDark = BoardSkinController.IsDark(tile:GetAttribute("Column"), tile:GetAttribute("Row"))

    if tile:GetAttribute("BaseColor") == nil then
        tile:SetAttribute("BaseColor", tile.BackgroundColor3)
    end

    tile.BackgroundColor3 = (isDark and skin.Dark or skin.Light) or tile:GetAttribute("BaseColor")

    local image = tile:FindFirstChild("SkinImage")

    if skin.Image and skin.Image ~= 0 then
        if not image then
            image = Instance.new("ImageLabel")
            image.Name = "SkinImage"
            image.Size = UDim2.fromScale(1, 1)
            image.BackgroundTransparency = 1
            image.ResampleMode = Enum.ResamplerMode.Pixelated
            image.ZIndex = tile.ZIndex
            -- First child, so the overlay and pieces draw over it
            image.LayoutOrder = -1
            image.Parent = tile
        end

        local size = SkinConfig.BOARD_IMAGE_TILE
        local column, row = tile:GetAttribute("Column"), tile:GetAttribute("Row")

        image.Image = "rbxassetid://" .. skin.Image
        image.ImageRectSize = Vector2.new(size, size)
        image.ImageRectOffset = Vector2.new((column - 1) * size, (BoardConfig.SIZE - row) * size)
        image.Visible = true
    elseif image then
        image.Visible = false
    end

    local accent = tile:FindFirstChild("SkinAccent")

    if skin.Accent then
        if not accent then
            accent = Instance.new("UIStroke")
            accent.Name = "SkinAccent"
            accent.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            accent.Thickness = ACCENT_THICKNESS
            accent.Parent = tile
        end

        accent.Color = skin.Accent
        accent.Enabled = true
    elseif accent then
        accent.Enabled = false
    end
end

function BoardSkinController.Paint(board, skinName)
    for _, tile in pairs(board:GetChildren()) do
        if tile:IsA("GuiObject") and tile:GetAttribute("Column") then
            BoardSkinController.PaintTile(tile, skinName)
        end
    end
end

-- Fills a frame with a small square board (bottom left corner of the real one) painted in a skin, for shop and Armory cards
function BoardSkinController.BuildPreview(frame, skinName)
    local size = PREVIEW_TILES

    for column = 1, size do
        for row = 1, size do
            local tile = Instance.new("Frame")
            tile.Name = "Tile"
            tile.Size = UDim2.fromScale(1 / size, 1 / size)
            tile.Position = UDim2.fromScale((column - 1) / size, (size - row) / size)
            tile.BorderSizePixel = 0
            tile.ZIndex = frame.ZIndex
            tile:SetAttribute("Column", column)
            tile:SetAttribute("Row", row)
            -- Classic falls back to the color a tile starts with, so preview tiles start as the real board's
            tile.BackgroundColor3 = BoardSkinController.IsDark(column, row) and CLASSIC_DARK or CLASSIC_LIGHT
            tile.Parent = frame

            BoardSkinController.PaintTile(tile, skinName)

            -- Preview tiles are small, so the accent border is thinner than on the real board
            local accent = tile:FindFirstChild("SkinAccent")
            if accent then
                accent.Thickness = PREVIEW_ACCENT_THICKNESS
            end
        end
    end
end

local init = false
function BoardSkinController.Init(board)
    if init then return end
    init = true

    local function Refresh()
        BoardSkinController.Paint(board, player:GetAttribute("BoardSkin"))
    end

    player:GetAttributeChangedSignal("BoardSkin"):Connect(Refresh)
    Refresh()
end

return BoardSkinController
