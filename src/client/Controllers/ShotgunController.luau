local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)
local BoardRules = require(ReplicatedStorage.Shared.Board.BoardRules)
local ShotgunRules = require(ReplicatedStorage.Shared.Combat.ShotgunRules)
local SpriteConfig = require(ReplicatedStorage.Shared.Sprites.SpriteConfig)

local HIT_COLOR = Color3.fromHex("C8644F")
local TRACER_COLOR = Color3.fromHex("E9E3D6")
local OUTLINE_COLOR = Color3.fromHex("271F29")

-- Sizes and speeds in tiles
local PIXEL = SpriteConfig.CELL_TILES / SpriteConfig.CELL
local DOT_SPACING = 0.2
local TICK_LENGTH = 2
local PELLET_SPEED = 18
local TRACER_LENGTH = 0.8
local TRACER_THICKNESS = 2 * PIXEL
local MUZZLE_OFFSET = 0.45
local HIT_FLASH_TIME = 0.2

local PREVIEW_TRANSPARENCY = 0.8

-- Gun pivot is a square this many tiles wide, centered on the King's hand
local GUN_PIVOT_TILES = 2
local GUN_HOLD = Vector2.new(0.7, 0.53)
local GUN_KICK = 0.12
local GUN_KICK_TIME = 0.15

local board = nil
local gunPivot = nil
local gunImage = nil
local getKingPosition = nil
local isBlockingTile = nil
local active = false
local arcDots = {}
local previewTiles = {}
local lastPreviewKey = nil

