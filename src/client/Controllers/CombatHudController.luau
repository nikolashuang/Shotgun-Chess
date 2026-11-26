local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
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
-- Energy the planned action is about to spend
local ENERGY_PREVIEW_COLOR = Color3.fromHex("C8644F")
-- It blinks between red and the empty bar's color, so the energy looks like it's draining
local ENERGY_PREVIEW_BLINK_COLOR = Color3.fromHex("332A35")
-- Seconds per fade
local ENERGY_PREVIEW_BLINK_TIME = 0.25
-- In pixels
local DIVIDER_WIDTH = 2
local HEALTH_DIVIDER_WIDTH = 1

-- Pieces that join the player's side and get their own health card, with the name shown above it
local COMPANIONS = {
    FallenKnight = "Fallen Knight",
}
-- Gap between companion cards, as a fraction of the turn bar's width
local COMPANION_GAP = 0.02
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
local energyPreview = nil
local energyPreviewBlink = nil
local energy, maxEnergy = 0, 1
local previewCost = 0
local dividerCount = 0
local shotgunName = nil
local kingCard = nil
local kingMaxHealth = 1
local companionTemplate = nil
-- Duels only: the rival King's health on the right of the turn bar
local rivalCard = nil
-- Companion piece id -> its health card (and the health it last showed), in the order they joined
local companionCards = {}
local companionOrder = {}

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

-- The last segments of the fill turn white, as many as the planned action costs
local function DrawEnergyPreview()
    local cost = math.min(previewCost, energy)
    local wasVisible = energyPreview.Visible

    energyPreview.Visible = cost > 0

    if cost <= 0 then
        energyPreviewBlink:Cancel()
        return
    end

    -- Restart from solid white whenever it appears
    if not wasVisible then
        energyPreview.BackgroundColor3 = ENERGY_PREVIEW_COLOR
        energyPreviewBlink:Play()
    end

    energyPreview.Position = UDim2.fromScale((energy - cost) / energy, 0)
    energyPreview.Size = UDim2.fromScale(cost / energy, 1)
end

local function UpdateEnergy(newEnergy, newMaxEnergy)
    energy, maxEnergy = newEnergy, newMaxEnergy

    if dividerCount ~= maxEnergy then
        DrawDividers(energyBar, energyFill, maxEnergy, DIVIDER_WIDTH)
        dividerCount = maxEnergy
    end

    energyFill.Size = UDim2.fromScale(energy / maxEnergy, 1)
    energyCount.Text = string.format("%d/%d", energy, maxEnergy)
    SummonPanelController.SetEnergy(energy)
    DrawEnergyPreview()
end

function CombatHudController.SetEnergyPreview(cost)
    previewCost = cost
    DrawEnergyPreview()
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

    -- Duels are the matches with clocks
    if rivalCard then
        rivalCard.Frame.Visible = state.Clock ~= nil
    end
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

-- Cards line up to the right of the King's card, one per companion
local function PlaceCompanionCards()
    local step = companionTemplate.Size.X.Scale + COMPANION_GAP

    for i, id in ipairs(companionOrder) do
        local frame = companionCards[id].Frame
        frame.Position = UDim2.new(companionTemplate.Position.X.Scale + (i - 1) * step, 0, companionTemplate.Position.Y.Scale, 0)
    end
end

local function AddCompanion(id, pieceType)
    local frame = companionTemplate:Clone()
    frame.Name = "Companion" .. id
    frame.Caption.Text = COMPANIONS[pieceType]

    local portrait = frame.PortraitFrame.Portrait
    portrait.Image = SpriteConfig.ASSET_ID
    portrait.ImageRectOffset = Vector2.new(
        SpriteConfig.Columns[pieceType] + PORTRAIT_INSET,
        SpriteConfig.Pieces[pieceType].Idle + SpriteConfig.HeadRows[pieceType]
    )
    portrait.ImageRectSize = Vector2.new(PORTRAIT_SIZE, PORTRAIT_SIZE)

    frame.Visible = true
    frame.Parent = companionTemplate.Parent

    companionCards[id] = NewHealthCard(frame)
    table.insert(companionOrder, id)
    PlaceCompanionCards()
