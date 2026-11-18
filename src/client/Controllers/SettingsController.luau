local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local KeybindConfig = require(ReplicatedStorage.Shared.Player.KeybindConfig)
local CrtController = require(script.Parent.CrtController)
local ProfileController = require(script.Parent.ProfileController)

local ProfileRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ProfileRemote")

local WAITING_COLOR = Color3.fromHex("F1D4AC")
local DEFAULT_COLOR = Color3.fromHex("9C574B")

local input = nil
local rows = {}
local crtButtons = {}
local capturingAction = nil

-- Keybinds only last for the session until they are saved to a profile; the CRT filter toggle is saved
-- Every keybind panel (main menu and in-match) shows the same bindings
local SettingsController = {}

local function Refresh()
    for _, row in pairs(rows) do
        local action = row.Name
        local isCapturing = action == capturingAction

        row.Key.Text = isCapturing and "Press a key" or input.GetKeyLabel(input.GetBinding(action))
        row.Key.UIStroke.Color = isCapturing and WAITING_COLOR or DEFAULT_COLOR
    end
end

local function StopCapture()
    capturingAction = nil
    input.CancelCapture()
    Refresh()
end

-- Escape cancels; reserved keys are ignored
local function StartCapture(action)
    capturingAction = action
    Refresh()

    input.CaptureNextKey(function(keyCode)
        if keyCode ~= Enum.KeyCode.Escape then
            input.SetBinding(action, keyCode)
        end

        StopCapture()
    end)
end

local function BindPanel(panel)
    local template = panel:WaitForChild("Template")

    for i, action in ipairs(KeybindConfig.ORDER) do
        local row = template:Clone()
        row.Name = action
        row.Label.Text = KeybindConfig.DisplayNames[action]
        row.LayoutOrder = i
        row.Visible = true
        row.Parent = panel.List

        row.Key.Activated:Connect(function()
            if capturingAction == action then
                StopCapture()
            else
                StartCapture(action)
            end
        end)

        table.insert(rows, row)
    end

    local resetButton = panel:WaitForChild("ResetButton")

    resetButton.Activated:Connect(function()
        StopCapture()
        input.ResetBindings()
    end)

    -- Same style as Reset, mirrored to the right side of the panel
    local crtButton = resetButton:Clone()
    crtButton.Name = "CrtButton"
    crtButton.Position = UDim2.new(1 - resetButton.Position.X.Scale - resetButton.Size.X.Scale, 0, resetButton.Position.Y.Scale, 0)
    crtButton.Parent = panel

    crtButton.Activated:Connect(function()
        CrtController.SetEnabled(not CrtController.isEnabled)
        ProfileRemote:FireServer("SetSetting", "CRT", CrtController.isEnabled)
    end)

    table.insert(crtButtons, crtButton)

    -- Closing the panel mid-capture shouldn't leave a key waiting
    panel:GetPropertyChangedSignal("Visible"):Connect(function()
        if not panel.Visible and capturingAction then
            StopCapture()
        end
    end)
end

local init = false
function SettingsController.Init(inputController)
    if init then return end
    init = true

    input = inputController

    local playerGui = Players.LocalPlayer.PlayerGui
    BindPanel(playerGui:WaitForChild("MainMenu"):WaitForChild("Root"):WaitForChild("SettingsPanel"))
    BindPanel(playerGui:WaitForChild("GameHUD"):WaitForChild("PauseOverlay"):WaitForChild("KeybindsPanel"))

    input.OnBindingsChanged = Refresh
    Refresh()

    local function RefreshCrt(isEnabled)
        for _, button in ipairs(crtButtons) do
            button.Text = isEnabled and "CRT Filter: On" or "CRT Filter: Off"
        end
    end

    CrtController.OnChanged(RefreshCrt)
    RefreshCrt(CrtController.isEnabled)

    -- The saved choice arrives with the profile
    ProfileController.OnChanged(function()
        local saved = ProfileController.Data.Settings.CRT

        if saved ~= nil and saved ~= CrtController.isEnabled then
            CrtController.SetEnabled(saved)
        end
    end)
end

return SettingsController
