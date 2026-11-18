local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SpriteConfig = require(ReplicatedStorage.Shared.Sprites.SpriteConfig)

-- Radians per second of the up and down bob
local BOB_SPEED = 4

local activeEffects = {}

-- A looping board effect from SpriteConfig.Effects (stun stars, command arrow) that can bob up and down
local EffectSpriteClass = {}

EffectSpriteClass.__index = EffectSpriteClass

function EffectSpriteClass.new(effectName, parent)
    local self = setmetatable({}, EffectSpriteClass)

    self.Effect = SpriteConfig.Effects[effectName]

    local firstRect = SpriteConfig.Rects[self.Effect.Rects[1]]

    self.Image = Instance.new("ImageLabel")
    self.Image.Name = effectName .. "Effect"
    self.Image.BackgroundTransparency = 1
    self.Image.Image = SpriteConfig.ASSET_ID
    self.Image.ImageRectSize = Vector2.new(firstRect[3], firstRect[4])
    self.Image.ResampleMode = Enum.ResamplerMode.Pixelated
    self.Image.AnchorPoint = Vector2.new(0.5, 0.5)
    self.Image.Interactable = false
    self.Image.Parent = parent

    -- Size of one frame in tiles, so the effect keeps the pieces' pixel scale
    self.Width = firstRect[3] * SpriteConfig.CELL_TILES / SpriteConfig.CELL
    self.Height = firstRect[4] * SpriteConfig.CELL_TILES / SpriteConfig.CELL

    self.BasePosition = UDim2.new()
    -- In tiles
    self.BobHeight = 0

    self.Frame = 1
    self.LastFrame = time()

    activeEffects[self] = true
    self:SetFrame(1)

    return self
end

function EffectSpriteClass:SetFrame(frame)
    self.Frame = frame

    local rect = SpriteConfig.Rects[self.Effect.Rects[frame]]
    self.Image.ImageRectOffset = Vector2.new(rect[1], rect[2])
end

function EffectSpriteClass:Step(now)
    if now - self.LastFrame >= self.Effect.FrameTime then
        self.LastFrame = now
        self:SetFrame(self.Frame % #self.Effect.Rects + 1)
    end

    local bob = self.BobHeight * (0.5 + 0.5 * math.sin(now * BOB_SPEED))
    self.Image.Position = self.BasePosition - UDim2.fromScale(0, bob)
end

function EffectSpriteClass:Destroy()
    activeEffects[self] = nil
    self.Image:Destroy()
end

RunService.RenderStepped:Connect(function()
    local now = time()

    for effect in pairs(activeEffects) do
        effect:Step(now)
    end
end)

return EffectSpriteClass
