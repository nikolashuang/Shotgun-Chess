local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DevConfig = require(ReplicatedStorage.Shared.Player.DevConfig)
local ProgressionConfig = require(ReplicatedStorage.Shared.Player.ProgressionConfig)
local ProgressionRules = require(ReplicatedStorage.Shared.Player.ProgressionRules)
local ShotgunConfig = require(ReplicatedStorage.Shared.Combat.ShotgunConfig)
local ClassConfig = require(ReplicatedStorage.Shared.Combat.ClassConfig)
local CampaignConfig = require(ReplicatedStorage.Shared.Campaign.CampaignConfig)
local CampaignRules = require(ReplicatedStorage.Shared.Campaign.CampaignRules)
local ProfileService = require(ServerScriptService.Player.ProfileService)

local DevRemote = ReplicatedStorage.Remotes.DevRemote

-- Testing shortcuts for the accounts in DevConfig; every request is checked here, never on the client
local DevService = {}

local function GetExpForLevel(level)
    local total = 0

    for current = ProgressionConfig.START_LEVEL, level - 1 do
        total += ProgressionRules.GetExpToLevel(current)
    end

    return total
end

-- Owns every shotgun and class, clears every campaign node and raises the level to the Duels unlock
local function UnlockAll(data)
    for name in pairs(ShotgunConfig.Shotguns) do
        data.Shotguns[name] = true
    end

    for name in pairs(ClassConfig.Classes) do
        data.Classes[name] = true
    end

    for regionId, region in pairs(CampaignConfig.Regions) do
        for nodeId in pairs(region.Nodes) do
            data.Nodes[CampaignRules.GetNodeKey(regionId, nodeId)] = true
        end
    end

    data.Exp = math.max(data.Exp, GetExpForLevel(ProgressionConfig.DUELS_UNLOCK_LEVEL))
end

local init = false
function DevService.Init()
    if init then return end
    init = true

    DevRemote.OnServerEvent:Connect(function(player, action)
        if not DevConfig.IsDev(player) then return end

        local profile = ProfileService.Get(player)
        if not profile then return end

        if action == "UnlockAll" then
            UnlockAll(profile.Data)
        elseif action == "AddGold" then
            ProfileService.AddGold(player, DevConfig.GOLD_GRANT)
        elseif action == "Reset" then
            ProfileService.Reset(player)
        else
            return
        end

        ProfileService.Sync(player)
    end)
end

return DevService
