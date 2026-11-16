local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ShotgunRules = require(ReplicatedStorage.Shared.Combat.ShotgunRules)
local ShotgunController = require(script.Parent.ShotgunController)
local SummonPanelController = require(script.Parent.SummonPanelController)

local BoardRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BoardRemote")

local ALT_MODE_NAMES = {
    Precise = "PRECISE SHOT",
    Knife = "KNIFE SWING",
}

local EMPTY_COLOR = Color3.fromHex("D9544D")
local AMMO_COLOR = Color3.fromHex("698FA9")

local fireLabel = nil
local ammoText = nil
local chargeFill = nil
local chargeText = nil
local energyText = nil
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

local function Update(state)
    shotgunName = state.Shotgun
    UpdateFireLabel(ShotgunController.GetMode())

    ammoText.Text = string.format("%d/%d", state.Ammo, state.MaxAmmo)
    ammoText.TextColor3 = state.Ammo > 0 and AMMO_COLOR or EMPTY_COLOR

    chargeFill.Size = UDim2.fromScale(state.UltimateCharge / state.MaxUltimateCharge, 1)
    chargeText.Text = string.format("%d/%d", state.UltimateCharge, state.MaxUltimateCharge)

    energyText.Text = string.format("ENERGY %d/%d", state.Energy, state.MaxEnergy)
    SummonPanelController.SetEnergy(state.Energy)
end

local init = false
function CombatHudController.Init()
    if init then return end
    init = true

    local hud = Players.LocalPlayer.PlayerGui:WaitForChild("GameHUD")
    local root = hud:WaitForChild("Root")
    local actionPanel = root:WaitForChild("ActionPanel")
    local fireButton = actionPanel:WaitForChild("FireButton")
    local ultimateButton = actionPanel:WaitForChild("UltimateButton")

    fireLabel = fireButton:WaitForChild("Label")
    ammoText = fireButton:WaitForChild("AmmoText")
    chargeFill = ultimateButton:WaitForChild("ChargeBar"):WaitForChild("ChargeFill")
    chargeText = ultimateButton:WaitForChild("ChargeText")
    energyText = root:WaitForChild("RightPanel"):WaitForChild("EnergyText")

    ShotgunController.OnModeChanged = UpdateFireLabel

    BoardRemote.OnClientEvent:Connect(function(action, state)
        if action ~= "TurnState" then return end

        Update(state)
    end)
end

return CombatHudController
