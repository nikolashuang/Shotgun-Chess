local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ShotgunConfig = require(ReplicatedStorage.Shared.Combat.ShotgunConfig)
local ClassConfig = require(ReplicatedStorage.Shared.Combat.ClassConfig)
local SpriteConfig = require(ReplicatedStorage.Shared.Sprites.SpriteConfig)
local CampaignConfig = require(ReplicatedStorage.Shared.Campaign.CampaignConfig)
local AtlasImage = require(script.Parent.Parent.UI.AtlasImage)
local ProfileController = require(script.Parent.ProfileController)

local LoadoutRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("LoadoutRemote")

local EQUIPPED_COLOR = Color3.fromHex("F1D4AC")
local DEFAULT_COLOR = Color3.fromHex("9C574B")
local LOCKED_TRANSPARENCY = 0.5

local player = Players.LocalPlayer
local rowsByKind = {
    Shotgun = {},
    Class = {},
}
local detailsTitle = nil
local detailsBody = nil
local shownKind = nil
local shownName = nil

local ArmoryController = {}

local function IsOwned(kind, name)
    local owned = kind == "Shotgun" and ProfileController.Data.Shotguns or ProfileController.Data.Classes

    return owned[name] == true
end

local function GetClassRegion(name)
    for _, regionId in ipairs(CampaignConfig.ORDER) do
        local region = CampaignConfig.Regions[regionId]
        if region.Class == name then return region end
    end

    return nil
end

local function ShowShotgunDetails(name)
    shownKind = "Shotgun"
    shownName = name

    local weapon = ShotgunConfig.Shotguns[name]
    local damage = string.format("%g-%g", weapon.MaxDamage, weapon.MinDamage)

    if weapon.Blasts > 1 then
        damage ..= " x" .. weapon.Blasts
    end

    detailsTitle.Text = weapon.DisplayName
    detailsBody.Text = string.format("%s\nAmmo %d   Range %d   Damage %s", weapon.Description, weapon.MaxAmmo, weapon.MaxRange, damage)

    if not IsOwned("Shotgun", name) then
        detailsBody.Text ..= string.format("\nLocked: buy it in the Shop for %d Gold", weapon.Price)
    end
end

local function ShowClassDetails(name)
    shownKind = "Class"
    shownName = name

    local class = ClassConfig.Classes[name]

    detailsTitle.Text = class.DisplayName
    detailsBody.Text = string.format("%s\n%s\n%s", class.Passive, class.Special, class.Ultimate)

    local region = GetClassRegion(name)

    if not IsOwned("Class", name) and region then
        detailsBody.Text ..= string.format("\nLocked: defeat the King of %s", region.DisplayName)
    end
end

-- Redraws rows and the open details, since ownership arrives after the panel is built
local function Refresh()
    if shownKind == "Shotgun" then
        ShowShotgunDetails(shownName)
    elseif shownKind == "Class" then
        ShowClassDetails(shownName)
    end

    for kind, rows in pairs(rowsByKind) do
        local equipped = player:GetAttribute(kind)

        for name, row in pairs(rows) do
            local isEquipped = name == equipped
            local isOwned = IsOwned(kind, name)

            row.UIStroke.Color = isEquipped and EQUIPPED_COLOR or DEFAULT_COLOR
            row.Label.TextTransparency = isOwned and 0 or LOCKED_TRANSPARENCY

            if isEquipped then
                row.Tag.Text = "Equipped"
            elseif not isOwned then
                row.Tag.Text = "Locked"
            else
                row.Tag.Text = ""
            end
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

    -- Clicking the equipped class takes it off, leaving the king classless
    row.Activated:Connect(function()
        if kind == "Class" and player:GetAttribute("Class") == name then
            LoadoutRemote:FireServer("Unequip", kind)
        elseif IsOwned(kind, name) then
            LoadoutRemote:FireServer("Equip", kind, name)
        end

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
    ProfileController.OnChanged(Refresh)
    Refresh()

    ShowShotgunDetails(player:GetAttribute("Shotgun") or ShotgunConfig.STARTER)
end

return ArmoryController
