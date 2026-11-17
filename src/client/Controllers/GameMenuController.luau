local Players = game:GetService("Players")

local overlay = nil
local pausePanel = nil
local keybindsPanel = nil

-- In-match settings: resume, rebind keys, or leave to the main menu
local GameMenuController = {}

local function Close()
    keybindsPanel.Visible = false
    pausePanel.Visible = false
    overlay.Visible = false
end

local function ShowPage(page)
    pausePanel.Visible = page == pausePanel
    keybindsPanel.Visible = page == keybindsPanel
    overlay.Visible = true
end

local init = false
-- onReturn runs after the main menu is shown again
function GameMenuController.Init(leaveMatch, onReturn)
    if init then return end
    init = true

    local playerGui = Players.LocalPlayer.PlayerGui
    local menu = playerGui:WaitForChild("MainMenu")
    local hud = playerGui:WaitForChild("GameHUD")
    local root = hud:WaitForChild("Root")

    overlay = hud:WaitForChild("PauseOverlay")
    pausePanel = overlay:WaitForChild("PausePanel")
    keybindsPanel = overlay:WaitForChild("KeybindsPanel")

    root:WaitForChild("SettingsButton").Activated:Connect(function()
        if overlay.Visible then
            Close()
        else
            ShowPage(pausePanel)
        end
    end)

    pausePanel:WaitForChild("ResumeButton").Activated:Connect(Close)

    pausePanel:WaitForChild("KeybindsButton").Activated:Connect(function()
        ShowPage(keybindsPanel)
    end)

    keybindsPanel:WaitForChild("BackButton").Activated:Connect(function()
        ShowPage(pausePanel)
    end)

    pausePanel:WaitForChild("MenuButton").Activated:Connect(function()
        Close()
        leaveMatch()
        hud.Enabled = false
        menu.Enabled = true

        if onReturn then
            onReturn()
        end
    end)
end

return GameMenuController
