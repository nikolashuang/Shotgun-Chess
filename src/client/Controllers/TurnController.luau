local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local BoardRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BoardRemote")

local PLAYER_COLOR = Color3.fromHex("E9E3D6")
local ENEMY_COLOR = Color3.fromHex("C8644F")
local READY_COLOR = Color3.fromHex("F1D4AC")
local DISABLED_COLOR = Color3.fromHex("9C574B")

local turnLabel = nil
local endTurnButton = nil
local isMyTurn = false

local TurnController = {}

local function Update(state)
    isMyTurn = state.Phase == "PlayerTurn"

    if isMyTurn then
        local moves = state.HasMoved and 0 or 1

        turnLabel.Text = string.format("Turn %d   Move %d", state.Turn, moves)
        turnLabel.TextColor3 = PLAYER_COLOR
    elseif state.Phase == "Over" then
        turnLabel.Text = "Match Over"
        turnLabel.TextColor3 = READY_COLOR
    else
        turnLabel.Text = "Enemy Turn"
        turnLabel.TextColor3 = ENEMY_COLOR
    end

    endTurnButton.UIStroke.Color = isMyTurn and READY_COLOR or DISABLED_COLOR
    endTurnButton.Label.TextTransparency = isMyTurn and 0 or 0.6
end

function TurnController.SetKeyLabel(text)
    endTurnButton.Label.Text = "End Turn [" .. text .. "]"
end

function TurnController.EndTurn()
    if not isMyTurn then return end

    BoardRemote:FireServer("EndTurn")
end

local init = false
function TurnController.Init()
    if init then return end
    init = true

    local hud = Players.LocalPlayer.PlayerGui:WaitForChild("GameHUD")
    local turnBar = hud:WaitForChild("Root"):WaitForChild("TurnBar")

    turnLabel = turnBar:WaitForChild("TurnLabel")
    endTurnButton = turnBar:WaitForChild("EndTurnButton")

    endTurnButton.Activated:Connect(TurnController.EndTurn)

    BoardRemote.OnClientEvent:Connect(function(action, state)
        if action ~= "TurnState" then return end

        Update(state)
    end)
end

return TurnController
