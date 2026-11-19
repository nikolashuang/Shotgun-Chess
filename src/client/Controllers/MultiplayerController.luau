local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ProgressionConfig = require(ReplicatedStorage.Shared.Player.ProgressionConfig)
local DuelConfig = require(ReplicatedStorage.Shared.Duel.DuelConfig)
local ArmoryArt = require(ReplicatedStorage.Shared.UI.ArmoryArt)

local DuelRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DuelRemote")

local TEXT_COLOR = Color3.fromHex("E9E3D6")
local MUTED_COLOR = Color3.fromHex("8A8290")
local HOVER_COLOR = Color3.fromHex("F1D4AC")
local DEFAULT_COLOR = Color3.fromHex("9C574B")

-- Seconds a "Sent" or "Declined" note stays on a player's button
local NOTE_TIME = 4

local REASON_TEXT = {
    KingKilled = "King slain",
    Timeout = "Clock ran out",
    Forfeit = "Forfeit",
}

-- Header text for each view; Back steps to the view listed as its parent
local VIEWS = {
    Hub = {Title = "Multiplayer"},
    DuelsView = {Title = "Duels", Parent = "Hub"},
    ChallengeView = {Title = "Challenge", Parent = "DuelsView"},
}

local screen = nil
local root = nil
local menu = nil
local hud = nil
local queueCard = nil
local queueStatus = nil
local list = nil
local emptyLabel = nil
local template = nil
local invitePanel = nil
local resultOverlay = nil

local currentView = "Hub"
local isQueued = false
-- Player -> note text shown on their button for a moment
local notes = {}
local pendingChallenger = nil

-- Duels (quick-match queue and direct challenges), and the start and result of every duel (Practice included)
local MultiplayerController = {}

local function IsUnlocked(player)
    return (player:GetAttribute("Level") or ProgressionConfig.START_LEVEL) >= ProgressionConfig.DUELS_UNLOCK_LEVEL
end

local function ShowView(name)
    currentView = name

    for viewName in pairs(VIEWS) do
        root[viewName].Visible = viewName == name
    end

    root.Header.Text = VIEWS[name].Title
end

local function BindHover(card)
    card.MouseEnter:Connect(function()
        card.UIStroke.Color = HOVER_COLOR
    end)

    card.MouseLeave:Connect(function()
        card.UIStroke.Color = DEFAULT_COLOR
    end)
end

local function SetupCard(card, icon, onActivated)
    ArmoryArt.SetIcon(card.Art.Image, icon)
    BindHover(card)
    card.Activated:Connect(onActivated)
end

--QUEUE--

local function UpdateQueue()
    queueCard.Label.Text = isQueued and "Searching..." or "Queue"
    queueStatus.Text = isQueued and "Click again to cancel" or ""
end

--CHALLENGES--

local function GetButtonText(player)
    if notes[player] then return notes[player], false end
    if not IsUnlocked(player) then return "Lv " .. ProgressionConfig.DUELS_UNLOCK_LEVEL, false end
    if player:GetAttribute("InMatch") then return "Busy", false end

    return "Challenge", true
end

local function SetNote(player, text)
    notes[player] = text
    MultiplayerController.Refresh()

    task.delay(NOTE_TIME, function()
        if notes[player] ~= text then return end

        notes[player] = nil
        MultiplayerController.Refresh()
    end)
end

