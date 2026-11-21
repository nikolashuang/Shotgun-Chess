local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)
local CampaignConfig = require(ReplicatedStorage.Shared.Campaign.CampaignConfig)
local CampaignRules = require(ReplicatedStorage.Shared.Campaign.CampaignRules)
local EncounterRules = require(script.Parent.EncounterRules)
local MatchClass = require(ServerScriptService.Match.MatchClass)
local ProfileService = require(ServerScriptService.Player.ProfileService)
local LoadoutService = require(ServerScriptService.Player.LoadoutService)

local CampaignRemote = ReplicatedStorage.Remotes.CampaignRemote

local RestConfig = CampaignConfig.Rest
local TreasureConfig = CampaignConfig.Treasure

local REST_CHOICES = {"Rest", "Train", "Maintenance"}

-- Campaign progression: region runs, what each node does and what finishing a region pays
-- Combat itself is handled by MatchClass, which reports back through OnEnd
local CampaignService = {}

local function GetData(player)
    local profile = ProfileService.Get(player)

    return profile and profile.Data
end

-- Returns the run the node belongs to, starting one when the node is the region's start
local function GetPlayableRun(player, regionId, nodeId)
    if typeof(regionId) ~= "string" or typeof(nodeId) ~= "string" then return nil end

    local region = CampaignConfig.Regions[regionId]
    if not region or not region.Nodes[nodeId] then return nil end

    local data = GetData(player)
    if not data then return nil end
    if not CampaignRules.IsRegionUnlocked(data.Nodes, regionId) then return nil end

    local run = data.Runs[regionId]
    if CampaignRules.GetNodeState(run, regionId, nodeId) ~= "Available" then return nil end

    if not run then
        run = CampaignRules.NewRun()
        data.Runs[regionId] = run
    end

    return run
end

-- Pays the pouch out, unlocks the class and ends the run
local function FinishRegion(player, regionId, summary)
    local data = GetData(player)
    local region = CampaignConfig.Regions[regionId]
    local run = data.Runs[regionId]

    local isReplay = CampaignRules.IsRegionComplete(data.Nodes, regionId)
    local gold, exp = CampaignRules.GetPayout(run, isReplay)

    ProfileService.AddGold(player, gold)
    ProfileService.AddExp(player, exp)

    data.Nodes[CampaignRules.GetNodeKey(regionId, region.Final)] = true
    data.Runs[regionId] = nil

    if region.Class and not data.Classes[region.Class] then
        summary.Class = region.Class
        data.Classes[region.Class] = true
    end

    summary.RegionComplete = true
    summary.Replay = isReplay
    summary.PaidGold = gold
    summary.PaidExp = exp
end

-- Moves the run onto the node and drops its reward in the pouch
function CampaignService.CompleteNode(player, regionId, nodeId, gold, exp)
    local data = GetData(player)
    local region = CampaignConfig.Regions[regionId]
    local node = region.Nodes[nodeId]
    local run = data.Runs[regionId]

    if not gold then
        gold, exp = CampaignRules.GetReward(regionId, nodeId)
    end

    table.insert(run.Path, nodeId)
    run.Gold += gold
    run.Exp += exp

    local summary = {
        Victory = true,
        Region = regionId,
        Node = nodeId,
        Type = node.Type,
        Gold = gold,
        Exp = exp,
        PouchGold = run.Gold,
        PouchExp = run.Exp,
    }

    if nodeId == region.Final then
        FinishRegion(player, regionId, summary)
    end

    ProfileService.Sync(player)

    return summary
end

-- Losing sends the run back to its last Rest Site, or ends it when there isn't one
local function FailRun(player, regionId, nodeId)
    local data = GetData(player)
    local rewound = CampaignRules.Rewind(data.Runs[regionId])
    data.Runs[regionId] = rewound

    ProfileService.Sync(player)

    return {Victory = false, Region = regionId, Node = nodeId, Checkpoint = rewound ~= nil}
end

function CampaignService.CreateMatch(player, regionId, nodeId)
    local run = GetPlayableRun(player, regionId, nodeId)
    if not run then return nil end

    local node = CampaignRules.GetNode(regionId, nodeId)
    if not CampaignRules.IsBattle(node) then return nil end

    local enemies = EncounterRules.Generate(CampaignRules.GetPoints(regionId, nodeId), node.Type)
    local shotgun, class = LoadoutService.GetLoadout(player)
    local match = MatchClass.new(player, shotgun, class, enemies, CampaignConfig.AI_RATING)

    -- The King carries its health and upgrades from battle to battle
    local king = match.King
    king.MaxHealth = run.MaxHealth
    king.Health = run.Health
    king.DamageBonus = run.DamageBonus

    match.OnEnd = function(result)
        local summary = nil

        if result == "Victory" then
            run.Health = king.Health
            summary = CampaignService.CompleteNode(player, regionId, nodeId)
        else
            summary = FailRun(player, regionId, nodeId)
        end

        CampaignRemote:FireClient(player, "Result", summary)
    end

    return match
