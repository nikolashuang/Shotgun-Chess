local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PieceConfig = require(ReplicatedStorage.Shared.Board.PieceConfig)
local ExpeditionConfig = require(script.Parent.ExpeditionConfig)
local ExpeditionMap = require(script.Parent.ExpeditionMap)

local EnemyConfig = ExpeditionConfig.Enemies
local ScalingConfig = ExpeditionConfig.Scaling
local MysteryConfig = ExpeditionConfig.Mystery
local TreasureConfig = MysteryConfig.Treasure

-- A run is one Expedition attempt: the three rolled regions, the walk through the current Act's map, the King's
-- health, upgrades and Artifacts, and the pouch. It lives in the profile until it is won or abandoned
local ExpeditionRules = {}

--RUNS--

function ExpeditionRules.GetStartPoints(mode, act)
    local points = ExpeditionConfig.Acts[act].StartPoints

    if mode == "Elite" then
        points += ExpeditionConfig.Elite.START_POINTS_BONUS
    end

    return points
end

function ExpeditionRules.NewRun(mode, random)
    local regions = {}
    local seeds = {}

    for act, actConfig in ipairs(ExpeditionConfig.Acts) do
        regions[act] = actConfig.Pool[random:NextInteger(1, #actConfig.Pool)]
        seeds[act] = random:NextInteger(1, 2 ^ 30)
    end

    return {
        Mode = mode,
        Act = 1,
        Regions = regions,
        Seeds = seeds,
        -- Nodes walked on the current Act's map, in order
        Path = {},
        Points = ExpeditionRules.GetStartPoints(mode, 1),

        Health = PieceConfig.Health.King,
        MaxHealth = PieceConfig.Health.King,

        -- Run-only upgrades; they never touch the permanent profile
        Upgrades = {
            Damage = 0,
            -- Gun Maintenance picks; each is worth more ammo on the Double Barrel
            Ammo = 0,
            SummonHealth = 0,
            SummonDamage = 0,
            StartCharge = 0,
            Energy = 0,
            HealAfterBattle = 0,
        },
        -- Artifact names held, in the order they were found
        Artifacts = {},
        -- The Fallen Knight once he joins: {Health, MaxHealth}
        Companion = nil,

        -- The pouch: Silver is spent during the run, Gold and XP are paid out when Act III is beaten
        Silver = 0,
        Gold = 0,
        Exp = 0,

        -- Regional Encounters already met, so none repeats in the run
        UsedExclusives = {},
        -- Last universal Mystery rolled, so the next one is different
        LastMystery = nil,
        -- The encounter open on the current node: {Node, Kind, Name, Fight, ...}
        Encounter = nil,
        -- Shop inventories by "Act.Node", kept so a restored checkpoint shows the same stock
        Shops = {},
        -- An Artifact waiting for the player to pick a slot for it (holding the max already)
        PendingArtifact = nil,

        -- Copy of the run from just before its last Rest Site choice, restored on death (Normal only)
        Checkpoint = nil,
    }
end

local function DeepCopy(value)
    if typeof(value) ~= "table" then return value end

    local copy = {}

    for key, item in pairs(value) do
        copy[key] = DeepCopy(item)
    end

    return copy
end

-- The run without its own checkpoint
function ExpeditionRules.CopyRun(run)
    local copy = DeepCopy(run)
    copy.Checkpoint = nil

    return copy
end

-- Back to the last Rest Site, or nil when there isn't one and the Expedition starts over
function ExpeditionRules.Rewind(run)
    if not run or not run.Checkpoint then return nil end

    local rewound = ExpeditionRules.CopyRun(run.Checkpoint)
    rewound.Checkpoint = ExpeditionRules.CopyRun(run.Checkpoint)

    return rewound
end

-- What the client may see: no checkpoint copy, and the treasure's tile stays on the server
function ExpeditionRules.GetClientRun(run)
    if not run then return nil end

    local copy = ExpeditionRules.CopyRun(run)
    copy.HasCheckpoint = run.Checkpoint ~= nil

    local encounter = copy.Encounter
    if encounter and encounter.Treasure then
        encounter.Treasure = {Digs = encounter.Treasure.Digs}
    end

    return copy
end

function ExpeditionRules.GetRegion(run)
    return ExpeditionConfig.Regions[run.Regions[run.Act]]
end

-- Every client and the server build the same map from the Act's seed
local mapCache = {}

function ExpeditionRules.GetMap(run, act)
    act = act or run.Act
    local key = run.Seeds[act]

    if not mapCache[key] then
        mapCache[key] = ExpeditionMap.Build(run.Seeds[act])
    end

    return mapCache[key]
end

function ExpeditionRules.GetNode(run, nodeId)
    if typeof(nodeId) ~= "string" then return nil end

    return ExpeditionRules.GetMap(run).Nodes[nodeId]
end

function ExpeditionRules.GetCurrentNode(run)
    return run.Path[#run.Path]
end

-- "Cleared", "Current", "Available" or "Locked"; the player only moves to nodes linked from where they stand
function ExpeditionRules.GetNodeState(run, nodeId)
    local map = ExpeditionRules.GetMap(run)
    if not map.Nodes[nodeId] then return "Locked" end

    local current = ExpeditionRules.GetCurrentNode(run)

    if table.find(run.Path, nodeId) then return "Cleared" end

    -- A node entered but not finished (an open encounter or Shop) must be finished before moving on
    if run.Encounter then
        return run.Encounter.Node == nodeId and "Current" or "Locked"
    end

    if not current then
        return table.find(map.Starts, nodeId) and "Available" or "Locked"
    end

    if table.find(map.Nodes[current].Links, nodeId) then return "Available" end

    return "Locked"
end

--BATTLES--

function ExpeditionRules.IsBattle(nodeType)
    return nodeType == "Battle" or nodeType == "Elite" or nodeType == "Boss"
end

-- Point budget for a battle of this kind at the run's current allocation
function ExpeditionRules.GetPoints(run, nodeType)
    if nodeType == "Elite" then return run.Points + EnemyConfig.ELITE_BONUS end
    if nodeType == "Boss" then return run.Points + EnemyConfig.BOSS_BONUS end

    return run.Points
end

-- Max health of an enemy piece in this Act, compounded and rounded up
function ExpeditionRules.GetEnemyHealth(pieceType, act)
    local base = PieceConfig.Health[pieceType]
    if ScalingConfig.FIXED[pieceType] then return base end

    return math.ceil(base * (1 + ScalingConfig.HEALTH_PER_ACT) ^ (act - 1))
end

-- Damage added to an enemy piece's base damage in this Act
function ExpeditionRules.GetEnemyDamageBonus(pieceType, act)
    if ScalingConfig.FIXED[pieceType] then return 0 end

    return (ScalingConfig.DamagePerAct[pieceType] or 0) * (act - 1)
end

--REWARDS--

-- Gold, XP and Silver a reward kind adds to the pouch in the run's current Act
function ExpeditionRules.GetReward(run, kind)
    local reward = ExpeditionConfig.Rewards[kind]
    local scale = ExpeditionConfig.ACT_REWARD_SCALE[run.Act] or 1

    return math.floor(reward.Gold * scale), math.floor(reward.Exp * scale), reward.Silver
end

--UPGRADES--

function ExpeditionRules.GetAmmoBonus(run, shotgunName)
    local perPick = ExpeditionConfig.Rest.AmmoByShotgun[shotgunName] or ExpeditionConfig.Rest.AMMO

    return run.Upgrades.Ammo * perPick
end

function ExpeditionRules.GetRestHeal(run)
    return math.ceil((run.MaxHealth - run.Health) * ExpeditionConfig.Rest.HEAL_MISSING)
end

function ExpeditionRules.HasArtifactRoom(run)
    return #run.Artifacts < ExpeditionConfig.Artifacts.MAX
end

--MYSTERY--

-- The universal Mysteries plus the current region's Regional Encounters not yet met this run
-- Returns the name and whether it is a Regional Encounter
function ExpeditionRules.RollMystery(run, random)
    local options = {}

    for _, name in ipairs(MysteryConfig.ENCOUNTERS) do
        if name ~= run.LastMystery then
            table.insert(options, name)
        end
    end

    for _, name in ipairs(ExpeditionRules.GetRegion(run).Exclusives) do
        if ExpeditionConfig.Exclusives[name].Enabled and not table.find(run.UsedExclusives, name) then
            table.insert(options, name)
        end
    end

    local name = options[random:NextInteger(1, #options)]

    return name, ExpeditionConfig.Exclusives[name] ~= nil
end

-- Whether the run can take this choice; the second value says why not, for the button
function ExpeditionRules.CanChoose(run, name, choice, extra)
    if name == "Gunsmith" then
        if choice == "Upgrade" then return run.Silver >= MysteryConfig.Gunsmith.COST, "Not enough Silver" end
        return choice == "Leave"
    elseif name == "Altar" then
        local altar = MysteryConfig.Altar
        if choice == "Blood" then return run.Health > altar.BLOOD_COST, "Too hurt" end
        if choice == "Royal" then return run.Health > altar.ROYAL_COST, "Too hurt" end
        return choice == "Leave"
    elseif name == "Barracks" then
        return choice == "Armor" or choice == "Weapons"
    elseif name == "Doctor" then
        return choice == "Treatment" or choice == "Vitality"
    elseif name == "HolyRook" then
        -- Losing max health can't take the King below 1
        if choice == "Power" then return run.MaxHealth > MysteryConfig.HolyRook.POWER_HEALTH, "Too weak" end
        return choice == "Vitality"
    elseif name == "Gambler" then
        if choice == "Wager" then
            local wager = MysteryConfig.Gambler.WAGERS[extra]
            if not wager then return false end
            return run.Silver >= wager, "Not enough Silver"
        end
        return choice == "Leave"
    elseif name == "FallenKnight" then
        return choice == "Challenge" or choice == "Leave"
    elseif name == "Ambush" then
        return choice == "Fight"
    end

    return false
end

--TREASURE--

local function IsOnTreasureBoard(column, row)
    return column >= 1 and column <= TreasureConfig.SIZE and row >= 1 and row <= TreasureConfig.SIZE
end

ExpeditionRules.IsOnTreasureBoard = IsOnTreasureBoard

function ExpeditionRules.GetDigTiles(column, row)
    local reach = math.floor(TreasureConfig.DIG_SIZE / 2)
    local tiles = {}

    for x = column - reach, column + reach do
        for y = row - reach, row + reach do
            if IsOnTreasureBoard(x, y) then
                table.insert(tiles, {x, y})
            end
        end
    end

    return tiles
end

function ExpeditionRules.IsDigHit(column, row, treasureColumn, treasureRow)
    local reach = math.floor(TreasureConfig.DIG_SIZE / 2)

    return math.abs(column - treasureColumn) <= reach and math.abs(row - treasureRow) <= reach
end

-- digNumber is the dig that found it, nil if it was never found
function ExpeditionRules.GetTreasureSilver(digNumber)
    if not digNumber then return TreasureConfig.CONSOLATION end

    return TreasureConfig.Rewards[digNumber] or TreasureConfig.CONSOLATION
end

return ExpeditionRules
