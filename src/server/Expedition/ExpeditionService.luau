local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PieceConfig = require(ReplicatedStorage.Shared.Board.PieceConfig)
local DevConfig = require(ReplicatedStorage.Shared.Player.DevConfig)
local ExpeditionConfig = require(ReplicatedStorage.Shared.Expedition.ExpeditionConfig)
local ExpeditionRules = require(ReplicatedStorage.Shared.Expedition.ExpeditionRules)
local EncounterRules = require(script.Parent.EncounterRules)

-- Regional Encounters with their own board rules, each run by its own module
local Encounters = {
    DeadmanWalking = require(script.Parent.Encounters.DeadmanWalking),
    DangerousPayload = require(script.Parent.Encounters.DangerousPayload),
    HauntedMansion = require(script.Parent.Encounters.HauntedMansion),
}

-- Encounters whose fight starts as soon as they're entered, after showing their rules
local FORCED_FIGHTS = {DeadmanWalking = true, DangerousPayload = true}
local MatchClass = require(ServerScriptService.Match.MatchClass)
local ProfileService = require(ServerScriptService.Player.ProfileService)
local LoadoutService = require(ServerScriptService.Player.LoadoutService)

local ExpeditionRemote = ReplicatedStorage.Remotes.ExpeditionRemote

local MysteryConfig = ExpeditionConfig.Mystery
local TreasureConfig = MysteryConfig.Treasure
local ArtifactConfig = ExpeditionConfig.Artifacts

local REST_CHOICES = {"Rest", "GunMaintenance"}

-- Expedition runs: starting and abandoning them, what each node does, checkpoints, and paying out the pouch
-- Combat itself is handled by MatchClass, which reports back through OnEnd
local ExpeditionService = {}

local function GetData(player)
    local profile = ProfileService.Get(player)

    return profile and profile.Data
end

local function GetRun(player)
    local data = GetData(player)

    return data and data.Expedition
end

-- Every step of a run is written to the DataStore soon after, so leaving (or a crash) never loses it
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

local function Changed(player)
    ProfileService.Sync(player)
    SaveSoon(player)
end

--POUCH AND ARTIFACTS--

local function AddReward(run, kind, summary)
    local gold, exp, silver = ExpeditionRules.GetReward(run, kind)

    run.Gold += gold
    run.Exp += exp
    run.Silver += silver

    summary.Gold = (summary.Gold or 0) + gold
    summary.Exp = (summary.Exp or 0) + exp
    summary.Silver = (summary.Silver or 0) + silver
end

-- Artifacts not held yet, so none is found twice
local function GetArtifactOptions(run)
    local options = {}

    for name in pairs(ArtifactConfig.Pool) do
        if not table.find(run.Artifacts, name) then
            table.insert(options, name)
        end
    end

    table.sort(options)

    return options
end

