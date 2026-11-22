local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ProgressionConfig = require(ReplicatedStorage.Shared.Player.ProgressionConfig)
local DuelConfig = require(ReplicatedStorage.Shared.Duel.DuelConfig)
local ArmoryArt = require(ReplicatedStorage.Shared.UI.ArmoryArt)
local DuelResult = require(script.Parent.Parent.UI.DuelResult)
local SingleplayerController = require(script.Parent.SingleplayerController)

local DuelRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DuelRemote")
local BoardRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BoardRemote")

local TEXT_COLOR = Color3.fromHex("E9E3D6")
local MUTED_COLOR = Color3.fromHex("8A8290")
local LOCKED_COLOR = Color3.fromHex("8A8290")
local HOVER_COLOR = Color3.fromHex("F1D4AC")
local DEFAULT_COLOR = Color3.fromHex("9C574B")

-- Seconds a "Sent" or "Declined" note stays on a player's button
local NOTE_TIME = 4

local POSITION_TEXT = {
    Teammate = "Teammate",
    Rival1 = "Rival 1",
    Rival2 = "Rival 2",
}

-- Header text for each view; Back steps to the view listed as its parent
-- Duels first picks 1v1 (DuelsView) or 2v2 (TeamView)
local VIEWS = {
    Hub = {Title = "Multiplayer"},
    ModeView = {Title = "Duels", Parent = "Hub"},
    DuelsView = {Title = "1v1", Parent = "ModeView"},
    TeamView = {Title = "2v2", Parent = "ModeView"},
    ChallengeView = {Title = "Challenge", Parent = "DuelsView"},
    LobbyView = {Title = "2v2 Challenge", Parent = "TeamView"},
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
local lobbyView = nil
local lobbyList = nil
local lobbyEmptyLabel = nil
local surrenderButton = nil
local teammatePanel = nil

local currentView = "Hub"
local isQueued = false
-- Shown under the queue card in place of the usual hint (match found, teleport failed, requeued)
local queueNote = nil
-- Player -> note text shown on their button for a moment
local notes = {}
-- The open invite: {Kind = "Challenge", From} or {Kind = "Lobby", From, Position}
local pendingInvite = nil
-- Latest 2v2 lobby from the server ({Host, Teammate, Rival1, Rival2}), nil when not in one
local lobbyState = nil
-- The empty position the host's next invite fills
local selectedPosition = "Teammate"

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

-- Duels open at a higher level than the Multiplayer screen itself
local function UpdateDuelsLock(card)
    local isUnlocked = IsUnlocked(Players.LocalPlayer)

    card.Label.Text = isUnlocked and "Duels" or "Duels [Lv " .. ProgressionConfig.DUELS_UNLOCK_LEVEL .. "]"
    card.Label.TextTransparency = isUnlocked and 0 or 0.5
    card.Art.Image.ImageColor3 = isUnlocked and Color3.new(1, 1, 1) or LOCKED_COLOR
end

--QUEUE--

local function UpdateQueue()
    queueCard.Label.Text = isQueued and "Searching..." or "Global Queue"
    queueStatus.Text = queueNote or (isQueued and "Click again to cancel" or "")
end

local function SetQueueNote(text)
    queueNote = text
    UpdateQueue()

    task.delay(NOTE_TIME, function()
        if queueNote ~= text then return end

        queueNote = nil
        UpdateQueue()
    end)
end

--2V2 LOBBY--

local function IsInLobby(player)
    if not lobbyState then return false end
    if lobbyState.Host == player then return true end

    for position in pairs(POSITION_TEXT) do
        if lobbyState[position] == player then return true end
    end

    return false
end

local function GetLobbyButtonText(player)
    if notes[player] then return notes[player], false end
    if IsInLobby(player) then return "In Lobby", false end
    if lobbyState.Host ~= Players.LocalPlayer then return "Host invites", false end
    if lobbyState[selectedPosition] then return "Pick a slot", false end
    if not IsUnlocked(player) then return "Lv " .. ProgressionConfig.DUELS_UNLOCK_LEVEL, false end
    if player:GetAttribute("InMatch") then return "Busy", false end

    return "Invite", true
end

-- Empty positions can be picked by the host; filled ones show who took them
local function RefreshLobby()
    if not lobbyView or not lobbyState then return end

    local slots = lobbyView.SlotsPanel
    local isHost = lobbyState.Host == Players.LocalPlayer

    slots.HostSlot.Label.Text = "Host: " .. lobbyState.Host.DisplayName

    for position, text in pairs(POSITION_TEXT) do
        local player = lobbyState[position]
        local slot = slots[position .. "Slot"]
        local isSelected = isHost and not player and position == selectedPosition

        slot.Label.Text = text .. ": " .. (player and player.DisplayName or "Empty")
        slot.UIStroke.Color = isSelected and HOVER_COLOR or DEFAULT_COLOR
    end

    lobbyView.PlayersPanel.Title.Text = isHost and "Invite to: " .. POSITION_TEXT[selectedPosition] or "Waiting for the host"

    for _, child in pairs(lobbyList:GetChildren()) do
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

        local text, canInvite = GetLobbyButtonText(player)
        local button = row.ChallengeButton
        button.Label.Text = text
        button.Label.TextColor3 = canInvite and TEXT_COLOR or MUTED_COLOR

        button.Activated:Connect(function()
            if not lobbyState or not select(2, GetLobbyButtonText(player)) then return end

            DuelRemote:FireServer("LobbyInvite", player, selectedPosition)
            notes[player] = "Sent"
            RefreshLobby()

            task.delay(NOTE_TIME, function()
                if notes[player] ~= "Sent" then return end

                notes[player] = nil
                RefreshLobby()
            end)
        end)

        row.Visible = true
        row.Parent = lobbyList
    end

    lobbyEmptyLabel.Visible = count == 0
end

local function OnLobbyState(state)
    lobbyState = state

    if not state then
        if currentView == "LobbyView" then
            ShowView("TeamView")
        end
        return
    end

    -- The host's pick moves on to the next empty position
    if state[selectedPosition] then
        for _, position in ipairs(DuelConfig.LOBBY_POSITIONS) do
            if not state[position] then
                selectedPosition = position
                break
            end
        end
    end

    if screen.Enabled and currentView ~= "LobbyView" then
        ShowView("LobbyView")
    end

    RefreshLobby()
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
    RefreshLobby()

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
    pendingInvite = nil
    invitePanel.Visible = false
end

-- Invites only pop up outside of matches; a newer one replaces the last
local function ShowInvite(invite)
    if hud.Enabled then return end

    pendingInvite = invite

    if invite.Kind == "Lobby" then
        invitePanel.Message.Text = string.format("%s invites you to a 2v2 as %s!", invite.From.DisplayName, POSITION_TEXT[invite.Position])
    else
        invitePanel.Message.Text = invite.From.DisplayName .. " challenges you to a duel!"
    end

    invitePanel.Visible = true

    task.delay(DuelConfig.CHALLENGE_TIMEOUT, function()
        if pendingInvite ~= invite then return end

        HideInvite()
    end)
end

local function Respond(isAccepted)
    if not pendingInvite then return end

    if pendingInvite.Kind == "Lobby" then
        DuelRemote:FireServer("LobbyRespond", pendingInvite.From, isAccepted)
    else
        DuelRemote:FireServer("Respond", pendingInvite.From, isAccepted)
    end

    HideInvite()
end

--2V2 MATCH--

local function OnTurnState(state)
    local isShown = state.TeamDuel and state.Phase ~= "Over" and not state.IsOut
    surrenderButton.Visible = isShown == true

    if not isShown then
        teammatePanel.Visible = false
    end
end

local function Surrender()
    BoardRemote:FireServer("Surrender")
    surrenderButton.Label.Text = "Waiting for teammate"
    teammatePanel.Visible = false
end

--MATCHES--

-- Whichever screen the player was on, the duel takes over
local function OnDuelStarted()
    HideInvite()
    isQueued = false
    UpdateQueue()
    lobbyState = nil
    surrenderButton.Label.Text = "Surrender"
    teammatePanel.Visible = false

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

    DuelResult.Show(resultOverlay, summary)
end

-- Back steps out one view at a time, then back to the main menu
local function Back()
    local parent = VIEWS[currentView].Parent

    if currentView == "LobbyView" then
        DuelRemote:FireServer("LeaveLobby")
    end

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
    local modeView = root:WaitForChild("ModeView")
    local duels = root:WaitForChild("DuelsView")
    local teamView = root:WaitForChild("TeamView")
    local challengeView = root:WaitForChild("ChallengeView")
    lobbyView = root:WaitForChild("LobbyView")
    lobbyList = lobbyView:WaitForChild("PlayersPanel"):WaitForChild("List")
    lobbyEmptyLabel = lobbyView.PlayersPanel:WaitForChild("EmptyLabel")

    queueCard = duels:WaitForChild("QueueCard")
    queueStatus = duels:WaitForChild("QueueStatus")

    local playersPanel = challengeView:WaitForChild("PlayersPanel")
    list = playersPanel:WaitForChild("List")
    emptyLabel = playersPanel:WaitForChild("EmptyLabel")

    -- The hub has room for more multiplayer modes next to Duels
    local duelsCard = hub:WaitForChild("DuelsCard")

    SetupCard(duelsCard, "Duels", function()
        if not IsUnlocked(Players.LocalPlayer) then return end

        ShowView("ModeView")
    end)

    UpdateDuelsLock(duelsCard)
    Players.LocalPlayer:GetAttributeChangedSignal("Level"):Connect(function()
        UpdateDuelsLock(duelsCard)
    end)

    -- Co-op Siege is locked until the mode is built
    local siegeCard = hub:WaitForChild("SiegeCard")
    ArmoryArt.SetIcon(siegeCard.Art.Image, "SiegeCoop")
    siegeCard.Art.Image.ImageColor3 = LOCKED_COLOR
    siegeCard.Label.TextTransparency = 0.5
    SingleplayerController.AddLock(siegeCard.Art)

    SetupCard(modeView:WaitForChild("OneCard"), "Duels", function()
        ShowView("DuelsView")
    end)

    SetupCard(modeView:WaitForChild("TwoCard"), "Duels", function()
        ShowView("TeamView")
    end)

    -- The 2v2 queue isn't built yet
    local teamQueueCard = teamView:WaitForChild("QueueCard")
    ArmoryArt.SetIcon(teamQueueCard.Art.Image, "GlobalQueue")
    teamQueueCard.Art.Image.ImageColor3 = LOCKED_COLOR
    teamQueueCard.Label.TextTransparency = 0.5

    SetupCard(queueCard, "GlobalQueue", function()
        DuelRemote:FireServer(isQueued and "LeaveQueue" or "Queue")
    end)

    SetupCard(duels:WaitForChild("ChallengeCard"), "Challenge", function()
        MultiplayerController.Refresh()
        ShowView("ChallengeView")
    end)

    SetupCard(teamView:WaitForChild("ChallengeCard"), "Challenge", function()
        if lobbyState then
            ShowView("LobbyView")
            RefreshLobby()
            return
        end

        DuelRemote:FireServer("CreateLobby")
    end)

    local slots = lobbyView:WaitForChild("SlotsPanel")

    for position in pairs(POSITION_TEXT) do
        slots:WaitForChild(position .. "Slot").Activated:Connect(function()
            if not lobbyState or lobbyState.Host ~= Players.LocalPlayer then return end
            if lobbyState[position] then return end

            selectedPosition = position
            RefreshLobby()
        end)
    end

    slots:WaitForChild("LeaveButton").Activated:Connect(function()
        DuelRemote:FireServer("LeaveLobby")
    end)

    surrenderButton = hud:WaitForChild("Root"):WaitForChild("SurrenderButton")
    surrenderButton.Activated:Connect(Surrender)

    teammatePanel = hud:WaitForChild("TeammatePanel")
    teammatePanel:WaitForChild("FightOnButton").Activated:Connect(function()
        teammatePanel.Visible = false
    end)
    teammatePanel:WaitForChild("SurrenderButton").Activated:Connect(Surrender)

    screen:WaitForChild("BackButton").Activated:Connect(Back)

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
        elseif not hud.Enabled then
            if isQueued then
                DuelRemote:FireServer("LeaveQueue")
            end

            if lobbyState then
                DuelRemote:FireServer("LeaveLobby")
            end
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

        if pendingInvite and pendingInvite.From == player then
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
        elseif action == "MatchFound" then
            SetQueueNote("Match found! Joining the duel...")
        elseif action == "TeleportFailed" then
            SetQueueNote("Couldn't join the duel. Queue again to retry.")
        elseif action == "Requeued" then
            SetQueueNote("Your rival didn't arrive, so you're back in the queue.")
        elseif action == "Challenged" then
            ShowInvite({Kind = "Challenge", From = ...})
        elseif action == "ChallengeDeclined" then
            SetNote(..., "Declined")
        elseif action == "LobbyState" then
            OnLobbyState(...)
        elseif action == "LobbyInvited" then
            local host, position = ...
            ShowInvite({Kind = "Lobby", From = host, Position = position})
        elseif action == "LobbyDeclined" then
            SetNote(..., "Declined")
        elseif action == "DuelStarted" then
            OnDuelStarted()
        elseif action == "Result" then
            ShowResult(...)
        end
    end)

    BoardRemote.OnClientEvent:Connect(function(action, state)
        if action == "TurnState" then
            OnTurnState(state)
        elseif action == "TeammateLeft" then
            teammatePanel.Visible = true
        elseif action == "SurrenderVote" then
            surrenderButton.Label.Text = "Teammate wants to surrender"
        end
    end)

    ShowView("Hub")
    UpdateQueue()
end

return MultiplayerController
