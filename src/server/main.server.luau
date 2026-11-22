local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ProfileService = require(ServerScriptService.Player.ProfileService)
local LoadoutService = require(ServerScriptService.Player.LoadoutService)
local CampaignService = require(ServerScriptService.Campaign.CampaignService)
local DuelService = require(ServerScriptService.Duel.DuelService)
local DuelPlaceService = require(ServerScriptService.Duel.DuelPlaceService)
local DuelConfig = require(ReplicatedStorage.Shared.Duel.DuelConfig)
local DevService = require(ServerScriptService.Player.DevService)
local PurchaseService = require(ServerScriptService.Player.PurchaseService)
local MirrorRules = require(ServerScriptService.Match.MirrorRules)

local BoardRemote = ReplicatedStorage.Remotes.BoardRemote

-- Both duel players point at the same match
local Matches = {}

local function LeaveMatch(player)
    if Matches[player] then
        Matches[player]:Leave(player)
    end

    Matches[player] = nil
    player:SetAttribute("InMatch", nil)
end

local function StartMatch(player, match)
    LeaveMatch(player)

    Matches[player] = match
    player:SetAttribute("InMatch", true)
end

-- The duel place shares this code but only runs the global duel it was reserved for
local isDuelPlace = game.PlaceId == DuelConfig.DUEL_PLACE_ID

ProfileService.Init()
LoadoutService.Init()
-- Both places take receipts, since Roblox retries an unfinished purchase wherever the player joins next
PurchaseService.Init()

if isDuelPlace then
    DuelPlaceService.Init(StartMatch)
else
    CampaignService.Init()
    DuelService.Init(StartMatch)
    DevService.Init()
end

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
        if isDuelPlace or first ~= "Campaign" then return end

        local match = CampaignService.CreateMatch(player, second, third)
        if not match then return end

        StartMatch(player, match)
        match:Start()
        return
    elseif action == "LeaveMatch" then
        LeaveMatch(player)
        return
    end

    local match = Matches[player]
    if not match then return end

    local side = match:GetSide(player)
    if not side then return end

    -- The Black player sees the board turned around, so their input is turned back
    local isMirrored = side.Team == "Black"

    if action == "Move" then
        if not IsTileArgument(first, second) then return end

        if isMirrored then
            first, second = MirrorRules.Tile(first), MirrorRules.Tile(second)
        end

        match:Move(side, first, second)
    elseif action == "Fire" then
        if not IsFiniteNumber(first) or not IsFiniteNumber(second) then return end
        if third ~= "Normal" and third ~= "Alt" then return end

        if isMirrored then
            first, second = MirrorRules.Point(first), MirrorRules.Point(second)
        end

        match:Fire(side, first, second, third)
    elseif action == "Reload" then
        match:Reload(side)
    elseif action == "Special" then
        if typeof(first) ~= "table" then return end

        match:Special(side, isMirrored and MirrorRules.Table(first) or first)
    elseif action == "Ultimate" then
        if typeof(first) ~= "table" then return end

        match:Ultimate(side, isMirrored and MirrorRules.Table(first) or first)
    elseif action == "Summon" then
        if typeof(first) ~= "string" then return end
        if not IsTileArgument(second, third) then return end

        if isMirrored then
            second, third = MirrorRules.Tile(second), MirrorRules.Tile(third)
        end

        match:Summon(side, first, second, third)
    elseif action == "Command" then
        if not IsFiniteNumber(first) then return end
        if not IsTileArgument(second, third) then return end

        if isMirrored then
            second, third = MirrorRules.Tile(second), MirrorRules.Tile(third)
        end

        match:Command(side, first, second, third)
    elseif action == "EndTurn" then
        match:EndTurn(side)
    elseif action == "Surrender" then
        match:Surrender(side)
    end
end)

Players.PlayerRemoving:Connect(LeaveMatch)
