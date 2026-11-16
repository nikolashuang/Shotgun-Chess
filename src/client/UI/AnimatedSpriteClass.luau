local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SpriteConfig = require(ReplicatedStorage.Shared.Sprites.SpriteConfig)

local activeSprites = {}

local AnimatedSpriteClass = {}

AnimatedSpriteClass.__index = AnimatedSpriteClass

function AnimatedSpriteClass.new(pieceName, parent, team)
    local self = setmetatable({}, AnimatedSpriteClass)

    self.PieceName = pieceName
    self.Rows = SpriteConfig.Pieces[pieceName]
    self.TeamOffset = SpriteConfig.Teams[team or "White"]

    self.Image = Instance.new("ImageLabel")
    self.Image.Name = pieceName .. "Sprite"
    self.Image.BackgroundTransparency = 1
    self.Image.Image = SpriteConfig.ASSET_ID
    self.Image.ImageRectSize = Vector2.new(SpriteConfig.CELL, SpriteConfig.CELL)
    self.Image.ResampleMode = Enum.ResamplerMode.Pixelated
    self.Image.Interactable = false
    self.Image.Parent = parent

    self.Anim = nil
    self.Frame = 1
    self.LastFrame = 0
    self.isPlaying = false
    self.OnFinished = nil

    activeSprites[self] = true
    self:Play("Idle")

    return self
end

function AnimatedSpriteClass:SetFrame(frame)
    self.Frame = frame
    self.Image.ImageRectOffset = Vector2.new(self.TeamOffset + (frame - 1) * SpriteConfig.STRIDE, self.Rows[self.Anim])
end

function AnimatedSpriteClass:Play(anim, onFinished)
    if not self.Rows[anim] then return end

    self.Anim = anim
    self.OnFinished = onFinished
    self.LastFrame = time()
    self.isPlaying = true
    self:SetFrame(1)
end

function AnimatedSpriteClass:Step(now)
    if not self.isPlaying then return end

    local info = SpriteConfig.Anims[self.Anim]
    if now - self.LastFrame < info.FrameTime then return end

    self.LastFrame = now

    if self.Frame < info.Frames then
        self:SetFrame(self.Frame + 1)
        return
    end

    if info.Looped then
        self:SetFrame(1)
        return
    end

    local onFinished = self.OnFinished
    self.OnFinished = nil

    -- Death holds its last frame
    if self.Anim == "Death" then
        self.isPlaying = false
    else
        self:Play("Idle")
    end

    if onFinished then
        onFinished()
    end
end

function AnimatedSpriteClass:Destroy()
    activeSprites[self] = nil
    self.Image:Destroy()
end

RunService.RenderStepped:Connect(function()
    local now = time()

    for sprite in pairs(activeSprites) do
        sprite:Step(now)
    end
end)

return AnimatedSpriteClass
