local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local ShopConfig = require(ReplicatedStorage.Shared.Shop.ShopConfig)
local ProfileService = require(ServerScriptService.Player.ProfileService)

-- Grants Robux purchases (gold packs, 2x boosts, donations)
-- Each purchase is granted once: its id is saved with the profile before Roblox is told it went through
local PurchaseService = {}

local function Grant(player, product)
    local item = product.Item

    if product.Kind == "Gold" then
        ProfileService.AddGold(player, item.Gold)
    elseif product.Kind == "Boost" then
        ProfileService.AddBoost(player, item.Kind, ShopConfig.BOOST_SECONDS)
    end
    -- Donations grant nothing
end

local function ProcessReceipt(receipt)
    local player = Players:GetPlayerByUserId(receipt.PlayerId)
    if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end

    local product = ShopConfig.GetProduct(receipt.ProductId)
    if not product then
        warn("[PurchaseService] Unknown product " .. tostring(receipt.ProductId))
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end

    -- Roblox retries the receipt later, so a profile that hasn't loaded yet just waits
    local profile = ProfileService.Get(player)
    if not profile then return Enum.ProductPurchaseDecision.NotProcessedYet end

    if ProfileService.HasReceipt(player, receipt.PurchaseId) then
        return Enum.ProductPurchaseDecision.PurchaseGranted
    end

    Grant(player, product)
    ProfileService.AddReceipt(player, receipt.PurchaseId)
    ProfileService.Sync(player)

    -- A temporary profile (DataStores off, as in Studio without API access) can't be saved; the grant still stands
    if profile.CanSave and not ProfileService.Save(player) then
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end

    return Enum.ProductPurchaseDecision.PurchaseGranted
end

local init = false
function PurchaseService.Init()
    if init then return end
    init = true

    MarketplaceService.ProcessReceipt = ProcessReceipt
end

return PurchaseService
