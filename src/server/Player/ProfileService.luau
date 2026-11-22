local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ProgressionConfig = require(ReplicatedStorage.Shared.Player.ProgressionConfig)
local ProgressionRules = require(ReplicatedStorage.Shared.Player.ProgressionRules)
local SettingsConfig = require(ReplicatedStorage.Shared.Player.SettingsConfig)
local KeybindConfig = require(ReplicatedStorage.Shared.Player.KeybindConfig)
local ShotgunConfig = require(ReplicatedStorage.Shared.Combat.ShotgunConfig)
local CampaignConfig = require(ReplicatedStorage.Shared.Campaign.CampaignConfig)
local CampaignRules = require(ReplicatedStorage.Shared.Campaign.CampaignRules)

local ProfileRemote = ReplicatedStorage.Remotes.ProfileRemote

local STORE_NAME = "PlayerProfile_v1"
local LOAD_ATTEMPTS = 3
local AUTOSAVE_INTERVAL = 120

local store = nil
local Profiles = {}

-- Persistent player data: gold, exp, owned shotguns, unlocked classes, campaign progress and runs, and loadout
-- Gold, Level and Exp are mirrored to player attributes; the rest is sent to the client as a snapshot
local ProfileService = {}

local function NewData()
    return {
        Gold = ProgressionConfig.START_GOLD,
        Exp = 0,
        Shotguns = {[ShotgunConfig.STARTER] = true},
        Classes = {},
        Nodes = {},
        -- Region -> the campaign run in progress there
        Runs = {},
        Equipped = {
            Shotgun = ShotgunConfig.STARTER,
            Class = nil,
        },
        Settings = table.clone(SettingsConfig.DEFAULTS),
        -- Action -> Enum.KeyCode name, only for actions moved off their default key
        Keybinds = {},
    }
end

-- Fills in fields added after a profile was first saved
local function Reconcile(data)
    local default = NewData()

    for key, value in pairs(default) do
        if data[key] == nil then
            data[key] = value
        end
    end

    data.Shotguns[ShotgunConfig.STARTER] = true

    for name, value in pairs(SettingsConfig.DEFAULTS) do
        if data.Settings[name] == nil then
            data.Settings[name] = value
        end
    end

    return data
end

-- keybinds is action -> Enum.KeyCode name; returns only the ones that differ from the defaults,
-- or nil if anything is invalid (unknown action or key, reserved key, or a key bound twice)
local function ValidateKeybinds(keybinds)
    if typeof(keybinds) ~= "table" then return nil end

    local saved = {}
    local used = {}

    for _, action in ipairs(KeybindConfig.ORDER) do
        local keyName = keybinds[action] or KeybindConfig.Defaults[action]
        if typeof(keyName) ~= "string" then return nil end
        if table.find(KeybindConfig.RESERVED, keyName) then return nil end
        if used[keyName] then return nil end

        local isKey = pcall(function()
            return Enum.KeyCode[keyName]
        end)
        if not isKey then return nil end

        used[keyName] = true

        if keyName ~= KeybindConfig.Defaults[action] then
            saved[action] = keyName
        end
    end

    return saved
end

