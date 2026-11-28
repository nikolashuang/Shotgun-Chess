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
    -- Added to the piece's base damage (Expedition Act scaling, summon upgrades)
    self.DamageBonus = 0

    self.BleedDamage = 0
    self.BleedTurns = 0

    self.StunTurns = 0
    self.isStunShown = false

    return self
end

function PieceClass:GetDamage()
    return (PieceConfig.Damage[self.Type] or 0) + self.DamageBonus
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

function PieceClass:Stun(turns)
    self.StunTurns = math.max(self.StunTurns, turns)
end

function PieceClass:IsStunned()
    return self.StunTurns > 0
end

-- Called once per enemy turn; returns true when the piece may move or attack this turn
function PieceClass:TickStun()
    if not self:IsStunned() then return true end

    self.StunTurns -= 1

    return false
end

return PieceClass
