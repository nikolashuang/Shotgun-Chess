local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local CombatConfig = require(ReplicatedStorage.Shared.Combat.CombatConfig)
local PieceConfig = require(ReplicatedStorage.Shared.Board.PieceConfig)
local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)
local BoardRules = require(ReplicatedStorage.Shared.Board.BoardRules)

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
-- The action button under the mouse, so its energy cost can be previewed before it's picked
ActionPanelController.HoveredAction = nil
ActionPanelController.OnHoverChanged = nil

-- Summon costs depend on the piece, so it shows the cheapest to the dearest
local function GetCostText(action)
    if action == "Summon" then
        local lowest, highest = math.huge, 0

        for _, pieceType in ipairs(PieceConfig.SUMMONABLE) do
            lowest = math.min(lowest, PieceConfig.Cost[pieceType])
            highest = math.max(highest, PieceConfig.Cost[pieceType])
        end

        return string.format("%d-%d Energy", lowest, highest)
    end

    local cost = CombatConfig.ActionCost[action]
    if not cost then return "" end
    if cost == 0 then return "Free" end
    -- Longer commands cost more, up to a slide from one corner of the board to the other
    if action == "Command" then
        local highest = BoardRules.GetCommandCost(1, 1, BoardConfig.SIZE, BoardConfig.SIZE)
        return string.format("%d-%d Energy", cost, highest)
    end

    return cost .. " Energy"
end

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

            local costLabel = button:FindFirstChild("CostLabel")
            if costLabel then
                costLabel.Text = GetCostText(button:GetAttribute("Action"))
            end

            button.Activated:Connect(function()
                ActionPanelController.Select(button)
            end)

            local action = button:GetAttribute("Action")

            button.MouseEnter:Connect(function()
                ActionPanelController.HoveredAction = action
                if ActionPanelController.OnHoverChanged then ActionPanelController.OnHoverChanged() end
            end)

            button.MouseLeave:Connect(function()
                if ActionPanelController.HoveredAction ~= action then return end

                ActionPanelController.HoveredAction = nil
                if ActionPanelController.OnHoverChanged then ActionPanelController.OnHoverChanged() end
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
