local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local BoardRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BoardRemote")

local PLAYER_COLOR = Color3.fromHex("E9E3D6")
local ENEMY_COLOR = Color3.fromHex("C8644F")
local READY_COLOR = Color3.fromHex("F1D4AC")
local DISABLED_COLOR = Color3.fromHex("9C574B")

-- Duel clocks turn red below this many seconds
local LOW_CLOCK = 30

local turnLabel = nil
local endTurnButton = nil
local clockLabel = nil
local isMyTurn = false

-- Duel clocks as last sent by the server, and when they arrived; nil outside duels
local clocks = nil

local TurnController = {}

local function FormatClock(seconds)
    seconds = math.max(math.ceil(seconds), 0)

    return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- Only the clock of the player whose turn it is runs
local function UpdateClock()
    if not clocks then return end

    local elapsed = time() - clocks.ReceivedAt
    local mine = clocks.Mine - (clocks.Phase == "PlayerTurn" and elapsed or 0)
    local enemy = clocks.Enemy - (clocks.Phase == "EnemyTurn" and elapsed or 0)

    clockLabel.Text = string.format("You %s   |   Rival %s", FormatClock(mine), FormatClock(enemy))
    clockLabel.TextColor3 = (isMyTurn and mine <= LOW_CLOCK) and ENEMY_COLOR or PLAYER_COLOR
end

local function Update(state)
    isMyTurn = state.Phase == "PlayerTurn"

    if state.Clock then
        clocks = {Mine = state.Clock, Enemy = state.EnemyClock, Phase = state.Phase, ReceivedAt = time()}
    else
        clocks = nil
    end

    clockLabel.Visible = clocks ~= nil
    UpdateClock()

    if isMyTurn then
        local moves = state.HasMoved and 0 or 1

        turnLabel.Text = string.format("Turn %d   Move %d", state.Turn, moves)
        turnLabel.TextColor3 = PLAYER_COLOR
    elseif state.Phase == "Stunned" then
        turnLabel.Text = "Stunned - Turn Skipped"
        turnLabel.TextColor3 = ENEMY_COLOR
    elseif state.Phase == "Over" then
        turnLabel.Text = "Match Over"
        turnLabel.TextColor3 = READY_COLOR
    else
        turnLabel.Text = clocks and "Opponent's Turn" or "Enemy Turn"

        -- Warns a stunned player that their next turn will be skipped
        if state.KingStunned then
            turnLabel.Text ..= " - You're Stunned"
        end
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
    clockLabel = hud.Root:WaitForChild("DuelClock")

    endTurnButton.Activated:Connect(TurnController.EndTurn)
    RunService.Heartbeat:Connect(UpdateClock)

    BoardRemote.OnClientEvent:Connect(function(action, state)
        if action ~= "TurnState" then return end

        Update(state)
    end)
end

return TurnController
