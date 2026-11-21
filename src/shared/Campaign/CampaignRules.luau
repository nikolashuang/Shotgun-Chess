local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)
local PieceConfig = require(ReplicatedStorage.Shared.Board.PieceConfig)
local CampaignConfig = require(script.Parent.CampaignConfig)
local CampaignMap = require(script.Parent.CampaignMap)

local EncounterConfig = CampaignConfig.Encounter
local TreasureConfig = CampaignConfig.Treasure

-- Cleared is the profile's set of cleared node keys ("Region.Node"); a region is complete once its King key is set
-- A run is one attempt at a region: the route walked so far (Path), the King's health and upgrades, and the pouch
local CampaignRules = {}

function CampaignRules.GetNodeKey(regionId, nodeId)
    return regionId .. "." .. nodeId
end

function CampaignRules.GetNode(regionId, nodeId)
    local region = CampaignConfig.Regions[regionId]
    if not region then return nil end

    return region.Nodes[nodeId]
end

function CampaignRules.IsCleared(cleared, regionId, nodeId)
    return cleared[CampaignRules.GetNodeKey(regionId, nodeId)] == true
end

function CampaignRules.IsRegionComplete(cleared, regionId)
    local region = CampaignConfig.Regions[regionId]

    return CampaignRules.IsCleared(cleared, regionId, region.Final)
end

function CampaignRules.IsRegionUnlocked(cleared, regionId)
    local region = CampaignConfig.Regions[regionId]
    if not region then return false end

    for _, required in ipairs(region.Requires) do
        if not CampaignRules.IsRegionComplete(cleared, required) then return false end
    end

    return true
end

--RUNS--

function CampaignRules.NewRun()
    return {
        Path = {},
        Health = PieceConfig.Health.King,
        MaxHealth = PieceConfig.Health.King,
        DamageBonus = 0,

        -- The pouch, paid out when the region's King falls
        Gold = 0,
        Exp = 0,

        -- Copy of the run from just before its last Rest Site, restored on death
        Checkpoint = nil,
        -- The Treasure Hunt being dug: {Node, Column, Row, Digs = {{Column, Row}}}
        Treasure = nil,
    }
end

-- The run without its checkpoint or treasure dig
function CampaignRules.CopyRun(run)
    return {
        Path = table.clone(run.Path),
        Health = run.Health,
        MaxHealth = run.MaxHealth,
        DamageBonus = run.DamageBonus,
        Gold = run.Gold,
        Exp = run.Exp,
    }
end

-- Back to the last Rest Site, or nil when there isn't one and the region starts over
function CampaignRules.Rewind(run)
    if not run or not run.Checkpoint then return nil end

    local rewound = CampaignRules.CopyRun(run.Checkpoint)
    rewound.Checkpoint = CampaignRules.CopyRun(run.Checkpoint)

    return rewound
end

-- What the client may see of the runs; the treasure's tile stays on the server
function CampaignRules.GetClientRuns(runs)
    local shown = {}

    for regionId, run in pairs(runs) do
        local copy = CampaignRules.CopyRun(run)
        copy.HasCheckpoint = run.Checkpoint ~= nil

        if run.Treasure then
            copy.Treasure = {Node = run.Treasure.Node, Digs = run.Treasure.Digs}
        end

        shown[regionId] = copy
    end

    return shown
end

