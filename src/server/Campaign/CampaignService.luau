local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)
local PieceConfig = require(ReplicatedStorage.Shared.Board.PieceConfig)
local CampaignConfig = require(ReplicatedStorage.Shared.Campaign.CampaignConfig)
local DevConfig = require(ReplicatedStorage.Shared.Player.DevConfig)
local CampaignRules = require(ReplicatedStorage.Shared.Campaign.CampaignRules)
local EncounterRules = require(script.Parent.EncounterRules)
local MatchClass = require(ServerScriptService.Match.MatchClass)
local ProfileService = require(ServerScriptService.Player.ProfileService)
local LoadoutService = require(ServerScriptService.Player.LoadoutService)

local CampaignRemote = ReplicatedStorage.Remotes.CampaignRemote

local RestConfig = CampaignConfig.Rest
local TreasureConfig = CampaignConfig.Treasure
local MysteryConfig = CampaignConfig.Mystery

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
    if region.DevOnly and not DevConfig.IsDev(player) then return nil end

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

-- Every step of a run is written to the DataStore right away, so leaving (or a crash) never loses it
-- Saves wait SAVE_DELAY so a burst of steps becomes one write
local SAVE_DELAY = 3
local pendingSaves = {}

local function SaveSoon(player)
    if pendingSaves[player] then return end
    pendingSaves[player] = true

    task.delay(SAVE_DELAY, function()
        pendingSaves[player] = nil

        if player.Parent then
            ProfileService.Save(player)
        end
    end)
end

-- Pays the pouch out, unlocks the class and ends the run
local function FinishRegion(player, regionId, summary)
    local data = GetData(player)
    local region = CampaignConfig.Regions[regionId]
    local run = data.Runs[regionId]

    local isReplay = CampaignRules.IsRegionComplete(data.Nodes, regionId)
    local gold, exp = CampaignRules.GetPayout(run, isReplay)

    -- Testing in the dev region never touches the profile's gold or exp
    if region.DevOnly then
        gold, exp = 0, 0
    end

    ProfileService.AddGold(player, gold)
    ProfileService.AddExp(player, exp)

    if not region.DevOnly then
        data.Nodes[CampaignRules.GetNodeKey(regionId, region.Final)] = true
    end
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
    run.Mystery = nil
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
    SaveSoon(player)

    return summary
end

-- Losing sends the run back to its last Rest Site, or ends it when there isn't one
local function FailRun(player, regionId, nodeId)
    local data = GetData(player)
    local rewound = CampaignRules.Rewind(data.Runs[regionId])
    data.Runs[regionId] = rewound

    ProfileService.Sync(player)
    SaveSoon(player)

    return {Victory = false, Region = regionId, Node = nodeId, Checkpoint = rewound ~= nil}
end

-- The army for a battle node, or for a fight a mystery encounter started on this node
local function GetEnemies(run, regionId, nodeId)
    local node = CampaignRules.GetNode(regionId, nodeId)

    if CampaignRules.IsBattle(node) then
        return EncounterRules.Generate(CampaignRules.GetPoints(regionId, nodeId), node.Type)
    end

    local mystery = run.Mystery
    if node.Type ~= "Mystery" or not mystery or mystery.Node ~= nodeId then return nil end

    if mystery.Fight == "FallenKnight" then
        local tile = MysteryConfig.FallenKnight.TILE
        local enemies = {{Type = "FallenKnight", Column = tile[1], Row = tile[2]}}

        for _, pawnTile in ipairs(MysteryConfig.FallenKnight.PAWN_TILES) do
            table.insert(enemies, {Type = "FallenPawn", Column = pawnTile[1], Row = pawnTile[2]})
        end

        return enemies
    elseif mystery.Fight == "Ambush" then
        return EncounterRules.Generate(CampaignRules.GetPoints(regionId, nodeId), "Combat")
    end

    return nil
end

-- What winning a mystery fight gives: the Knight joins, an ambush pays like a battle
local function CompleteMysteryFight(player, regionId, nodeId, run)
    local fight = run.Mystery.Fight

    if fight == "FallenKnight" then
        local health = PieceConfig.Health.FallenKnight
        run.Companion = {Health = health, MaxHealth = health}

        local _, exp = CampaignRules.GetReward(regionId, nodeId)
        local summary = CampaignService.CompleteNode(player, regionId, nodeId, 0, exp)
        summary.Companion = true

        return summary
    end

    local region = CampaignConfig.Regions[regionId]
    local reward = CampaignConfig.Rewards.Combat

    return CampaignService.CompleteNode(player, regionId, nodeId, math.floor(reward.Gold * region.RewardScale), math.floor(reward.Exp * region.RewardScale))
end

