local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local BoardRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BoardRemote")

local PLAYER_COLOR = Color3.fromHex("E9E3D6")
local ENEMY_COLOR = Color3.fromHex("C8644F")
local READY_COLOR = Color3.fromHex("F1D4AC")
local DISABLED_COLOR = Color3.fromHex("9C574B")
local MUTED_COLOR = Color3.fromHex("8A8290")

-- Duel clocks turn red below this many seconds
local LOW_CLOCK = 30

-- Move Ready grows and shrinks while the King can still move
local MOVE_PULSE = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local MOVE_PULSE_SCALE = 1.12

local turnLabel = nil
-- Beside the Actions header, so players see whether their King can still move this turn
local moveLabel = nil
local movePulse = nil
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
        turnLabel.Text = string.format("Turn %d", state.Turn)
        turnLabel.TextColor3 = PLAYER_COLOR
    elseif state.Phase == "Stunned" then
        turnLabel.Text = "Stunned - Turn Skipped"
        turnLabel.TextColor3 = ENEMY_COLOR
    elseif state.Phase == "Countdown" then
        turnLabel.Text = "Starting in " .. state.Countdown
        turnLabel.TextColor3 = READY_COLOR
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

    moveLabel.Visible = isMyTurn or state.Phase == "Stunned"

    if state.Phase == "Stunned" then
        moveLabel.Text = "Can't Move"
        moveLabel.TextColor3 = ENEMY_COLOR
    elseif state.HasMoved then
        moveLabel.Text = "Moved"
        moveLabel.TextColor3 = MUTED_COLOR
    else
        moveLabel.Text = "Move Ready"
        moveLabel.TextColor3 = READY_COLOR
    end

    local isPulsing = isMyTurn and not state.HasMoved

    if isPulsing and movePulse.PlaybackState ~= Enum.PlaybackState.Playing then
        movePulse:Play()
    elseif not isPulsing and movePulse.PlaybackState == Enum.PlaybackState.Playing then
        movePulse:Cancel()
        movePulse.Instance.Scale = 1
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
    moveLabel = hud.Root:WaitForChild("ActionPanel"):WaitForChild("MoveLabel")
    moveLabel.Visible = false
    movePulse = TweenService:Create(moveLabel:WaitForChild("UIScale"), MOVE_PULSE, {Scale = MOVE_PULSE_SCALE})

    endTurnButton.Activated:Connect(TurnController.EndTurn)
    RunService.Heartbeat:Connect(UpdateClock)

    BoardRemote.OnClientEvent:Connect(function(action, state)
        if action ~= "TurnState" then return end

        Update(state)
    end)
end

return TurnController
