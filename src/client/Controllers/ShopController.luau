local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ShotgunConfig = require(ReplicatedStorage.Shared.Combat.ShotgunConfig)
local SpriteConfig = require(ReplicatedStorage.Shared.Sprites.SpriteConfig)
local AtlasImage = require(script.Parent.Parent.UI.AtlasImage)
local ProfileController = require(script.Parent.ProfileController)

local LoadoutRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("LoadoutRemote")

local AFFORDABLE_COLOR = Color3.fromHex("F1D4AC")
local OWNED_COLOR = Color3.fromHex("D49A77")
local LOCKED_COLOR = Color3.fromHex("C8644F")

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
local init = false
function ShopController.Init()
    if init then return end
    init = true

    local panel = player.PlayerGui:WaitForChild("MainMenu"):WaitForChild("Root"):WaitForChild("ShopPanel")
    local template = panel:WaitForChild("Template")

    for i, name in ipairs(ShotgunConfig.ORDER) do
        local weapon = ShotgunConfig.Shotguns[name]

        local row = template:Clone()
        row.Name = name
        row.Label.Text = weapon.DisplayName
        row.Price.Text = weapon.Price > 0 and weapon.Price .. " Gold" or "Starter"
        row.LayoutOrder = i
        AtlasImage.SetRect(row.Icon, SpriteConfig.Guns[name].Rect)
        row.Visible = true
        row.Parent = panel.List

        row.Activated:Connect(function()
            if ProfileController.Data.Shotguns[name] then return end
            if (player:GetAttribute("Gold") or 0) < weapon.Price then return end

            LoadoutRemote:FireServer("Buy", "Shotgun", name)
        end)

        rows[name] = row
    end

    player:GetAttributeChangedSignal("Gold"):Connect(Refresh)
    ProfileController.OnChanged(Refresh)
    Refresh()
end

return ShopController
