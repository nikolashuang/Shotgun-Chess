local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local ProgressionConfig = require(ReplicatedStorage.Shared.Player.ProgressionConfig)
local DuelConfig = require(ReplicatedStorage.Shared.Duel.DuelConfig)
local ShotgunConfig = require(ReplicatedStorage.Shared.Combat.ShotgunConfig)
local ClassConfig = require(ReplicatedStorage.Shared.Combat.ClassConfig)
local AIConfig = require(ServerScriptService.AI.AIConfig)
local MatchClass = require(ServerScriptService.Match.MatchClass)
local LoadoutService = require(ServerScriptService.Player.LoadoutService)
local GlobalQueueService = require(script.Parent.GlobalQueueService)
local DuelRewards = require(script.Parent.DuelRewards)

local DuelRemote = ReplicatedStorage.Remotes.DuelRemote

-- Pairs players for PvP through the global queue (GlobalQueueService) or direct challenges, and pays out results
-- Combat itself is handled by MatchClass, which reports back through OnEnd
local DuelService = {}

-- challenges[target][challenger] = time() the challenge was sent
local challenges = {}
-- 2v2 lobbies keyed by host: {Host, Teammate, Rival1, Rival2}
local lobbies = {}
-- Player -> the lobby they are in, hosting or invited into
local lobbyOf = {}
-- lobbyInvites[target] = {Host, Position, Time}
local lobbyInvites = {}
local random = Random.new()

-- Set by main to register each player's match
local onMatchCreated = nil

local function IsUnlocked(player)
    return (player:GetAttribute("Level") or ProgressionConfig.START_LEVEL) >= ProgressionConfig.DUELS_UNLOCK_LEVEL
end

-- Only unlocked players still in the server and not already in a match can be paired
local function IsAvailable(player)
    if not player.Parent then return false end
    if not IsUnlocked(player) then return false end
    if player:GetAttribute("InMatch") then return false end

    return true
end

local function RemoveFromQueue(player)
    GlobalQueueService.Leave(player)
end

--LOBBIES--

local function GetLobbyMembers(lobby)
    local members = {lobby.Host}

    for _, position in ipairs(DuelConfig.LOBBY_POSITIONS) do
        if lobby[position] then
            table.insert(members, lobby[position])
        end
    end

    return members
end

local function SendLobby(lobby)
    local state = {Host = lobby.Host}

    for _, position in ipairs(DuelConfig.LOBBY_POSITIONS) do
        state[position] = lobby[position]
    end

    for _, member in ipairs(GetLobbyMembers(lobby)) do
        DuelRemote:FireClient(member, "LobbyState", state)
    end
end

-- The host leaving closes the lobby; anyone else just frees their position
local function LeaveLobby(player)
    lobbyInvites[player] = nil

    local lobby = lobbyOf[player]
    if not lobby then return end

    lobbyOf[player] = nil

    if lobby.Host == player then
        lobbies[player] = nil

        for _, member in ipairs(GetLobbyMembers(lobby)) do
            if member == player then continue end

            lobbyOf[member] = nil
            DuelRemote:FireClient(member, "LobbyState", nil)
        end

        DuelRemote:FireClient(player, "LobbyState", nil)
        return
    end

    for _, position in ipairs(DuelConfig.LOBBY_POSITIONS) do
        if lobby[position] == player then
            lobby[position] = nil
        end
    end

    DuelRemote:FireClient(player, "LobbyState", nil)
    SendLobby(lobby)
end

local function CreateLobby(player)
    if not IsAvailable(player) then return end
    if lobbyOf[player] then return end

    RemoveFromQueue(player)

    local lobby = {Host = player}
    lobbies[player] = lobby
    lobbyOf[player] = lobby

    SendLobby(lobby)
end

local function InviteToLobby(player, target, position)
    local lobby = lobbies[player]
    if not lobby then return end
    if not table.find(DuelConfig.LOBBY_POSITIONS, position) then return end
    if lobby[position] then return end
    if typeof(target) ~= "Instance" or not target:IsA("Player") then return end
    if target == player or lobbyOf[target] then return end
    if not IsAvailable(target) then return end

    lobbyInvites[target] = {Host = player, Position = position, Time = time()}
    DuelRemote:FireClient(target, "LobbyInvited", player, position)
