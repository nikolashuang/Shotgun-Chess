local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local MenuArt = require(ReplicatedStorage.Shared.UI.MenuArt)
local SettingsConfig = require(ReplicatedStorage.Shared.Player.SettingsConfig)

-- Screen pixels per texture pixel of the scanlines
local SCANLINE_SCALE = 1
-- A faint bright band rolls down the screen like an old CRT refresh
local ROLL_TIME = 7
local ROLL_HEIGHT = 0.18
local ROLL_TRANSPARENCY = 0.94

local gui = nil
local listeners = {}

-- Full-screen CRT look (scanlines, vignette, rolling band) drawn over every other screen
local CrtController = {}

CrtController.isEnabled = SettingsConfig.DEFAULTS.CRT

local function NewLayer(className, name)
    local layer = Instance.new(className)
    layer.Name = name
    layer.BackgroundTransparency = 1
    layer.Size = UDim2.fromScale(1, 1)
    layer.Interactable = false
    layer.Parent = gui

    return layer
end

local function BuildFilter()
    gui = Instance.new("ScreenGui")
    gui.Name = "CRTFilter"
    gui.DisplayOrder = 1000
    gui.IgnoreGuiInset = true
    gui.ScreenInsets = Enum.ScreenInsets.None
    gui.ResetOnSpawn = false
    gui.Enabled = CrtController.isEnabled
    gui.Parent = Players.LocalPlayer.PlayerGui

    local vignette = NewLayer("ImageLabel", "Vignette")
    vignette.Image = MenuArt.VIGNETTE

    local scanlines = NewLayer("ImageLabel", "Scanlines")
    scanlines.Image = MenuArt.SCANLINES
    scanlines.ScaleType = Enum.ScaleType.Tile
    scanlines.TileSize = UDim2.new(1, 0, 0, MenuArt.SCANLINE_PERIOD * SCANLINE_SCALE)
    scanlines.ResampleMode = Enum.ResamplerMode.Pixelated

    local roll = NewLayer("Frame", "Roll")
    roll.BackgroundColor3 = Color3.new(1, 1, 1)
    roll.BackgroundTransparency = ROLL_TRANSPARENCY
    roll.BorderSizePixel = 0
    roll.Size = UDim2.fromScale(1, ROLL_HEIGHT)

    -- Fades the band's top and bottom edges so it reads as a soft glow
    local gradient = Instance.new("UIGradient")
    gradient.Rotation = 90
    gradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.5, 0),
        NumberSequenceKeypoint.new(1, 1),
    })
    gradient.Parent = roll

    roll.Position = UDim2.fromScale(0, -ROLL_HEIGHT)
    local rollTween = TweenService:Create(roll, TweenInfo.new(ROLL_TIME, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
        Position = UDim2.fromScale(0, 1),
    })
    rollTween:Play()
end

function CrtController.SetEnabled(isEnabled)
    CrtController.isEnabled = isEnabled
    gui.Enabled = isEnabled

    for _, callback in ipairs(listeners) do
        callback(isEnabled)
    end
end

function CrtController.OnChanged(callback)
    table.insert(listeners, callback)
end

local init = false
function CrtController.Init()
    if init then return end
    init = true

    BuildFilter()
end

return CrtController
