-- Builds a region's area map from its Map settings, laid out left to right in lanes
-- Uses a seeded Random so the server and every client build the same map
local CampaignMap = {}

-- Column 1 is the single start node. Every route fights 3 times, then hits one Rest and one Treasure
local PATTERN = {"Fight", "Fight", "Fight", "Break", "Break", "Fight", "Fight", "Fight", "Break", "Break"}

local START_X = 0.04
local COLUMN_SPACING = 0.08
local QUEEN_X = 0.85
local KING_X = 0.94
local LANE_TOP = 0.13
local LANE_BOTTOM = 0.87

local JITTER_X = 0.012
local JITTER_Y = 0.045

-- Chance a node also links to a neighbouring lane, and that a branch replaces its straight link
local BRANCH_CHANCE = 0.4
local MERGE_CHANCE = 0.35

local function GetNodeId(column, lane)
    return column .. "-" .. lane
end

local function GetLaneY(lane, lanes)
    if lanes == 1 then return 0.5 end

    return LANE_TOP + (lane - 1) / (lanes - 1) * (LANE_BOTTOM - LANE_TOP)
end

-- Break columns come in pairs; each lane gets one Rest and one Treasure, in an order that varies by lane
local function GetBreakType(column, lane, flip)
    local isFirst = PATTERN[column - 1] ~= "Break"
    local isRest = (lane + flip) % 2 == 0

    if not isFirst then
        isRest = not isRest
    end

    return isRest and "Rest" or "Treasure"
end

function CampaignMap.Build(map)
    local random = Random.new(map.Seed)
    local lanes = map.Lanes
    local flip = random:NextInteger(0, 1)
    local nodes = {}
    local parentCounts = {}
    local fightIndex = 1

    local function Jitter(amount)
        return (random:NextNumber() * 2 - 1) * amount
    end

    nodes.Start = {Type = "Combat", Army = map.Armies[1], Position = {START_X, 0.5}, Links = {}}

    for column = 2, #PATTERN do
        local kind = PATTERN[column]

        if kind == "Fight" then
            fightIndex += 1
        end

        for lane = 1, lanes do
            local nodeId = GetNodeId(column, lane)
            local x = START_X + (column - 1) * COLUMN_SPACING + Jitter(JITTER_X)
            local y = GetLaneY(lane, lanes) + Jitter(JITTER_Y)

            if kind == "Fight" then
                nodes[nodeId] = {Type = "Combat", Army = map.Armies[fightIndex], Position = {x, y}, Links = {}}
            else
                nodes[nodeId] = {Type = GetBreakType(column, lane, flip), Position = {x, y}, Links = {}}
            end

            parentCounts[nodeId] = 0
        end
    end

    nodes.Queen = {Type = "Queen", Army = map.QueenArmy, Position = {QUEEN_X, 0.5}, Links = {"King"}}
    nodes.King = {Type = "King", Army = map.KingArmy, Position = {KING_X, 0.5}, Links = {}}

    for lane = 1, lanes do
        table.insert(nodes.Start.Links, GetNodeId(2, lane))
        parentCounts[GetNodeId(2, lane)] += 1
        table.insert(nodes[GetNodeId(#PATTERN, lane)].Links, "Queen")
    end

    for column = 2, #PATTERN - 1 do
        -- Inside a break pair routes stay in their lane, so nobody gets two Rests or two Treasures
        local isBreakPair = PATTERN[column] == "Break" and PATTERN[column + 1] == "Break"

        for lane = 1, lanes do
            local links = nodes[GetNodeId(column, lane)].Links
            table.insert(links, GetNodeId(column + 1, lane))
            parentCounts[GetNodeId(column + 1, lane)] += 1

            if not isBreakPair and lanes > 1 and random:NextNumber() < BRANCH_CHANCE then
                local side = random:NextInteger(0, 1) == 0 and -1 or 1

                if lane + side < 1 or lane + side > lanes then
                    side = -side
                end

                table.insert(links, GetNodeId(column + 1, lane + side))
                parentCounts[GetNodeId(column + 1, lane + side)] += 1
            end
        end

        -- A branch can replace the straight link, as long as nothing is left without a parent
        for lane = 1, lanes do
            local links = nodes[GetNodeId(column, lane)].Links
            local straightId = GetNodeId(column + 1, lane)

            if #links > 1 and parentCounts[straightId] > 1 and random:NextNumber() < MERGE_CHANCE then
                table.remove(links, table.find(links, straightId))
                parentCounts[straightId] -= 1
            end
        end
    end

    return nodes
end

return CampaignMap
