local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local PieceConfig = require(ReplicatedStorage.Shared.Board.PieceConfig)
local AnimatedSpriteClass = require(script.Parent.Parent.UI.AnimatedSpriteClass)
local PieceController = require(script.Parent.PieceController)

local SELECTED_COLOR = Color3.fromHex("F1D4AC")
local DEFAULT_COLOR = Color3.fromHex("9C574B")
local AFFORDABLE_COLOR = Color3.fromHex("D49A77")
local EXPENSIVE_COLOR = Color3.fromHex("C8644F")
-- Cards for pieces already at their limit on the board (one Queen) are faded out
local MAXED_TRANSPARENCY = 0.6

local CARD_PIECES = {
    PawnCard = "Pawn",
    KnightCard = "Knight",
    BishopCard = "Bishop",
    RookCard = "Rook",
    QueenCard = "Queen",
}

local SLIDE_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local cardsByPiece = {}
local spritesByPiece = {}
-- Piece type -> true while its card shows as maxed out
local maxedPieces = {}
-- Piece type -> true when this fight doesn't allow summoning it (Deadman Walking only takes Rooks and Queens)
local blockedPieces = {}
local energyLeft = 0
-- Piece type -> cost replacing PieceConfig.Cost, from the equipped class (Monarch's Loyalty)
local costOverrides = {}
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

-- True when the player's side already has as many of this piece as it's allowed (the one Queen), or the fight
-- doesn't allow it at all
function SummonPanelController.IsMaxed(pieceType)
    if blockedPieces[pieceType] then return true end

    local maxActive = PieceConfig.MaxActive[pieceType]
    if not maxActive then return false end

    local count = 0

    for _, piece in ipairs(PieceController.GetTeamPieces("White")) do
        if piece.Type == pieceType then
            count += 1
        end
    end

    return count >= maxActive
end

function SummonPanelController.GetCost(pieceType)
    return costOverrides[pieceType] or PieceConfig.Cost[pieceType]
end

-- Costs turn red when the player can't afford the piece
function SummonPanelController.SetEnergy(energy)
    energyLeft = energy

    for pieceType, card in pairs(cardsByPiece) do
        card.Cost.TextColor3 = energy >= SummonPanelController.GetCost(pieceType) and AFFORDABLE_COLOR or EXPENSIVE_COLOR
    end
end

function SummonPanelController.SetCostOverrides(overrides)
    costOverrides = overrides

    for pieceType, card in pairs(cardsByPiece) do
        if not maxedPieces[pieceType] then
            card.Cost.Text = SummonPanelController.GetCost(pieceType) .. " Energy"
        end
    end

    SummonPanelController.SetEnergy(energyLeft)
end

local function SetMaxed(pieceType, isMaxed)
    local card = cardsByPiece[pieceType]
    local transparency = isMaxed and MAXED_TRANSPARENCY or 0

    maxedPieces[pieceType] = isMaxed
    card.PieceName.TextTransparency = transparency
    card.Health.TextTransparency = transparency
    card.Cost.TextTransparency = transparency
    card.Cost.Text = isMaxed and (blockedPieces[pieceType] and "Unavailable" or "On Board") or SummonPanelController.GetCost(pieceType) .. " Energy"
    spritesByPiece[pieceType].Image.ImageTransparency = transparency

    if isMaxed and SummonPanelController.SelectedPiece == pieceType then
        SummonPanelController.ClearSelection()
    end
end

-- Pieces come and go in many ways (summons, kills, captures), so the limits are checked every frame
local function UpdateLimits()
    for pieceType in pairs(PieceConfig.MaxActive) do
        local isMaxed = SummonPanelController.IsMaxed(pieceType)

        if isMaxed ~= (maxedPieces[pieceType] == true) then
            SetMaxed(pieceType, isMaxed)
            SummonPanelController.SetEnergy(energyLeft)
        end
    end
end

-- allowed is the list of piece types this fight lets the player summon, or nil for all of them
function SummonPanelController.SetAllowed(allowed)
    for pieceType in pairs(cardsByPiece) do
        blockedPieces[pieceType] = allowed ~= nil and not table.find(allowed, pieceType) or nil
        SetMaxed(pieceType, SummonPanelController.IsMaxed(pieceType))
    end

    SummonPanelController.SetEnergy(energyLeft)
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
        spritesByPiece[pieceType] = sprite

        card.Activated:Connect(function()
            if maxedPieces[pieceType] then return end

            SummonPanelController.SelectPiece(pieceType)
        end)
    end

    RunService.Heartbeat:Connect(UpdateLimits)

    summonPanel.Position = GetClosedPosition()

    hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if isOpen then return end

        summonPanel.Position = GetClosedPosition()
    end)
end

return SummonPanelController
