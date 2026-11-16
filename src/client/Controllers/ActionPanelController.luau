local Players = game:GetService("Players")

local SELECTED_COLOR = Color3.fromHex("E6C47C")
local DEFAULT_COLOR = Color3.fromHex("354867")

local buttonsByKeybind = {}
local buttonsByAction = {}
local selectedButton = nil

local ActionPanelController = {}

ActionPanelController.SelectedAction = nil
ActionPanelController.OnSelectionChanged = nil

local function SetHighlight(button, enabled)
    local stroke = button:FindFirstChildOfClass("UIStroke")
    if not stroke then return end

    stroke.Color = enabled and SELECTED_COLOR or DEFAULT_COLOR
end

local init = false
function ActionPanelController.Init()
    if init then return end
    init = true

    local hud = Players.LocalPlayer.PlayerGui:WaitForChild("GameHUD")
    local actionPanel = hud:WaitForChild("Root"):WaitForChild("ActionPanel")

    for _, button in pairs(actionPanel:GetChildren()) do
        if not button:IsA("TextButton") then continue end

        buttonsByAction[button:GetAttribute("Action")] = button

        local keybind = button:GetAttribute("Keybind")
        if keybind then
            buttonsByKeybind[keybind] = button
        end

        button.Activated:Connect(function()
            ActionPanelController.Select(button)
        end)
    end
end

function ActionPanelController.Select(button)
    if selectedButton then
        SetHighlight(selectedButton, false)
    end

    if selectedButton == button then
        selectedButton = nil
        ActionPanelController.SelectedAction = nil
    else
        selectedButton = button
        ActionPanelController.SelectedAction = button:GetAttribute("Action")
        SetHighlight(button, true)
    end

    if ActionPanelController.OnSelectionChanged then
        ActionPanelController.OnSelectionChanged()
    end
end

function ActionPanelController.ClearSelection()
    if not selectedButton then return end

    ActionPanelController.Select(selectedButton)
end

-- Selects without toggling off an action that is already selected
function ActionPanelController.SelectAction(action)
    local button = buttonsByAction[action]
    if not button then return end
    if selectedButton == button then return end

    ActionPanelController.Select(button)
end

function ActionPanelController.SelectByKeybind(keybind)
    local button = buttonsByKeybind[keybind]
    if not button then return end

    ActionPanelController.Select(button)
end

return ActionPanelController
