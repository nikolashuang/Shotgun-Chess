local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SpriteConfig = require(ReplicatedStorage.Shared.Sprites.SpriteConfig)
local ClassKingConfig = require(ReplicatedStorage.Shared.Sprites.ClassKingConfig)
local PieceConfig = require(ReplicatedStorage.Shared.Board.PieceConfig)
local SpeedController = require(script.Parent.Parent.Controllers.SpeedController)

local activeSprites = {}

local AnimatedSpriteClass = {}

AnimatedSpriteClass.__index = AnimatedSpriteClass

-- outfit is a class name: a King with one is drawn from the class King atlas, wearing that class's clothes
function AnimatedSpriteClass.new(pieceName, parent, team, outfit)
    local self = setmetatable({}, AnimatedSpriteClass)

    -- Pieces without a sprite of their own yet borrow another's, tinted
    local standIn = PieceConfig.SpriteStandIns[pieceName]

    self.PieceName = standIn and standIn.Sprite or pieceName
    self.Team = team or "White"

    self.Image = Instance.new("ImageLabel")
    self.Image.Name = pieceName .. "Sprite"
    self.Image.BackgroundTransparency = 1
    self.Image.ImageRectSize = Vector2.new(SpriteConfig.CELL, SpriteConfig.CELL)
    self.Image.ResampleMode = Enum.ResamplerMode.Pixelated
    self.Image.Interactable = false
    self.Image.ImageColor3 = standIn and standIn.Tint or Color3.new(1, 1, 1)
    self.Image.Parent = parent

    self.Anim = nil
    self.Frame = 1
    self.LastFrame = 0
    self.isPlaying = false
    self.OnFinished = nil

    self:SetOutfit(outfit)

    activeSprites[self] = true
    self:Play("Idle")

    return self
end

-- Swaps between the plain sprite and a class outfit (Kings only), keeping the current animation frame
function AnimatedSpriteClass:SetOutfit(outfit)
    -- Until the class King atlas is uploaded (id 0) every King keeps the classic look
    local isUploaded = ClassKingConfig.ASSET_ID ~= "rbxassetid://0"
    local classRows = isUploaded and self.PieceName == "King" and outfit and ClassKingConfig.Classes[outfit]

    self.Outfit = classRows and outfit or nil

    if classRows then
        self.Rows = classRows
        self.TeamOffset = ClassKingConfig.Teams[self.Team]
        self.Image.Image = ClassKingConfig.ASSET_ID
    else
        self.Rows = SpriteConfig.Pieces[self.PieceName]
        -- Special pieces (the Fallen Knight) have their own column and look the same on both teams
        self.TeamOffset = SpriteConfig.Columns[self.PieceName] or SpriteConfig.Teams[self.Team]
        self.Image.Image = SpriteConfig.ASSET_ID
    end

    if self.Anim then
        self:SetFrame(self.Frame)
    end
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
    -- Looping idles keep their pace; only one-shot animations follow the speed setting
    local frameTime = info.Looped and info.FrameTime or SpeedController.Scale(info.FrameTime)
    if now - self.LastFrame < frameTime then return end

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
