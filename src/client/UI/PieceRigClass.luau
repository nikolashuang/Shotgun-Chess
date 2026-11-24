local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)
local SpriteConfig = require(ReplicatedStorage.Shared.Sprites.SpriteConfig)
local AnimatedSpriteClass = require(script.Parent.AnimatedSpriteClass)
local EffectSpriteClass = require(script.Parent.EffectSpriteClass)
local SpeedController = require(script.Parent.Parent.Controllers.SpeedController)

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
-- Bolas wrap the body this far down from the head, as a fraction of the head-to-feet height
local BOLAS_DROP = 0.55

-- One divider per point of health, like the energy bar
local TICK_COLOR = Color3.fromHex("271F29")
local TICK_TRANSPARENCY = 0.35

local OUTLINE_COLOR = Color3.fromHex("271F29")
local EMPTY_COLOR = Color3.fromHex("4A3D48")
-- Health an attack is about to take, marked white on the bar
local PREVIEW_COLOR = Color3.new(1, 1, 1)
-- Border of the health bar while a Morale shield is up
local SHIELD_COLOR = Color3.fromHex("8CD3F2")
local PREVIEW_PULSE_TIME = 0.45

-- Name shown above the health bar, fading in and out with it, in tiles
local NAME_HEIGHT = 0.3
local NAME_GAP = PIXEL
local NAME_COLOR = Color3.fromHex("E9E3D6")
local NAME_FONT = Font.new("rbxasset://fonts/families/Fondamento.json", Enum.FontWeight.Bold)
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

-- outfit is the class a King is dressed in, or nil for the classic look
function PieceRigClass.new(board, pieceType, team, outfit)
    local self = setmetatable({}, PieceRigClass)

    self.Rig = Instance.new("Frame")
    self.Rig.Name = team .. pieceType
    self.Rig.BackgroundTransparency = 1
    self.Rig.AnchorPoint = Vector2.new(0.5, 0.5)
    self.Rig.Size = UDim2.fromScale(1 / BoardConfig.SIZE, 1 / BoardConfig.SIZE)
    self.Rig.ZIndex = 3
    self.Rig.Interactable = false
    self.Rig.Parent = GetPieceLayer(board)

    self.Sprite = AnimatedSpriteClass.new(pieceType, self.Rig, team, outfit)
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
    self.isBarShown = false
    self.PreviewDamage = 0
    self.Shield = 0

    self.StunEffect = nil
    self.ArrowEffect = nil
    self.MarkEffect = nil
    self.AuraEffect = nil

    -- The Fallen Knight and his pawns burn with a blue-green aura drawn behind their sprites
    if pieceType == "FallenKnight" or pieceType == "FallenPawn" then
        local aura = EffectSpriteClass.new("Aura", self.Rig)
        -- Pawns are shorter, so theirs is smaller
        local scale = pieceType == "FallenPawn" and 0.75 or 1
        aura.Image.Size = UDim2.fromScale(aura.Width * scale, aura.Height * scale)
        aura.Image.ZIndex = 2
        -- See-through so the knight himself still reads in front of it
        aura.Image.ImageTransparency = 0.65
        aura.BasePosition = UDim2.fromScale(0.5, BODY_BOTTOM - aura.Height * scale / 2)

        self.AuraEffect = aura
    end

    self:CreateHealthBar(board, pieceType, team)
    self:CreateNameLabel(board, pieceType)
    self:CreateArrow()

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

    self.DamagePreview = Instance.new("Frame")
    self.DamagePreview.Name = "DamagePreview"
    self.DamagePreview.BackgroundColor3 = PREVIEW_COLOR
    self.DamagePreview.BorderSizePixel = 0
    self.DamagePreview.Visible = false
    self.DamagePreview.ZIndex = 2
    self.DamagePreview.Parent = track

    TweenService:Create(self.DamagePreview, TweenInfo.new(PREVIEW_PULSE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
        BackgroundTransparency = 0.45,
    }):Play()

    self.HealthTrack = track
    self.TickCount = 0

    local barOffset = UDim2.fromScale(0, -GetBarOffset(pieceType) / BoardConfig.SIZE)

    self.Rig:GetPropertyChangedSignal("Position"):Connect(function()
        self.HealthBar.Position = self.Rig.Position - barOffset
    end)
