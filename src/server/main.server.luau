local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ProgressionConfig = require(ReplicatedStorage.Shared.Player.ProgressionConfig)
local MatchClass = require(ServerScriptService.Match.MatchClass)
local ProfileService = require(ServerScriptService.Player.ProfileService)
local LoadoutService = require(ServerScriptService.Player.LoadoutService)
local CampaignService = require(ServerScriptService.Campaign.CampaignService)
local DevService = require(ServerScriptService.Player.DevService)

local BoardRemote = ReplicatedStorage.Remotes.BoardRemote

local Matches = {}

ProfileService.Init()
LoadoutService.Init()
CampaignService.Init()
DevService.Init()

local function IsFiniteNumber(value)
    return typeof(value) == "number" and value == value and math.abs(value) < 1e6
end

local function IsTileArgument(column, row)
    if not IsFiniteNumber(column) or not IsFiniteNumber(row) then return false end
    if column % 1 ~= 0 or row % 1 ~= 0 then return false end

    return true
end

BoardRemote.OnServerEvent:Connect(function(player, action, first, second, third)
    if action == "StartMatch" then
        local match = nil

        if first == "Campaign" then
            match = CampaignService.CreateMatch(player, second, third)
        elseif first == "Duel" then
            if (player:GetAttribute("Level") or ProgressionConfig.START_LEVEL) < ProgressionConfig.DUELS_UNLOCK_LEVEL then return end

            match = MatchClass.new(player, LoadoutService.GetLoadout(player))
        end

        if not match then return end

        if Matches[player] then
            Matches[player]:Destroy()
        end

        Matches[player] = match
        match:Start()
        return
    elseif action == "LeaveMatch" then
        if Matches[player] then
            Matches[player]:Destroy()
        end

        Matches[player] = nil
        return
    end

    local match = Matches[player]
    if not match then return end

    if action == "Move" then
        if not IsTileArgument(first, second) then return end

        match:Move(first, second)
    elseif action == "Fire" then
        if not IsFiniteNumber(first) or not IsFiniteNumber(second) then return end
        if third ~= "Normal" and third ~= "Alt" then return end

        match:Fire(first, second, third)
    elseif action == "Reload" then
        match:Reload()
    elseif action == "Summon" then
        if typeof(first) ~= "string" then return end
        if not IsTileArgument(second, third) then return end

        match:Summon(first, second, third)
    elseif action == "Command" then
        if not IsFiniteNumber(first) then return end
        if not IsTileArgument(second, third) then return end

        match:Command(first, second, third)
    elseif action == "EndTurn" then
        match:EndTurn()
    end
end)

Players.PlayerRemoving:Connect(function(player)
    if Matches[player] then
        Matches[player]:Destroy()
    end

    Matches[player] = nil
end)
