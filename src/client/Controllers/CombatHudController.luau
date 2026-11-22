local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local ShotgunRules = require(ReplicatedStorage.Shared.Combat.ShotgunRules)
local SpriteConfig = require(ReplicatedStorage.Shared.Sprites.SpriteConfig)
local AtlasImage = require(script.Parent.Parent.UI.AtlasImage)
local ShotgunController = require(script.Parent.ShotgunController)
local SummonPanelController = require(script.Parent.SummonPanelController)
local PieceController = require(script.Parent.PieceController)

local BoardRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BoardRemote")

local ALT_MODE_NAMES = {
    Knife = "Knife Swing",
}

local DIVIDER_COLOR = Color3.fromHex("271F29")
-- In pixels
local DIVIDER_WIDTH = 2
local HEALTH_DIVIDER_WIDTH = 1

-- Pieces that join the player's side and get their own health card, by the name shown beside it
local COMPANION_NAMES = {
    FallenKnight = "Fallen Knight",
}
-- Pixels of the companion's idle sprite cropped for its portrait, like the King's head on his card
local PORTRAIT_SIZE = 12
local PORTRAIT_INSET = 10

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
local kingCard = nil
local kingMaxHealth = 1
local companionCard = nil
local companionLabel = nil
-- The companion piece on the board and the health its card last showed
local companionId = nil
local companionShown = nil

local CombatHudController = {}

local function UpdateFireLabel(mode)
    local weapon = ShotgunRules.GetWeapon(shotgunName)
    if not weapon then return end

    if mode == "Alt" and weapon.AltMode then
        fireLabel.Text = ALT_MODE_NAMES[weapon.AltMode]
    else
        fireLabel.Text = "Shoot"
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

-- Divider lines split a bar into one segment per point
local function DrawDividers(bar, fill, count, width)
    for _, child in pairs(bar:GetChildren()) do
        if child.Name == "Divider" then
            child:Destroy()
        end
    end

    for i = 1, count - 1 do
        local divider = Instance.new("Frame")
        divider.Name = "Divider"
        divider.BorderSizePixel = 0
        divider.BackgroundColor3 = DIVIDER_COLOR
        divider.AnchorPoint = Vector2.new(0.5, 0)
        divider.Position = UDim2.fromScale(i / count, 0)
        divider.Size = UDim2.new(0, width, 1, 0)
        divider.ZIndex = fill.ZIndex + 1
        divider.Parent = bar
    end
end

local function UpdateEnergy(energy, maxEnergy)
    if dividerCount ~= maxEnergy then
        DrawDividers(energyBar, energyFill, maxEnergy, DIVIDER_WIDTH)
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

    CombatHudController.SetKingHealth(state.KingHealth, state.KingMaxHealth)
end

-- A portrait card's health text and bar, with one tick per point of max health
local function NewHealthCard(frame)
    local bar = frame:WaitForChild("HealthBar")

    return {
        Frame = frame,
        Text = frame:WaitForChild("HealthText"),
        Bar = bar,
        Fill = bar:WaitForChild("Fill"),
        DividerCount = 0,
    }
end

local function DrawHealthCard(card, health, maxHealth)
    if card.DividerCount ~= maxHealth then
        DrawDividers(card.Bar, card.Fill, maxHealth, HEALTH_DIVIDER_WIDTH)
        card.DividerCount = maxHealth
    end

    -- Revolver hits deal half points
    local shown = health % 1 == 0 and string.format("%d", health) or string.format("%.1f", health)

    card.Fill.Size = UDim2.fromScale(math.clamp(health / maxHealth, 0, 1), 1)
    card.Text.Text = string.format("%s/%d", shown, maxHealth)
end

-- The king portrait's health beside the turn bar; maxHealth can be left out after the first call
function CombatHudController.SetKingHealth(health, maxHealth)
    if not kingCard then return end

    kingMaxHealth = maxHealth or kingMaxHealth
    DrawHealthCard(kingCard, health, kingMaxHealth)
end

--COMPANIONS--

local function ShowCompanion(id, pieceType)
    companionId = id
    companionShown = nil
    companionLabel.Text = COMPANION_NAMES[pieceType]

    local portrait = companionCard.Frame.PortraitFrame.Portrait
    portrait.Image = SpriteConfig.ASSET_ID
    portrait.ImageRectOffset = Vector2.new(
        SpriteConfig.Columns[pieceType] + PORTRAIT_INSET,
        SpriteConfig.Pieces[pieceType].Idle + SpriteConfig.HeadRows[pieceType]
    )
    portrait.ImageRectSize = Vector2.new(PORTRAIT_SIZE, PORTRAIT_SIZE)

    companionCard.Frame.Visible = true
    companionLabel.Visible = true
end

local function HideCompanion()
    companionId = nil
    companionCard.Frame.Visible = false
    companionLabel.Visible = false
end

-- Follows the companion's board health, so every way it can be hurt or healed shows up; gone once it dies
local function UpdateCompanion()
    if not companionId then return end

    local piece = PieceController.Get(companionId)
    if not piece then
        HideCompanion()
        return
    end

    local health, maxHealth = piece.Rig.Health, piece.Rig.MaxHealth
    if not health or not maxHealth then return end
    if companionShown == health then return end

    companionShown = health
    DrawHealthCard(companionCard, health, maxHealth)
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

    kingCard = NewHealthCard(root:WaitForChild("TurnBar"):WaitForChild("KingHealth"))
    companionCard = NewHealthCard(root:WaitForChild("CompanionHealth"))
    companionLabel = root:WaitForChild("CompanionLabel")
    HideCompanion()

    ShotgunController.OnModeChanged = UpdateFireLabel

    BoardRemote.OnClientEvent:Connect(function(action, ...)
        if action == "TurnState" then
            Update(...)
        elseif action == "MatchStarted" then
            HideCompanion()
        elseif action == "PieceAdded" then
            local id, pieceType, team = ...
            if team == "White" and COMPANION_NAMES[pieceType] then
                ShowCompanion(id, pieceType)
            end
        end
    end)

    RunService.Heartbeat:Connect(UpdateCompanion)
end

return CombatHudController