-- Dev regions are for testing only: their runs and cleared nodes are never written to the DataStore
local function StripDevRegions(data)
    local stripped = table.clone(data)
    stripped.Runs = table.clone(data.Runs)
    stripped.Nodes = table.clone(data.Nodes)

    for regionId, region in pairs(CampaignConfig.Regions) do
        if not region.DevOnly then continue end

        stripped.Runs[regionId] = nil
        local prefix = regionId .. "."

        for key in pairs(data.Nodes) do
            if string.sub(key, 1, #prefix) == prefix then
                stripped.Nodes[key] = nil
            end
        end
    end

    return stripped
end

local function LoadData(player)
    if not store then return nil end

    for _ = 1, LOAD_ATTEMPTS do
        local ok, result = pcall(function()
            return store:GetAsync(tostring(player.UserId))
        end)

        -- Runs are saved as they stand, so leaving mid-region picks up exactly where the player left
        if ok then return StripDevRegions(Reconcile(result or NewData())) end

        warn("[ProfileService] Load failed for " .. player.Name .. ": " .. tostring(result))
        task.wait(1)
    end

    return nil
end

function ProfileService.Get(player)
    return Profiles[player]
end

function ProfileService.Sync(player)
    local profile = Profiles[player]
    if not profile then return end

    local data = profile.Data
    local level, exp = ProgressionRules.GetLevel(data.Exp)

    player:SetAttribute("Gold", data.Gold)
    player:SetAttribute("Level", level)
    player:SetAttribute("Exp", exp)
    player:SetAttribute("Shotgun", data.Equipped.Shotgun)
    player:SetAttribute("Class", data.Equipped.Class)
    -- Matches read this to shorten the wait for enemy animations
    player:SetAttribute("GameSpeed", SettingsConfig.SPEEDS[data.Settings.Speed] or 1)

    ProfileRemote:FireClient(player, "Profile", {
        Shotguns = data.Shotguns,
        Classes = data.Classes,
        Nodes = data.Nodes,
        Runs = CampaignRules.GetClientRuns(data.Runs),
        Settings = data.Settings,
        Keybinds = data.Keybinds,
    })
end

function ProfileService.AddGold(player, amount)
    local profile = Profiles[player]
    if not profile then return end

    profile.Data.Gold += amount
end

function ProfileService.SpendGold(player, amount)
    local profile = Profiles[player]
    if not profile then return false end
    if profile.Data.Gold < amount then return false end

    profile.Data.Gold -= amount

    return true
end

function ProfileService.AddExp(player, amount)
    local profile = Profiles[player]
    if not profile then return end

    profile.Data.Exp += amount
end

-- Wipes the player back to a new profile; saving stays allowed only if their data loaded
function ProfileService.Reset(player)
    local profile = Profiles[player]
    if not profile then return end

    profile.Data = NewData()
end

-- Throws away the player's dev region progress so the next visit starts fresh
function ProfileService.ResetDevRegions(player)
    local profile = Profiles[player]
    if not profile then return end

    profile.Data = StripDevRegions(profile.Data)
end

function ProfileService.Save(player)
    local profile = Profiles[player]
    if not profile then return end

    -- Profiles that failed to load are never saved so they can't overwrite real data
    if not profile.CanSave then return end
    -- Already saved for a teleport; a later save could overwrite what the next place writes
    if profile.isTeleporting then return end

    local ok, result = pcall(function()
        store:UpdateAsync(tostring(player.UserId), function()
            return StripDevRegions(profile.Data)
        end)
    end)

    if not ok then
        warn("[ProfileService] Save failed for " .. player.Name .. ": " .. tostring(result))
    end
end

-- Saves now and stops this server saving the player again, so the place they teleport to loads their latest data
function ProfileService.SaveForTeleport(player)
    ProfileService.Save(player)

    local profile = Profiles[player]
    if profile then
        profile.isTeleporting = true
    end
end

-- The teleport failed and the player is staying, so this server saves them again
function ProfileService.CancelTeleport(player)
    local profile = Profiles[player]
    if profile then
        profile.isTeleporting = false
    end
end

local function SetupPlayer(player)
    local data = LoadData(player)
    if not player.Parent then return end

    if not data then
        warn("[ProfileService] Using a temporary profile for " .. player.Name .. ", progress won't be saved")
    end

    Profiles[player] = {
        Data = data or NewData(),
        CanSave = data ~= nil,
    }

    ProfileService.Sync(player)
end

local init = false
function ProfileService.Init()
    if init then return end
    init = true

    local ok, result = pcall(function()
        return DataStoreService:GetDataStore(STORE_NAME)
    end)

    if ok then
        store = result
    else
        warn("[ProfileService] DataStores unavailable: " .. tostring(result))
    end

    Players.PlayerAdded:Connect(SetupPlayer)

    for _, player in pairs(Players:GetPlayers()) do
        task.spawn(SetupPlayer, player)
    end

    Players.PlayerRemoving:Connect(function(player)
        ProfileService.Save(player)
        Profiles[player] = nil
    end)

    game:BindToClose(function()
        for player in pairs(Profiles) do
            task.spawn(ProfileService.Save, player)
        end

        task.wait(2)
    end)

    ProfileRemote.OnServerEvent:Connect(function(player, action, name, value)
        if action == "Request" then
            ProfileService.Sync(player)
        elseif action == "SetSetting" then
            local profile = Profiles[player]
            if not profile then return end

            -- Only known settings, and only values of the default's type
            local default = SettingsConfig.DEFAULTS[name]
            if default == nil then return end
            if typeof(value) ~= typeof(default) then return end
            -- Number settings are volumes
            if typeof(value) == "number" and not (value >= 0 and value <= 1) then return end
            if typeof(value) == "string" and not table.find(SettingsConfig.OPTIONS[name] or {}, value) then return end

            profile.Data.Settings[name] = value

            if name == "Speed" then
                player:SetAttribute("GameSpeed", SettingsConfig.SPEEDS[value])
            end
        elseif action == "SetKeybinds" then
            local profile = Profiles[player]
            if not profile then return end

            local keybinds = ValidateKeybinds(name)
            if not keybinds then return end

            profile.Data.Keybinds = keybinds
        end
    end)

    task.spawn(function()
        while true do
            task.wait(AUTOSAVE_INTERVAL)

            for player in pairs(Profiles) do
                task.spawn(ProfileService.Save, player)
            end
        end
    end)
end

return ProfileService
