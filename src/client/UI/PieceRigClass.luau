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

local PieceRigClass = {}

PieceRigClass.__index = PieceRigClass

local function ToBoardPosition(column, row)
    return UDim2.fromScale((column - 0.5) / BoardConfig.SIZE, 1 - (row - 0.5) / BoardConfig.SIZE)
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

    return self
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

function PieceRigClass:Die()
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
    self.Rig:Destroy()
end

return PieceRigClass
