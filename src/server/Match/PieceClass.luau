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

    self.BleedDamage = 0
    self.BleedTurns = 0

    return self
end

-- Returns the health actually lost
function PieceClass:TakeDamage(amount)
    local dealt = math.min(amount, self.Health)
    self.Health -= dealt

    return dealt
end

function PieceClass:IsAlive()
    return self.Health > 0
end

-- Reapplying refreshes the bleed instead of stacking it
function PieceClass:ApplyBleed(damage, turns)
    self.BleedDamage = damage
    self.BleedTurns = turns
end

function PieceClass:IsBleeding()
    return self.BleedTurns > 0
end

function PieceClass:TickBleed()
    self.BleedTurns -= 1

    return self.BleedDamage
end

return PieceClass