end

-- "FallenKnight" -> "Fallen Knight"
local function GetDisplayName(pieceType)
    return (pieceType:gsub("(%l)(%u)", "%1 %2"))
end

function PieceRigClass:CreateNameLabel(board, pieceType)
    self.NameLabel = Instance.new("TextLabel")
    self.NameLabel.Name = self.Rig.Name .. "Name"
    self.NameLabel.BackgroundTransparency = 1
    self.NameLabel.AnchorPoint = Vector2.new(0.5, 1)
    self.NameLabel.Size = UDim2.fromScale(2 / BoardConfig.SIZE, NAME_HEIGHT / BoardConfig.SIZE)
    self.NameLabel.FontFace = NAME_FONT
    self.NameLabel.Text = GetDisplayName(pieceType)
    self.NameLabel.TextColor3 = NAME_COLOR
    self.NameLabel.TextScaled = true
    self.NameLabel.TextStrokeColor3 = OUTLINE_COLOR
    self.NameLabel.TextTransparency = 1
    self.NameLabel.TextStrokeTransparency = 1
    self.NameLabel.Interactable = false
    self.NameLabel.Parent = GetBarLayer(board)

    local nameBottom = GetBarOffset(pieceType) - BAR_HEIGHT / 2 - NAME_GAP
    local nameOffset = UDim2.fromScale(0, nameBottom / BoardConfig.SIZE)

    self.Rig:GetPropertyChangedSignal("Position"):Connect(function()
        self.NameLabel.Position = self.Rig.Position + nameOffset
    end)
end

-- Stars circling the head while the piece is stunned, or bolas wrapped around its body (kind "Bolas")
function PieceRigClass:SetStunned(isStunned, kind)
    if self.StunEffect then
        self.StunEffect:Destroy()
        self.StunEffect = nil
    end

    if not isStunned then return end

    local headTop = GetHeadTop(self.PieceType)
    local isBolas = kind == "Bolas"

    self.StunEffect = EffectSpriteClass.new(isBolas and "BolasBound" or "Stun", self.Rig)
    self.StunEffect.Image.Size = UDim2.fromScale(self.StunEffect.Width, self.StunEffect.Height)
    self.StunEffect.Image.ZIndex = 4

    if isBolas then
        self.StunEffect.BasePosition = UDim2.fromScale(0.5, headTop + (BODY_BOTTOM - headTop) * BOLAS_DROP)
    else
        self.StunEffect.BasePosition = UDim2.fromScale(0.5, headTop + STUN_DROP)
    end
end

-- Height of an effect's center when it floats above the health bar, and above the name while it shows
function PieceRigClass:GetAboveBarPosition(effect)
    local barTop = GetHeadTop(self.PieceType) - BAR_GAP - BAR_HEIGHT

    if self.isBarShown then
        barTop -= NAME_GAP + NAME_HEIGHT
    end

    return UDim2.fromScale(0.5, barTop - ARROW_GAP - effect.Height / 2)
end

-- Red X bobbing above an enemy marked by High Noon's Bounty
function PieceRigClass:SetMarked(isMarked)
    if not isMarked then
        if self.MarkEffect then
            self.MarkEffect:Destroy()
            self.MarkEffect = nil
        end
        return
    end

    if self.MarkEffect then return end

    local mark = EffectSpriteClass.new("Mark", self.Rig)
    mark.Image.Size = UDim2.fromScale(mark.Width, mark.Height)
    mark.Image.ZIndex = 4
    mark.BasePosition = self:GetAboveBarPosition(mark)
    mark.BobHeight = ARROW_BOB

    self.MarkEffect = mark
