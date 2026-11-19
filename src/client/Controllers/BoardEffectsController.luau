local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)
local SpriteConfig = require(ReplicatedStorage.Shared.Sprites.SpriteConfig)
local EffectSpriteClass = require(script.Parent.Parent.UI.EffectSpriteClass)
local PieceController = require(script.Parent.PieceController)
local SpeedController = require(script.Parent.SpeedController)

-- In tiles
local SOUL_LIFT = 0.42
local SOUL_BOB = 0.06
local GHOST_SIZE = 1.05
local GHOST_TRANSPARENCY = 0.35
local GHOST_COLOR = Color3.fromHex("7FE3C8")
local BOLT_RISE = 0.7
local TRAP_RISE = 0.9
-- Raises the snap from the tile center onto the trapped piece's body
local TRAP_SNAP_LIFT = 0.35

-- In seconds
local FADE_TIME = 0.35
local ABSORB_TIME = 0.4
local BOLT_TIME = 0.8
local BOLT_STAGGER = 0.15
local BOLAS_FLIGHT_TIME = 0.35
-- Waits for an enemy's hop to land before its trap snaps
local TRAP_SNAP_DELAY = 0.25
local TRAP_HOLD_TIME = 0.15
local TRAP_FADE_TIME = 1

-- See-through enough that pieces inside still show
local SMOKE_TRANSPARENCY = 0.4

local board = nil
local layers = {}
local souls = {}
local traps = {}
local smoke = nil
local getKingTile = nil

-- Board-level effects that aren't tied to one piece: souls, traps, smoke, energy pickups and bolas throws
local BoardEffectsController = {}

local function ToBoardPosition(column, row)
    return UDim2.fromScale((column - 0.5) / BoardConfig.SIZE, 1 - (row - 0.5) / BoardConfig.SIZE)
end

local function GetLayer(name, zIndex)
    if layers[name] then return layers[name] end

    local layer = Instance.new("Frame")
    layer.Name = name
    layer.BackgroundTransparency = 1
    layer.Size = UDim2.fromScale(1, 1)
    layer.ZIndex = zIndex
    layer.Interactable = false
    layer.Parent = board

    layers[name] = layer

    return layer
end

-- Effect sized in tiles at the pieces' pixel scale, centered on a tile (offset is in tiles, up is negative)
local function NewEffect(effectName, layer, column, row, offsetY)
    local effect = EffectSpriteClass.new(effectName, layer)
    effect.Image.Size = UDim2.fromScale(effect.Width / BoardConfig.SIZE, effect.Height / BoardConfig.SIZE)
    effect.BasePosition = ToBoardPosition(column, row) + UDim2.fromScale(0, (offsetY or 0) / BoardConfig.SIZE)

    return effect
end

-- EffectSpriteClass sets Position every frame from BasePosition, so motion moves the base instead
local function GlideTo(effect, target, duration, onDone)
    local from = effect.BasePosition
    local startTime = time()

    task.spawn(function()
        while time() - startTime < duration do
            local alpha = (time() - startTime) / duration
            effect.BasePosition = from:Lerp(target, 1 - (1 - alpha) ^ 2)
            task.wait()
        end

        effect.BasePosition = target

        if onDone then
            onDone()
        end
    end)
end

-- Fades the effect out (optionally drifting to target) and destroys it
local function FadeAndDestroy(effect, target, duration)
    duration = SpeedController.Scale(duration or FADE_TIME)

    TweenService:Create(effect.Image, TweenInfo.new(duration), {ImageTransparency = 1}):Play()
    GlideTo(effect, target or effect.BasePosition, duration, function()
        effect:Destroy()
    end)
end

--SOULS--

-- A faint copy of the piece the soul came from, so players can tell what Assimilate would give them
local function NewGhost(soul)
    local rows = SpriteConfig.Pieces[soul.Type]

    local ghost = Instance.new("ImageLabel")
    ghost.Name = "SoulGhost"
    ghost.BackgroundTransparency = 1
    ghost.Image = SpriteConfig.ASSET_ID
    ghost.ImageRectOffset = Vector2.new(SpriteConfig.Teams.White, rows.Idle)
    ghost.ImageRectSize = Vector2.new(SpriteConfig.CELL, SpriteConfig.CELL)
    ghost.ImageTransparency = GHOST_TRANSPARENCY
    ghost.ImageColor3 = GHOST_COLOR
    ghost.ResampleMode = Enum.ResamplerMode.Pixelated
    ghost.AnchorPoint = Vector2.new(0.5, 0.5)
    ghost.Size = UDim2.fromScale(GHOST_SIZE / BoardConfig.SIZE, GHOST_SIZE / BoardConfig.SIZE)
    ghost.Position = ToBoardPosition(soul.Column, soul.Row)
    ghost.Interactable = false
    ghost.Parent = GetLayer("Souls", 3)

    return ghost
end

function BoardEffectsController.AddSoul(id, pieceType, column, row)
    local soul = {Id = id, Type = pieceType, Column = column, Row = row}

    soul.Ghost = NewGhost(soul)
    soul.Effect = NewEffect("Soul", GetLayer("Souls", 3), column, row, -SOUL_LIFT)
    soul.Effect.Image.AnchorPoint = Vector2.new(0.5, 0.5)
    soul.Effect.BobHeight = SOUL_BOB / BoardConfig.SIZE

    souls[id] = soul
