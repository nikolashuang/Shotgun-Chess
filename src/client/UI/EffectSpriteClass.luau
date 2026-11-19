local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SpriteConfig = require(ReplicatedStorage.Shared.Sprites.SpriteConfig)
local SpeedController = require(script.Parent.Parent.Controllers.SpeedController)

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
    -- Hidden until the first Step puts it at BasePosition, so it never flashes at the parent's corner
    self.Image.Visible = false
    self.Image.Parent = parent

    -- Kept effects (the command arrow) are hidden and shown instead of rebuilt
    self.isShown = true
    -- New images can draw a frame before their position applies, so effects only show after one placed frame
    self.isPlaced = false

    -- Size of one frame in tiles, so the effect keeps the pieces' pixel scale
    self.Width = firstRect[3] * SpriteConfig.CELL_TILES / SpriteConfig.CELL
    self.Height = firstRect[4] * SpriteConfig.CELL_TILES / SpriteConfig.CELL

    self.BasePosition = UDim2.new()
    -- In tiles
    self.BobHeight = 0

    self.Frame = 1
    self.LastFrame = time()

    -- One-shot effects hold their last frame and call OnFinished once
    self.isLooped = true
    self.OnFinished = nil

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
    local frameTime = self.isLooped and self.Effect.FrameTime or SpeedController.Scale(self.Effect.FrameTime)

    if now - self.LastFrame >= frameTime then
        self.LastFrame = now

        if self.Frame < #self.Effect.Rects then
            self:SetFrame(self.Frame + 1)
        elseif self.isLooped then
            self:SetFrame(1)
        elseif self.OnFinished then
            local onFinished = self.OnFinished
            self.OnFinished = nil
            onFinished()
        end
    end

    self:Place(now)

    if self.isPlaced then
        self.Image.Visible = self.isShown
    end

    self.isPlaced = true
end

function EffectSpriteClass:Place(now)
    local bob = self.BobHeight * (0.5 + 0.5 * math.sin(now * BOB_SPEED))
    self.Image.Position = self.BasePosition - UDim2.fromScale(0, bob)
end

-- Places the effect before showing it so it appears already in position
function EffectSpriteClass:SetShown(isShown)
    self.isShown = isShown

    if isShown then
        self:Place(time())
    end

    self.Image.Visible = isShown and self.isPlaced
end

-- Restarts a one-shot effect from its first frame
function EffectSpriteClass:PlayOnce(onFinished)
    self.isLooped = false
    self.OnFinished = onFinished
    self.LastFrame = time()
    self:SetFrame(1)
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
