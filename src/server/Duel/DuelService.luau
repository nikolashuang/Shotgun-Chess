local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local ProgressionConfig = require(ReplicatedStorage.Shared.Player.ProgressionConfig)
local DuelConfig = require(ReplicatedStorage.Shared.Duel.DuelConfig)
local ShotgunConfig = require(ReplicatedStorage.Shared.Combat.ShotgunConfig)
local ClassConfig = require(ReplicatedStorage.Shared.Combat.ClassConfig)
local AIConfig = require(ServerScriptService.AI.AIConfig)
local MatchClass = require(ServerScriptService.Match.MatchClass)
local ProfileService = require(ServerScriptService.Player.ProfileService)
local LoadoutService = require(ServerScriptService.Player.LoadoutService)

local DuelRemote = ReplicatedStorage.Remotes.DuelRemote

-- Pairs players for PvP through the quick-match queue or direct challenges, and pays out results
-- Combat itself is handled by MatchClass, which reports back through OnEnd
local DuelService = {}

local queue = {}
-- challenges[target][challenger] = time() the challenge was sent
local challenges = {}
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
    local index = table.find(queue, player)
    if not index then return end

    table.remove(queue, index)
    DuelRemote:FireClient(player, "QueueState", false)
end

local function PayOut(player, reward)
    ProfileService.AddGold(player, reward.Gold)
    ProfileService.AddExp(player, reward.Exp)
    ProfileService.Sync(player)
end

-- Forfeiting pays nothing to the player who left
local function GetReward(isWinner, reason)
    if isWinner then return DuelConfig.WIN_REWARD end
    if reason == "Forfeit" then return nil end

    return DuelConfig.LOSS_REWARD
end

local function StartDuel(first, second)
    RemoveFromQueue(first)
    RemoveFromQueue(second)
    challenges[first] = nil
    challenges[second] = nil

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
            local reward = GetReward(isWinner, reason)

            if reward then
                PayOut(player, reward)
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

-- Pairs the two longest waiting players, dropping anyone who stopped being available
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

local function TryPair()
    for i = #queue, 1, -1 do
        if not IsAvailable(queue[i]) then
            RemoveFromQueue(queue[i])
        end
    end

    if #queue < 2 then return end

    StartDuel(queue[1], queue[2])
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

    DuelRemote.OnServerEvent:Connect(function(player, action, first, second, third)
        if action == "Queue" then
            if not IsAvailable(player) then return end
            if table.find(queue, player) then return end

            table.insert(queue, player)
            DuelRemote:FireClient(player, "QueueState", true)
            TryPair()
        elseif action == "LeaveQueue" then
            RemoveFromQueue(player)
        elseif action == "Challenge" then
            Challenge(player, first)
        elseif action == "Respond" then
            Respond(player, first, second)
        elseif action == "Practice" then
            StartPractice(player, first, second, third)
        end
    end)

    Players.PlayerRemoving:Connect(function(player)
        RemoveFromQueue(player)
        challenges[player] = nil
    end)
end

return DuelService
