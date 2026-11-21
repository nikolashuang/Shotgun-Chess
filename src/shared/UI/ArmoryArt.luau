-- Ability, menu card and campaign pouch drawings rendered by art/tools/build_armory_icons.py and packed by build_armory_art.py
local ArmoryArt = {
    ICONS = "rbxassetid://101811508933391",
    -- Pixels per icon (64 px render plus a 1 px outline each side), packed left to right, top to bottom
    TILE = 66,
    COLUMNS = 4,

    -- Icons are named <Class><Kind> with kinds Passive, Special and Ultimate, matching ClassConfig
    IconOrder = {
        "ReaperPassive", "ReaperSpecial", "ReaperUltimate",
        "HunterPassive", "HunterSpecial", "HunterUltimate",
        "GunslingerPassive", "GunslingerSpecial", "GunslingerUltimate",
        "OutlawPassive", "OutlawSpecial", "OutlawUltimate",
        "Siege", "Duels", "Practice", "Queue", "Challenge",
        "Pouch",
    },
}

-- Shows one icon from the sheet on an ImageLabel
function ArmoryArt.SetIcon(image, name)
    local index = table.find(ArmoryArt.IconOrder, name)

    if not index then
        image.Image = ""
        return
    end

    index -= 1
    image.Image = ArmoryArt.ICONS
    image.ImageRectOffset = Vector2.new(index % ArmoryArt.COLUMNS, index // ArmoryArt.COLUMNS) * ArmoryArt.TILE
    image.ImageRectSize = Vector2.new(ArmoryArt.TILE, ArmoryArt.TILE)
    image.ResampleMode = Enum.ResamplerMode.Pixelated
end

return ArmoryArt