end

-- The checkpoint is taken before the choice, so dying lets the player pick again
local function Rest(player, regionId, nodeId, choice)
    if not table.find(REST_CHOICES, choice) then return end

    local node = CampaignRules.GetNode(regionId, nodeId)
    if not node or node.Type ~= "Rest" then return end

    local run = GetPlayableRun(player, regionId, nodeId)
    if not run then return end

    run.Checkpoint = CampaignRules.CopyRun(run)

    if choice == "Rest" then
        run.Health = run.MaxHealth
    elseif choice == "Train" then
        run.MaxHealth += RestConfig.TRAIN_HEALTH
        run.Health += RestConfig.TRAIN_HEALTH
    elseif choice == "Maintenance" then
        run.DamageBonus += RestConfig.MAINTENANCE_DAMAGE
    end

    local summary = CampaignService.CompleteNode(player, regionId, nodeId)
    summary.Choice = choice

    CampaignRemote:FireClient(player, "Result", summary)
end

-- The treasure's tile is rolled once per visit and kept in the run, so leaving and coming back can't reroll it
local function StartTreasure(player, regionId, nodeId)
    local node = CampaignRules.GetNode(regionId, nodeId)
    if not node or node.Type ~= "Treasure" then return end

    local run = GetPlayableRun(player, regionId, nodeId)
    if not run then return end

    if not run.Treasure or run.Treasure.Node ~= nodeId then
        local random = Random.new()

        run.Treasure = {
            Node = nodeId,
            Column = random:NextInteger(1, BoardConfig.SIZE),
            Row = random:NextInteger(1, BoardConfig.SIZE),
            Digs = {},
        }
    end

    ProfileService.Sync(player)
    CampaignRemote:FireClient(player, "Treasure", {Region = regionId, Node = nodeId, Digs = run.Treasure.Digs})
end

local function IsTile(value)
    return typeof(value) == "number" and value % 1 == 0 and value >= 1 and value <= BoardConfig.SIZE
end

local function Dig(player, regionId, nodeId, column, row)
    if not IsTile(column) or not IsTile(row) then return end

    local run = GetPlayableRun(player, regionId, nodeId)
    if not run then return end

    local treasure = run.Treasure
    if not treasure or treasure.Node ~= nodeId then return end

    for _, dug in ipairs(treasure.Digs) do
        if dug[1] == column and dug[2] == row then return end
    end

    table.insert(treasure.Digs, {column, row})

    local isFound = CampaignRules.IsDigHit(column, row, treasure.Column, treasure.Row)
    local digsLeft = TreasureConfig.DIGS - #treasure.Digs

    local result = {
        Region = regionId,
        Node = nodeId,
        Column = column,
        Row = row,
        Found = isFound,
        DigsLeft = digsLeft,
    }

    if not isFound and digsLeft > 0 then
        ProfileService.Sync(player)
        CampaignRemote:FireClient(player, "Dig", result)
        return
    end

    -- The hunt is over: show where it was and pay out
    result.Done = true
    result.TreasureColumn = treasure.Column
    result.TreasureRow = treasure.Row
    run.Treasure = nil

    CampaignRemote:FireClient(player, "Dig", result)

    local gold = CampaignRules.GetTreasureGold(isFound and #treasure.Digs or nil)
    local summary = CampaignService.CompleteNode(player, regionId, nodeId, gold, 0)
    summary.Found = isFound

    CampaignRemote:FireClient(player, "Result", summary)
end

local init = false
function CampaignService.Init()
    if init then return end
    init = true

    CampaignRules.Validate()

    CampaignRemote.OnServerEvent:Connect(function(player, action, regionId, nodeId, first, second)
        if action == "Rest" then
            Rest(player, regionId, nodeId, first)
        elseif action == "StartTreasure" then
            StartTreasure(player, regionId, nodeId)
        elseif action == "Dig" then
            Dig(player, regionId, nodeId, first, second)
        end
    end)
end

return CampaignService
