local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)
local SpriteConfig = require(ReplicatedStorage.Shared.Sprites.SpriteConfig)
local AnimatedSpriteClass = require(script.Parent.AnimatedSpriteClass)

-- In tiles
local HOP_HEIGHT = 0.35
local BODY_BOTTOM = 0.95

local DEATH_FADE_TIME = 0.3

-- Health bar sizes in tiles, times in seconds
local PIXEL = SpriteConfig.CELL_TILES / SpriteConfig.CELL
local BAR_WIDTH = 0.8
local BAR_HEIGHT = 4 * PIXEL
local BAR_GAP = 2 * PIXEL
local BAR_SHOW_TIME = 0.15
local BAR_HIDE_TIME = 0.3
local BAR_HIDE_DELAY = 1.5
local BAR_DRAIN_TIME = 0.25

local OUTLINE_COLOR = Color3.fromHex("171D32")
local EMPTY_COLOR = Color3.fromHex("3B3F52")
local HEALTH_COLORS = {
    White = Color3.fromHex("E6C47C"),
    Black = Color3.fromHex("D9544D"),
}

local PieceRigClass = {}

PieceRigClass.__index = PieceRigClass

local function ToBoardPosition(column, row)
    return UDim2.fromScale((column - 0.5) / BoardConfig.SIZE, 1 - (row - 0.5) / BoardConfig.SIZE)
end

local function GetBarLayer(board)
    local layer = board:FindFirstChild("HealthBars")

    if not layer then
        layer = Instance.new("Frame")
        layer.Name = "HealthBars"
        layer.BackgroundTransparency = 1
        layer.Size = UDim2.fromScale(1, 1)
        layer.ZIndex = 6
        layer.Interactable = false
        layer.Parent = board
    end

    return layer
end

-- Distance from the tile center up to just above the sprite's head, in tiles
local function GetBarOffset(pieceType)
    local headRow = SpriteConfig.HeadRows[pieceType]
    local spriteTop = BODY_BOTTOM - SpriteConfig.CELL_TILES * (1 - headRow / SpriteConfig.CELL)

    return spriteTop - 0.5 - BAR_GAP - BAR_HEIGHT / 2
end

function PieceRigClass.new(board, pieceType, team)
    local self = setmetatable({}, PieceRigClass)

    self.Rig = Instance.new("Frame")
    self.Rig.Name = team .. pieceType
    self.Rig.BackgroundTransparency = 1
    self.Rig.AnchorPoint = Vector2.new(0.5, 0.5)
    self.Rig.Size = UDim2.fromScale(1 / BoardConfig.SIZE, 1 / BoardConfig.SIZE)
    self.Rig.ZIndex = 3
    self.Rig.Interactable = false
    self.Rig.Parent = board

    self.Sprite = AnimatedSpriteClass.new(pieceType, self.Rig, team)
    self.Sprite.Image.AnchorPoint = Vector2.new(0.5, 1)
    self.Sprite.Image.Position = UDim2.fromScale(0.5, BODY_BOTTOM)
    self.Sprite.Image.Size = UDim2.fromScale(SpriteConfig.CELL_TILES, SpriteConfig.CELL_TILES)
    self.Sprite.Image.ZIndex = 3

    self.Column = nil
    self.Row = nil
    self.HopConnection = nil

    self.MaxHealth = nil
    self.Health = nil
    self.HideToken = 0
    self.isHovered = false

    self:CreateHealthBar(board, pieceType, team)

    return self
end

