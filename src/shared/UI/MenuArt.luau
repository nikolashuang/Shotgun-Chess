-- Asset ids for art/tools/build_ribbon.py and build_menu_art.py outputs in art/menu
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
}

return MenuArt
