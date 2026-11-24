-- Uploaded images, built by art/tools/build_campaign_art.py
local CampaignArt = {
    LOGO = "rbxassetid://88380874545396",

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
    REST_FIRE = "rbxassetid://138717388200632",
    REST_FIRE_FRAME = Vector2.new(195, 100),
    REST_FIRE_FRAMES = 12,
    REST_FIRE_COLUMNS = 4,
    REST_FIRE_TIME = 0.09,
    RestFireRow = {Party = 0, Knight = 3},
    -- Where the fire sheet sits on the background, as fractions of it: x, y, width, height
    REST_FIRE_RECT = {480 / 1672, 250 / 941, 780 / 1672, 400 / 941},
    REST_ASPECT = 1672 / 941,
    -- The three choice cards on the Rest Site screen, built by art/tools/build_rest_cards.py, left to right
    REST_CARDS = "rbxassetid://135905483379568",
    REST_CARD_SIZE = Vector2.new(96, 72),
    RestCardOrder = {Rest = 0, Train = 1, Maintenance = 2},

    -- Mystery encounter screens, built by art/tools/build_mystery_art.py; every background is 1672x941 like the camp
    MysteryBackgrounds = {
        Altar = "rbxassetid://113565901767238",
        Ambush = "rbxassetid://91466943784949",
        Gunsmith = "rbxassetid://132885799635283",
        FallenKnight = "rbxassetid://122636487856177",
    },
    MYSTERY_ASPECT = 1672 / 941,
    -- The bishop at the anvil, built by art/tools/build_gunsmith.py; plays over the Gunsmith background
    GUNSMITH_SHEET = "rbxassetid://93677776912006",
    GUNSMITH_FRAME = Vector2.new(100, 100),
    GUNSMITH_FRAMES = 8,
    GUNSMITH_COLUMNS = 4,
    GUNSMITH_TIME = 0.11,
    GUNSMITH_RECT = {520 / 1672, 220 / 941, 400 / 1672, 400 / 941},
    -- The Fallen Knight's eye traced in teal, laid exactly over his eye on the background when he wakes
    -- Rect is x, y, width, height as fractions of the background; matches EYE_BOX in build_mystery_art.py
    EYE_WAKE = "rbxassetid://84506445068510",
    EYE_RECT = {944 / 1672, 460 / 941, 48 / 1672, 40 / 941},
}

return CampaignArt
