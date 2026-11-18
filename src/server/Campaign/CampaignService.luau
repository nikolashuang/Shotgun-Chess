local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)
local CampaignConfig = require(ReplicatedStorage.Shared.Campaign.CampaignConfig)
local CampaignRules = require(ReplicatedStorage.Shared.Campaign.CampaignRules)
local MatchClass = require(ServerScriptService.Match.MatchClass)
local ProfileService = require(ServerScriptService.Player.ProfileService)
local LoadoutService = require(ServerScriptService.Player.LoadoutService)

local CampaignRemote = ReplicatedStorage.Remotes.CampaignRemote

-- Campaign progression only: which nodes can be played and what clearing them gives
-- Combat itself is handled by MatchClass, which reports back through OnEnd
local CampaignService = {}

local function CanPlay(player, regionId, nodeId)
    if typeof(regionId) ~= "string" or typeof(nodeId) ~= "string" then return false end
    if not CampaignRules.GetNode(regionId, nodeId) then return false end

    local profile = ProfileService.Get(player)
    if not profile then return false end

    return CampaignRules.GetNodeState(profile.Data.Nodes, regionId, nodeId) ~= "Locked"
end

-- Marks the node cleared and pays out; first clears pay in full, replays pay the reduced reward
function CampaignService.CompleteNode(player, regionId, nodeId)
    local profile = ProfileService.Get(player)
    if not profile then return nil end

    local data = profile.Data
    local region = CampaignConfig.Regions[regionId]
    local node = region.Nodes[nodeId]
    local isFirstClear = not CampaignRules.IsCleared(data.Nodes, regionId, nodeId)
    local gold, exp = CampaignRules.GetReward(regionId, nodeId, isFirstClear)

    data.Nodes[CampaignRules.GetNodeKey(regionId, nodeId)] = true
    ProfileService.AddGold(player, gold)
    ProfileService.AddExp(player, exp)

    local unlockedClass = nil

    if node.Type == "King" and region.Class then
        if not data.Classes[region.Class] then
            unlockedClass = region.Class
        end

        data.Classes[region.Class] = true
    end

    ProfileService.Sync(player)

    return {
        Victory = true,
        Region = regionId,
        Node = nodeId,
        Type = node.Type,
        Gold = gold,
        Exp = exp,
        FirstClear = isFirstClear,
        Class = unlockedClass,
        RegionComplete = isFirstClear and nodeId == region.Final,
    }
end

-- Shifts the whole formation up the board without letting its back piece go off the edge
local function PlaceArmy(army)
    local frontRow = math.huge
    local backRow = 0

    for _, enemy in ipairs(army) do
        frontRow = math.min(frontRow, enemy.Row)
        backRow = math.max(backRow, enemy.Row)
    end

    local offset = math.clamp(CampaignConfig.ARMY_FRONT_ROW - frontRow, 0, BoardConfig.SIZE - backRow)
    local placed = {}

    for _, enemy in ipairs(army) do
        table.insert(placed, {Type = enemy.Type, Column = enemy.Column, Row = enemy.Row + offset})
    end

    return placed
end

function CampaignService.CreateMatch(player, regionId, nodeId)
    if not CanPlay(player, regionId, nodeId) then return nil end

    local node = CampaignRules.GetNode(regionId, nodeId)
    if not CampaignRules.IsBattle(node) then return nil end

    local shotgun, class = LoadoutService.GetLoadout(player)
    local match = MatchClass.new(player, shotgun, class, PlaceArmy(CampaignConfig.Armies[node.Army]), CampaignConfig.AI_RATING)

    match.OnEnd = function(result)
        local summary = {Victory = false, Region = regionId, Node = nodeId}

        if result == "Victory" then
            summary = CampaignService.CompleteNode(player, regionId, nodeId)
        end

        CampaignRemote:FireClient(player, "Result", summary)
    end

    return match
end

local init = false
function CampaignService.Init()
    if init then return end
    init = true

    CampaignRules.Validate()

    -- Rest and Treasure nodes clear as soon as they're entered
    -- Rest sites have nothing to restore until health carries between battles
    CampaignRemote.OnServerEvent:Connect(function(player, action, regionId, nodeId)
        if action ~= "ResolveNode" then return end
        if not CanPlay(player, regionId, nodeId) then return end
        if CampaignRules.IsBattle(CampaignRules.GetNode(regionId, nodeId)) then return end

        -- Only battles can be replayed, so treasure can't be farmed
        local profile = ProfileService.Get(player)
        if CampaignRules.IsCleared(profile.Data.Nodes, regionId, nodeId) then return end

        CampaignRemote:FireClient(player, "Result", CampaignService.CompleteNode(player, regionId, nodeId))
    end)
end

return CampaignService
