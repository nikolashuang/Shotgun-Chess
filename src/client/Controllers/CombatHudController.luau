local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ShotgunRules = require(ReplicatedStorage.Shared.Combat.ShotgunRules)
local SpriteConfig = require(ReplicatedStorage.Shared.Sprites.SpriteConfig)
local AtlasImage = require(script.Parent.Parent.UI.AtlasImage)
local ShotgunController = require(script.Parent.ShotgunController)
local SummonPanelController = require(script.Parent.SummonPanelController)

local BoardRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BoardRemote")

local ALT_MODE_NAMES = {
    Knife = "Knife Swing",
}

local DIVIDER_COLOR = Color3.fromHex("271F29")
-- In pixels
local DIVIDER_WIDTH = 2

local fireLabel = nil
local gunIcon = nil
local slugFrame = nil
local slugs = {}
local chargeFill = nil
local chargeText = nil
local energyFill = nil
local energyBar = nil
local energyCount = nil
local dividerCount = 0
local shotgunName = nil

local CombatHudController = {}

local function UpdateFireLabel(mode)
    local weapon = ShotgunRules.GetWeapon(shotgunName)
    if not weapon then return end

    if mode == "Alt" and weapon.AltMode then
        fireLabel.Text = ALT_MODE_NAMES[weapon.AltMode]
    else
        fireLabel.Text = weapon.DisplayName
    end
end

-- One slug per shell in the magazine, spent shells show as empty slots
local function UpdateAmmo(ammo, maxAmmo)
    while #slugs < maxAmmo do
        local slug = AtlasImage.New("Slug", "ShellFull")
        slug.UIAspectRatioConstraint.DominantAxis = Enum.DominantAxis.Height
        slug.LayoutOrder = #slugs + 1
        slug.Parent = slugFrame
        table.insert(slugs, slug)
    end

    while #slugs > maxAmmo do
        table.remove(slugs):Destroy()
    end

    for i, slug in ipairs(slugs) do
        AtlasImage.SetRect(slug, i <= ammo and "ShellFull" or "ShellEmpty")
    end
end

-- Divider lines split the bar into one segment per energy
local function UpdateEnergy(energy, maxEnergy)
    if dividerCount ~= maxEnergy then
        for _, child in pairs(energyBar:GetChildren()) do
            if child.Name == "Divider" then
                child:Destroy()
            end
        end

        for i = 1, maxEnergy - 1 do
            local divider = Instance.new("Frame")
            divider.Name = "Divider"
            divider.BorderSizePixel = 0
            divider.BackgroundColor3 = DIVIDER_COLOR
            divider.AnchorPoint = Vector2.new(0.5, 0)
            divider.Position = UDim2.fromScale(i / maxEnergy, 0)
            divider.Size = UDim2.new(0, DIVIDER_WIDTH, 1, 0)
            divider.ZIndex = energyFill.ZIndex + 1
            divider.Parent = energyBar
        end

        dividerCount = maxEnergy
    end

    energyFill.Size = UDim2.fromScale(energy / maxEnergy, 1)
    energyCount.Text = string.format("%d/%d", energy, maxEnergy)
    SummonPanelController.SetEnergy(energy)
end

local function Update(state)
    if state.Shotgun ~= shotgunName then
        shotgunName = state.Shotgun
        AtlasImage.SetRect(gunIcon, SpriteConfig.Guns[shotgunName].Rect)
    end

    UpdateFireLabel(ShotgunController.GetMode())
    UpdateAmmo(state.Ammo, state.MaxAmmo)
    UpdateEnergy(state.Energy, state.MaxEnergy)

    chargeFill.Size = UDim2.fromScale(state.UltimateCharge / state.MaxUltimateCharge, 1)
    chargeText.Text = string.format("%d/%d", state.UltimateCharge, state.MaxUltimateCharge)
end

local init = false
function CombatHudController.Init()
    if init then return end
    init = true

    local hud = Players.LocalPlayer.PlayerGui:WaitForChild("GameHUD")
    local root = hud:WaitForChild("Root")
    local actionPanel = root:WaitForChild("ActionPanel")
    local ultimateButton = root:WaitForChild("AbilityPanel"):WaitForChild("UltimateButton")
    local ammoBar = root:WaitForChild("AmmoBar")
    local energyPanel = root:WaitForChild("EnergyPanel")

    fireLabel = actionPanel:WaitForChild("FireButton"):WaitForChild("Label")
    gunIcon = ammoBar:WaitForChild("GunIcon")
    slugFrame = ammoBar:WaitForChild("Slugs")
    chargeFill = ultimateButton:WaitForChild("ChargeBar"):WaitForChild("ChargeFill")
    chargeText = ultimateButton:WaitForChild("ChargeText")
    energyBar = energyPanel:WaitForChild("EnergyBar")
    energyFill = energyBar:WaitForChild("Fill")
    energyCount = energyPanel:WaitForChild("EnergyCount")

    ShotgunController.OnModeChanged = UpdateFireLabel

    BoardRemote.OnClientEvent:Connect(function(action, state)
        if action ~= "TurnState" then return end

        Update(state)
    end)
end

return CombatHudController
