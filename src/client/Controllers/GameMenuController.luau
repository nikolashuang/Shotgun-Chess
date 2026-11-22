local Players = game:GetService("Players")

local overlay = nil
local pausePanel = nil

-- In-match menu: resume, open the settings overlay, or leave to the main menu
-- The duel place has no main menu, so there the last button surrenders instead
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
-- onReturn runs after the main menu is shown again; passing surrender (duel place) swaps Back to Menu for Surrender
function GameMenuController.Init(leaveMatch, onReturn, openSettings, closeSettings, surrender)
    if init then return end
    init = true

    local playerGui = Players.LocalPlayer.PlayerGui
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

    local menuButton = pausePanel:WaitForChild("MenuButton")
    local surrenderButton = pausePanel:WaitForChild("SurrenderButton")
    menuButton.Visible = surrender == nil
    surrenderButton.Visible = surrender ~= nil

    if surrender then
        surrenderButton.Activated:Connect(function()
            Close()
            closeSettings()
            surrender()
        end)
        return
    end

    local menu = playerGui:WaitForChild("MainMenu")

    menuButton.Activated:Connect(function()
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
