local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)
local SpriteConfig = require(ReplicatedStorage.Shared.Sprites.SpriteConfig)
local AnimatedSpriteClass = require(script.Parent.AnimatedSpriteClass)
local EffectSpriteClass = require(script.Parent.EffectSpriteClass)

-- In tiles
local HOP_HEIGHT = 0.35
local BODY_BOTTOM = 0.95

local DEATH_FADE_TIME = 0.3

-- Attacks stop this many tiles short of the target's center
local LUNGE_STOP = 0.45
local LUNGE_PAUSE = 0.2

-- Seconds for a killed piece to fall over before it crumbles
local TOPPLE_TIME = 0.16

-- Health bar sizes in tiles, times in seconds
local PIXEL = SpriteConfig.CELL_TILES / SpriteConfig.CELL
local BAR_WIDTH = 0.8
local BAR_HEIGHT = 4 * PIXEL
local BAR_GAP = 2 * PIXEL
local BAR_SHOW_TIME = 0.15
local BAR_HIDE_TIME = 0.3
local BAR_HIDE_DELAY = 1.5
local BAR_DRAIN_TIME = 0.25

-- Stun stars sit this far below the top of the head, the command arrow this far above the health bar, in tiles
local STUN_DROP = 2 * PIXEL
local ARROW_GAP = 2 * PIXEL
local ARROW_BOB = 3 * PIXEL

local OUTLINE_COLOR = Color3.fromHex("271F29")
local EMPTY_COLOR = Color3.fromHex("4A3D48")
local HEALTH_COLORS = {
    White = Color3.fromHex("F1D4AC"),
    Black = Color3.fromHex("C8644F"),
}

local PieceRigClass = {}

PieceRigClass.__index = PieceRigClass

local function ToBoardPosition(column, row)
    return UDim2.fromScale((column - 0.5) / BoardConfig.SIZE, 1 - (row - 0.5) / BoardConfig.SIZE)
end

-- Lower rows draw on top so a piece never covers the one in front of it
local function PlaceRig(rig, column, row, lift)
    rig.Position = ToBoardPosition(column, row + (lift or 0))
    rig.ZIndex = BoardConfig.SIZE - math.round(row) + 1
end

-- Rigs share one layer so their row ordering doesn't mix with tiles, tracers or health bars
local function GetPieceLayer(board)
    local layer = board:FindFirstChild("Pieces")

    if not layer then
        layer = Instance.new("Frame")
        layer.Name = "Pieces"
        layer.BackgroundTransparency = 1
        layer.Size = UDim2.fromScale(1, 1)
        layer.ZIndex = 3
        layer.Interactable = false
        layer.Parent = board
    end

    return layer
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

-- Height of the top of the sprite's head inside the rig, in tiles from the rig's top
local function GetHeadTop(pieceType)
    local headRow = SpriteConfig.HeadRows[pieceType]

    return BODY_BOTTOM - SpriteConfig.CELL_TILES * (1 - headRow / SpriteConfig.CELL)
end

-- Distance from the tile center up to just above the sprite's head, in tiles
local function GetBarOffset(pieceType)
    return GetHeadTop(pieceType) - 0.5 - BAR_GAP - BAR_HEIGHT / 2
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
    self.Rig.Parent = GetPieceLayer(board)

    self.Sprite = AnimatedSpriteClass.new(pieceType, self.Rig, team)
    self.Sprite.Image.AnchorPoint = Vector2.new(0.5, 1)
    self.Sprite.Image.Position = UDim2.fromScale(0.5, BODY_BOTTOM)
    self.Sprite.Image.Size = UDim2.fromScale(SpriteConfig.CELL_TILES, SpriteConfig.CELL_TILES)
    self.Sprite.Image.ZIndex = 3

    self.Column = nil
    self.Row = nil
    self.HopConnection = nil
    self.TiltConnection = nil

    self.PieceType = pieceType

    self.MaxHealth = nil
    self.Health = nil
    self.HideToken = 0
    self.isHovered = false

    self.StunEffect = nil
    self.ArrowEffect = nil

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

-- Stars circling the head while the piece is stunned
function PieceRigClass:SetStunned(isStunned)
    if not isStunned then
        if self.StunEffect then
            self.StunEffect:Destroy()
            self.StunEffect = nil
        end
        return
    end

    if self.StunEffect then return end

    self.StunEffect = EffectSpriteClass.new("Stun", self.Rig)
    self.StunEffect.Image.Size = UDim2.fromScale(self.StunEffect.Width, self.StunEffect.Height)
    self.StunEffect.Image.ZIndex = 4
    self.StunEffect.BasePosition = UDim2.fromScale(0.5, GetHeadTop(self.PieceType) + STUN_DROP)
end

