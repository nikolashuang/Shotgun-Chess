local CampaignConfig = require(script.Parent.CampaignConfig)

-- Cleared is the profile's set of cleared node keys ("Region.Node")
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

-- A node opens once any node linking to it is cleared
function CampaignRules.IsNodeOpen(cleared, regionId, nodeId)
    local region = CampaignConfig.Regions[regionId]
    if not region or not region.Nodes[nodeId] then return false end
    if not CampaignRules.IsRegionUnlocked(cleared, regionId) then return false end
    if nodeId == region.Start then return true end

    for parentId, parent in pairs(region.Nodes) do
        if table.find(parent.Links, nodeId) and CampaignRules.IsCleared(cleared, regionId, parentId) then return true end
    end

    return false
end

-- "Cleared", "Available" or "Locked"
function CampaignRules.GetNodeState(cleared, regionId, nodeId)
    if CampaignRules.IsCleared(cleared, regionId, nodeId) then return "Cleared" end
    if CampaignRules.IsNodeOpen(cleared, regionId, nodeId) then return "Available" end

    return "Locked"
end

-- Battle nodes are fought on the board, the rest resolve straight from the map
function CampaignRules.IsBattle(node)
    return node.Type == "Combat" or node.Type == "Queen" or node.Type == "King"
end

function CampaignRules.GetReward(regionId, nodeId, isFirstClear)
    local region = CampaignConfig.Regions[regionId]
    local node = region.Nodes[nodeId]
    local reward = node.Reward or CampaignConfig.Rewards[node.Type]
    local scale = node.Reward and 1 or region.RewardScale

    if not isFirstClear then
        scale *= CampaignConfig.REPLAY_REWARD_SCALE
    end

    return math.floor(reward.Gold * scale), math.floor(reward.Exp * scale)
end

local function Check(condition, message)
    if condition then return end

    error("[CampaignConfig] " .. message, 2)
end

-- Errors on data that would break progression, including a King that can be reached without its Queen
function CampaignRules.Validate()
    for _, regionId in ipairs(CampaignConfig.ORDER) do
        local region = CampaignConfig.Regions[regionId]
        Check(region, regionId .. " is in ORDER but has no region data")
        Check(region.Nodes[region.Start], regionId .. " start node is missing")
        Check(region.Nodes[region.Final], regionId .. " final node is missing")

        for _, required in ipairs(region.Requires) do
            Check(CampaignConfig.Regions[required], regionId .. " requires unknown region " .. required)
        end

        for nodeId, node in pairs(region.Nodes) do
            Check(CampaignConfig.Rewards[node.Type], regionId .. "." .. nodeId .. " has unknown type " .. tostring(node.Type))

            if CampaignRules.IsBattle(node) then
                Check(CampaignConfig.Armies[node.Army], regionId .. "." .. nodeId .. " has no army")
            else
                Check(node.Army == nil, regionId .. "." .. nodeId .. " isn't a battle but has an army")
            end

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
