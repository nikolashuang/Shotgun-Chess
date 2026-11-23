local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ShotgunConfig = require(ReplicatedStorage.Shared.Combat.ShotgunConfig)
local ClassConfig = require(ReplicatedStorage.Shared.Combat.ClassConfig)
local SkinConfig = require(ReplicatedStorage.Shared.Skins.SkinConfig)
local ProfileService = require(ServerScriptService.Player.ProfileService)

local LoadoutRemote = ReplicatedStorage.Remotes.LoadoutRemote

-- Shotguns are bought with gold, classes are unlocked by defeating regional Kings, board skins come from crates
local LoadoutService = {}

function LoadoutService.IsUnlocked(player, kind, name)
    local profile = ProfileService.Get(player)
    if not profile then return false end

    if kind == "Shotgun" then return ShotgunConfig.Shotguns[name] ~= nil and profile.Data.Shotguns[name] == true end
    if kind == "Class" then return ClassConfig.Classes[name] ~= nil and profile.Data.Classes[name] == true end

    if kind == "BoardSkin" then
        local skin = SkinConfig.Skins.Board[name]
        return skin ~= nil and (skin.Starter == true or profile.Data.Skins.Board[name] == true)
    end

    return false
end

-- A nil class means the king plays with normal turns and summons only
function LoadoutService.GetLoadout(player)
    local profile = ProfileService.Get(player)
    if not profile then return ShotgunConfig.STARTER, ClassConfig.STARTER end

    local equipped = profile.Data.Equipped
    local shotgun = equipped.Shotgun
    local class = equipped.Class

    if not LoadoutService.IsUnlocked(player, "Shotgun", shotgun) then
        shotgun = ShotgunConfig.STARTER
    end

    if class and not LoadoutService.IsUnlocked(player, "Class", class) then
        class = nil
    end

    return shotgun, class
end

local function Equip(player, kind, name)
    if not LoadoutService.IsUnlocked(player, kind, name) then return end

    ProfileService.Get(player).Data.Equipped[kind] = name
    ProfileService.Sync(player)
end

local function UnequipClass(player)
    local profile = ProfileService.Get(player)
    if not profile then return end

    profile.Data.Equipped.Class = nil
    ProfileService.Sync(player)
end

local function BuyShotgun(player, name)
    local weapon = ShotgunConfig.Shotguns[name]
    if not weapon then return end

    local profile = ProfileService.Get(player)
    if not profile then return end
    if profile.Data.Shotguns[name] then return end
    if not ProfileService.SpendGold(player, weapon.Price) then return end

    profile.Data.Shotguns[name] = true
    ProfileService.Sync(player)
end

local init = false
function LoadoutService.Init()
    if init then return end
    init = true

    LoadoutRemote.OnServerEvent:Connect(function(player, action, kind, name)
        if kind ~= "Shotgun" and kind ~= "Class" and kind ~= "BoardSkin" then return end

        if action == "Unequip" then
            if kind ~= "Class" then return end

            UnequipClass(player)
            return
        end

        if typeof(name) ~= "string" then return end

        if action == "Equip" then
            Equip(player, kind, name)
        elseif action == "Buy" then
            if kind ~= "Shotgun" then return end

            BuyShotgun(player, name)
        end
    end)
end

return LoadoutService
