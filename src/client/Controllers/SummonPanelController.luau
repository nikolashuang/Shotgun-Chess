local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PieceConfig = require(ReplicatedStorage.Shared.Board.PieceConfig)
local AnimatedSpriteClass = require(script.Parent.Parent.UI.AnimatedSpriteClass)

local SELECTED_COLOR = Color3.fromHex("E6C47C")
local DEFAULT_COLOR = Color3.fromHex("354867")
local AFFORDABLE_COLOR = Color3.fromHex("698FA9")
local EXPENSIVE_COLOR = Color3.fromHex("D9544D")

local CARD_PIECES = {
    PawnCard = "Pawn",
    KnightCard = "Knight",
    BishopCard = "Bishop",
    RookCard = "Rook",
    QueenCard = "Queen",
}

local cardsByPiece = {}

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

local init = false
function SummonPanelController.Init()
    if init then return end
    init = true

    local hud = Players.LocalPlayer.PlayerGui:WaitForChild("GameHUD")
    local rightPanel = hud:WaitForChild("Root"):WaitForChild("RightPanel")

    for cardName, pieceType in pairs(CARD_PIECES) do
        local card = rightPanel:WaitForChild(cardName)
        cardsByPiece[pieceType] = card
        card:WaitForChild("Cost").Text = PieceConfig.Cost[pieceType] .. " ENERGY"

        local sprite = AnimatedSpriteClass.new(pieceType, card:WaitForChild("Sprite"))
        sprite.Image.Size = UDim2.fromScale(1, 1)

        card.Activated:Connect(function()
            SummonPanelController.SelectPiece(pieceType)
        end)
    end
end

return SummonPanelController
