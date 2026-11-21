local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local ShotgunConfig = require(ReplicatedStorage.Shared.Combat.ShotgunConfig)
local ClassConfig = require(ReplicatedStorage.Shared.Combat.ClassConfig)
local SpriteConfig = require(ReplicatedStorage.Shared.Sprites.SpriteConfig)
local ArmoryArt = require(ReplicatedStorage.Shared.UI.ArmoryArt)
local AtlasImage = require(script.Parent.Parent.UI.AtlasImage)
local PlayerCard = require(script.Parent.Parent.UI.PlayerCard)
local ProfileController = require(script.Parent.ProfileController)

local LoadoutRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("LoadoutRemote")

local EQUIPPED_COLOR = Color3.fromHex("F1D4AC")
local DEFAULT_COLOR = Color3.fromHex("E9E3D6")
local NO_CLASS = "None"
local KINDS = {"Passive", "Special", "Ultimate"}

local player = Players.LocalPlayer
local classBar = nil
local classRows = {}
local shotgunBar = nil
local gunImage = nil
local gunBody = nil
local dropdowns = {}

-- Loadout screen: each side has a bar showing what's equipped; its dropdown lists what you own and picking one equips it
local ArmoryController = {}

local function CloseDropdowns()
    for _, dropdown in pairs(dropdowns) do
        dropdown.List.Visible = false
        dropdown.Bar.Arrow.Text = "▼"
    end
end

local function IsOver(gui, position)
    local corner = gui.AbsolutePosition
    local size = gui.AbsoluteSize

    return position.X >= corner.X and position.Y >= corner.Y and position.X <= corner.X + size.X and position.Y <= corner.Y + size.Y
end

-- Ability text is "Name: description"
local function SplitAbility(text)
    local name, description = string.match(text, "^(.-):%s*(.*)$")

    return name or text, description or ""
end

local function ShowClass()
    local name = player:GetAttribute("Class")
    local class = name and ClassConfig.Classes[name]

    classBar.Label.Text = class and class.DisplayName or "No Class"

    for _, kind in ipairs(KINDS) do
        local row = classRows[kind]

        if class then
            local title, description = SplitAbility(class[kind])

            row.Text.Title.Text = title
            row.Text.Body.Text = description
            ArmoryArt.SetIcon(row.IconBox.Icon, name .. kind)
        else
            row.Text.Title.Text = "Locked"
            row.Text.Body.Text = "Defeat a regional King in the Campaign to unlock a class."
            ArmoryArt.SetIcon(row.IconBox.Icon, nil)
        end
    end
end

local function ShowShotgun()
    local name = player:GetAttribute("Shotgun") or ShotgunConfig.STARTER
    local weapon = ShotgunConfig.Shotguns[name]
    local damage = string.format("%g-%g", weapon.MaxDamage, weapon.MinDamage)

    if weapon.Blasts > 1 then
        damage ..= " x" .. weapon.Blasts
    end

    shotgunBar.Label.Text = weapon.DisplayName
    AtlasImage.SetRect(gunImage, SpriteConfig.Guns[name].Rect)
    gunBody.Text = string.format("%s\n\nAmmo %d   Range %d   Damage %s", weapon.Description, weapon.MaxAmmo, weapon.MaxRange, damage)
end

-- Rebuilds a dropdown's options from what the player owns
local function FillDropdown(dropdown)
    for _, option in pairs(dropdown.List:GetChildren()) do
        if option:IsA("TextButton") then
            option:Destroy()
        end
    end

    local equipped = player:GetAttribute(dropdown.Kind) or (dropdown.Kind == "Class" and NO_CLASS or nil)
    local height = dropdown.Bar.AbsoluteSize.Y

    for i, entry in ipairs(dropdown.GetOptions()) do
        local option = dropdown.Template:Clone()
        option.Name = entry.Name
        option.LayoutOrder = i
        option.Size = UDim2.new(1, 0, 0, height)
        option.Label.Text = entry.DisplayName
        option.Label.TextColor3 = entry.Name == equipped and EQUIPPED_COLOR or DEFAULT_COLOR
        option.Visible = true
        option.Parent = dropdown.List

        option.Activated:Connect(function()
            if entry.Name == NO_CLASS then
                LoadoutRemote:FireServer("Unequip", dropdown.Kind)
            elseif entry.Name ~= equipped then
                LoadoutRemote:FireServer("Equip", dropdown.Kind, entry.Name)
            end

            CloseDropdowns()
        end)
    end
end

local function BindDropdown(kind, box, barName, getOptions)
    local template = box:WaitForChild("OptionTemplate")
    template:FindFirstChildOfClass("UIAspectRatioConstraint"):Destroy()

    local dropdown = {
        Kind = kind,
        Bar = box:WaitForChild(barName),
        List = box:WaitForChild(barName .. "List"),
        Template = template,
        GetOptions = getOptions,
    }

    dropdown.Bar.Activated:Connect(function()
        local isOpen = dropdown.List.Visible

        CloseDropdowns()
        if isOpen then return end

        FillDropdown(dropdown)
        dropdown.List.Visible = true
        dropdown.Bar.Arrow.Text = "▲"
    end)

    dropdowns[kind] = dropdown

    return dropdown.Bar
end

local function GetOwnedClasses()
    local options = {{Name = NO_CLASS, DisplayName = "No Class"}}

    for _, name in ipairs(ClassConfig.ORDER) do
        if ProfileController.Data.Classes[name] then
            table.insert(options, {Name = name, DisplayName = ClassConfig.Classes[name].DisplayName})
        end
    end

    return options
end

local function GetOwnedShotguns()
    local options = {}

    for _, name in ipairs(ShotgunConfig.ORDER) do
        if ProfileController.Data.Shotguns[name] or name == ShotgunConfig.STARTER then
            table.insert(options, {Name = name, DisplayName = ShotgunConfig.Shotguns[name].DisplayName})
        end
    end

    return options
end

local init = false
function ArmoryController.Init()
    if init then return end
    init = true

    local screen = player.PlayerGui:WaitForChild("ArmoryScreen")
    local root = screen:WaitForChild("Root")
    PlayerCard.Bind(screen:WaitForChild("Profile"))

    local classBox = root:WaitForChild("ClassBox")
    local shotgunBox = root:WaitForChild("ShotgunBox")

    classBar = BindDropdown("Class", classBox, "ClassBar", GetOwnedClasses)
    shotgunBar = BindDropdown("Shotgun", shotgunBox, "ShotgunBar", GetOwnedShotguns)

    for _, kind in ipairs(KINDS) do
        classRows[kind] = classBox:WaitForChild(kind)
    end

    gunImage = shotgunBox:WaitForChild("Art"):WaitForChild("Gun")
    gunBody = shotgunBox:WaitForChild("Info"):WaitForChild("Body")

    -- Clicking anywhere outside an open dropdown (and its bar, which toggles it itself) closes it
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end

        -- Input positions skip the top bar inset, but this screen ignores it
        local position = Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()

        for _, dropdown in pairs(dropdowns) do
            if not dropdown.List.Visible then continue end
            if IsOver(dropdown.List, position) or IsOver(dropdown.Bar, position) then continue end

            CloseDropdowns()
        end
    end)

    screen:GetPropertyChangedSignal("Enabled"):Connect(CloseDropdowns)

    player:GetAttributeChangedSignal("Class"):Connect(ShowClass)
    player:GetAttributeChangedSignal("Shotgun"):Connect(ShowShotgun)
    ShowClass()
    ShowShotgun()
end

return ArmoryController