end

-- Every rig keeps one hidden arrow so hovering only toggles it; a new one could draw a frame out of place
function PieceRigClass:CreateArrow()
    local arrow = EffectSpriteClass.new("Arrow", self.Rig)

    arrow.Image.Size = UDim2.fromScale(arrow.Width, arrow.Height)
    arrow.Image.ZIndex = 4
    arrow.BasePosition = self:GetAboveBarPosition(arrow)
    arrow.BobHeight = ARROW_BOB
    arrow:SetShown(false)

    self.ArrowEffect = arrow
end

-- Spinning arrow bobbing above the health bar while the piece is chosen, hovered or targeted
-- color tints the gold sprite; nil keeps it gold
function PieceRigClass:SetArrow(isShown, color)
    local arrow = self.ArrowEffect
    if not arrow then return end

    if isShown then
        self:PlaceArrow()
        arrow.Image.ImageColor3 = color or Color3.new(1, 1, 1)
    end

    arrow:SetShown(isShown)
end

function PieceRigClass:PlaceArrow()
    local arrow = self.ArrowEffect
    arrow.BasePosition = self:GetAboveBarPosition(arrow)

    -- A bounty mark already floats there, so the arrow sits on top of it
    if self.MarkEffect then
        arrow.BasePosition -= UDim2.fromScale(0, self.MarkEffect.Height + ARROW_GAP)
    end
end

-- Draws a divider between every point of health so players can count the hits left
function PieceRigClass:DrawTicks()
    local count = math.max(math.floor(self.MaxHealth) - 1, 0)
    if count == self.TickCount then return end

    for _, child in pairs(self.HealthTrack:GetChildren()) do
        if child.Name == "Tick" then
            child:Destroy()
        end
    end

    for i = 1, count do
        local tick = Instance.new("Frame")
        tick.Name = "Tick"
        tick.BackgroundColor3 = TICK_COLOR
        tick.BackgroundTransparency = TICK_TRANSPARENCY
        tick.BorderSizePixel = 0
        tick.AnchorPoint = Vector2.new(0.5, 0)
        tick.Position = UDim2.fromScale(i / self.MaxHealth, 0)
        tick.Size = UDim2.new(0, 1, 1, 0)
        tick.ZIndex = 3
        tick.Parent = self.HealthTrack
    end

    self.TickCount = count
end

function PieceRigClass:SetHealth(health, maxHealth)
    self.MaxHealth = maxHealth or self.MaxHealth
    self.Health = health
    self:DrawTicks()

    local fill = UDim2.fromScale(math.clamp(health / self.MaxHealth, 0, 1), 1)
    TweenService:Create(self.HealthFill, TweenInfo.new(SpeedController.Scale(BAR_DRAIN_TIME)), {Size = fill}):Play()

    self:SetDamagePreview(self.PreviewDamage)
end

-- Marks the slice of health an attack is about to take; 0 hides it
function PieceRigClass:SetDamagePreview(damage)
    local wasShown = self.PreviewDamage > 0
    self.PreviewDamage = damage

    local health = self.Health or 0
    local lost = math.min(damage, health)

    self.DamagePreview.Visible = lost > 0

    if lost > 0 then
        self.DamagePreview.Position = UDim2.fromScale((health - lost) / self.MaxHealth, 0)
        self.DamagePreview.Size = UDim2.fromScale(lost / self.MaxHealth, 1)
    end

    if damage > 0 and not wasShown then
        self:ShowHealth()
    elseif damage <= 0 and wasShown then
        self:HideHealth()
    end
end

