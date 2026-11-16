local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local KeybindConfig = require(ReplicatedStorage.Shared.Player.KeybindConfig)

local WAITING_COLOR = Color3.fromHex("E6C47C")
local DEFAULT_COLOR = Color3.fromHex("354867")

local input = nil
local rowsByAction = {}
local capturingAction = nil

-- Keybinds only last for the session until settings are saved to a profile
local SettingsController = {}

local function Refresh()
    for action, row in pairs(rowsByAction) do
        local isCapturing = action == capturingAction

        row.Key.Text = isCapturing and "PRESS KEY" or input.GetKeyLabel(input.GetBinding(action))
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

local init = false
function SettingsController.Init(inputController)
    if init then return end
    init = true

    input = inputController

    local panel = Players.LocalPlayer.PlayerGui:WaitForChild("MainMenu"):WaitForChild("Root"):WaitForChild("SettingsPanel")
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

        rowsByAction[action] = row
    end

    panel:WaitForChild("ResetButton").Activated:Connect(function()
        StopCapture()
        input.ResetBindings()
    end)

    -- Closing the panel mid-capture shouldn't leave a key waiting
    panel:GetPropertyChangedSignal("Visible"):Connect(function()
        if not panel.Visible and capturingAction then
            StopCapture()
        end
    end)

    input.OnBindingsChanged = Refresh
    Refresh()
end

return SettingsController