-- Spinning arrow bobbing above the health bar while the piece is chosen for a command
function PieceRigClass:SetArrow(isShown)
    if not isShown then
        if self.ArrowEffect then
            self.ArrowEffect:Destroy()
            self.ArrowEffect = nil
        end
        return
    end

    if self.ArrowEffect then return end

    local arrow = EffectSpriteClass.new("Arrow", self.Rig)
    local barTop = GetHeadTop(self.PieceType) - BAR_GAP - BAR_HEIGHT

    arrow.Image.Size = UDim2.fromScale(arrow.Width, arrow.Height)
    arrow.Image.ZIndex = 4
    arrow.BasePosition = UDim2.fromScale(0.5, barTop - ARROW_GAP - arrow.Height / 2)
    arrow.BobHeight = ARROW_BOB

    self.ArrowEffect = arrow
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
    PlaceRig(self.Rig, column, row)
end

-- Animates a hop between two board positions without changing the rig's tile
function PieceRigClass:Hop(fromColumn, fromRow, toColumn, toRow, onLanded)
    if self.HopConnection then
        self.HopConnection:Disconnect()
    end

    local hopAnim = SpriteConfig.Anims.Hop
    local duration = hopAnim.Frames * hopAnim.FrameTime
    local startTime = time()

    self.Sprite:Play("Hop")

    self.HopConnection = RunService.RenderStepped:Connect(function()
        local alpha = math.min((time() - startTime) / duration, 1)
        local hopColumn = fromColumn + (toColumn - fromColumn) * alpha
        local hopRow = fromRow + (toRow - fromRow) * alpha

        PlaceRig(self.Rig, hopColumn, hopRow, math.sin(alpha * math.pi) * HOP_HEIGHT)

        if alpha < 1 then return end

        self.HopConnection:Disconnect()
        self.HopConnection = nil

        if onLanded then
            onLanded()
        end
    end)
end

function PieceRigClass:HopTo(column, row)
    if not self.Column then
        self:SetTile(column, row)
        return
    end

    local fromColumn = self.Column
    local fromRow = self.Row
    self.Column = column
    self.Row = row

    self:Hop(fromColumn, fromRow, column, row)
end

-- Hops up to a target, calls onHit, then hops back to its own tile
function PieceRigClass:Lunge(column, row, onHit)
    local homeColumn = self.Column
    local homeRow = self.Row
    local deltaColumn = column - homeColumn
    local deltaRow = row - homeRow
    local length = math.sqrt(deltaColumn * deltaColumn + deltaRow * deltaRow)
    local reach = math.max(length - LUNGE_STOP, 0) / length

    local strikeColumn = homeColumn + deltaColumn * reach
    local strikeRow = homeRow + deltaRow * reach

    self:Hop(homeColumn, homeRow, strikeColumn, strikeRow, function()
        onHit()

        task.delay(LUNGE_PAUSE, function()
            if not self.Rig.Parent then return end

            self:Hop(strikeColumn, strikeRow, self.Column, self.Row)
        end)
    end)
end

-- Rotates the sprite around its base, positive degrees tip it to the right
function PieceRigClass:SetTilt(degrees)
    local image = self.Sprite.Image
    local angle = math.rad(degrees)
    local halfHeight = SpriteConfig.CELL_TILES / 2

    image.Rotation = degrees
    image.Position = UDim2.fromScale(0.5 + halfHeight * math.sin(angle), BODY_BOTTOM + halfHeight - halfHeight * math.cos(angle))
end

function PieceRigClass:Tilt(fromDegrees, toDegrees, duration, easingStyle, easingDirection, onFinished)
    if self.TiltConnection then
        self.TiltConnection:Disconnect()
    end

    local startTime = time()

    self.TiltConnection = RunService.RenderStepped:Connect(function()
        local alpha = math.min((time() - startTime) / duration, 1)
        local eased = TweenService:GetValue(alpha, easingStyle, easingDirection)

        self:SetTilt(fromDegrees + (toDegrees - fromDegrees) * eased)

        if alpha < 1 then return end

        self.TiltConnection:Disconnect()
        self.TiltConnection = nil

        if onFinished then
            onFinished()
        end
    end)
end

-- Classic chess knock over for a killed piece: falls away from the attacker, then crumbles
function PieceRigClass:KnockOver(direction)
    self:Tilt(0, 90 * direction, TOPPLE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In, function()
        self:Die()
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

function PieceRigClass:FadeOut()
    self.HideToken += 1
    TweenService:Create(self.HealthBar, TweenInfo.new(BAR_HIDE_TIME), {GroupTransparency = 1}):Play()

    local fade = TweenService:Create(self.Sprite.Image, TweenInfo.new(DEATH_FADE_TIME), {ImageTransparency = 1})

    fade.Completed:Connect(function()
        self:Destroy()
    end)

    fade:Play()
end

function PieceRigClass:Die()
    self:SetStunned(false)
    self:SetArrow(false)

    self.HideToken += 1
    TweenService:Create(self.HealthBar, TweenInfo.new(BAR_HIDE_TIME), {GroupTransparency = 1}):Play()

    self.Sprite:Play("Death", function()
        self:FadeOut()
    end)
end

function PieceRigClass:Destroy()
    self:SetStunned(false)
    self:SetArrow(false)

    if self.HopConnection then
        self.HopConnection:Disconnect()
    end

    if self.TiltConnection then
        self.TiltConnection:Disconnect()
    end

    self.Sprite:Destroy()
    self.HealthBar:Destroy()
    self.Rig:Destroy()
end

return PieceRigClass