end

local function StartTeamDuel(lobby)
    local members = GetLobbyMembers(lobby)

    for _, member in ipairs(members) do
        if not IsAvailable(member) then return end
    end

    lobbies[lobby.Host] = nil

    for _, member in ipairs(members) do
        lobbyOf[member] = nil
        lobbyInvites[member] = nil
        challenges[member] = nil
        RemoveFromQueue(member)
    end

    local function GetEntry(player)
        local shotgun, className = LoadoutService.GetLoadout(player)
        return {Player = player, Shotgun = shotgun, Class = className}
    end

    -- Coin flip for which team plays White and moves first
    local hosts = {GetEntry(lobby.Host), GetEntry(lobby.Teammate)}
    local rivals = {GetEntry(lobby.Rival1), GetEntry(lobby.Rival2)}
    local whites, blacks = hosts, rivals
    if random:NextNumber() < 0.5 then
        whites, blacks = rivals, hosts
    end

    local match = MatchClass.newTeamDuel(whites, blacks)

    match.OnEnd = function(winner, reason)
        for _, side in pairs(match.Sides) do
            local player = side.Player
            if not player.Parent or side.isDisconnected then continue end

            local isWinner = side.Team == winner.Team
            local reward = DuelRewards.GetTeam(match, side, isWinner, reason)

            if reward then
                reward = DuelRewards.PayOut(player, reward)
            end

            DuelRemote:FireClient(player, "Result", {
                Victory = isWinner,
                Reason = reason,
                Gold = reward and reward.Gold or 0,
                Exp = reward and reward.Exp or 0,
            })
        end
    end

    for _, member in ipairs(members) do
        onMatchCreated(member, match)
        DuelRemote:FireClient(member, "DuelStarted", "2v2")
    end

    match:Start()
end

-- The duel starts as soon as every position is filled
local function RespondToLobby(player, host, isAccepted)
    local invite = lobbyInvites[player]
    if not invite or invite.Host ~= host then return end

    lobbyInvites[player] = nil

    local lobby = lobbies[host]
    if not lobby then return end
    if time() - invite.Time > DuelConfig.CHALLENGE_TIMEOUT then return end

    if isAccepted ~= true then
        DuelRemote:FireClient(host, "LobbyDeclined", player)
        return
    end

    if lobby[invite.Position] or lobbyOf[player] then return end
    if not IsAvailable(player) then return end

    RemoveFromQueue(player)
    lobby[invite.Position] = player
    lobbyOf[player] = lobby
    SendLobby(lobby)

    for _, position in ipairs(DuelConfig.LOBBY_POSITIONS) do
        if not lobby[position] then return end
    end

    StartTeamDuel(lobby)
end

--DUELS--

local function StartDuel(first, second)
    RemoveFromQueue(first)
    RemoveFromQueue(second)
    challenges[first] = nil
    challenges[second] = nil
    LeaveLobby(first)
    LeaveLobby(second)

    -- Coin flip for who plays White and moves first
    local white, black = first, second
    if random:NextNumber() < 0.5 then
        white, black = second, first
    end

    local whiteShotgun, whiteClass = LoadoutService.GetLoadout(white)
    local blackShotgun, blackClass = LoadoutService.GetLoadout(black)
    local match = MatchClass.newDuel(white, whiteShotgun, whiteClass, black, blackShotgun, blackClass)

    match.OnEnd = function(winner, reason)
        for _, player in ipairs({white, black}) do
            if not player.Parent then continue end

            local isWinner = winner.Player == player
            local reward = DuelRewards.Get(isWinner, reason)

            if reward then
                reward = DuelRewards.PayOut(player, reward)
            end

            DuelRemote:FireClient(player, "Result", {
                Victory = isWinner,
                Reason = reason,
                Gold = reward and reward.Gold or 0,
                Exp = reward and reward.Exp or 0,
            })
        end
    end

    onMatchCreated(white, match)
    onMatchCreated(black, match)

    DuelRemote:FireClient(white, "DuelStarted", black.Name)
    DuelRemote:FireClient(black, "DuelStarted", white.Name)

    match:Start()
