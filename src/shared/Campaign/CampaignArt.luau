-- Uploaded images, built by art/tools/build_campaign_art.py
local CampaignArt = {
    LOGO = "rbxassetid://76189780619268",

    NODE_ICONS = "rbxassetid://119794303932713",
    -- Pixels per icon in the atlas, icons sit side by side in this order
    NODE_TILE = 100,
    NodeOrder = {Combat = 0, Rest = 1, Treasure = 2, Queen = 3, King = 4},

    -- World map islands rendered by art/tools/build_islands.py, ISLAND_SIZE pixels square
    -- Row 0 is the islands in color, row 1 the same islands grayed out, row 2 the chain and padlock layers
    ISLANDS = "rbxassetid://133568068913211",
    ISLAND_SIZE = 160,
    IslandColumn = {Training = 0, Forest = 1, Cliffside = 2, Outskirts = 3, Gravehollow = 4},
    LockColumn = {ChainA = 0, ChainB = 1, Lock = 2},

    -- Area map backgrounds: Size is the full painted panel; Scene is the part without the title banner and badge, used behind area maps
    Regions = {
        Training = {Image = "rbxassetid://109861305585942", Size = {480, 326}, Scene = {0, 52, 480, 236}},
        Forest = {Image = "rbxassetid://71484457402117", Size = {494, 326}, Scene = {0, 52, 494, 236}},
        Cliffside = {Image = "rbxassetid://70595856593672", Size = {490, 324}, Scene = {0, 52, 490, 234}},
        Outskirts = {Image = "rbxassetid://111929062853601", Size = {524, 296}, Scene = {0, 50, 524, 208}},
        Gravehollow = {Image = "rbxassetid://98556437228024", Size = {530, 296}, Scene = {0, 50, 530, 208}},
    },
}

return CampaignArt
