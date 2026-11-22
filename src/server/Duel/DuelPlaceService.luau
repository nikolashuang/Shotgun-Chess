local MemoryStoreService = game:GetService("MemoryStoreService")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local DuelConfig = require(ReplicatedStorage.Shared.Duel.DuelConfig)
local MatchClass = require(ServerScriptService.Match.MatchClass)
local ProfileService = require(ServerScriptService.Player.ProfileService)
local LoadoutService = require(ServerScriptService.Player.LoadoutService)
local DuelRewards = require(script.Parent.DuelRewards)

local DuelRemote = ReplicatedStorage.Remotes.DuelRemote

local matchStore = MemoryStoreService:GetHashMap("DuelMatches")
local requeueStore = MemoryStoreService:GetHashMap("DuelRequeue")

-- Studio has no reserved servers, so a Studio test pairs the first player with the Practice AI
local STUDIO_AI_RATING = 1000

-- Runs the one global duel this reserved server of the duel place was made for:
-- waits for every matched player to load in, counts down, plays the match and sends everyone back to the main game
local DuelPlaceService = {}

-- UserId -> true once that player's client has the board up
local ready = {}
-- Player -> how many times their teleport back has failed
local returnFailures = {}
local isOver = false
local onMatchCreated = nil

local RETURN_ATTEMPTS = 3

local function Retry(callback)
    for attempt = 1, 3 do
        local ok, result = pcall(callback)
        if ok then return true, result end

        warn("[DuelPlaceService] " .. tostring(result))
        task.wait(attempt)
    end

    return false, nil
end

local function ReportReturnFailed(player, reason)
    ProfileService.CancelTeleport(player)

    if player.Parent then
        DuelRemote:FireClient(player, "ReturnFailed", tostring(reason))
    end
end

-- Saves first so the main game loads the rewards just paid out
-- Each player goes on their own so one failed teleport can't hold back the other
local function SendBack(players)
    for _, player in ipairs(players) do
        if not player.Parent then continue end

        task.spawn(function()
            ProfileService.SaveForTeleport(player)

            -- A single-player teleport can otherwise try to route back into a private server
            local options = Instance.new("TeleportOptions")
            options.ForcePublicServer = true

            local ok, result = pcall(function()
                TeleportService:TeleportAsync(DuelConfig.MAIN_PLACE_ID, {player}, options)
            end)

            if not ok then
                warn("[DuelPlaceService] Teleport back failed for " .. player.Name .. ": " .. tostring(result))
                ReportReturnFailed(player, result)
            end
        end)
    end
end

-- Teleports can also fail after they start; retry a few times, then leave it to the Return to Lobby button
local function OnTeleportFailed(player, result, errorMessage)
    warn("[DuelPlaceService] Teleport back failed for " .. player.Name .. ": " .. tostring(result) .. " " .. tostring(errorMessage))

    returnFailures[player] = (returnFailures[player] or 0) + 1

    if returnFailures[player] < RETURN_ATTEMPTS then
        task.wait(returnFailures[player] * 2)
        SendBack({player})
        return
    end

    ReportReturnFailed(player, tostring(result) .. ": " .. tostring(errorMessage))
end

-- Profiles load as players arrive; the match needs their loadouts
local function WaitForProfile(player)
    local started = os.clock()

    while player.Parent and not ProfileService.Get(player) and os.clock() - started < DuelConfig.ARRIVAL_TIMEOUT do
        task.wait(0.2)
    end

    return ProfileService.Get(player) ~= nil
end

local function GetMatchInfo()
    if RunService:IsStudio() then
        local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
        return {Mode = "1v1", Players = {player.UserId}, isStudio = true}
    end

    local ok, info = Retry(function()
        return matchStore:GetAsync(game.PrivateServerId)
    end)

    return ok and info or nil
end

