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

    -- Parchment behind every area map
    PAPER = "rbxassetid://96902313749636",
}

return CampaignArt
