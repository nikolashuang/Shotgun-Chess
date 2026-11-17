local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local DevConfig = require(ReplicatedStorage.Shared.Player.DevConfig)

local DevRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DevRemote")

-- Shows the dev menu button to dev accounts; the panel itself opens through MenuController like other panels
local DevPanelController = {}

local init = false
function DevPanelController.Init()
    if init then return end
    init = true

    local player = Players.LocalPlayer
    local root = player.PlayerGui:WaitForChild("MainMenu"):WaitForChild("Root")
    local button = root:WaitForChild("DevButton")
    local panel = root:WaitForChild("DevPanel")

    button.Visible = DevConfig.IsDev(player)
    if not button.Visible then
        panel:Destroy()
        return
    end

    local status = panel:WaitForChild("Status")

    for _, actionButton in pairs(panel:GetChildren()) do
        local action = actionButton:GetAttribute("DevAction")
        if not action then continue end

        actionButton.Activated:Connect(function()
            DevRemote:FireServer(action)
            status.Text = actionButton:GetAttribute("Done")
        end)
    end
end

return DevPanelController