-- The name fades in and out with the bar; the mark and arrow move up to make room for it
function PieceRigClass:FadeBar(isShown, duration)
    local transparency = isShown and 0 or 1
    local info = TweenInfo.new(duration)

    TweenService:Create(self.HealthBar, info, {GroupTransparency = transparency}):Play()
    TweenService:Create(self.NameLabel, info, {TextTransparency = transparency, TextStrokeTransparency = transparency}):Play()

    if self.isBarShown == isShown then return end
    self.isBarShown = isShown

    if self.MarkEffect then
        self.MarkEffect.BasePosition = self:GetAboveBarPosition(self.MarkEffect)
    end

    if self.ArrowEffect then
        self:PlaceArrow()
    end
end

function PieceRigClass:SetOutfit(outfit)
    if self.Sprite.Outfit == outfit then return end

    self.Sprite:SetOutfit(outfit)
end

-- A shielded piece keeps its bar up, bordered in blue, until the shield is gone
function PieceRigClass:SetShield(amount)
    self.Shield = amount
    self.HealthBar.BackgroundColor3 = amount > 0 and SHIELD_COLOR or OUTLINE_COLOR

    if amount > 0 then
        self:ShowHealth()
    else
        self:HideHealth()
    end
end

function PieceRigClass:ShowHealth()
    self.HideToken += 1

    self:FadeBar(true, BAR_SHOW_TIME)
end

-- Fades the bar out after a delay unless it is shown again first
function PieceRigClass:HideHealth()
    self.HideToken += 1
    local token = self.HideToken

    task.delay(BAR_HIDE_DELAY, function()
        if self.HideToken ~= token then return end
        if self.isHovered or self.PreviewDamage > 0 or self.Shield > 0 then return end
        if not self.HealthBar.Parent then return end

        self:FadeBar(false, BAR_HIDE_TIME)
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
    local duration = SpeedController.Scale(hopAnim.Frames * hopAnim.FrameTime)
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

        task.delay(SpeedController.Scale(LUNGE_PAUSE), function()
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
    self:Tilt(0, 90 * direction, SpeedController.Scale(TOPPLE_TIME), Enum.EasingStyle.Quad, Enum.EasingDirection.In, function()
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

-- Calls back once the rig has stopped hopping, including the hop back from a lunge
function PieceRigClass:WhenSettled(callback)
    task.spawn(function()
        local settledSince = time()

        while self.Rig.Parent and time() - settledSince < SpeedController.Scale(LUNGE_PAUSE) + 0.05 do
            if self.HopConnection then
                settledSince = time()
            end

            task.wait()
        end

        if self.Rig.Parent then
            callback()
        end
    end)
end

function PieceRigClass:FadeOut()
    self.HideToken += 1
    self:FadeBar(false, BAR_HIDE_TIME)

    local fade = TweenService:Create(self.Sprite.Image, TweenInfo.new(SpeedController.Scale(DEATH_FADE_TIME)), {ImageTransparency = 1})

    fade.Completed:Connect(function()
        self:Destroy()
    end)

    fade:Play()
end

function PieceRigClass:Die()
    self:SetStunned(false)
    self:SetArrow(false)
    self:SetMarked(false)
    self:RemoveAura()
    self.PreviewDamage = 0

    self.HideToken += 1
    self:FadeBar(false, BAR_HIDE_TIME)

    self.Sprite:Play("Death", function()
        self:FadeOut()
    end)
end

function PieceRigClass:RemoveAura()
    if self.AuraEffect then
        self.AuraEffect:Destroy()
        self.AuraEffect = nil
    end
end

function PieceRigClass:Destroy()
    self:SetStunned(false)
    self:SetMarked(false)
    self:RemoveAura()

    if self.ArrowEffect then
        self.ArrowEffect:Destroy()
        self.ArrowEffect = nil
    end

    if self.HopConnection then
        self.HopConnection:Disconnect()
    end

    if self.TiltConnection then
        self.TiltConnection:Disconnect()
    end

    self.Sprite:Destroy()
    self.HealthBar:Destroy()
    self.NameLabel:Destroy()
    self.Rig:Destroy()
end

return PieceRigClass
