-- Builds an Act's branching map from a seed, bottom (layer 1) to top (the Boss)
-- Seeded so the server and every client build the same map, and a restored checkpoint gets it back unchanged
local ExpeditionConfig = require(script.Parent.ExpeditionConfig)

local MapConfig = ExpeditionConfig.Map

local ExpeditionMap = {}

ExpeditionMap.BOSS = "Boss"

function ExpeditionMap.GetNodeId(layer, column)
    return layer .. "-" .. column
end

-- Edge lanes only branch inward, so left alone the two middle lanes rarely trade routes. Adds crossings between them
-- on random layers that have none until there are MIN_CENTER_LINKS
local function AddCenterLinks(links, random)
    local left = MapConfig.WIDTH // 2
    local right = left + 1
    local count = 0
    local open = {}

    for layer = 1, MapConfig.LAYERS - 1 do
        local crosses = table.find(links[layer][left], right) or table.find(links[layer][right], left)

        if crosses then
            count += 1
        else
            table.insert(open, layer)
        end
    end

    while count < MapConfig.MIN_CENTER_LINKS and #open > 0 do
        local layer = table.remove(open, random:NextInteger(1, #open))

        if random:NextInteger(0, 1) == 0 then
            table.insert(links[layer][left], right)
        else
            table.insert(links[layer][right], left)
        end

        count += 1
    end
end

-- Every lane has a node on every layer, like the old Campaign map: each node links straight up, sometimes also into
-- a neighboring lane, and a branch can replace the straight link as long as no node is left without a way in
-- Routes may cross
local function BuildLinks(random)
    local links = {}
    local parents = {}

    for layer = 1, MapConfig.LAYERS do
        links[layer] = {}
        parents[layer] = {}

        for column = 1, MapConfig.WIDTH do
            links[layer][column] = {}
            parents[layer][column] = 0
        end
    end

    for layer = 1, MapConfig.LAYERS - 1 do
        for column = 1, MapConfig.WIDTH do
            local targets = links[layer][column]
            table.insert(targets, column)
            parents[layer + 1][column] += 1

            if random:NextNumber() < MapConfig.BRANCH_CHANCE then
                local side = random:NextInteger(0, 1) == 0 and -1 or 1

                if column + side < 1 or column + side > MapConfig.WIDTH then
                    side = -side
                end

                table.insert(targets, column + side)
                parents[layer + 1][column + side] += 1
            end
        end

        for column = 1, MapConfig.WIDTH do
            local targets = links[layer][column]

            if #targets > 1 and parents[layer + 1][column] > 1 and random:NextNumber() < MapConfig.MERGE_CHANCE then
                table.remove(targets, table.find(targets, column))
                parents[layer + 1][column] -= 1
            end
        end
    end

    AddCenterLinks(links, random)

    return links
end

local function PickWeighted(random, weights)
    local total = 0

    for _, weight in pairs(weights) do
        total += weight
    end

    local roll = random:NextNumber() * total

    -- Fixed order so the same seed always picks the same type
    for _, nodeType in ipairs({"Battle", "Mystery", "Elite", "Shop", "Rest"}) do
        local weight = weights[nodeType]

        if weight then
            roll -= weight
            if roll <= 0 then return nodeType end
        end
    end

    return "Battle"
end

local function HasNeighborOfType(nodes, nodeId, nodeType)
    local node = nodes[nodeId]

    for _, link in ipairs(node.Links) do
        if nodes[link] and nodes[link].Type == nodeType then return true end
    end

    for _, parentId in ipairs(node.Parents) do
        if nodes[parentId].Type == nodeType then return true end
    end

    return false
end

local function AssignTypes(nodes, order, random)
    local weights = MapConfig.Weights

    for _, nodeId in ipairs(order) do
        local node = nodes[nodeId]

        if node.Layer == 1 then
            node.Type = "Battle"
            continue
        end

        local nodeType = PickWeighted(random, weights)

        -- Rest Sites and Elites never follow one of their own kind
        for _ = 1, 10 do
            if not MapConfig.NO_REPEAT[nodeType] or not HasNeighborOfType(nodes, nodeId, nodeType) then break end
            nodeType = PickWeighted(random, weights)
        end

        if MapConfig.NO_REPEAT[nodeType] and HasNeighborOfType(nodes, nodeId, nodeType) then
            nodeType = "Battle"
        end

        node.Type = nodeType
    end

    -- Every Act has at least one Rest Site and Shop, placed on a node that keeps the no-repeat rule
    local counts = {}

    for _, nodeId in ipairs(order) do
        local nodeType = nodes[nodeId].Type
        counts[nodeType] = (counts[nodeType] or 0) + 1
    end

    for _, required in ipairs(MapConfig.REQUIRED) do
        if (counts[required] or 0) > 0 then continue end

        local candidates = {}

        for _, nodeId in ipairs(order) do
            local node = nodes[nodeId]
            local isLast = table.find(MapConfig.REQUIRED, node.Type) and counts[node.Type] == 1

            if node.Layer > 1 and not isLast and not HasNeighborOfType(nodes, nodeId, required) then
                table.insert(candidates, nodeId)
            end
        end

        if #candidates > 0 then
            local node = nodes[candidates[random:NextInteger(1, #candidates)]]
            counts[node.Type] -= 1
            node.Type = required
            counts[required] = 1
        end
    end
end

-- Returns {Nodes = id -> {Layer, Column, Type, Links, Parents}, Starts = layer 1 ids}
function ExpeditionMap.Build(seed)
    local random = Random.new(seed)
    local links = BuildLinks(random)

    local nodes = {}
    local order = {}

    for layer = 1, MapConfig.LAYERS do
        for column = 1, MapConfig.WIDTH do
            local nodeId = ExpeditionMap.GetNodeId(layer, column)
            nodes[nodeId] = {Layer = layer, Column = column, Type = nil, Links = {}, Parents = {}}
            table.insert(order, nodeId)
        end
    end

    for layer = 1, MapConfig.LAYERS - 1 do
        for column = 1, MapConfig.WIDTH do
            local fromId = ExpeditionMap.GetNodeId(layer, column)
            local targets = links[layer][column]
            table.sort(targets)

            for _, target in ipairs(targets) do
                local toId = ExpeditionMap.GetNodeId(layer + 1, target)

                table.insert(nodes[fromId].Links, toId)
                table.insert(nodes[toId].Parents, fromId)
            end
        end
    end

    -- Every lane ends at the Boss
    nodes[ExpeditionMap.BOSS] = {Layer = MapConfig.LAYERS + 1, Column = nil, Type = "Boss", Links = {}, Parents = {}}

    for column = 1, MapConfig.WIDTH do
        local nodeId = ExpeditionMap.GetNodeId(MapConfig.LAYERS, column)
        table.insert(nodes[nodeId].Links, ExpeditionMap.BOSS)
        table.insert(nodes[ExpeditionMap.BOSS].Parents, nodeId)
    end

    AssignTypes(nodes, order, random)

    local starts = {}

    for column = 1, MapConfig.WIDTH do
        table.insert(starts, ExpeditionMap.GetNodeId(1, column))
    end

    return {Nodes = nodes, Starts = starts}
end

return ExpeditionMap