local weapon = nil
-- Another weapon's aim and hitbox to preview instead of the shotgun's (Hunting Strike's bolas)
local aimWeapon = nil
local gunSprite = SpriteConfig.Guns.Pump
-- The equipped shotgun's sprite; gunSprite is the revolver while Fan the Hammer is aimed or firing
local shotgunSprite = SpriteConfig.Guns.Pump
local isRevolverAimed = false
local isRevolverFiring = false
local revolverToken = 0
local aimAngle = 0
local mode = "Normal"
-- Set while aiming a straight-line ability instead of the shotgun
local lineRange = nil

local ShotgunController = {}

ShotgunController.OnModeChanged = nil

local function ToBoardUDim(x, y)
    return UDim2.fromScale(x / BoardConfig.SIZE, 1 - y / BoardConfig.SIZE)
end

local function SetRect(image, rectName, parentTiles)
    local rect = SpriteConfig.Rects[rectName]

    image.ImageRectOffset = Vector2.new(rect[1], rect[2])
    image.ImageRectSize = Vector2.new(rect[3], rect[4])
    image.Size = UDim2.fromScale(rect[3] * PIXEL / parentTiles, rect[4] * PIXEL / parentTiles)
end

local function NewSprite(name, rectName, zIndex, parentTiles)
    local image = Instance.new("ImageLabel")
    image.Name = name
    image.BackgroundTransparency = 1
    image.Image = SpriteConfig.ASSET_ID
    image.ResampleMode = Enum.ResamplerMode.Pixelated
    image.AnchorPoint = Vector2.new(0.5, 0.5)
    image.ZIndex = zIndex
    image.Interactable = false
    SetRect(image, rectName, parentTiles)
    return image
end

local function GetDot(index)
    local dot = arcDots[index]

    if not dot then
        dot = NewSprite("ArcDot", "ArcDot", 4, BoardConfig.SIZE)
        dot.Parent = board
        arcDots[index] = dot
    end

    return dot
end

local function GetTileMark(tile)
    local mark = tile:FindFirstChild("TileMark")

    if not mark then
        mark = NewSprite("TileMark", "TileMark", 2, 1)
        mark.Position = UDim2.fromScale(0.5, 0.5)
        mark.Size = UDim2.fromScale(1, 1)
        mark.Parent = tile
    end

    return mark
end

local function AimGun(angle)
    if not gunImage then return end

    aimAngle = angle

    -- Use the flipped sprite when aiming left so the gun is never upside down
    local flipped = math.cos(angle) < 0
    local rectName = flipped and gunSprite.FlippedRect or gunSprite.Rect
    local rect = SpriteConfig.Rects[rectName]
    local grip = gunSprite.Grip
    local gripY = flipped and rect[4] - grip.Y or grip.Y

    SetRect(gunImage, rectName, GUN_PIVOT_TILES)
    gunImage.AnchorPoint = Vector2.new(grip.X / rect[3], gripY / rect[4])

    gunPivot.Position = UDim2.fromScale(flipped and 1 - GUN_HOLD.X or GUN_HOLD.X, GUN_HOLD.Y)
    gunPivot.Rotation = -math.deg(angle)
end

local function HideDots(fromIndex)
    for i = fromIndex, #arcDots do
        arcDots[i].Visible = false
    end
end

local function GetTile(column, row)
    return board:FindFirstChild(BoardRules.GetTileName(column, row))
end

local function ClearPreviewTiles()
    for _, tile in pairs(previewTiles) do
        tile.Overlay.Visible = false
        GetTileMark(tile).Visible = false
    end

    previewTiles = {}
    lastPreviewKey = nil
end

-- Hit tiles are only recalculated when the preview key changes
local function UpdatePreviewTiles(previewKey, getHitTiles)
    if previewKey == lastPreviewKey then return end

    ClearPreviewTiles()
    lastPreviewKey = previewKey

    for _, target in pairs(getHitTiles()) do
        local tile = GetTile(target.Column, target.Row)

        if tile then
            tile.Overlay.BackgroundColor3 = HIT_COLOR
            tile.Overlay.BackgroundTransparency = PREVIEW_TRANSPARENCY
            tile.Overlay.Visible = true
            GetTileMark(tile).Visible = true
            table.insert(previewTiles, tile)
        end
    end
end

function ShotgunController.GetMouseBoardPosition()
    local inset = GuiService:GetGuiInset()
    local mouse = UserInputService:GetMouseLocation() - inset
    local relative = (mouse - board.AbsolutePosition) / board.AbsoluteSize

    return relative.X * BoardConfig.SIZE, (1 - relative.Y) * BoardConfig.SIZE
end

local function DrawArc()
    local weapon = aimWeapon or weapon
    local mode = aimWeapon and "Normal" or mode
    local column, row = getKingPosition()
    if not column then
        HideDots(1)
        ClearPreviewTiles()
        return
    end

    local originX, originY = ShotgunRules.GetKingOrigin(column, row)
    local targetX, targetY = ShotgunController.GetMouseBoardPosition()
    local angle, radius = ShotgunRules.GetAim(originX, originY, targetX, targetY, weapon)

    if not angle then
        HideDots(1)
        ClearPreviewTiles()
        return
    end

    -- Line abilities and knife swings only preview their tiles
    if lineRange or mode == "Alt" then
        local hitTiles = nil

        if lineRange then
            hitTiles = select(2, ShotgunRules.GetPreciseShot(column, row, targetX, targetY, lineRange))
        else
            hitTiles = select(2, ShotgunRules.GetFireResult(column, row, targetX, targetY, weapon, mode, isBlockingTile))
        end

        hitTiles = hitTiles or {}

        local tileNames = {}
        for _, target in pairs(hitTiles) do
            table.insert(tileNames, BoardRules.GetTileName(target.Column, target.Row))
        end

        UpdatePreviewTiles(table.concat(tileNames, ","), function()
            return hitTiles
        end)

        if hitTiles[1] then
            AimGun(math.atan2(hitTiles[1].Row - 0.5 - originY, hitTiles[1].Column - 0.5 - originX))
        end

        HideDots(1)
        return
    end

    local pointBlankColumn, pointBlankRow = ShotgunRules.GetPointBlankTarget(column, row, targetX, targetY, isBlockingTile)

    if pointBlankColumn then
        local pointBlankAngle = math.atan2(pointBlankRow - 0.5 - originY, pointBlankColumn - 0.5 - originX)

        UpdatePreviewTiles("PointBlank" .. BoardRules.GetTileName(pointBlankColumn, pointBlankRow), function()
            return {{Column = pointBlankColumn, Row = pointBlankRow}}
        end)
        AimGun(pointBlankAngle)
        HideDots(1)
        return
    end

    local previewKey = string.format("%d,%d,%.3f,%.2f", column, row, angle, radius)

    UpdatePreviewTiles(previewKey, function()
        return select(2, ShotgunRules.GetShot(originX, originY, angle, radius, isBlockingTile, weapon))
    end)
    AimGun(angle)

    local halfArc = math.rad(weapon.ArcDegrees) / 2
    local count = math.max(2, math.ceil(radius * halfArc * 2 / DOT_SPACING))
    local index = 0

    local function PlaceDot(dotAngle, dotRadius, rectName)
        index += 1
        local dot = GetDot(index)
        SetRect(dot, rectName, BoardConfig.SIZE)
        dot.Position = ToBoardUDim(originX + math.cos(dotAngle) * dotRadius, originY + math.sin(dotAngle) * dotRadius)
        dot.Visible = true
    end

    for i = 0, count do
        PlaceDot(angle - halfArc + halfArc * 2 * i / count, radius, "ArcDot")
    end

    for _, edgeAngle in pairs({angle - halfArc, angle + halfArc}) do
        for step = -TICK_LENGTH, TICK_LENGTH do
            if step ~= 0 then
                PlaceDot(edgeAngle, radius + step * DOT_SPACING * 0.8, "ArcEdge")
            end
        end
    end

    HideDots(index + 1)
end

local function FlashTile(column, row)
    local tile = GetTile(column, row)
    if not tile then return end

    local flash = Instance.new("Frame")
    flash.Name = "HitFlash"
    flash.BorderSizePixel = 0
    flash.Size = UDim2.fromScale(1, 1)
    flash.BackgroundColor3 = HIT_COLOR
    flash.BackgroundTransparency = 0.25
    flash.ZIndex = 2
    flash.Parent = tile

    task.delay(HIT_FLASH_TIME, function()
        flash:Destroy()
    end)
end

local function SetMode(newMode)
    if mode == newMode then return end

    mode = newMode
    ClearPreviewTiles()

    if ShotgunController.OnModeChanged then
        ShotgunController.OnModeChanged(mode)
    end
end

function ShotgunController.GetMode()
    return mode
end

function ShotgunController.GetWeapon()
    return weapon
end

function ShotgunController.SetWeapon(shotgunName, className)
    local newWeapon = ShotgunRules.GetWeapon(shotgunName, className)
    if newWeapon == weapon then return end

    weapon = newWeapon
    shotgunSprite = SpriteConfig.Guns[shotgunName]

    ClearPreviewTiles()
    ShotgunController.UpdateGunSprite()
end

function ShotgunController.UpdateGunSprite()
    local newSprite = (isRevolverAimed or isRevolverFiring) and SpriteConfig.Guns.Revolver or shotgunSprite
    if newSprite == gunSprite then return end

    gunSprite = newSprite
    AimGun(aimAngle)
end

-- weaponName previews that weapon's normal shot instead of the shotgun's; nil goes back to the shotgun
function ShotgunController.SetAimWeapon(weaponName)
    local newAim = weaponName and ShotgunRules.GetWeapon(weaponName) or nil
    if newAim == aimWeapon then return end

    aimWeapon = newAim
    ClearPreviewTiles()
end

-- The Gunslinger holds a revolver while aiming Fan the Hammer
function ShotgunController.SetRevolverAimed(isAimed)
    isRevolverAimed = isAimed
    ShotgunController.UpdateGunSprite()
end

-- Keeps the revolver out for duration seconds while Fan the Hammer fires
function ShotgunController.ShowRevolver(duration)
    revolverToken += 1
    local token = revolverToken

    isRevolverFiring = true
    ShotgunController.UpdateGunSprite()

    task.delay(duration, function()
        if revolverToken ~= token then return end

        isRevolverFiring = false
        ShotgunController.UpdateGunSprite()
    end)
end

-- Right click switches to the shotgun's alt mode, if it has one
function ShotgunController.ToggleMode()
    if not weapon or not weapon.AltMode then return end
    if lineRange then return end

    SetMode(mode == "Normal" and "Alt" or "Normal")
end

function ShotgunController.SetLineAim(range)
    if lineRange == range then return end

    lineRange = range
    ClearPreviewTiles()
end

function ShotgunController.SetActive(enabled)
    active = enabled and weapon ~= nil

    if not active then
        HideDots(1)
        ClearPreviewTiles()
        SetMode("Normal")
    end
end

function ShotgunController.AttachGun(rig)
    gunPivot = Instance.new("Frame")
    gunPivot.Name = "GunPivot"
    gunPivot.BackgroundTransparency = 1
    gunPivot.AnchorPoint = Vector2.new(0.5, 0.5)
    gunPivot.Size = UDim2.fromScale(GUN_PIVOT_TILES, GUN_PIVOT_TILES)
    gunPivot.ZIndex = 4
    gunPivot.Interactable = false
    gunPivot.Parent = rig

    gunImage = NewSprite("Shotgun", gunSprite.Rect, 4, GUN_PIVOT_TILES)
    gunImage.Position = UDim2.fromScale(0.5, 0.5)
    gunImage.Parent = gunPivot

    AimGun(aimAngle)
end

local function KickGun()
    if not gunImage then return end

    local rest = UDim2.fromScale(0.5, 0.5)
    gunImage.Position = UDim2.fromScale(0.5 - GUN_KICK / GUN_PIVOT_TILES, 0.5)

    TweenService:Create(gunImage, TweenInfo.new(GUN_KICK_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = rest,
    }):Play()
end

local function NewTracer()
    local tracer = Instance.new("Frame")
    tracer.Name = "Tracer"
    tracer.BorderSizePixel = 0
    tracer.AnchorPoint = Vector2.new(0.5, 0.5)
    tracer.BackgroundColor3 = TRACER_COLOR
    tracer.ZIndex = 5
    tracer.Interactable = false
    tracer.Visible = false

    local stroke = Instance.new("UIStroke")
    stroke.Color = OUTLINE_COLOR
    stroke.Thickness = 1
    stroke.Parent = tracer

    return tracer
end

-- Seconds until the shot reaches a point this far from the king
function ShotgunController.GetTravelTime(distance)
    return math.max(distance - MUZZLE_OFFSET, 0) / PELLET_SPEED
end

-- originColumn and originRow fire from another tile (enemy Kings); otherwise the shot comes from the player's king
function ShotgunController.PlayShot(pellets, hitTiles, onTileReached, originColumn, originRow)
    local column, row = originColumn, originRow

    if not column then
        column, row = getKingPosition()
        if not column then return end

        KickGun()
    end

    local originX, originY = ShotgunRules.GetKingOrigin(column, row)
    local tracers = {}

    for _, target in ipairs(pellets) do
        local deltaX = target.X - originX
        local deltaY = target.Y - originY
        local length = math.sqrt(deltaX * deltaX + deltaY * deltaY)

        if length > MUZZLE_OFFSET then
            local tracer = NewTracer()
            tracer.Rotation = -math.deg(math.atan2(deltaY, deltaX))
            tracer.Parent = board

            table.insert(tracers, {
                Frame = tracer,
                DirectionX = deltaX / length,
                DirectionY = deltaY / length,
                Length = length,
            })
        end
    end

    -- Every pellet leaves the muzzle on the same frame
    local startTime = time()
    local connection = nil

    connection = RunService.RenderStepped:Connect(function()
        local travelled = MUZZLE_OFFSET + (time() - startTime) * PELLET_SPEED
        local isFlying = false

        for _, tracer in pairs(tracers) do
            local head = math.min(travelled, tracer.Length)
            local tail = math.clamp(travelled - TRACER_LENGTH, MUZZLE_OFFSET, tracer.Length)

            if tail >= tracer.Length then
                tracer.Frame.Visible = false
            else
                isFlying = true

                local middle = (head + tail) / 2
                tracer.Frame.Position = ToBoardUDim(originX + tracer.DirectionX * middle, originY + tracer.DirectionY * middle)
                tracer.Frame.Size = UDim2.fromScale((head - tail) / BoardConfig.SIZE, TRACER_THICKNESS / BoardConfig.SIZE)
                tracer.Frame.Visible = true
            end
        end

        if isFlying then return end

        connection:Disconnect()

        for _, tracer in pairs(tracers) do
            tracer.Frame:Destroy()
        end
    end)

    -- Each tile flashes as the shot reaches it
    for _, target in pairs(hitTiles) do
        local distance = math.sqrt((target.Column - 0.5 - originX) ^ 2 + (target.Row - 0.5 - originY) ^ 2)

        task.delay(ShotgunController.GetTravelTime(distance), function()
            FlashTile(target.Column, target.Row)

            if onTileReached then
                onTileReached(target.Column, target.Row)
            end
        end)
    end
end

local init = false
function ShotgunController.Init(boardFrame, kingPositionGetter, blockingTileCheck)
    if init then return end
    init = true

    board = boardFrame
    getKingPosition = kingPositionGetter
    isBlockingTile = blockingTileCheck

    RunService.RenderStepped:Connect(function()
        if active then
            DrawArc()
        end
    end)

    -- Board tiles sink mouse input, so processed isn't checked here
    UserInputService.InputBegan:Connect(function(input)
        if not active then return end
        if input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end

        ShotgunController.ToggleMode()
    end)
end

return ShotgunController