-- With a free slot it goes straight in; holding the max, the player picks one to replace or declines it
-- Returns the Artifact's name, or nil when there are none left to find
local function GiveArtifact(run, name)
    if not name then
        local options = GetArtifactOptions(run)
        if #options == 0 then return nil end

        name = options[Random.new():NextInteger(1, #options)]
    end

    if ExpeditionRules.HasArtifactRoom(run) then
        table.insert(run.Artifacts, name)
    else
        run.PendingArtifact = name
    end

    return name
end

local function ResolveArtifact(player, choice, slot)
    local run = GetRun(player)
    if not run or not run.PendingArtifact then return end

    if choice == "Replace" then
        if typeof(slot) ~= "number" or not run.Artifacts[slot] then return end

        -- Discarded Artifacts are gone for good
        run.Artifacts[slot] = run.PendingArtifact
    elseif choice ~= "Decline" then
        return
    end

    run.PendingArtifact = nil
    Changed(player)
end

--RUN FLOW--

local function NewSummary(run, nodeId, nodeType)
    return {
        Victory = true,
        Node = nodeId,
        Type = nodeType,
        Act = run.Act,
        Gold = 0,
        Exp = 0,
        Silver = 0,
    }
end

-- The run is over: Act III beaten pays out the pouch, everything else is lost with the run
local function EndRun(player, summary)
    local data = GetData(player)
    local run = data.Expedition

    if summary.ExpeditionComplete then
        local gold, exp = ProfileService.AddEarned(player, run.Gold, run.Exp)
        summary.PaidGold = gold
        summary.PaidExp = exp
    end

    data.Expedition = nil
end

-- Beating a Boss opens the next Act's map, or completes the Expedition after Act III
local function FinishAct(player, run, summary)
    summary.ActComplete = true

    if run.Act >= #ExpeditionConfig.Acts then
        summary.ExpeditionComplete = true
        EndRun(player, summary)
        return
    end

    run.Act += 1
    run.Path = {}
    run.Points = ExpeditionRules.GetStartPoints(run.Mode, run.Act)
    -- The checkpoint stays: dying in the new Act still goes back to the last Rest Site
    summary.NextRegion = run.Regions[run.Act]
end

-- Moves the run onto the node and closes whatever was open there
local function CompleteNode(player, run, nodeId, summary)
    table.insert(run.Path, nodeId)
    run.Encounter = nil

    summary.Silver = summary.Silver or 0
    summary.PouchGold = run.Gold
    summary.PouchExp = run.Exp
    summary.PouchSilver = run.Silver

    local node = ExpeditionRules.GetNode(run, nodeId)

    if node and node.Type == "Boss" then
        FinishAct(player, run, summary)
    end

    Changed(player)

    return summary
end

local function SendResult(player, summary)
    ExpeditionRemote:FireClient(player, "Result", summary)
end

-- Losing a fight, or an encounter's penalty killing the King
-- Normal goes back to the last Rest Site; Elite (or no checkpoint yet) ends the run
local function FailRun(player, nodeId)
    local data = GetData(player)
    local run = data.Expedition
    local summary = {Victory = false, Node = nodeId, Mode = run.Mode}

    local rewound = run.Mode == "Normal" and ExpeditionRules.Rewind(run) or nil

    if rewound then
        data.Expedition = rewound
        summary.Checkpoint = true
    else
        data.Expedition = nil
        summary.RunLost = true
    end

    Changed(player)

    return summary
end

--BATTLES--

-- Enemies get the Act's health and damage; extra is added on top (the Fallen Knight's army)
local function ScaleEnemies(enemies, act, extra)
    for _, enemy in ipairs(enemies) do
        enemy.MaxHealth = ExpeditionRules.GetEnemyHealth(enemy.Type, act)
        enemy.DamageBonus = ExpeditionRules.GetEnemyDamageBonus(enemy.Type, act)

        if extra and enemy.Type ~= "FallenKnight" then
            enemy.MaxHealth += extra.Health
            enemy.DamageBonus += extra.Damage
        end
    end

    return enemies
end

local function GetBattleEnemies(run, node)
    local region = ExpeditionRules.GetRegion(run)
    local points = ExpeditionRules.GetPoints(run, node.Type)
    local kind = node.Type == "Battle" and "Battle" or node.Type
    local enemies = EncounterRules.Generate(points, kind, nil, {Pool = region.EnemyPool})

    -- The region's boss King fights with its class
    for _, enemy in ipairs(enemies) do
        if enemy.Type == "King" then
            enemy.Class = region.BossClass
        end
    end

    return ScaleEnemies(enemies, run.Act)
end

local function GetEncounterEnemies(run)
    local encounter = run.Encounter
    local region = ExpeditionRules.GetRegion(run)

    if encounter.Name == "Ambush" then
        local enemies = EncounterRules.Generate(run.Points, "Battle", nil, {Pool = region.EnemyPool, Ambush = MysteryConfig.Ambush})

        return ScaleEnemies(enemies, run.Act)
    elseif encounter.Name == "FallenKnight" then
        local knight = ExpeditionConfig.Exclusives.FallenKnight
        local points = math.max(run.Points - knight.POINTS, 0)
        local enemies = EncounterRules.Generate(points, "Battle", nil, {Pool = knight.POOL, Taken = {knight.TILE}})

        ScaleEnemies(enemies, run.Act, knight.ArmyBonus)

        table.insert(enemies, 1, {
            Type = "FallenKnight",
            Column = knight.TILE[1],
            Row = knight.TILE[2],
            MaxHealth = PieceConfig.Health.FallenKnight,
            DamageBonus = 0,
        })

        return enemies
    elseif Encounters[encounter.Name] then
        return ScaleEnemies(Encounters[encounter.Name].GetEnemies(run), run.Act)
    end

    return nil
end

-- Pays out what the King picked up during a Regional Encounter (the Haunted Mansion's chests)
local function PayCollected(run, rules, summary)
    for _, chest in ipairs(rules and rules.Collected or {}) do
        if chest == "Gold" then
            local gold = ExpeditionConfig.Exclusives.HauntedMansion.CHEST_GOLD
            run.Gold += gold
            summary.Gold += gold
        elseif chest == "Artifact" then
            local artifact = GiveArtifact(run)

            -- No Artifacts left to find (or none made yet): Silver instead
            if artifact then
                summary.Artifact = artifact
                summary.ArtifactPending = run.PendingArtifact ~= nil
            else
                local silver = ExpeditionConfig.Exclusives.HauntedMansion.ARTIFACT_SILVER
                run.Silver += silver
                summary.Silver += silver
            end
        end
    end
end

-- A Regional Encounter lost without the King dying (the payload destroyed): no reward, the run goes on
local function FailEncounter(player, run, nodeId, node)
    local summary = NewSummary(run, nodeId, node.Type)
    summary.Encounter = run.Encounter.Name
    summary.Failed = true

    return CompleteNode(player, run, nodeId, summary)
end

-- What winning gives: battles raise the allocation (Elites also drop an Artifact), encounter fights pay out
-- and never raise it, and the Fallen Knight joins the run
local function CompleteFight(player, run, nodeId, node, isEncounter, rules)
    local summary = NewSummary(run, nodeId, node.Type)

    if isEncounter then
        summary.Encounter = run.Encounter.Name
        AddReward(run, "EncounterFight", summary)
        PayCollected(run, rules, summary)

        if run.Encounter.Name == "FallenKnight" then
            local health = PieceConfig.Health.FallenKnight
            run.Companion = {Health = health, MaxHealth = health}
            summary.Companion = true
        end

        return CompleteNode(player, run, nodeId, summary)
    end

    AddReward(run, node.Type, summary)

    if node.Type == "Battle" or node.Type == "Elite" then
        run.Points += ExpeditionConfig.Enemies.POINTS_PER_BATTLE
    end

    if node.Type == "Elite" then
        summary.Artifact = GiveArtifact(run)
        summary.ArtifactPending = run.PendingArtifact ~= nil
    end

    return CompleteNode(player, run, nodeId, summary)
end

-- A battle node the run can move to, or the node whose encounter has a fight waiting
function ExpeditionService.CreateMatch(player, nodeId)
    local run = GetRun(player)
    if not run then return nil end
    if run.PendingArtifact then return nil end

    local node = ExpeditionRules.GetNode(run, nodeId)
    if not node then return nil end

    local isEncounter = run.Encounter ~= nil and run.Encounter.Node == nodeId and run.Encounter.Fight == true
    local enemies = nil

    if isEncounter then
        enemies = GetEncounterEnemies(run)
    elseif ExpeditionRules.GetNodeState(run, nodeId) == "Available" then
        -- The dev panel can start any kind of battle on whatever node comes next
        if run.DevBattle then
            node = {Type = run.DevBattle}
            run.DevBattle = nil
        end

        if ExpeditionRules.IsBattle(node.Type) then
            enemies = GetBattleEnemies(run, node)
        end
    end

    if not enemies then return nil end

    local act = run.Act
    local upgrades = run.Upgrades
    local shotgun, class = LoadoutService.GetLoadout(player)
    local match = MatchClass.new(player, shotgun, class, enemies, ExpeditionConfig.AI_RATING)

    local encounterModule = isEncounter and Encounters[run.Encounter.Name]
    if encounterModule then
        match.Rules = encounterModule.new(run)
    end

    match.RegionAI = ExpeditionRules.GetRegion(run)
    match.SummonBonus = {Health = upgrades.SummonHealth, Damage = upgrades.SummonDamage}
    match.ScaleEnemy = function(pieceType)
        return ExpeditionRules.GetEnemyHealth(pieceType, act), ExpeditionRules.GetEnemyDamageBonus(pieceType, act)
    end

    -- The King carries his health and upgrades from battle to battle
    local king = match.King
    local side = match.Sides.White

    king.MaxHealth = run.MaxHealth
    king.Health = run.Health
    king.DamageBonus = upgrades.Damage
    king:SetAmmoBonus(ExpeditionRules.GetAmmoBonus(run, shotgun))

    side.UltimateCharge = upgrades.StartCharge
    side.MaxEnergy = math.max(side.MaxEnergy + upgrades.Energy, 1)

    -- Ambushed mid-road: the King starts in the middle of the board with the army all around him
    if isEncounter and run.Encounter.Name == "Ambush" then
        king.Column, king.Row = MysteryConfig.Ambush.KING_TILE[1], MysteryConfig.Ambush.KING_TILE[2]
    end

    -- Regional Encounters start the King where their board needs him
    if match.Rules and match.Rules.KingTile then
        king.Column, king.Row = match.Rules.KingTile[1], match.Rules.KingTile[2]
    end

    -- So does the Fallen Knight, who starts beside the King
    if run.Companion then
        match.CompanionStart = {
            Type = "FallenKnight",
            Column = king.Column + ExpeditionConfig.COMPANION_OFFSET,
            Row = king.Row,
            Health = run.Companion.Health,
        }
    end

    match.OnEnd = function(result)
        -- The run may have been abandoned or replaced while the fight went on
        if GetRun(player) ~= run then return end

        local summary = nil

        if result == "Victory" or result == "Failed" then
            -- A failed encounter still ends with the King alive, but without the after-battle heal
            local heal = result == "Victory" and upgrades.HealAfterBattle or 0
            run.Health = math.min(king.Health + heal, run.MaxHealth)

            if run.Companion then
                local companion = match.Companion
                run.Companion.Health = companion and companion:IsAlive() and companion.Health or 0

                if run.Companion.Health <= 0 then
                    run.Companion = nil
                end
            end

            if result == "Victory" then
                summary = CompleteFight(player, run, nodeId, node, isEncounter, match.Rules)
            else
                summary = FailEncounter(player, run, nodeId, node)
            end
        else
            summary = FailRun(player, nodeId)
        end

        SendResult(player, summary)
    end

    return match
end

--ENCOUNTERS--

local function SendEncounter(player, run)
    local encounter = run.Encounter

    local data = {
        Node = encounter.Node,
        Kind = encounter.Kind,
        Name = encounter.Name,
        Fight = encounter.Fight,
    }

    if encounter.Treasure then
        data.Digs = encounter.Treasure.Digs
    end

    if encounter.Kind == "Shop" then
        data.Stock = run.Shops[run.Act .. "." .. encounter.Node]
    end

    ExpeditionRemote:FireClient(player, "Encounter", data)
end

local function NewShopStock(run)
    local options = GetArtifactOptions(run)
    local random = Random.new()
    random:Shuffle(options)

    local stock = {}

    for i = 1, math.min(ExpeditionConfig.Shop.INVENTORY_SIZE, #options) do
        local name = options[i]
        table.insert(stock, {Name = name, Price = ArtifactConfig.Pool[name].Price, Sold = false})
    end

    return stock
end

-- Rolls what waits on the node; kept in the run so leaving and coming back can't reroll it
local function OpenEncounter(player, run, nodeId, node)
    local random = Random.new()
    local encounter = {Node = nodeId, Kind = node.Type}

    if node.Type == "Rest" then
        encounter.Name = "Rest"
    elseif node.Type == "Shop" then
        encounter.Name = "Shop"

        local key = run.Act .. "." .. nodeId
        run.Shops[key] = run.Shops[key] or NewShopStock(run)
    else
        local name, isExclusive = ExpeditionRules.RollMystery(run, random)

        -- Dev testing can pin the next encounter
        if run.DevEncounter then
            name = run.DevEncounter
            isExclusive = ExpeditionConfig.Exclusives[name] ~= nil
            run.DevEncounter = nil
        end

        run.LastMystery = name

        -- Regional Encounters happen once per run
        if isExclusive then
            table.insert(run.UsedExclusives, name)
        end

        encounter.Name = name

        if name == "Treasure" then
            encounter.Treasure = {
                Column = random:NextInteger(1, TreasureConfig.SIZE),
                Row = random:NextInteger(1, TreasureConfig.SIZE),
                Digs = {},
            }
        end
    end

    run.Encounter = encounter

    -- Some encounters go straight to their fight once their rules are shown
    if FORCED_FIGHTS[encounter.Name] then
        encounter.Fight = true
    end

    Changed(player)
    SendEncounter(player, run)
end

-- Entering a non-battle node, or coming back to the one left open
local function Enter(player, nodeId)
    local run = GetRun(player)
    if not run or run.PendingArtifact then return end

    local node = ExpeditionRules.GetNode(run, nodeId)
    if not node or ExpeditionRules.IsBattle(node.Type) then return end

    local state = ExpeditionRules.GetNodeState(run, nodeId)

    if state == "Current" then
        ProfileService.Sync(player)
        SendEncounter(player, run)
        return
    end

    if state ~= "Available" then return end

    OpenEncounter(player, run, nodeId, node)
end

local function GetOpenEncounter(player, nodeId)
    local run = GetRun(player)
    if not run then return nil end

    local encounter = run.Encounter
    if not encounter or encounter.Node ~= nodeId then return nil end

    return run, encounter
end

-- The checkpoint is taken before the choice, so dying brings the player back here to choose again
local function Rest(player, run, encounter, choice)
    if not table.find(REST_CHOICES, choice) then return end

    if run.Mode == "Normal" then
        run.Checkpoint = ExpeditionRules.CopyRun(run)
    end

    local summary = NewSummary(run, encounter.Node, "Rest")
    summary.Choice = choice
    summary.Checkpoint = run.Mode == "Normal"

    if choice == "Rest" then
        local heal = ExpeditionRules.GetRestHeal(run)
        run.Health += heal
        summary.Healed = heal

        local companion = run.Companion
        if companion then
            companion.Health += math.ceil((companion.MaxHealth - companion.Health) * ExpeditionConfig.Rest.HEAL_MISSING)
        end
    else
        run.Upgrades.Ammo += 1
    end

    AddReward(run, "Rest", summary)
    SendResult(player, CompleteNode(player, run, encounter.Node, summary))
end

-- Applies a Mystery choice; returns false when the choice isn't allowed
local function ApplyChoice(player, run, encounter, choice, extra, summary)
    local name = encounter.Name
    local upgrades = run.Upgrades

    if not ExpeditionRules.CanChoose(run, name, choice, extra) then return false end

    if name == "Gunsmith" and choice == "Upgrade" then
        run.Silver -= MysteryConfig.Gunsmith.COST
        upgrades.Damage += MysteryConfig.Gunsmith.DAMAGE
    elseif name == "Altar" then
        local altar = MysteryConfig.Altar

        if choice == "Blood" then
            run.Health -= altar.BLOOD_COST
            run.MaxHealth += altar.BLOOD_HEALTH
        elseif choice == "Royal" then
            run.Health -= altar.ROYAL_COST
            upgrades.Damage += altar.ROYAL_DAMAGE
        end
    elseif name == "Barracks" then
        if choice == "Armor" then
            upgrades.SummonHealth += MysteryConfig.Barracks.HEALTH
        else
            upgrades.SummonDamage += MysteryConfig.Barracks.DAMAGE
        end
    elseif name == "Doctor" then
        if choice == "Treatment" then
            run.Health = run.MaxHealth
        else
            run.MaxHealth += MysteryConfig.Doctor.VITALITY
            run.Health += MysteryConfig.Doctor.VITALITY
        end
    elseif name == "HolyRook" then
        local holyRook = MysteryConfig.HolyRook

        if choice == "Power" then
            upgrades.StartCharge = math.min(upgrades.StartCharge + holyRook.POWER_CHARGE, 100)
            run.MaxHealth -= holyRook.POWER_HEALTH
            run.Health = math.min(run.Health, run.MaxHealth)
        else
            upgrades.HealAfterBattle += holyRook.VITALITY_HEAL
            upgrades.Energy -= holyRook.VITALITY_ENERGY
        end
    elseif name == "Ambush" and choice == "Endure" then
        run.Health -= MysteryConfig.Ambush.DAMAGE
    elseif name == "Gambler" and choice == "Wager" then
        local wager = MysteryConfig.Gambler.WAGERS[extra]
        local isWin = Random.new():NextNumber() < MysteryConfig.Gambler.WIN_CHANCE

        run.Silver += isWin and wager or -wager
        summary.Wager = wager
        summary.Won = isWin
    end

    return true
end

local function Choose(player, nodeId, choice, extra)
    if typeof(choice) ~= "string" then return end

    local run, encounter = GetOpenEncounter(player, nodeId)
    if not run then return end

    if encounter.Kind == "Rest" then
        Rest(player, run, encounter, choice)
        return
    end

    if encounter.Kind ~= "Mystery" then return end
    if encounter.Fight or encounter.Treasure then return end

    -- Fights start a match on this node; the result arrives when it ends
    if choice == "Challenge" then
        if not ExpeditionRules.CanChoose(run, encounter.Name, choice) then return end

        encounter.Fight = true
        Changed(player)
        ExpeditionRemote:FireClient(player, "EncounterFight", {Node = nodeId})
        return
    end

    local summary = NewSummary(run, nodeId, encounter.Kind)
    summary.Encounter = encounter.Name
    summary.Choice = choice

    if not ApplyChoice(player, run, encounter, choice, extra, summary) then return end

    AddReward(run, "Encounter", summary)
    SendResult(player, CompleteNode(player, run, nodeId, summary))
end

local function IsTile(value)
    return typeof(value) == "number" and value % 1 == 0 and value >= 1 and value <= TreasureConfig.SIZE
end

local function Dig(player, nodeId, column, row)
    if not IsTile(column) or not IsTile(row) then return end

    local run, encounter = GetOpenEncounter(player, nodeId)
    if not run then return end

    local treasure = encounter.Treasure
    if not treasure then return end

    for _, dug in ipairs(treasure.Digs) do
        if dug[1] == column and dug[2] == row then return end
    end

    table.insert(treasure.Digs, {column, row})

    local isFound = ExpeditionRules.IsDigHit(column, row, treasure.Column, treasure.Row)
    local digsLeft = TreasureConfig.DIGS - #treasure.Digs

    local result = {
        Node = nodeId,
        Column = column,
        Row = row,
        Found = isFound,
        DigsLeft = digsLeft,
    }

    if not isFound and digsLeft > 0 then
        Changed(player)
        ExpeditionRemote:FireClient(player, "Dig", result)
        return
    end

    -- The hunt is over: show where it was and pay out
    result.Done = true
    result.TreasureColumn = treasure.Column
    result.TreasureRow = treasure.Row

    ExpeditionRemote:FireClient(player, "Dig", result)

    local summary = NewSummary(run, nodeId, encounter.Kind)
    summary.Encounter = "Treasure"
    summary.Found = isFound

    local silver = ExpeditionRules.GetTreasureSilver(isFound and #treasure.Digs or nil)
    run.Silver += silver
    summary.Silver = silver
    AddReward(run, "Encounter", summary)

    SendResult(player, CompleteNode(player, run, nodeId, summary))
end

local function Buy(player, nodeId, index)
    if typeof(index) ~= "number" then return end

    local run, encounter = GetOpenEncounter(player, nodeId)
    if not run or encounter.Kind ~= "Shop" or run.PendingArtifact then return end

    local stock = run.Shops[run.Act .. "." .. nodeId]
    local item = stock and stock[index]
    if not item or item.Sold then return end
    if run.Silver < item.Price then return end
    if table.find(run.Artifacts, item.Name) then return end

    run.Silver -= item.Price
    item.Sold = true
    GiveArtifact(run, item.Name)

    Changed(player)
    SendEncounter(player, run)
end

local function LeaveShop(player, nodeId)
    local run, encounter = GetOpenEncounter(player, nodeId)
    if not run or encounter.Kind ~= "Shop" or run.PendingArtifact then return end

    local summary = NewSummary(run, nodeId, "Shop")
    SendResult(player, CompleteNode(player, run, nodeId, summary))
end

--STARTING AND ABANDONING--

local function Start(player, mode)
    if not table.find(ExpeditionConfig.MODES, mode) then return end

    local data = GetData(player)
    if not data or data.Expedition then return end

    data.Expedition = ExpeditionRules.NewRun(mode, Random.new())

    Changed(player)
    ExpeditionRemote:FireClient(player, "Started")
end

-- Abandoning forfeits everything in the pouch
local function Abandon(player)
    local data = GetData(player)
    if not data or not data.Expedition then return end

    data.Expedition = nil

    Changed(player)
    ExpeditionRemote:FireClient(player, "Abandoned")
end

-- Node types the dev panel can open besides the Mysteries and Regional Encounters
local DEV_NODE_TYPES = {Battle = true, Elite = true, Boss = true, Rest = true, Shop = true}

local function IsMysteryName(name)
    return table.find(MysteryConfig.ENCOUNTERS, name) ~= nil or ExpeditionConfig.Exclusives[name] ~= nil
end

-- Dev panel: opens any encounter right away on the next node, dropping whatever was left open
local function DevOpen(player, run, value)
    local isMystery = IsMysteryName(value)
    if not isMystery and not DEV_NODE_TYPES[value] then return end

    run.Encounter = nil
    run.DevBattle = nil

    local nodeId = nil

    for id in pairs(ExpeditionRules.GetMap(run).Nodes) do
        if ExpeditionRules.GetNodeState(run, id) == "Available" then
            nodeId = id
            break
        end
    end

    if not nodeId then return end

    if ExpeditionRules.IsBattle(value) then
        run.DevBattle = value
        Changed(player)
        ExpeditionRemote:FireClient(player, "EncounterFight", {Node = nodeId})
    elseif isMystery then
        run.DevEncounter = value
        OpenEncounter(player, run, nodeId, {Type = "Mystery"})
    else
        OpenEncounter(player, run, nodeId, {Type = value})
    end
end

-- Developer shortcuts for testing: pin the next encounter, open one right away on the next node, or jump to an
-- Act's map
local function DevAction(player, action, value)
    if not DevConfig.IsDev(player) then return end

    local run = GetRun(player)
    if not run then return end

    if action == "DevOpen" then
        DevOpen(player, run, value)
        return
    elseif action == "DevEncounter" then
        if not IsMysteryName(value) then return end

        run.DevEncounter = value
    elseif action == "DevAct" then
        if not ExpeditionConfig.Acts[value] then return end

        run.Act = value
        run.Path = {}
        run.Encounter = nil
        run.Points = ExpeditionRules.GetStartPoints(run.Mode, value)
    end

    Changed(player)
end

local init = false
function ExpeditionService.Init()
    if init then return end
    init = true

    ExpeditionRemote.OnServerEvent:Connect(function(player, action, first, second, third)
        if action == "Start" then
            Start(player, first)
        elseif action == "Abandon" then
            Abandon(player)
        elseif action == "Enter" then
            Enter(player, first)
        elseif action == "Choose" then
            Choose(player, first, second, third)
        elseif action == "Dig" then
            Dig(player, first, second, third)
        elseif action == "Buy" then
            Buy(player, first, second)
        elseif action == "LeaveShop" then
            LeaveShop(player, first)
        elseif action == "Artifact" then
            ResolveArtifact(player, first, second)
        elseif action == "DevEncounter" or action == "DevOpen" or action == "DevAct" then
            DevAction(player, action, first)
        end
    end)
end

return ExpeditionService
