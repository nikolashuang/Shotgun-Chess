local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ShotgunConfig = require(ReplicatedStorage.Shared.Combat.ShotgunConfig)
local SpriteConfig = require(ReplicatedStorage.Shared.Sprites.SpriteConfig)
local AtlasImage = require(script.Parent.Parent.UI.AtlasImage)
local PlayerCard = require(script.Parent.Parent.UI.PlayerCard)
local ProfileController = require(script.Parent.ProfileController)

local LoadoutRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("LoadoutRemote")

local AFFORDABLE_COLOR = Color3.fromHex("F1D4AC")
local OWNED_COLOR = Color3.fromHex("D49A77")
local LOCKED_COLOR = Color3.fromHex("C8644F")
local DONATE_NOTICE_TIME = 1.5
-- Row width over height, so rows keep their shape at any screen size
local ROW_ASPECT = 5

local player = Players.LocalPlayer
local rows = {}

local ShopController = {}

local function Refresh()
    local gold = player:GetAttribute("Gold") or 0

    for name, row in pairs(rows) do
        local weapon = ShotgunConfig.Shotguns[name]

        if ProfileController.Data.Shotguns[name] then
            row.Tag.Text = "Owned"
            row.Tag.TextColor3 = OWNED_COLOR
        elseif gold >= weapon.Price then
            row.Tag.Text = "Buy"
            row.Tag.TextColor3 = AFFORDABLE_COLOR
        else
            row.Tag.Text = "Locked"
            row.Tag.TextColor3 = LOCKED_COLOR
        end
    end
end

-- Shotguns are bought with gold; the server checks the price and ownership
-- Crates and Donate are placeholders until they're designed
local init = false
function ShopController.Init()
    if init then return end
    init = true

    local screen = player.PlayerGui:WaitForChild("ShopScreen")
    local root = screen:WaitForChild("Root")
    local template = root:WaitForChild("Template")
    local list = root:WaitForChild("ShotgunList")

    for i, name in ipairs(ShotgunConfig.ORDER) do
        local weapon = ShotgunConfig.Shotguns[name]

        local row = template:Clone()
        row.Name = name
        row.Label.Text = weapon.DisplayName
        row.Price.Text = weapon.Price > 0 and weapon.Price .. " Gold" or "Starter"
        row.LayoutOrder = i
        AtlasImage.SetRect(row.Icon, SpriteConfig.Guns[name].Rect)
        row.Visible = true
        row.Parent = list

        row.Activated:Connect(function()
            if ProfileController.Data.Shotguns[name] then return end
            if (player:GetAttribute("Gold") or 0) < weapon.Price then return end

            LoadoutRemote:FireServer("Buy", "Shotgun", name)
        end)

        rows[name] = row
    end

    -- AutomaticCanvasSize ignores the rows' aspect ratio sizing, so the canvas follows the layout instead
    local layout = list:WaitForChild("UIListLayout")
    local padding = list:WaitForChild("UIPadding")

    local function FitCanvas()
        local height = layout.AbsoluteContentSize.Y + padding.PaddingTop.Offset + padding.PaddingBottom.Offset

        list.CanvasSize = UDim2.fromOffset(0, height)
    end

    list.AutomaticCanvasSize = Enum.AutomaticSize.None
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(FitCanvas)
    FitCanvas()

    -- Rows are sized from the list's width and the canvas from the rows, so the list always scrolls to the last gun
    local layout = list:WaitForChild("UIListLayout")
    local padding = list:WaitForChild("UIPadding")

    local function Resize()
        local rowHeight = list.AbsoluteSize.X * template.Size.X.Scale / ROW_ASPECT

        for _, row in pairs(rows) do
            row.Size = UDim2.new(template.Size.X.Scale, 0, 0, rowHeight)
        end
    end

    local function UpdateCanvas()
        local extra = padding.PaddingTop.Offset + padding.PaddingBottom.Offset
        list.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + extra)
    end

    list:GetPropertyChangedSignal("AbsoluteSize"):Connect(Resize)
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(UpdateCanvas)
    Resize()
    UpdateCanvas()

    local donateLabel = root:WaitForChild("DonateButton"):WaitForChild("Label")
    root.DonateButton.Activated:Connect(function()
        donateLabel.Text = "Coming Soon"
        task.delay(DONATE_NOTICE_TIME, function()
            donateLabel.Text = "Donate"
        end)
    end)

    player:GetAttributeChangedSignal("Gold"):Connect(Refresh)
    ProfileController.OnChanged(Refresh)
    Refresh()

    PlayerCard.Bind(screen:WaitForChild("Profile"))
end

return ShopController
