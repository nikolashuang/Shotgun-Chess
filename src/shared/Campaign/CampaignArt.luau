-- Uploaded images, built by art/tools/build_campaign_art.py
local CampaignArt = {
    LOGO = "rbxassetid://77550011946469",

    NODE_ICONS = "rbxassetid://102924180242957",
    -- Pixels per icon in the atlas, icons sit side by side in this order
    NODE_TILE = 100,
    NodeOrder = {Combat = 0, Rest = 1, Treasure = 2, Queen = 3, King = 4, Mystery = 5},

    -- World map islands rendered by art/tools/build_islands.py, ISLAND_SIZE pixels square
    -- Row 0 is the islands in color, row 1 the same islands grayed out, row 2 the chain and padlock layers
    ISLANDS = "rbxassetid://84139968706737",
    ISLAND_SIZE = 160,
    IslandColumn = {Training = 0, Forest = 1, Cliffside = 2, Outskirts = 3, Gravehollow = 4},
    LockColumn = {ChainA = 0, ChainB = 1, Lock = 2},

    -- Parchment behind every area map
    PAPER = "rbxassetid://96902313749636",

    -- Rest Site campfire, built by art/tools/build_rest_camp.py and build_rest_art.py
    -- The fire sheet plays over the background; each version (party, or the Fallen Knight) has its own rows
    REST_BACKGROUND = "rbxassetid://133730252181741",
    REST_FIRE = "rbxassetid://118720635859055",
    REST_FIRE_FRAME = Vector2.new(195, 75),
    REST_FIRE_FRAMES = 8,
    REST_FIRE_COLUMNS = 4,
    REST_FIRE_TIME = 0.12,
    RestFireRow = {Party = 0, Knight = 2},
    -- Where the fire sheet sits on the background, as fractions of it: x, y, width, height
    REST_FIRE_RECT = {480 / 1672, 350 / 941, 780 / 1672, 300 / 941},
    REST_ASPECT = 1672 / 941,
}

return CampaignArt
