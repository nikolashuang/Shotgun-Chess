local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardRules = require(ReplicatedStorage.Shared.Board.BoardRules)
local ShotgunRules = require(ReplicatedStorage.Shared.Combat.ShotgunRules)

local KingClass = {}

KingClass.__index = KingClass

function KingClass.new(player, column, row)
    local self = setmetatable({}, KingClass)

    self.Player = player

    self.Column = column
    self.Row = row

    self.MaxHealth = 15
    self.Health = 15

    return self
end

function KingClass:MoveTo(column, row)
    if not BoardRules.IsValidKingMove(self.Column, self.Row, column, row) then return false end

    self.Column = column
    self.Row = row

    return true
end

function KingClass:Fire(targetX, targetY, isBlocking)
    local originX, originY = ShotgunRules.GetKingOrigin(self.Column, self.Row)
    local angle, radius = ShotgunRules.GetAim(originX, originY, targetX, targetY)

    if not angle then return nil end

    return ShotgunRules.GetShot(originX, originY, angle, radius, isBlocking)
end

return KingClass
