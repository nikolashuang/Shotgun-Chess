-- Asset ids for art/tools/build_ribbon.py, build_menu_art.py and build_menu_fire.py outputs in art/menu
local MenuArt = {
    -- Gold banner behind a hovered main menu button
    RIBBON = "rbxassetid://81564494828559",
    RIBBON_SIZE = Vector2.new(114, 34),
    -- Pixel row of the band's middle; the tails hang below it, so it sits above the image's center
    RIBBON_BAND_CENTER = 13.5,

    -- CRT filter: a scanline strip tiled over the screen and a stretched vignette
    SCANLINES = "rbxassetid://70414370509953",
    SCANLINE_PERIOD = 3,
    VIGNETTE = "rbxassetid://126289948708188",

    -- Campfire flame over the background art, built by build_menu_fire.py and build_menu_background.py
    FIRE = "rbxassetid://133527294137987",
    FIRE_FRAME = Vector2.new(40, 45),
    FIRE_FRAMES = 12,
    FIRE_COLUMNS = 4,
    FIRE_TIME = 0.09,
    -- Where the fire sheet sits on the 1670x942 background, as fractions of it: x, y, width, height
    FIRE_RECT = {749 / 1670, 652 / 942, 160 / 1670, 180 / 942},
}

return MenuArt
