local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PatchNotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI"):WaitForChild("PatchNotes"))
local DuelResult = require(script.Parent.Parent.UI.DuelResult)

local DuelRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DuelRemote")
local BoardRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BoardRemote")

-- The duel place: the board is up from the moment the player arrives, and the only ways out are
-- surrendering or the duel ending, after which the server sends everyone back to the main game
local DuelPlaceController = {}

local surrenderButton = nil

function DuelPlaceController.Surrender()
    BoardRemote:FireServer("Surrender")
end

local init = false
function DuelPlaceController.Init()
    if init then return end
    init = true

    local playerGui = Players.LocalPlayer.PlayerGui
    local hud = playerGui:WaitForChild("GameHUD")
    local root = hud:WaitForChild("Root")
    local resultOverlay = hud:WaitForChild("ResultOverlay")
    local resultPanel = resultOverlay:WaitForChild("ResultPanel")
    local returnButton = resultPanel:WaitForChild("ContinueButton")
    local turnLabel = root:WaitForChild("TurnBar"):WaitForChild("TurnLabel")

    surrenderButton = root:WaitForChild("SurrenderButton")
    surrenderButton.Visible = true
    surrenderButton.Activated:Connect(DuelPlaceController.Surrender)

    hud.Enabled = true
    turnLabel.Text = "Waiting for your rival..."
    -- The main game sets this from its patch notes screen, which the duel place doesn't have
    playerGui:WaitForChild("VersionGui"):WaitForChild("Version").Text = "v" .. PatchNotes.VERSION

    -- Only shown if the automatic return failed
    returnButton.Activated:Connect(function()
        returnButton.Visible = false
        resultPanel.Rewards.Text ..= "\nReturning..."
        DuelRemote:FireServer("Return")
    end)

    BoardRemote.OnClientEvent:Connect(function(action, state)
        if action ~= "TurnState" then return end

        surrenderButton.Visible = state.Phase ~= "Over"
    end)

    DuelRemote.OnClientEvent:Connect(function(action, summary)
        if action == "Result" then
            surrenderButton.Visible = false
            DuelResult.Show(resultOverlay, summary)
        elseif action == "ReturnFailed" then
            resultPanel.Rewards.Text = "Couldn't return you to the lobby:\n" .. summary
            returnButton.Label.Text = "Return to Lobby"
            returnButton.Visible = true
            resultOverlay.Visible = true
        elseif action == "RivalMissing" then
            surrenderButton.Visible = false
            turnLabel.Text = "Your rival didn't arrive - back to the queue..."
        end
    end)

    -- The board is ready; the server starts once every matched player says so
    DuelRemote:FireServer("Ready")
end

return DuelPlaceController
