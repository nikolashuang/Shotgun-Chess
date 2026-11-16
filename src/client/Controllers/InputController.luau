local UserInputService = game:GetService("UserInputService")

local Keybinds = {
    [Enum.KeyCode.One] = 1,
    [Enum.KeyCode.Two] = 2,
    [Enum.KeyCode.Three] = 3,
    [Enum.KeyCode.Four] = 4,
    [Enum.KeyCode.Five] = 5,
    [Enum.KeyCode.Six] = 6,
}

local InputController = {}

local init = false
function InputController.Init(actionPanelController)
    if init then return end
    init = true

    UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end

        local keybind = Keybinds[input.KeyCode]
        if keybind then
            actionPanelController.SelectByKeybind(keybind)
        end
    end)
end

return InputController
