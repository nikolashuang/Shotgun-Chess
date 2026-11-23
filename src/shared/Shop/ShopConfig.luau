-- ProductIds are the experience's Developer Products (product icons are in art/shop); 0 means not created yet
local ShopConfig = {
    -- Skin crate prices live in SkinConfig

    -- Shop order, top to bottom; the 50k pack is the best gold per Robux (35.7, against 33.3 for 100k)
    -- Pulse makes the tag grow and shrink
    GoldPacks = {
        {Id = "Gold1k", ProductId = 3734583626, Gold = 1000, Robux = 50},
        {Id = "Gold10k", ProductId = 3734583743, Gold = 10000, Robux = 400},
        {Id = "Gold50k", ProductId = 3734583764, Gold = 50000, Robux = 1400, Tag = "Best Value!!!", Pulse = true},
        {Id = "Gold100k", ProductId = 3734583790, Gold = 100000, Robux = 3000},
    },

    -- Each purchase adds BOOST_SECONDS of play time; time only runs down while the player is in the game
    BOOST_SECONDS = 3600,
    Boosts = {
        {Id = "GoldBoost", ProductId = 3734583919, Kind = "Gold", DisplayName = "2x Gold", Robux = 50},
        {Id = "ExpBoost", ProductId = 3734583935, Kind = "Exp", DisplayName = "2x XP", Robux = 50},
    },
    BOOST_MULTIPLIER = 2,

    Donations = {
        {Id = "Donate500", ProductId = 3734583958, Robux = 500},
        {Id = "Donate1000", ProductId = 3734583981, Robux = 1000},
        {Id = "Donate1500", ProductId = 3734584004, Robux = 1500},
        {Id = "Donate2000", ProductId = 3734584025, Robux = 2000},
    },
}

-- ProductId -> {Kind = "Gold" | "Boost" | "Donation", Item = the entry above}
function ShopConfig.GetProduct(productId)
    for kind, list in pairs({Gold = ShopConfig.GoldPacks, Boost = ShopConfig.Boosts, Donation = ShopConfig.Donations}) do
        for _, item in ipairs(list) do
            if item.ProductId ~= 0 and item.ProductId == productId then
                return {Kind = kind, Item = item}
            end
        end
    end

    return nil
end

return ShopConfig