end

-- Absorbed souls fly into the king; used ones just fade
function BoardEffectsController.RemoveSouls(ids, isAbsorbed)
    local kingColumn, kingRow = getKingTile()

    for _, id in ipairs(ids) do
        local soul = souls[id]

        if soul then
            souls[id] = nil
            soul.Ghost:Destroy()

            if isAbsorbed and kingColumn then
                soul.Effect.BobHeight = 0
                FadeAndDestroy(soul.Effect, ToBoardPosition(kingColumn, kingRow), ABSORB_TIME)
            else
                FadeAndDestroy(soul.Effect)
            end
        end
    end
end

function BoardEffectsController.GetSouls()
    return souls
end

function BoardEffectsController.GetSoulAt(column, row)
    for _, soul in pairs(souls) do
        if soul.Column == column and soul.Row == row then return soul end
    end

    return nil
end

--TRAPS--

function BoardEffectsController.AddTraps(placed)
    for _, trap in ipairs(placed) do
        local effect = NewEffect("Trap", GetLayer("Ground", 2), trap.Column, trap.Row)
        traps[trap.Id] = {Id = trap.Id, Column = trap.Column, Row = trap.Row, Effect = effect}
    end
end

-- The jaws clamp shut over the enemy, then the trap floats up and fades away
function BoardEffectsController.SpringTrap(trapId, pieceId, health)
    local trap = traps[trapId]
    traps[trapId] = nil

    task.delay(SpeedController.Scale(TRAP_SNAP_DELAY), function()
        PieceController.ApplyDamage(pieceId, health)

        if not trap then return end

        trap.Effect:Destroy()

        local snap = NewEffect("TrapSnap", GetLayer("Overhead", 7), trap.Column, trap.Row, -TRAP_SNAP_LIFT)
        snap:PlayOnce(function()
            task.delay(SpeedController.Scale(TRAP_HOLD_TIME), function()
                FadeAndDestroy(snap, snap.BasePosition - UDim2.fromScale(0, TRAP_RISE / BoardConfig.SIZE), TRAP_FADE_TIME)
            end)
        end)
    end)
end

function BoardEffectsController.GetTrapAt(column, row)
    for _, trap in pairs(traps) do
        if trap.Column == column and trap.Row == row then return trap end
    end

    return nil
end

--SMOKE--

-- radius is in tiles from the center; nil column clears the cloud
function BoardEffectsController.SetSmoke(column, row, radius)
    if smoke then
        FadeAndDestroy(smoke)
        smoke = nil
    end

    if not column then return end

    local size = (radius * 2 + 1) / BoardConfig.SIZE

    smoke = EffectSpriteClass.new("Smoke", GetLayer("Smoke", 5))
    smoke.Image.Size = UDim2.fromScale(size, size)
    smoke.Image.ImageTransparency = SMOKE_TRANSPARENCY
    smoke.BasePosition = ToBoardPosition(column, row)
end

--ENERGY AND BOLAS--

-- One bolt per energy floats up from where it dropped
function BoardEffectsController.ShowEnergy(column, row, amount)
    for i = 1, amount do
        task.delay(SpeedController.Scale((i - 1) * BOLT_STAGGER), function()
            local bolt = NewEffect("Bolt", GetLayer("Overhead", 7), column, row, -0.3)
            FadeAndDestroy(bolt, bolt.BasePosition - UDim2.fromScale(0, BOLT_RISE / BoardConfig.SIZE), BOLT_TIME)
        end)
    end
end

-- A spinning bolas flies from the king to the piece, which is then shown tied up
function BoardEffectsController.ThrowBolas(pieceId)
    local piece = PieceController.Get(pieceId)
    local kingColumn, kingRow = getKingTile()

    if not piece or not kingColumn then
        PieceController.SetStunned(pieceId, true, "Bolas")
        return
    end

    local bolas = NewEffect("Bolas", GetLayer("Overhead", 7), kingColumn, kingRow, -0.4)
    local target = ToBoardPosition(piece.Rig.Column, piece.Rig.Row) - UDim2.fromScale(0, 0.4 / BoardConfig.SIZE)

    GlideTo(bolas, target, SpeedController.Scale(BOLAS_FLIGHT_TIME), function()
        bolas:Destroy()
        PieceController.SetStunned(pieceId, true, "Bolas")
    end)
end

function BoardEffectsController.Clear()
    for _, soul in pairs(souls) do
        soul.Ghost:Destroy()
        soul.Effect:Destroy()
    end

    for _, trap in pairs(traps) do
        trap.Effect:Destroy()
    end

    if smoke then
        smoke:Destroy()
    end

    souls = {}
    traps = {}
    smoke = nil
end

local init = false
function BoardEffectsController.Init(boardFrame, kingTileGetter)
    if init then return end
    init = true

    board = boardFrame
    getKingTile = kingTileGetter
end

return BoardEffectsController
