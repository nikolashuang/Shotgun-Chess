local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local SkinConfig = require(ReplicatedStorage.Shared.Skins.SkinConfig)
local ProfileService = require(ServerScriptService.Player.ProfileService)

local CrateRemote = ReplicatedStorage.Remotes.CrateRemote

local random = Random.new()

-- Opens skin crates for gold; rolls happen here so the client can't pick its drop
-- A duplicate refunds part of what that crate cost (a crate from a 10-pack cost a tenth of the pack)
local CrateService = {}

local function Open(player, crateId, count)
    local crate = SkinConfig.Crates[crateId]
    if not crate then return end
    if count ~= 1 and count ~= 10 then return end
    if not SkinConfig.CanOpen(crateId) then return end

    local profile = ProfileService.Get(player)
    if not profile then return end

    local price = count == 1 and crate.Price or crate.TenPrice
    if not ProfileService.SpendGold(player, price) then return end

    local owned = profile.Data.Skins[crate.Kind]
    local refund = math.floor(price / count * SkinConfig.DUPLICATE_REFUND)
    local results = {}

    for _ = 1, count do
        local name = SkinConfig.Roll(crateId, random:NextNumber(), random:NextNumber())
        local isDuplicate = owned[name] == true

        owned[name] = true

        if isDuplicate then
            ProfileService.AddGold(player, refund)
        end

        table.insert(results, {Name = name, Duplicate = isDuplicate, Refund = isDuplicate and refund or 0})
    end

    ProfileService.Sync(player)
    CrateRemote:FireClient(player, "Opened", crateId, results)
end

local init = false
function CrateService.Init()
    if init then return end
    init = true

    CrateRemote.OnServerEvent:Connect(function(player, action, crateId, count)
        if action ~= "Open" then return end
        if typeof(crateId) ~= "string" or typeof(count) ~= "number" then return end

        Open(player, crateId, count)
    end)
end

return CrateService
