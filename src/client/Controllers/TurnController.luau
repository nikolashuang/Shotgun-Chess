local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local BoardRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BoardRemote")

local PLAYER_COLOR = Color3.fromHex("F0E9D8")
local ENEMY_COLOR = Color3.fromHex("D9544D")
local READY_COLOR = Color3.fromHex("E6C47C")
local DISABLED_COLOR = Color3.fromHex("354867")

local turnLabel = nil
local endTurnButton = nil
local isMyTurn = false

local TurnController = {}

local function Update(state)
    isMyTurn = state.Phase == "PlayerTurn"

    if isMyTurn then
        local moves = state.HasMoved and 0 or 1
        local actions = state.HasActed and 0 or 1

        turnLabel.Text = string.format("TURN %d   MOVE %d   ACTION %d", state.Turn, moves, actions)
        turnLabel.TextColor3 = PLAYER_COLOR
    else
        turnLabel.Text = "ENEMY TURN"
        turnLabel.TextColor3 = ENEMY_COLOR
    end

    endTurnButton.UIStroke.Color = isMyTurn and READY_COLOR or DISABLED_COLOR
    endTurnButton.Label.TextTransparency = isMyTurn and 0 or 0.6
end

local init = false
function TurnController.Init()
    if init then return end
    init = true

    local hud = Players.LocalPlayer.PlayerGui:WaitForChild("GameHUD")
    local turnBar = hud:WaitForChild("Root"):WaitForChild("TurnBar")

    turnLabel = turnBar:WaitForChild("TurnLabel")
    endTurnButton = turnBar:WaitForChild("EndTurnButton")

    endTurnButton.Activated:Connect(function()
        if not isMyTurn then return end

        BoardRemote:FireServer("EndTurn")
    end)

    BoardRemote.OnClientEvent:Connect(function(action, state)
        if action ~= "TurnState" then return end

        Update(state)
    end)
end

return TurnController
