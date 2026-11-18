local Players = game:GetService("Players")

local SELECTED_COLOR = Color3.fromHex("F1D4AC")
local DEFAULT_COLOR = Color3.fromHex("9C574B")

-- Label transparency of actions already used this turn
local USED_TRANSPARENCY = 0.6

-- Only usable with a class equipped
local CLASS_ACTIONS = {"Special", "Ultimate"}

local buttonsByAction = {}
local selectedButton = nil
local abilityPanel = nil

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

    local root = Players.LocalPlayer.PlayerGui:WaitForChild("GameHUD"):WaitForChild("Root")
    abilityPanel = root:WaitForChild("AbilityPanel")

    for _, panel in ipairs({root:WaitForChild("ActionPanel"), abilityPanel}) do
        for _, button in pairs(panel:GetChildren()) do
            if not button:IsA("TextButton") then continue end

            buttonsByAction[button:GetAttribute("Action")] = button

            button.Activated:Connect(function()
                ActionPanelController.Select(button)
            end)
        end
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
    if not button or not button.Visible then return end
    if selectedButton == button then return end

    ActionPanelController.Select(button)
end

function ActionPanelController.ToggleAction(action)
    local button = buttonsByAction[action]
    if not button or not button.Visible then return end

    ActionPanelController.Select(button)
end

-- A king with no class only has normal turns and summons, so class actions are hidden
function ActionPanelController.SetClassActionsVisible(isVisible)
    for _, action in ipairs(CLASS_ACTIONS) do
        local button = buttonsByAction[action]

        if button then
            if not isVisible and selectedButton == button then
                ActionPanelController.Select(button)
            end

            button.Visible = isVisible
        end
    end

    abilityPanel.Visible = isVisible
end

-- Each action can be used once per turn, so used ones are faded out
function ActionPanelController.SetUsedActions(usedActions)
    for action, button in pairs(buttonsByAction) do
        local label = button:FindFirstChild("Label")

        if label then
            label.TextTransparency = usedActions[action] and USED_TRANSPARENCY or 0
        end
    end
end

function ActionPanelController.SetKeyLabel(action, text)
    local button = buttonsByAction[action]
    if not button then return end

    button.KeybindBadge.Text = text
end

return ActionPanelController
