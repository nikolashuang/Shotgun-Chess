local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local ShotgunConfig = require(ReplicatedStorage.Shared.Combat.ShotgunConfig)
local ClassConfig = require(ReplicatedStorage.Shared.Combat.ClassConfig)
local SpriteConfig = require(ReplicatedStorage.Shared.Sprites.SpriteConfig)
local ArmoryArt = require(ReplicatedStorage.Shared.UI.ArmoryArt)
local SkinConfig = require(ReplicatedStorage.Shared.Skins.SkinConfig)
local AtlasImage = require(script.Parent.Parent.UI.AtlasImage)
local AnimatedSpriteClass = require(script.Parent.Parent.UI.AnimatedSpriteClass)
local PlayerCard = require(script.Parent.Parent.UI.PlayerCard)
local ProfileController = require(script.Parent.ProfileController)
local BoardSkinController = require(script.Parent.BoardSkinController)

local LoadoutRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("LoadoutRemote")

local EQUIPPED_COLOR = Color3.fromHex("F1D4AC")
local DEFAULT_COLOR = Color3.fromHex("E9E3D6")
local NO_CLASS = "None"
local LOCKED_COLOR = Color3.fromHex("6A5D66")
local SELECTED_TAB_COLOR = Color3.fromHex("9C574B")
local TAB_COLOR = Color3.fromHex("271F29")
local LOCKED_SHADE = 0.35
-- Skin card height over width
local CARD_RATIO = 1.3
local KINDS = {"Passive", "Special", "Ultimate"}

local player = Players.LocalPlayer
local classBar = nil
local classRows = {}
local shotgunBar = nil
local gunImage = nil
local gunBody = nil
local dropdowns = {}
local skinCards = {}
-- The King idling in the equipped class's outfit, so players see how they'll look
local kingPreview = nil
local kingCaption = nil

-- Loadout tab: each side has a bar showing what's equipped; its dropdown lists what you own and picking one equips it
-- Skins tab: every board skin as a card; owned ones equip on click
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
    kingPreview:SetOutfit(class and name or nil)
    kingCaption.Text = class and class.DisplayName .. " outfit" or "Classic"

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

-- Owned boards equip on click; boards you don't own yet show dimmed
local function ShowSkins()
    local owned = ProfileController.Data.Skins and ProfileController.Data.Skins.Board or {}
    local equipped = player:GetAttribute("BoardSkin") or SkinConfig.DEFAULT_BOARD

    for name, card in pairs(skinCards) do
        local skin = SkinConfig.Skins.Board[name]
        local isOwned = skin.Starter or owned[name] == true
        local rarity = SkinConfig.Rarities[skin.Rarity]

        card.UIStroke.Color = name == equipped and EQUIPPED_COLOR or rarity.Color
        card.UIStroke.Thickness = name == equipped and 3 or 2
        card.Preview.Shade.Visible = not isOwned
        card.SkinName.TextColor3 = isOwned and DEFAULT_COLOR or LOCKED_COLOR

        if name == equipped then
            card.Status.Text = "Equipped"
            card.Status.TextColor3 = EQUIPPED_COLOR
        elseif isOwned then
            card.Status.Text = rarity.DisplayName
            card.Status.TextColor3 = rarity.Color
        else
            card.Status.Text = "Locked - " .. rarity.DisplayName
            card.Status.TextColor3 = LOCKED_COLOR
        end
    end
end

local function BuildSkins(box)
    local grid = box:WaitForChild("Grid")
    local template = box:WaitForChild("SkinCard")
    local layout = grid:WaitForChild("UIGridLayout")

    for i, name in ipairs(SkinConfig.BOARD_ORDER) do
        local card = template:Clone()
        card.Name = name
        card.LayoutOrder = i
        card.SkinName.Text = SkinConfig.Skins.Board[name].DisplayName
        card.Visible = true
        BoardSkinController.BuildPreview(card.Preview, name)

        -- Boards you don't own yet show dimmed under a shade
        local shade = Instance.new("Frame")
        shade.Name = "Shade"
        shade.Size = UDim2.fromScale(1, 1)
        shade.BackgroundColor3 = TAB_COLOR
        shade.BackgroundTransparency = LOCKED_SHADE
        shade.BorderSizePixel = 0
        shade.ZIndex = card.Preview.ZIndex + 1
        shade.Parent = card.Preview

        card.Parent = grid

        card.Activated:Connect(function()
            if name == player:GetAttribute("BoardSkin") then return end
            if card.Preview.Shade.Visible then return end

            LoadoutRemote:FireServer("Equip", "BoardSkin", name)
        end)

        skinCards[name] = card
    end

    -- Cards keep their shape at any screen size
    local function Resize()
        local width = grid.AbsoluteSize.X * layout.CellSize.X.Scale
        layout.CellSize = UDim2.new(layout.CellSize.X.Scale, 0, 0, width * CARD_RATIO)
    end

    grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(Resize)
    Resize()
end

local function BindTabs(root, loadoutBoxes, skinsBox)
    local tabs = {Loadout = root:WaitForChild("LoadoutTab"), Skins = root:WaitForChild("SkinsTab")}

    local function Select(name)
        for _, box in pairs(loadoutBoxes) do
            box.Visible = name == "Loadout"
        end
        skinsBox.Visible = name == "Skins"

        for tabName, tab in pairs(tabs) do
            tab.BackgroundColor3 = tabName == name and SELECTED_TAB_COLOR or TAB_COLOR
        end

        CloseDropdowns()
    end

    for name, tab in pairs(tabs) do
        tab.Activated:Connect(function()
            Select(name)
        end)
    end

    Select("Loadout")
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

    local previewPanel = classBox:WaitForChild("KingPreview")
    kingCaption = previewPanel:WaitForChild("Caption")
    kingPreview = AnimatedSpriteClass.new("King", previewPanel:WaitForChild("Tiles"):WaitForChild("Stage"), "White")
    kingPreview.Image.Size = UDim2.fromScale(1, 1)
    kingPreview.Image.ZIndex = 3

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

    local skinsBox = root:WaitForChild("SkinsBox")
    BuildSkins(skinsBox)
    BindTabs(root, {classBox, shotgunBox}, skinsBox)

    player:GetAttributeChangedSignal("Class"):Connect(ShowClass)
    player:GetAttributeChangedSignal("Shotgun"):Connect(ShowShotgun)
    player:GetAttributeChangedSignal("BoardSkin"):Connect(ShowSkins)
    ProfileController.OnChanged(ShowSkins)
    ShowClass()
    ShowShotgun()
    ShowSkins()
end

return ArmoryController
