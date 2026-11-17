local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local PieceConfig = require(ReplicatedStorage.Shared.Board.PieceConfig)
local AnimatedSpriteClass = require(script.Parent.Parent.UI.AnimatedSpriteClass)

local SELECTED_COLOR = Color3.fromHex("F1D4AC")
local DEFAULT_COLOR = Color3.fromHex("9C574B")
local AFFORDABLE_COLOR = Color3.fromHex("D49A77")
local EXPENSIVE_COLOR = Color3.fromHex("C8644F")

local CARD_PIECES = {
    PawnCard = "Pawn",
    KnightCard = "Knight",
    BishopCard = "Bishop",
    RookCard = "Rook",
    QueenCard = "Queen",
}

local SLIDE_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local cardsByPiece = {}
local hud = nil
local root = nil
local summonPanel = nil
local openPosition = nil
local isOpen = false

local SummonPanelController = {}

SummonPanelController.SelectedPiece = nil
SummonPanelController.OnCardSelected = nil

local function SetHighlight(pieceType, enabled)
    local card = cardsByPiece[pieceType]
    if not card then return end

    card.UIStroke.Color = enabled and SELECTED_COLOR or DEFAULT_COLOR
end

function SummonPanelController.ClearSelection()
    if not SummonPanelController.SelectedPiece then return end

    SetHighlight(SummonPanelController.SelectedPiece, false)
    SummonPanelController.SelectedPiece = nil
end

-- Costs turn red when the player can't afford the piece
function SummonPanelController.SetEnergy(energy)
    for pieceType, card in pairs(cardsByPiece) do
        card.Cost.TextColor3 = energy >= PieceConfig.Cost[pieceType] and AFFORDABLE_COLOR or EXPENSIVE_COLOR
    end
end

function SummonPanelController.SelectPiece(pieceType)
    SummonPanelController.ClearSelection()
    SummonPanelController.SelectedPiece = pieceType
    SetHighlight(pieceType, true)

    if SummonPanelController.OnCardSelected then
        SummonPanelController.OnCardSelected(pieceType)
    end
end

-- Offset that pushes the panel just past the right edge of the screen
local function GetClosedPosition()
    if hud.AbsoluteSize.X == 0 then
        return openPosition + UDim2.fromScale(1, 0)
    end

    local openRight = root.AbsolutePosition.X + openPosition.X.Scale * root.AbsoluteSize.X
    local offset = hud.AbsoluteSize.X - openRight + 10

    return openPosition + UDim2.fromOffset(offset, 0)
end

-- Cards stay off screen until Summon is selected, so they can't be picked first
function SummonPanelController.SetOpen(open)
    if open == isOpen then return end
    isOpen = open

    local goal = open and openPosition or GetClosedPosition()
    TweenService:Create(summonPanel, SLIDE_INFO, {Position = goal}):Play()
end

local init = false
function SummonPanelController.Init()
    if init then return end
    init = true

    hud = Players.LocalPlayer.PlayerGui:WaitForChild("GameHUD")
    root = hud:WaitForChild("Root")
    summonPanel = root:WaitForChild("RightPanel")
    openPosition = summonPanel.Position

    for cardName, pieceType in pairs(CARD_PIECES) do
        local card = summonPanel:WaitForChild(cardName)
        cardsByPiece[pieceType] = card
        card:WaitForChild("Cost").Text = PieceConfig.Cost[pieceType] .. " Energy"

        local sprite = AnimatedSpriteClass.new(pieceType, card:WaitForChild("Sprite"))
        sprite.Image.Size = UDim2.fromScale(1, 1)

        card.Activated:Connect(function()
            SummonPanelController.SelectPiece(pieceType)
        end)
    end

    summonPanel.Position = GetClosedPosition()

    hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if isOpen then return end

        summonPanel.Position = GetClosedPosition()
    end)
end

return SummonPanelController
