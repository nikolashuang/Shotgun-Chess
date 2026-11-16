local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local KeybindConfig = require(ReplicatedStorage.Shared.Player.KeybindConfig)

local actionPanel = nil
local turnController = nil
local bindings = {}
local captureCallback = nil

local InputController = {}

InputController.OnBindingsChanged = nil

function InputController.GetKeyLabel(keyCode)
    return KeybindConfig.KeyLabels[keyCode.Name] or string.upper(keyCode.Name)
end

function InputController.GetBinding(action)
    return bindings[action]
end

local function RefreshLabels()
    for action, keyCode in pairs(bindings) do
        local label = InputController.GetKeyLabel(keyCode)

        if action == "EndTurn" then
            turnController.SetKeyLabel(label)
        else
            actionPanel.SetKeyLabel(action, label)
        end
    end

    if InputController.OnBindingsChanged then
        InputController.OnBindingsChanged()
    end
end

-- A key already bound to another action swaps over to this action's old key
function InputController.SetBinding(action, keyCode)
    if table.find(KeybindConfig.RESERVED, keyCode.Name) then return false end

    for other, otherKey in pairs(bindings) do
        if otherKey == keyCode and other ~= action then
            bindings[other] = bindings[action]
        end
    end

    bindings[action] = keyCode
    RefreshLabels()

    return true
end

function InputController.ResetBindings()
    for action, keyName in pairs(KeybindConfig.Defaults) do
        bindings[action] = Enum.KeyCode[keyName]
    end

    RefreshLabels()
end

-- The next key press goes to the callback instead of triggering an action
function InputController.CaptureNextKey(callback)
    captureCallback = callback
end

function InputController.CancelCapture()
    captureCallback = nil
end

local function GetAction(keyCode)
    for action, boundKey in pairs(bindings) do
        if boundKey == keyCode then return action end
    end

    return nil
end

local init = false
function InputController.Init(actionPanelController, turnControllerModule)
    if init then return end
    init = true

    actionPanel = actionPanelController
    turnController = turnControllerModule

    InputController.ResetBindings()

    UserInputService.InputBegan:Connect(function(input, processed)
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

        if captureCallback then
            local callback = captureCallback
            captureCallback = nil
            callback(input.KeyCode)
            return
        end

        if processed then return end

        local action = GetAction(input.KeyCode)
        if not action then return end

        if action == "EndTurn" then
            turnController.EndTurn()
        else
            actionPanel.ToggleAction(action)
        end
    end)
end

return InputController
