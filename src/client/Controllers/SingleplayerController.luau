local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local CampaignArt = require(ReplicatedStorage.Shared.Campaign.CampaignArt)
local ArmoryArt = require(ReplicatedStorage.Shared.UI.ArmoryArt)

local LOCKED_COLOR = Color3.fromHex("8A8290")
local HOVER_COLOR = Color3.fromHex("F1D4AC")
local DEFAULT_COLOR = Color3.fromHex("9C574B")

-- Picks Campaign or Siege; Siege is locked until the mode is designed
local SingleplayerController = {}

local function SetIsland(image, row, column)
    local size = CampaignArt.ISLAND_SIZE

    image.Image = CampaignArt.ISLANDS
    image.ImageRectOffset = Vector2.new(column, row) * size
    image.ImageRectSize = Vector2.new(size, size)
end

local function BindHover(card)
    card.MouseEnter:Connect(function()
        card.UIStroke.Color = HOVER_COLOR
    end)

    card.MouseLeave:Connect(function()
        card.UIStroke.Color = DEFAULT_COLOR
    end)
end

-- Drapes the campaign map's chain and padlock layers over a card's drawing
local function AddLock(art)
    for name, column in pairs(CampaignArt.LockColumn) do
        local layer = art.Image:Clone()
        layer.Name = name
        layer.ZIndex = 2
        SetIsland(layer, 2, column)
        layer.Parent = art
    end
end

local init = false
function SingleplayerController.Init(openSettings)
    if init then return end
    init = true

    local playerGui = Players.LocalPlayer.PlayerGui
    local screen = playerGui:WaitForChild("SingleplayerScreen")
    local campaign = playerGui:WaitForChild("CampaignScreen")
    local root = screen:WaitForChild("Root")

    local campaignCard = root:WaitForChild("CampaignCard")
    SetIsland(campaignCard.Art.Image, 0, CampaignArt.IslandColumn.Training)
    BindHover(campaignCard)

    campaignCard.Activated:Connect(function()
        screen.Enabled = false
        campaign.Enabled = true
    end)

    local siegeCard = root:WaitForChild("SiegeCard")
    ArmoryArt.SetIcon(siegeCard.Art.Image, "Siege")
    siegeCard.Art.Image.ImageColor3 = LOCKED_COLOR
    siegeCard.Label.TextTransparency = 0.5
    AddLock(siegeCard.Art)

    root:WaitForChild("SettingsButton").Activated:Connect(openSettings)
end

return SingleplayerController