function MultiplayerController.Refresh()
    if not list then return end

    for _, child in pairs(list:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end

    local count = 0

    for _, player in ipairs(Players:GetPlayers()) do
        if player == Players.LocalPlayer then continue end

        count += 1

        local row = template:Clone()
        row.Name = player.Name
        row.LayoutOrder = count
        row.NameLabel.Text = player.DisplayName
        row.LevelLabel.Text = "Lv " .. (player:GetAttribute("Level") or ProgressionConfig.START_LEVEL)

        local text, canChallenge = GetButtonText(player)
        local button = row.ChallengeButton
        button.Label.Text = text
        button.Label.TextColor3 = canChallenge and TEXT_COLOR or MUTED_COLOR

        button.Activated:Connect(function()
            if not select(2, GetButtonText(player)) then return end

            DuelRemote:FireServer("Challenge", player)
            SetNote(player, "Sent")
        end)

        row.Visible = true
        row.Parent = list
    end

    emptyLabel.Visible = count == 0
end

local function HideInvite()
    pendingChallenger = nil
    invitePanel.Visible = false
end

-- Challenges only pop up outside of matches; a newer one replaces the last
local function ShowInvite(challenger)
    if hud.Enabled then return end

    pendingChallenger = challenger
    invitePanel.Message.Text = challenger.DisplayName .. " challenges you to a duel!"
    invitePanel.Visible = true

    task.delay(DuelConfig.CHALLENGE_TIMEOUT, function()
        if pendingChallenger ~= challenger then return end

        HideInvite()
    end)
end

local function Respond(isAccepted)
    if not pendingChallenger then return end

    DuelRemote:FireServer("Respond", pendingChallenger, isAccepted)
    HideInvite()
end

--MATCHES--

-- Whichever screen the player was on, the duel takes over
local function OnDuelStarted()
    HideInvite()
    isQueued = false
    UpdateQueue()

    for _, gui in pairs(Players.LocalPlayer.PlayerGui:GetChildren()) do
        if gui:IsA("ScreenGui") and gui.Name:sub(-6) == "Screen" then
            gui.Enabled = false
        end
    end

    menu.Enabled = false
    hud.Enabled = true
end

-- Uses the match result panel; its Continue button returns to the main menu
local function ShowResult(summary)
    if not hud.Enabled then return end

    local panel = resultOverlay.ResultPanel
    local lines = {REASON_TEXT[summary.Reason] or ""}

    if summary.Gold > 0 or summary.Exp > 0 then
        table.insert(lines, string.format("+%d Gold", summary.Gold))
        table.insert(lines, string.format("+%d XP", summary.Exp))
    end

    panel.Title.Text = summary.Victory and "Victory!" or "Defeat"
    panel.Rewards.Text = table.concat(lines, "\n")
    resultOverlay.Visible = true
end

-- Back steps out one view at a time, then back to the main menu
local function Back()
    local parent = VIEWS[currentView].Parent

    if parent then
        ShowView(parent)
        return
    end

    screen.Enabled = false
    menu.Enabled = true
end

local init = false
function MultiplayerController.Init()
    if init then return end
    init = true

    local playerGui = Players.LocalPlayer.PlayerGui
    menu = playerGui:WaitForChild("MainMenu")
    hud = playerGui:WaitForChild("GameHUD")
    screen = playerGui:WaitForChild("MultiplayerScreen")
    resultOverlay = hud:WaitForChild("ResultOverlay")

    root = screen:WaitForChild("Root")
    template = root:WaitForChild("PlayerTemplate")

    local hub = root:WaitForChild("Hub")
    local duels = root:WaitForChild("DuelsView")
    local challengeView = root:WaitForChild("ChallengeView")

    queueCard = duels:WaitForChild("QueueCard")
    queueStatus = duels:WaitForChild("QueueStatus")

    local playersPanel = challengeView:WaitForChild("PlayersPanel")
    list = playersPanel:WaitForChild("List")
    emptyLabel = playersPanel:WaitForChild("EmptyLabel")

    -- The hub has room for more multiplayer modes next to Duels
    SetupCard(hub:WaitForChild("DuelsCard"), "Duels", function()
        ShowView("DuelsView")
    end)

    SetupCard(queueCard, "Queue", function()
        DuelRemote:FireServer(isQueued and "LeaveQueue" or "Queue")
    end)

    SetupCard(duels:WaitForChild("ChallengeCard"), "Challenge", function()
        MultiplayerController.Refresh()
        ShowView("ChallengeView")
    end)

    root:WaitForChild("BackButton").Activated:Connect(Back)

    invitePanel = playerGui:WaitForChild("DuelInvite"):WaitForChild("Panel")
    invitePanel:WaitForChild("AcceptButton").Activated:Connect(function()
        Respond(true)
    end)
    invitePanel:WaitForChild("DeclineButton").Activated:Connect(function()
        Respond(false)
    end)

    -- Opening the screen starts at the hub; leaving it leaves the queue
    screen:GetPropertyChangedSignal("Enabled"):Connect(function()
        if screen.Enabled then
            ShowView("Hub")
        elseif isQueued and not hud.Enabled then
            DuelRemote:FireServer("LeaveQueue")
        end
    end)

    local function WatchPlayer(player)
        player:GetAttributeChangedSignal("Level"):Connect(MultiplayerController.Refresh)
        player:GetAttributeChangedSignal("InMatch"):Connect(MultiplayerController.Refresh)
        MultiplayerController.Refresh()
    end

    Players.PlayerAdded:Connect(WatchPlayer)
    Players.PlayerRemoving:Connect(function(player)
        notes[player] = nil

        if pendingChallenger == player then
            HideInvite()
        end

        task.defer(MultiplayerController.Refresh)
    end)

    for _, player in ipairs(Players:GetPlayers()) do
        WatchPlayer(player)
    end

    DuelRemote.OnClientEvent:Connect(function(action, ...)
        if action == "QueueState" then
            isQueued = ...
            UpdateQueue()
        elseif action == "Challenged" then
            ShowInvite(...)
        elseif action == "ChallengeDeclined" then
            SetNote(..., "Declined")
        elseif action == "DuelStarted" then
            OnDuelStarted()
        elseif action == "Result" then
            ShowResult(...)
        end
    end)

    ShowView("Hub")
    UpdateQueue()
end

return MultiplayerController