-- "Cleared", "Available" or "Locked"; routes only go forward from the last node the run cleared
-- With no run (or an empty one) only the start node is open
function CampaignRules.GetNodeState(run, regionId, nodeId)
    local region = CampaignConfig.Regions[regionId]
    if not region or not region.Nodes[nodeId] then return "Locked" end

    if not run or #run.Path == 0 then
        return nodeId == region.Start and "Available" or "Locked"
    end

    if table.find(run.Path, nodeId) then return "Cleared" end

    local current = region.Nodes[run.Path[#run.Path]]
    if table.find(current.Links, nodeId) then return "Available" end

    return "Locked"
end

-- Battle nodes are fought on the board, the rest resolve on the map
function CampaignRules.IsBattle(node)
    return node.Type == "Combat" or node.Type == "Queen" or node.Type == "King"
end

-- Gold and Exp the node adds to the pouch
function CampaignRules.GetReward(regionId, nodeId)
    local region = CampaignConfig.Regions[regionId]
    local node = region.Nodes[nodeId]
    local reward = node.Reward or CampaignConfig.Rewards[node.Type]
    local scale = node.Reward and 1 or region.RewardScale

    return math.floor(reward.Gold * scale), math.floor(reward.Exp * scale)
end

-- What the pouch pays when the region is completed; replays of a completed region pay less
function CampaignRules.GetPayout(run, isReplay)
    local scale = isReplay and CampaignConfig.REPLAY_REWARD_SCALE or 1

    return math.floor(run.Gold * scale), math.floor(run.Exp * scale)
end

--ENCOUNTERS--

-- Point budget for a battle node, following the region's curve
function CampaignRules.GetPoints(regionId, nodeId)
    local region = CampaignConfig.Regions[regionId]
    local node = region.Nodes[nodeId]
    local lastFight = region.StartPoints + (CampaignMap.FIGHTS - 1) * EncounterConfig.POINTS_PER_FIGHT

    if node.Type == "Queen" then return lastFight + EncounterConfig.QUEEN_BONUS end
    if node.Type == "King" then return lastFight + EncounterConfig.QUEEN_BONUS + EncounterConfig.KING_BONUS end

    return region.StartPoints + (node.Fight - 1) * EncounterConfig.POINTS_PER_FIGHT
end

--TREASURE--

-- Tiles a dig centered on column, row uncovers, clipped to the board
function CampaignRules.GetDigTiles(column, row)
    local reach = math.floor(TreasureConfig.DIG_SIZE / 2)
    local tiles = {}

    for x = math.max(column - reach, 1), math.min(column + reach, BoardConfig.SIZE) do
        for y = math.max(row - reach, 1), math.min(row + reach, BoardConfig.SIZE) do
            table.insert(tiles, {x, y})
        end
    end

    return tiles
end

function CampaignRules.IsDigHit(column, row, treasureColumn, treasureRow)
    local reach = math.floor(TreasureConfig.DIG_SIZE / 2)

    return math.abs(column - treasureColumn) <= reach and math.abs(row - treasureRow) <= reach
end

-- digNumber is the dig that found it, nil if it was never found
function CampaignRules.GetTreasureGold(digNumber)
    if not digNumber then return TreasureConfig.CONSOLATION end

    return TreasureConfig.Rewards[digNumber] or TreasureConfig.CONSOLATION
end

--VALIDATION--

local function Check(condition, message)
    if condition then return end

    error("[CampaignConfig] " .. message, 2)
end

-- Errors on data that would break progression, including a King that can be reached without its Queen
function CampaignRules.Validate()
    Check(#TreasureConfig.Rewards >= TreasureConfig.DIGS, "Treasure needs a reward for every dig")

    for _, regionId in ipairs(CampaignConfig.ORDER) do
        local region = CampaignConfig.Regions[regionId]
        Check(region, regionId .. " is in ORDER but has no region data")
        Check(region.StartPoints, regionId .. " has no StartPoints")
        Check(region.Nodes[region.Start], regionId .. " start node is missing")
        Check(region.Nodes[region.Final], regionId .. " final node is missing")

        for _, required in ipairs(region.Requires) do
            Check(CampaignConfig.Regions[required], regionId .. " requires unknown region " .. required)
        end

        for nodeId, node in pairs(region.Nodes) do
            Check(CampaignConfig.Rewards[node.Type], regionId .. "." .. nodeId .. " has unknown type " .. tostring(node.Type))
            Check(node.Type ~= "Combat" or node.Fight, regionId .. "." .. nodeId .. " is a battle with no Fight number")

            for _, link in ipairs(node.Links) do
                Check(region.Nodes[link], regionId .. "." .. nodeId .. " links to missing node " .. link)
            end
        end

        Check(region.Nodes[region.Final].Type == "King", regionId .. " final node must be a King")

        local parents = {}

        for nodeId, node in pairs(region.Nodes) do
            if table.find(node.Links, region.Final) then
                table.insert(parents, nodeId)
            end
        end

        Check(#parents == 1, regionId .. " King must have exactly one node leading to it")
        Check(region.Nodes[parents[1]].Type == "Queen", regionId .. " node before the King must be a Queen")

        -- Every node has to be reachable from the start node
        local reached = {[region.Start] = true}
        local queue = {region.Start}

        while #queue > 0 do
            local nodeId = table.remove(queue, 1)

            for _, link in ipairs(region.Nodes[nodeId].Links) do
                if not reached[link] then
                    reached[link] = true
                    table.insert(queue, link)
                end
            end
        end

        for nodeId in pairs(region.Nodes) do
            Check(reached[nodeId], regionId .. "." .. nodeId .. " can't be reached from the start node")
        end
    end
end

return CampaignRules
