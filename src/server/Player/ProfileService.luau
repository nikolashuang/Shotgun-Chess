local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ProgressionConfig = require(ReplicatedStorage.Shared.Player.ProgressionConfig)
local ProgressionRules = require(ReplicatedStorage.Shared.Player.ProgressionRules)
local ShotgunConfig = require(ReplicatedStorage.Shared.Combat.ShotgunConfig)

local ProfileRemote = ReplicatedStorage.Remotes.ProfileRemote

local STORE_NAME = "PlayerProfile_v1"
local LOAD_ATTEMPTS = 3
local AUTOSAVE_INTERVAL = 120

local store = nil
local Profiles = {}

-- Persistent player data: gold, exp, owned shotguns, unlocked classes, cleared campaign nodes and loadout
-- Gold, Level and Exp are mirrored to player attributes; the rest is sent to the client as a snapshot
local ProfileService = {}

local function NewData()
    return {
        Gold = ProgressionConfig.START_GOLD,
        Exp = 0,
        Shotguns = {[ShotgunConfig.STARTER] = true},
        Classes = {},
        Nodes = {},
        Equipped = {
            Shotgun = ShotgunConfig.STARTER,
            Class = nil,
        },
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

    return data
end

local function LoadData(player)
    if not store then return nil end

    for _ = 1, LOAD_ATTEMPTS do
        local ok, result = pcall(function()
            return store:GetAsync(tostring(player.UserId))
        end)

        if ok then return Reconcile(result or NewData()) end

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

    ProfileRemote:FireClient(player, "Profile", {
        Shotguns = data.Shotguns,
        Classes = data.Classes,
        Nodes = data.Nodes,
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

function ProfileService.Save(player)
    local profile = Profiles[player]
    if not profile then return end

    -- Profiles that failed to load are never saved so they can't overwrite real data
    if not profile.CanSave then return end

    local ok, result = pcall(function()
        store:UpdateAsync(tostring(player.UserId), function()
            return profile.Data
        end)
    end)

    if not ok then
        warn("[ProfileService] Save failed for " .. player.Name .. ": " .. tostring(result))
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

    ProfileRemote.OnServerEvent:Connect(function(player, action)
        if action ~= "Request" then return end

        ProfileService.Sync(player)
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
