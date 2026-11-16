local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PieceConfig = require(ReplicatedStorage.Shared.Board.PieceConfig)

local PieceClass = {}

PieceClass.__index = PieceClass

function PieceClass.new(id, pieceType, team, column, row)
    local self = setmetatable({}, PieceClass)

    self.Id = id
    self.Type = pieceType
    self.Team = team

    self.Column = column
    self.Row = row

    self.MaxHealth = PieceConfig.Health[pieceType]
    self.Health = self.MaxHealth

    return self
end

function PieceClass:TakeDamage(amount)
    self.Health = math.max(self.Health - amount, 0)
end

function PieceClass:IsAlive()
    return self.Health > 0
end

return PieceClass
