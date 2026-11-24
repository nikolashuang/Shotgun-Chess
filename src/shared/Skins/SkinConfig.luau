-- Cosmetic skins and the crates that drop them
-- Board skins color the light and dark tiles; Epic boards also show one pixel image of the whole board
-- (art/skins/boards, 16 pixels per tile, row 10 at the top), each tile cut to its own square; 0 until uploaded
local SkinConfig = {
    DEFAULT_BOARD = "Classic",

    -- Lowest to highest; a rarity a crate has no skins for drops the next one down instead
    RARITY_ORDER = {"Common", "Rare", "Epic", "Legendary"},
    Rarities = {
        Common = {DisplayName = "Common", Color = Color3.fromHex("E9E3D6"), Weight = 80},
        Rare = {DisplayName = "Rare", Color = Color3.fromHex("6FA8DC"), Weight = 15},
        Epic = {DisplayName = "Epic", Color = Color3.fromHex("B07CD8"), Weight = 4.5},
        Legendary = {DisplayName = "Legendary", Color = Color3.fromHex("F2B544"), Weight = 0.5},
    },

    -- Duplicates refund this share of the gold paid for that crate
    DUPLICATE_REFUND = 0.1,

    CRATE_ORDER = {"Gameboard", "Shotgun", "Piece"},
    Crates = {
        Gameboard = {DisplayName = "Gameboard Crate", Kind = "Board", Price = 1000, TenPrice = 8000},
        Shotgun = {DisplayName = "Gun Skin Crate", Kind = "Shotgun", Price = 1000, TenPrice = 8000},
        Piece = {DisplayName = "Piece Skin Crate", Kind = "Piece", Price = 1000, TenPrice = 8000},
    },

    -- Kind -> skin list; Shotgun and Piece skins aren't designed yet, so their crates can't open
    Skins = {
        Board = {
            Classic = {DisplayName = "Classic", Rarity = "Common", Starter = true},

            Crimson = {DisplayName = "Crimson", Rarity = "Common", Light = Color3.fromHex("D98C7E"), Dark = Color3.fromHex("8E3B36")},
            Azure = {DisplayName = "Azure", Rarity = "Common", Light = Color3.fromHex("9DB7D5"), Dark = Color3.fromHex("3D5A80")},
            Onyx = {DisplayName = "Onyx", Rarity = "Common", Light = Color3.fromHex("5E5864"), Dark = Color3.fromHex("1E1B22")},
            Moss = {DisplayName = "Moss", Rarity = "Common", Light = Color3.fromHex("B7C98F"), Dark = Color3.fromHex("4F6B3A")},

            -- Accent is a thin inner border on every tile
            BlackGold = {DisplayName = "Black & Gold", Rarity = "Rare", Light = Color3.fromHex("D9B04C"), Dark = Color3.fromHex("1C1A1F"), Accent = Color3.fromHex("8C6A22")},
            IvoryCrimson = {DisplayName = "Ivory & Crimson", Rarity = "Rare", Light = Color3.fromHex("EDE4D0"), Dark = Color3.fromHex("8C1C2B"), Accent = Color3.fromHex("C9A66B")},
            Buckshot = {DisplayName = "Royal Buckshot", Rarity = "Rare", Light = Color3.fromHex("C9C2B8"), Dark = Color3.fromHex("3B3544"), Accent = Color3.fromHex("B8342F")},

            Ruined = {DisplayName = "Ruined Chessboard", Rarity = "Epic", Light = Color3.fromHex("A89C88"), Dark = Color3.fromHex("4A4038"), Image = 109582561838250},
            Castle = {DisplayName = "Abandoned Castle", Rarity = "Epic", Light = Color3.fromHex("8F8678"), Dark = Color3.fromHex("3E3A3F"), Image = 101685175471318},
        },
        Shotgun = {},
        Piece = {},
    },

    -- Display order in the Armory, by rarity then this list
    BOARD_IMAGE_TILE = 16,

    BOARD_ORDER = {"Classic", "Crimson", "Azure", "Onyx", "Moss", "BlackGold", "IvoryCrimson", "Buckshot", "Ruined", "Castle"},
}

-- Starter skins are owned by everyone and never drop
function SkinConfig.GetDroppable(kind, rarity)
    local names = {}

    for name, skin in pairs(SkinConfig.Skins[kind] or {}) do
        if skin.Rarity == rarity and not skin.Starter then
            table.insert(names, name)
        end
    end

    table.sort(names)

    return names
end

function SkinConfig.CanOpen(crateId)
    local crate = SkinConfig.Crates[crateId]
    if not crate then return false end

    for _, rarity in ipairs(SkinConfig.RARITY_ORDER) do
        if #SkinConfig.GetDroppable(crate.Kind, rarity) > 0 then return true end
    end

    return false
end

-- roll is in [0, 1); returns the skin name
function SkinConfig.Roll(crateId, rarityRoll, skinRoll)
    local crate = SkinConfig.Crates[crateId]
    local total = 0

    for _, rarity in ipairs(SkinConfig.RARITY_ORDER) do
        total += SkinConfig.Rarities[rarity].Weight
    end

    -- Highest rarity first, so the rare end of the roll is checked against the smallest weights
    local picked = SkinConfig.RARITY_ORDER[1]
    local threshold = total

    for i = #SkinConfig.RARITY_ORDER, 1, -1 do
        local rarity = SkinConfig.RARITY_ORDER[i]
        threshold -= SkinConfig.Rarities[rarity].Weight

        if rarityRoll * total >= threshold then
            picked = rarity
            break
        end
    end

    local index = table.find(SkinConfig.RARITY_ORDER, picked)

    for i = index, 1, -1 do
        local names = SkinConfig.GetDroppable(crate.Kind, SkinConfig.RARITY_ORDER[i])

        if #names > 0 then
            return names[math.floor(skinRoll * #names) + 1]
        end
    end

    return nil
end

return SkinConfig
