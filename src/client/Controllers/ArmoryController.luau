local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ShotgunConfig = require(ReplicatedStorage.Shared.Combat.ShotgunConfig)
local ClassConfig = require(ReplicatedStorage.Shared.Combat.ClassConfig)
local SpriteConfig = require(ReplicatedStorage.Shared.Sprites.SpriteConfig)
local AtlasImage = require(script.Parent.Parent.UI.AtlasImage)

local LoadoutRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("LoadoutRemote")

local EQUIPPED_COLOR = Color3.fromHex("E6C47C")
local DEFAULT_COLOR = Color3.fromHex("354867")

local player = Players.LocalPlayer
local rowsByKind = {
    Shotgun = {},
    Class = {},
}
local detailsTitle = nil
local detailsBody = nil

local ArmoryController = {}

local function ShowShotgunDetails(name)
    local weapon = ShotgunConfig.Shotguns[name]
    local damage = string.format("%g-%g", weapon.MaxDamage, weapon.MinDamage)

    if weapon.Blasts > 1 then
        damage ..= " x" .. weapon.Blasts
    end

    detailsTitle.Text = weapon.DisplayName
    detailsBody.Text = string.format("%s\n\nAMMO %d   RANGE %d   DAMAGE %s", weapon.Description, weapon.MaxAmmo, weapon.MaxRange, damage)
end

local function ShowClassDetails(name)
    local class = ClassConfig.Classes[name]

    detailsTitle.Text = class.DisplayName
    detailsBody.Text = string.format("%s\n%s\n%s", class.Passive, class.Special, class.Ultimate)
end

local function Refresh()
    for kind, rows in pairs(rowsByKind) do
        local equipped = player:GetAttribute(kind)

        for name, row in pairs(rows) do
            local isEquipped = name == equipped

            row.UIStroke.Color = isEquipped and EQUIPPED_COLOR or DEFAULT_COLOR
            row.Tag.Text = isEquipped and "EQUIPPED" or ""
        end
    end
end

local function NewRow(template, list, kind, name, displayName, order)
    local row = template:Clone()
    row.Name = name
    row.Label.Text = displayName
    row.LayoutOrder = order
    row.Visible = true
    row.Parent = list

    -- Shotgun rows show the gun sprite in front of the name
    if kind == "Shotgun" then
        AtlasImage.SetRect(row.Icon, SpriteConfig.Guns[name].Rect)
        row.Icon.Visible = true
        row.Label.Position = UDim2.fromScale(0.36, row.Label.Position.Y.Scale)
        row.Label.Size = UDim2.fromScale(0.36, row.Label.Size.Y.Scale)
    end

    row.Activated:Connect(function()
        LoadoutRemote:FireServer("Equip", kind, name)

        if kind == "Shotgun" then
            ShowShotgunDetails(name)
        else
            ShowClassDetails(name)
        end
    end)

    rowsByKind[kind][name] = row
end

local init = false
function ArmoryController.Init()
    if init then return end
    init = true

    local panel = player.PlayerGui:WaitForChild("MainMenu"):WaitForChild("Root"):WaitForChild("ArmoryPanel")
    local template = panel:WaitForChild("Template")
    local details = panel:WaitForChild("Details")

    detailsTitle = details:WaitForChild("Title")
    detailsBody = details:WaitForChild("Body")

    for i, name in ipairs(ShotgunConfig.ORDER) do
        NewRow(template, panel.ShotgunList, "Shotgun", name, ShotgunConfig.Shotguns[name].DisplayName, i)
    end

    for i, name in ipairs(ClassConfig.ORDER) do
        NewRow(template, panel.ClassList, "Class", name, ClassConfig.Classes[name].DisplayName, i)
    end

    player:GetAttributeChangedSignal("Shotgun"):Connect(Refresh)
    player:GetAttributeChangedSignal("Class"):Connect(Refresh)
    Refresh()

    ShowShotgunDetails(player:GetAttribute("Shotgun") or ShotgunConfig.STARTER)
end

return ArmoryController
