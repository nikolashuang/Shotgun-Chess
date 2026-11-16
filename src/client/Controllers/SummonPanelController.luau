local Players = game:GetService("Players")

local AnimatedSpriteClass = require(script.Parent.Parent.UI.AnimatedSpriteClass)

local SELECTED_COLOR = Color3.fromHex("E6C47C")
local DEFAULT_COLOR = Color3.fromHex("354867")

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

        local sprite = AnimatedSpriteClass.new(pieceType, card:WaitForChild("Sprite"))
        sprite.Image.Size = UDim2.fromScale(1, 1)

        card.Activated:Connect(function()
            SummonPanelController.SelectPiece(pieceType)
        end)
    end
end

return SummonPanelController
