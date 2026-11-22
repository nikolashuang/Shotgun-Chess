local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local CampaignArt = require(ReplicatedStorage.Shared.Campaign.CampaignArt)
local ArmoryArt = require(ReplicatedStorage.Shared.UI.ArmoryArt)
local PracticeController = require(script.Parent.PracticeController)

local LOCKED_COLOR = Color3.fromHex("8A8290")
local HOVER_COLOR = Color3.fromHex("F1D4AC")
local DEFAULT_COLOR = Color3.fromHex("9C574B")

-- Picks Campaign, Siege or Practice (a duel against the AI); Siege is locked until the mode is designed
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
    local menu = playerGui:WaitForChild("MainMenu")
    local screen = playerGui:WaitForChild("SingleplayerScreen")
    local campaign = playerGui:WaitForChild("CampaignScreen")
    local root = screen:WaitForChild("Root")
    local header = root:WaitForChild("Header")
    local practiceView = root:WaitForChild("PracticeView")
    local cards = {root:WaitForChild("CampaignCard"), root:WaitForChild("PracticeCard"), root:WaitForChild("SiegeCard")}

    -- Practice's Choose Difficulty panel replaces the cards on this screen
    local function ShowPractice(isShown)
        practiceView.Visible = isShown
        header.Text = isShown and "Practice" or "Singleplayer"

        for _, card in ipairs(cards) do
            card.Visible = not isShown
        end
    end

    local campaignCard = root:WaitForChild("CampaignCard")
    SetIsland(campaignCard.Art.Image, 0, CampaignArt.IslandColumn.Training)
    BindHover(campaignCard)

    campaignCard.Activated:Connect(function()
        screen.Enabled = false
        campaign.Enabled = true
    end)

    local practiceCard = root:WaitForChild("PracticeCard")
    ArmoryArt.SetIcon(practiceCard.Art.Image, "Practice")
    BindHover(practiceCard)

    practiceCard.Activated:Connect(function()
        ShowPractice(true)
    end)

    PracticeController.Init(practiceView)

    local siegeCard = root:WaitForChild("SiegeCard")
    ArmoryArt.SetIcon(siegeCard.Art.Image, "Siege")
    siegeCard.Art.Image.ImageColor3 = LOCKED_COLOR
    siegeCard.Label.TextTransparency = 0.5
    AddLock(siegeCard.Art)

    screen:WaitForChild("SettingsButton").Activated:Connect(openSettings)

    -- Back steps out of Practice first, then to the main menu
    screen:WaitForChild("BackButton").Activated:Connect(function()
        if practiceView.Visible then
            ShowPractice(false)
            return
        end

        screen.Enabled = false
        menu.Enabled = true
    end)

    screen:GetPropertyChangedSignal("Enabled"):Connect(function()
        if screen.Enabled then
            ShowPractice(false)
        end
    end)
end

return SingleplayerController
