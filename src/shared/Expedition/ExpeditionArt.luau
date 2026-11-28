-- Uploaded images; Expedition map trims are built by art/tools/build_expedition_art.py into art/expedition/,
-- the encounter icons are art/expedition/expedition_encounter_icons.png (from expedition_encounter_icons.blend)
local ExpeditionArt = {
    LOGO = "rbxassetid://88380874545396",

    -- Painted encounter badges, NODE_TILE pixels each, side by side; built by art/tools/build_encounter_badges.py
    NODE_ICONS = "rbxassetid://133113025848681",
    NODE_TILE = 100,
    NodeOrder = {Battle = 0, Elite = 1, Boss = 2, Mystery = 3, Shop = 4, Rest = 5},
    LEGEND_ORDER = {"Battle", "Elite", "Boss", "Mystery", "Shop", "Rest"},

    -- Nikolas's painted parchment, cut by art/tools/build_parchment.py. The legend sits on the page itself,
    -- 768x1024 and nine-sliced so the torn corners keep their shape
    PARCHMENT = "rbxassetid://104068274804411",
    PARCHMENT_SLICE = Rect.new(140, 160, 628, 864),
    PARCHMENT_SLICE_SCALE = 0.6,
    -- The map's tall sheet, scrolled through with the routes: the page with its middle repeated, stacked top to
    -- bottom from pieces this many pixels tall (Roblox images stop at 1024)
    PARCHMENT_TALL = {
        {Image = "rbxassetid://137756361002019", Height = 983},
        {Image = "rbxassetid://95195103548580", Height = 983},
        {Image = "rbxassetid://106788317170117", Height = 981},
    },

    -- Region trims laid over the parchment's edges, built by art/tools/build_expedition_art.py: a left Edge strip
    -- (flipped for the right), a top Border strip (flipped for the bottom) and a top-left Corner (turned for the
    -- others). TRIM_EDGE is the strips' width on screen, the 16px art at 2.5x; INSET is how far in from the
    -- parchment's outside they sit. Outskirts has no trim
    TRIM_EDGE = 40,

    -- Ink is the writing and icons, Faint the routes not walked, Accent the route walked and the selected node,
    -- Paper the parchment's color for outlining text over it
    Themes = {
        KingsThrone = {
            Paper = Color3.fromHex("DDB07A"),
            Ink = Color3.fromHex("1F1A24"),
            Faint = Color3.fromHex("8C8378"),
            Accent = Color3.fromHex("B8892E"),
            Trim = {
                Edge = "rbxassetid://75291444726136",
                Border = "rbxassetid://96244513268981",
                Corner = "rbxassetid://83827883108259",
                INSET = 10,
            },
        },

        Overgrowth = {
            Paper = Color3.fromHex("DDB07A"),
            Ink = Color3.fromHex("2C3519"),
            Faint = Color3.fromHex("8A8A62"),
            Accent = Color3.fromHex("5E7F2E"),
            Trim = {
                Edge = "rbxassetid://118069250959305",
                Border = "rbxassetid://83696113869004",
                Corner = "rbxassetid://127750516652130",
                INSET = 12,
            },
        },

        Cliffside = {
            Paper = Color3.fromHex("DDB07A"),
            Ink = Color3.fromHex("3A2A20"),
            Faint = Color3.fromHex("97826A"),
            Accent = Color3.fromHex("8E5A36"),
            Trim = {
                Edge = "rbxassetid://132580570467870",
                Border = "rbxassetid://112402345392005",
                Corner = "rbxassetid://117195350837462",
                INSET = 10,
            },
        },

        Outskirts = {
            Paper = Color3.fromHex("DDB07A"),
            Ink = Color3.fromHex("3B2416"),
            Faint = Color3.fromHex("A08766"),
            Accent = Color3.fromHex("A3412C"),
        },

        Gravehollow = {
            Paper = Color3.fromHex("DDB07A"),
            Ink = Color3.fromHex("22163A"),
            Faint = Color3.fromHex("5E4D7A"),
            Accent = Color3.fromHex("7FE0BE"),
            Trim = {
                Edge = "rbxassetid://116073491604423",
                Border = "rbxassetid://88055692205112",
                Corner = "rbxassetid://137171635998160",
                INSET = 6,
                -- Mist is see-through, so the strips stop where the corners start instead of doubling up under them
                CLEAR_CORNERS = true,
            },
        },
    },

    -- World map islands rendered by art/tools/build_islands.py, ISLAND_SIZE pixels square
    -- Row 0 is the islands in color, row 1 the same islands grayed out, row 2 the chain and padlock layers
    -- Still used for the Singleplayer cards and their locks
    ISLANDS = "rbxassetid://84139968706737",
    ISLAND_SIZE = 160,
    IslandColumn = {KingsThrone = 0, Overgrowth = 1, Cliffside = 2, Outskirts = 3, Gravehollow = 4},
    LockColumn = {ChainA = 0, ChainB = 1, Lock = 2},

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
    -- The Rest Site's choice cards, built by art/tools/build_rest_cards.py; Train's card is no longer offered
    REST_CARDS = "rbxassetid://135905483379568",
    REST_CARD_SIZE = Vector2.new(96, 72),
    RestCardOrder = {Rest = 0, Train = 1, GunMaintenance = 2},

    -- Mystery encounter screens, built by art/tools/build_mystery_art.py; every background is 1672x941 like the camp
    -- Encounters without their own art yet use FALLBACK_BACKGROUND
    MysteryBackgrounds = {
        Altar = "rbxassetid://113565901767238",
        Ambush = "rbxassetid://91466943784949",
        Gunsmith = "rbxassetid://132885799635283",
        FallenKnight = "rbxassetid://122636487856177",
    },
    FALLBACK_BACKGROUND = "rbxassetid://133730252181741",
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

return ExpeditionArt