end

local function RemoveCompanion(id)
    companionCards[id].Frame:Destroy()
    companionCards[id] = nil
    table.remove(companionOrder, table.find(companionOrder, id))
    PlaceCompanionCards()
end

local function ClearCompanions()
    for _, id in ipairs(table.clone(companionOrder)) do
        RemoveCompanion(id)
    end
end

-- Follows each companion's board health, so every way it can be hurt or healed shows up; a card goes once its piece dies
local function UpdateCompanions()
    for _, id in ipairs(table.clone(companionOrder)) do
        local card = companionCards[id]
        local piece = PieceController.Get(id)

        if not piece then
            RemoveCompanion(id)
            continue
        end

        local health, maxHealth = piece.Rig.Health, piece.Rig.MaxHealth
        if health and maxHealth and card.Shown ~= health then
            card.Shown = health
            DrawHealthCard(card, health, maxHealth)
        end
    end
end

--RIVAL--

local function GetRivalKing()
    for _, piece in ipairs(PieceController.GetTeamPieces("Black")) do
        if piece.Type == "King" then return piece end
    end

    return nil
end

-- Follows the rival King's board health like the companion cards; a dead King leaves the board, so it drops to 0
local function UpdateRival()
    if not rivalCard or not rivalCard.Frame.Visible then return end

    local piece = GetRivalKing()
    local health = piece and piece.Rig.Health or 0
    local maxHealth = piece and piece.Rig.MaxHealth or rivalCard.MaxHealth

    if not maxHealth or rivalCard.Shown == health then return end

    rivalCard.Shown = health
    rivalCard.MaxHealth = maxHealth
    DrawHealthCard(rivalCard, health, maxHealth)
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

    -- Inside the fill so it sits on the filled part and under the dividers
    energyPreview = Instance.new("Frame")
    energyPreview.Name = "Preview"
    energyPreview.BorderSizePixel = 0
    energyPreview.BackgroundColor3 = ENERGY_PREVIEW_COLOR
    energyPreview.Visible = false
    energyPreview.Parent = energyFill

    local blinkInfo = TweenInfo.new(ENERGY_PREVIEW_BLINK_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
    energyPreviewBlink = TweenService:Create(energyPreview, blinkInfo, {BackgroundColor3 = ENERGY_PREVIEW_BLINK_COLOR})

    kingCard = NewHealthCard(root:WaitForChild("TurnBar"):WaitForChild("KingHealth"))
    companionTemplate = root.TurnBar:WaitForChild("CompanionHealth")
    companionTemplate.Visible = false

    -- Missing from HUDs that haven't been updated yet (the Duels place)
    local rivalFrame = root.TurnBar:FindFirstChild("RivalHealth")
    if rivalFrame then
        rivalCard = NewHealthCard(rivalFrame)
        rivalFrame.Visible = false
        -- Follows the atlas when it's re-uploaded
        rivalFrame.PortraitFrame.Portrait.Image = SpriteConfig.ASSET_ID
    end

    ShotgunController.OnModeChanged = UpdateFireLabel

    BoardRemote.OnClientEvent:Connect(function(action, ...)
        if action == "TurnState" then
            Update(...)
        elseif action == "MatchStarted" then
            ClearCompanions()

            if rivalCard then
                rivalCard.Shown = nil
                rivalCard.MaxHealth = nil
            end
        elseif action == "PieceAdded" then
            local id, pieceType, team = ...
            if team == "White" and COMPANIONS[pieceType] then
                AddCompanion(id, pieceType)
            end
        end
    end)

    RunService.Heartbeat:Connect(UpdateCompanions)
    RunService.Heartbeat:Connect(UpdateRival)
end

return CombatHudController
