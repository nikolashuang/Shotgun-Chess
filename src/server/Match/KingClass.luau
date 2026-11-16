local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardRules = require(ReplicatedStorage.Shared.Board.BoardRules)

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

function KingClass:Fire(column, row)
    return BoardRules.GetShotgunArea(self.Column, self.Row, column, row)
end

return KingClass
