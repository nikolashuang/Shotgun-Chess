local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ShotgunConfig = require(ReplicatedStorage.Shared.Combat.ShotgunConfig)
local SpriteConfig = require(ReplicatedStorage.Shared.Sprites.SpriteConfig)
local AtlasImage = require(script.Parent.Parent.UI.AtlasImage)

local ShopController = {}

-- Everything shows as unlocked until gold and purchasing exist
local init = false
function ShopController.Init()
    if init then return end
    init = true

    local panel = Players.LocalPlayer.PlayerGui:WaitForChild("MainMenu"):WaitForChild("Root"):WaitForChild("ShopPanel")
    local template = panel:WaitForChild("Template")

    for i, name in ipairs(ShotgunConfig.ORDER) do
        local weapon = ShotgunConfig.Shotguns[name]

        local row = template:Clone()
        row.Name = name
        row.Label.Text = weapon.DisplayName
        row.Price.Text = weapon.Price > 0 and weapon.Price .. " GOLD" or "STARTER"
        row.Tag.Text = "UNLOCKED"
        row.LayoutOrder = i
        AtlasImage.SetRect(row.Icon, SpriteConfig.Guns[name].Rect)
        row.Visible = true
        row.Parent = panel.List
    end
end

return ShopController