end

-- Practice is a duel against PracticeAIService at the picked rating and loadout; it pays nothing
-- It's a Singleplayer mode, so it doesn't need the Multiplayer level
-- className "None" (or nil) gives the AI king no class
local function StartPractice(player, rating, shotgunName, className)
    if not player.Parent or player:GetAttribute("InMatch") then return end
    if typeof(rating) ~= "number" or not AIConfig.Ratings[rating] then return end
    if typeof(shotgunName) ~= "string" or not ShotgunConfig.Shotguns[shotgunName] then return end
    if className == "None" then
        className = nil
    end
    if className ~= nil and (typeof(className) ~= "string" or not ClassConfig.Classes[className]) then return end

    RemoveFromQueue(player)
    challenges[player] = nil

    local playerShotgun, playerClass = LoadoutService.GetLoadout(player)
    local match = nil
    local aiSide = nil

    -- Coin flip for who plays White and moves first
    if random:NextNumber() < 0.5 then
        match = MatchClass.newDuel(player, playerShotgun, playerClass, nil, shotgunName, className)
        aiSide = match.Sides.Black
    else
        match = MatchClass.newDuel(nil, shotgunName, className, player, playerShotgun, playerClass)
        aiSide = match.Sides.White
    end

    aiSide.AIRating = rating

    match.OnEnd = function(winner, reason)
        if not player.Parent then return end

        DuelRemote:FireClient(player, "Result", {
            Victory = winner.Player == player,
            Reason = reason,
            Practice = true,
            Gold = 0,
            Exp = 0,
        })
    end

    onMatchCreated(player, match)
    DuelRemote:FireClient(player, "DuelStarted", "Practice AI")
    match:Start()
end

local function Challenge(player, target)
    if typeof(target) ~= "Instance" or not target:IsA("Player") then return end
    if target == player then return end
    if not IsAvailable(player) or not IsAvailable(target) then return end

    challenges[target] = challenges[target] or {}
    challenges[target][player] = time()

    DuelRemote:FireClient(target, "Challenged", player)
end

local function Respond(player, challenger, isAccepted)
    if typeof(challenger) ~= "Instance" or not challenger:IsA("Player") then return end

    local sent = challenges[player] and challenges[player][challenger]
    if not sent then return end

    challenges[player][challenger] = nil

    if time() - sent > DuelConfig.CHALLENGE_TIMEOUT then return end

    if isAccepted ~= true then
        DuelRemote:FireClient(challenger, "ChallengeDeclined", player)
        return
    end

    if not IsAvailable(player) or not IsAvailable(challenger) then return end

    StartDuel(challenger, player)
end

local init = false
function DuelService.Init(matchCreatedCallback)
    if init then return end
    init = true

    onMatchCreated = matchCreatedCallback
    GlobalQueueService.Init()

    DuelRemote.OnServerEvent:Connect(function(player, action, first, second, third)
        if action == "Queue" then
            if not IsAvailable(player) then return end

            GlobalQueueService.Join(player)
        elseif action == "LeaveQueue" then
            RemoveFromQueue(player)
        elseif action == "Challenge" then
            Challenge(player, first)
        elseif action == "Respond" then
            Respond(player, first, second)
        elseif action == "Practice" then
            StartPractice(player, first, second, third)
        elseif action == "CreateLobby" then
            CreateLobby(player)
        elseif action == "LobbyInvite" then
            InviteToLobby(player, first, second)
        elseif action == "LobbyRespond" then
            RespondToLobby(player, first, second)
        elseif action == "LeaveLobby" then
            LeaveLobby(player)
        end
    end)

    Players.PlayerRemoving:Connect(function(player)
        challenges[player] = nil
        LeaveLobby(player)
    end)
end

return DuelService
