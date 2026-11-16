local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ShotgunConfig = require(ReplicatedStorage.Shared.Combat.ShotgunConfig)
local ClassConfig = require(ReplicatedStorage.Shared.Combat.ClassConfig)

local LoadoutRemote = ReplicatedStorage.Remotes.LoadoutRemote

-- Equipped items are player attributes so the client menu can read them
local LoadoutService = {}

-- Everything is unlocked until the shop and gold are implemented
function LoadoutService.IsUnlocked(player, kind, name)
    if kind == "Shotgun" then return ShotgunConfig.Shotguns[name] ~= nil end
    if kind == "Class" then return ClassConfig.Classes[name] ~= nil end

    return false
end

function LoadoutService.GetLoadout(player)
    return player:GetAttribute("Shotgun") or ShotgunConfig.STARTER, player:GetAttribute("Class") or ClassConfig.STARTER
end

local function SetupPlayer(player)
    player:SetAttribute("Shotgun", ShotgunConfig.STARTER)
    player:SetAttribute("Class", ClassConfig.STARTER)
end

local init = false
function LoadoutService.Init()
    if init then return end
    init = true

    Players.PlayerAdded:Connect(SetupPlayer)

    for _, player in pairs(Players:GetPlayers()) do
        SetupPlayer(player)
    end

    LoadoutRemote.OnServerEvent:Connect(function(player, action, kind, name)
        if action ~= "Equip" then return end
        if kind ~= "Shotgun" and kind ~= "Class" then return end
        if typeof(name) ~= "string" then return end
        if not LoadoutService.IsUnlocked(player, kind, name) then return end

        player:SetAttribute(kind, name)
    end)
end

return LoadoutService