function PieceRigClass:CreateHealthBar(board, pieceType, team)
    self.HealthBar = Instance.new("CanvasGroup")
    self.HealthBar.Name = self.Rig.Name .. "Health"
    self.HealthBar.AnchorPoint = Vector2.new(0.5, 0.5)
    self.HealthBar.Size = UDim2.fromScale(BAR_WIDTH / BoardConfig.SIZE, BAR_HEIGHT / BoardConfig.SIZE)
    self.HealthBar.BackgroundColor3 = OUTLINE_COLOR
    self.HealthBar.BorderSizePixel = 0
    self.HealthBar.GroupTransparency = 1
    self.HealthBar.Interactable = false
    self.HealthBar.Parent = GetBarLayer(board)

    local inset = PIXEL / BAR_WIDTH

    local track = Instance.new("Frame")
    track.Name = "Track"
    track.BackgroundColor3 = EMPTY_COLOR
    track.BorderSizePixel = 0
    track.Position = UDim2.fromScale(inset, PIXEL / BAR_HEIGHT)
    track.Size = UDim2.fromScale(1 - inset * 2, 1 - PIXEL * 2 / BAR_HEIGHT)
    track.Parent = self.HealthBar

    self.HealthFill = Instance.new("Frame")
    self.HealthFill.Name = "Fill"
    self.HealthFill.BackgroundColor3 = HEALTH_COLORS[team]
    self.HealthFill.BorderSizePixel = 0
    self.HealthFill.Size = UDim2.fromScale(1, 1)
    self.HealthFill.Parent = track

    local barOffset = UDim2.fromScale(0, -GetBarOffset(pieceType) / BoardConfig.SIZE)

    self.Rig:GetPropertyChangedSignal("Position"):Connect(function()
        self.HealthBar.Position = self.Rig.Position - barOffset
    end)
end

function PieceRigClass:SetHealth(health, maxHealth)
    self.MaxHealth = maxHealth or self.MaxHealth
    self.Health = health

    local fill = UDim2.fromScale(math.clamp(health / self.MaxHealth, 0, 1), 1)
    TweenService:Create(self.HealthFill, TweenInfo.new(BAR_DRAIN_TIME), {Size = fill}):Play()
end

function PieceRigClass:ShowHealth()
    self.HideToken += 1

    TweenService:Create(self.HealthBar, TweenInfo.new(BAR_SHOW_TIME), {GroupTransparency = 0}):Play()
end

-- Fades the bar out after a delay unless it is shown again first
function PieceRigClass:HideHealth()
    self.HideToken += 1
    local token = self.HideToken

    task.delay(BAR_HIDE_DELAY, function()
        if self.HideToken ~= token then return end
        if self.isHovered then return end
        if not self.HealthBar.Parent then return end

        TweenService:Create(self.HealthBar, TweenInfo.new(BAR_HIDE_TIME), {GroupTransparency = 1}):Play()
    end)
end

function PieceRigClass:SetTile(column, row)
    self.Column = column
    self.Row = row
    self.Rig.Position = ToBoardPosition(column, row)
end

function PieceRigClass:HopTo(column, row)
    if not self.Column then
        self:SetTile(column, row)
        return
    end

    if self.HopConnection then
        self.HopConnection:Disconnect()
    end

    local fromColumn = self.Column
    local fromRow = self.Row
    self.Column = column
    self.Row = row

    local hopAnim = SpriteConfig.Anims.Hop
    local duration = hopAnim.Frames * hopAnim.FrameTime
    local startTime = time()

    self.Sprite:Play("Hop")

    self.HopConnection = RunService.RenderStepped:Connect(function()
        local alpha = math.min((time() - startTime) / duration, 1)
        local hopColumn = fromColumn + (column - fromColumn) * alpha
        local hopRow = fromRow + (row - fromRow) * alpha + math.sin(alpha * math.pi) * HOP_HEIGHT

        self.Rig.Position = ToBoardPosition(hopColumn, hopRow)

        if alpha < 1 then return end

        self.HopConnection:Disconnect()
        self.HopConnection = nil
    end)
end

function PieceRigClass:SetHovered(hovered)
    self.isHovered = hovered

    if hovered then
        self:ShowHealth()
    else
        self:HideHealth()
    end
end

function PieceRigClass:Die()
    self.HideToken += 1
    TweenService:Create(self.HealthBar, TweenInfo.new(BAR_HIDE_TIME), {GroupTransparency = 1}):Play()

    self.Sprite:Play("Death", function()
        local fade = TweenService:Create(self.Sprite.Image, TweenInfo.new(DEATH_FADE_TIME), {ImageTransparency = 1})

        fade.Completed:Connect(function()
            self:Destroy()
        end)

        fade:Play()
    end)
end

function PieceRigClass:Destroy()
    if self.HopConnection then
        self.HopConnection:Disconnect()
    end

    self.Sprite:Destroy()
    self.HealthBar:Destroy()
    self.Rig:Destroy()
end

return PieceRigClass