function CampaignService.CreateMatch(player, regionId, nodeId)
    local run = GetPlayableRun(player, regionId, nodeId)
    if not run then return nil end

    local enemies = GetEnemies(run, regionId, nodeId)
    if not enemies then return nil end

    local node = CampaignRules.GetNode(regionId, nodeId)
    local shotgun, class = LoadoutService.GetLoadout(player)
    local match = MatchClass.new(player, shotgun, class, enemies, CampaignConfig.AI_RATING)

    -- The King carries its health and upgrades from battle to battle
    local king = match.King
    king.MaxHealth = run.MaxHealth
    king.Health = run.Health
    king.DamageBonus = run.DamageBonus

    -- So does the Fallen Knight, who starts beside the King
    if run.Companion then
        match.CompanionStart = {
            Type = "FallenKnight",
            Column = king.Column + CampaignConfig.COMPANION_OFFSET,
            Row = king.Row,
            Health = run.Companion.Health,
        }
    end

    match.OnEnd = function(result)
        local summary = nil

        if result == "Victory" then
            run.Health = king.Health

            if run.Companion then
                local companion = match.Companion
                run.Companion.Health = companion and companion:IsAlive() and companion.Health or 0

                if run.Companion.Health <= 0 then
                    run.Companion = nil
                end
            end

            if CampaignRules.IsBattle(node) then
                summary = CampaignService.CompleteNode(player, regionId, nodeId)
            else
                summary = CompleteMysteryFight(player, regionId, nodeId, run)
            end
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

        if run.Companion then
            run.Companion.Health = run.Companion.MaxHealth
        end
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
    local _, exp = CampaignRules.GetReward(regionId, nodeId)
    local summary = CampaignService.CompleteNode(player, regionId, nodeId, gold, exp)
    summary.Found = isFound

    CampaignRemote:FireClient(player, "Result", summary)
end

-- The encounter is rolled once per visit and kept in the run, so leaving and coming back can't reroll it
local function StartMystery(player, regionId, nodeId)
    local node = CampaignRules.GetNode(regionId, nodeId)
    if not node or node.Type ~= "Mystery" then return end

    local run = GetPlayableRun(player, regionId, nodeId)
    if not run then return end

    if not run.Mystery or run.Mystery.Node ~= nodeId then
        -- Dev nodes are pinned to one encounter so each can be tested on demand
        local encounter = node.Encounter or CampaignRules.RollMystery(run, Random.new())
        run.Mystery = {Node = nodeId, Encounter = encounter}
        run.LastMystery = encounter
    end

    ProfileService.Sync(player)
    CampaignRemote:FireClient(player, "Mystery", {Region = regionId, Node = nodeId, Encounter = run.Mystery.Encounter, Fight = run.Mystery.Fight})
end

local function ChooseMystery(player, regionId, nodeId, choice)
    if typeof(choice) ~= "string" then return end

    local run = GetPlayableRun(player, regionId, nodeId)
    if not run then return end

    local mystery = run.Mystery
    if not mystery or mystery.Node ~= nodeId or mystery.Fight then return end
    if not CampaignRules.CanChooseMystery(run, mystery.Encounter, choice) then return end

    local encounter = mystery.Encounter
    local outcome = nil

    -- Fights start a match on this node; the result arrives when it ends
    if choice == "Challenge" or choice == "Fight" then
        mystery.Fight = encounter
        ProfileService.Sync(player)
        CampaignRemote:FireClient(player, "MysteryFight", {Region = regionId, Node = nodeId})
        return
    end

    if encounter == "Gunsmith" then
        local gunsmith = MysteryConfig.Gunsmith

        if choice == "Upgrade" then
            run.Gold -= gunsmith.UPGRADE_COST
            run.DamageBonus += gunsmith.UPGRADE_DAMAGE
        elseif choice == "Gamble" then
            run.Gold -= gunsmith.GAMBLE_COST
            outcome = Random.new():NextInteger(0, 1) == 1 and gunsmith.GAMBLE_DAMAGE or -gunsmith.GAMBLE_DAMAGE
            run.DamageBonus += outcome
        end
    elseif encounter == "Ambush" and choice == "TakeHit" then
        run.Health -= MysteryConfig.Ambush.DAMAGE
    elseif encounter == "Altar" then
        local altar = MysteryConfig.Altar

        if choice == "Blood" then
            run.Health -= altar.BLOOD_COST
            run.MaxHealth += altar.BLOOD_HEALTH
        elseif choice == "Royal" then
            run.Health -= altar.ROYAL_COST
            run.DamageBonus += altar.ROYAL_DAMAGE
        end
    end

    local _, exp = CampaignRules.GetReward(regionId, nodeId)
    local summary = CampaignService.CompleteNode(player, regionId, nodeId, 0, exp)
    summary.Encounter = encounter
    summary.Choice = choice
    summary.Outcome = outcome

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
        elseif action == "StartMystery" then
            StartMystery(player, regionId, nodeId)
        elseif action == "Mystery" then
            ChooseMystery(player, regionId, nodeId, first)
        elseif action == "ResetDev" and DevConfig.IsDev(player) then
            -- Every visit to the dev region starts from a fresh run so every screen and fight can be seen again
            ProfileService.ResetDevRegions(player)
            ProfileService.Sync(player)
            CampaignRemote:FireClient(player, "DevReset")
        end
    end)
end

return CampaignService
