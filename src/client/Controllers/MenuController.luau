local Players = game:GetService("Players")

local MenuController = {}

local init = false
function MenuController.Init(startMatch)
    if init then return end
    init = true

    local playerGui = Players.LocalPlayer.PlayerGui
    local menu = playerGui:WaitForChild("MainMenu")
    local hud = playerGui:WaitForChild("GameHUD")

    for _, button in pairs(menu:WaitForChild("Root"):GetChildren()) do
        if not button:IsA("TextButton") then continue end

        local option = button:GetAttribute("Menu")

        button.Activated:Connect(function()
            if option == "Campaign" or option == "Duels" then
                menu.Enabled = false
                hud.Enabled = true
                startMatch()
            end
        end)
    end
end

return MenuController