local function WaitForPlayers(userIds)
    local started = os.clock()

    while os.clock() - started < DuelConfig.ARRIVAL_TIMEOUT do
        local isEveryoneReady = true

        for _, userId in ipairs(userIds) do
            if not ready[userId] then
                isEveryoneReady = false
            end
        end

        if isEveryoneReady then return true end

        task.wait(0.25)
    end

    return false
end

-- A rival who never arrived cancels the duel; everyone who did goes back and straight into the queue
local function CancelForNoShow()
    local arrived = Players:GetPlayers()
    isOver = true

    for _, player in ipairs(arrived) do
        pcall(function()
            requeueStore:SetAsync(tostring(player.UserId), true, DuelConfig.ASSIGNMENT_TIME)
        end)

        DuelRemote:FireClient(player, "RivalMissing")
    end

    task.wait(2)
    SendBack(arrived)
end

local function GetEntry(player)
    local shotgun, className = LoadoutService.GetLoadout(player)

    return {Player = player, Shotgun = shotgun, Class = className}
end

local function StartDuel(info)
    local players = {}

    for _, userId in ipairs(info.Players) do
        local player = Players:GetPlayerByUserId(userId)
        if not player or not WaitForProfile(player) then
            CancelForNoShow()
            return
        end

        table.insert(players, GetEntry(player))
    end

    -- A Studio test plays the Practice AI with the player's own loadout
    if info.isStudio then
        table.insert(players, {Shotgun = players[1].Shotgun, Class = players[1].Class})
    end

    -- Coin flip for who plays White and moves first
    local white, black = players[1], players[2]
    if math.random() < 0.5 then
        white, black = black, white
    end

    local match = MatchClass.newDuel(white.Player, white.Shotgun, white.Class, black.Player, black.Shotgun, black.Class)

    for _, side in pairs(match.Sides) do
        if not side.Player then
            side.AIRating = STUDIO_AI_RATING
        end
    end

    match.OnEnd = function(winner, reason)
        local inServer = {}

        for _, side in pairs(match.Sides) do
            local player = side.Player
            if not player or not player.Parent then continue end

            local isWinner = side.Team == winner.Team
            local reward = not info.isStudio and DuelRewards.Get(isWinner, reason) or nil

            if reward then
                DuelRewards.PayOut(player, reward)
            end

            DuelRemote:FireClient(player, "Result", {
                Victory = isWinner,
                Reason = reason,
                Gold = reward and reward.Gold or 0,
                Exp = reward and reward.Exp or 0,
                Returning = true,
            })

            table.insert(inServer, player)
        end

        isOver = true
        task.delay(DuelConfig.RETURN_DELAY, SendBack, inServer)
    end

    for _, entry in ipairs(players) do
        if entry.Player then
            onMatchCreated(entry.Player, match)
        end
    end

    match:Start(DuelConfig.COUNTDOWN)
end

local init = false
function DuelPlaceService.Init(matchCreatedCallback)
    if init then return end
    init = true

    onMatchCreated = matchCreatedCallback

    DuelRemote.OnServerEvent:Connect(function(player, action)
        if action == "Ready" then
            ready[player.UserId] = true
        elseif action == "Return" and isOver then
            returnFailures[player] = 0
            SendBack({player})
        end
    end)

    TeleportService.TeleportInitFailed:Connect(OnTeleportFailed)
    Players.PlayerRemoving:Connect(function(player)
        returnFailures[player] = nil
    end)

    task.spawn(function()
        local info = GetMatchInfo()

        -- Someone joined the duel place without a match (a public server); send them to the main game
        if not info then
            Players.PlayerAdded:Connect(function(player)
                SendBack({player})
            end)

            SendBack(Players:GetPlayers())
            return
        end

        -- Only the matched players belong here
        Players.PlayerAdded:Connect(function(player)
            if not table.find(info.Players, player.UserId) then
                SendBack({player})
            end
        end)

        if not WaitForPlayers(info.Players) then
            CancelForNoShow()
            return
        end

        StartDuel(info)
    end)
end

return DuelPlaceService
