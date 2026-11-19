local Players = game:GetService("Players")

local overlay = nil
local pausePanel = nil

-- In-match menu: resume, open the settings overlay, or leave to the main menu
local GameMenuController = {}

local function Close()
    pausePanel.Visible = false
    overlay.Visible = false
end

local function Open()
    pausePanel.Visible = true
    overlay.Visible = true
end

local init = false
-- onReturn runs after the main menu is shown again
function GameMenuController.Init(leaveMatch, onReturn, openSettings, closeSettings)
    if init then return end
    init = true

    local playerGui = Players.LocalPlayer.PlayerGui
    local menu = playerGui:WaitForChild("MainMenu")
    local hud = playerGui:WaitForChild("GameHUD")

    overlay = hud:WaitForChild("PauseOverlay")
    pausePanel = overlay:WaitForChild("PausePanel")

    hud:WaitForChild("MenuButton").Activated:Connect(function()
        if overlay.Visible then
            Close()
        else
            Open()
        end
    end)

    pausePanel:WaitForChild("ResumeButton").Activated:Connect(Close)
    pausePanel:WaitForChild("SettingsButton").Activated:Connect(openSettings)

    pausePanel:WaitForChild("MenuButton").Activated:Connect(function()
        Close()
        closeSettings()
        leaveMatch()
        hud.Enabled = false
        menu.Enabled = true

        if onReturn then
            onReturn()
        end
    end)
end

return GameMenuController
