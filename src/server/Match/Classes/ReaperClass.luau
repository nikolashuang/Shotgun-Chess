local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClassConfig = require(ReplicatedStorage.Shared.Combat.ClassConfig)
local ArgumentRules = require(script.Parent.Parent.ArgumentRules)

local ReaperConfig = ClassConfig.Classes.Reaper

-- Reap leaves a soul where any piece dies; Assimilate spends one to move like its piece,
-- Reaper's High absorbs them all for healing and next-shot damage
local ReaperClass = {}

ReaperClass.__index = ReaperClass

function ReaperClass.new(side)
    local self = setmetatable({}, ReaperClass)

    self.Side = side
    self.Match = side.Match

    self.Souls = {}

    -- Piece type the king moves like for the rest of this turn
    self.AssimilatedType = nil

    return self
end

function ReaperClass:CountSouls()
    local count = 0

    for _ in pairs(self.Souls) do
        count += 1
    end

    return count
end

-- The rival sees this Reaper's souls too (in red); soul ids are shared across the match so they never clash
function ReaperClass:OnPieceKilled(piece)
    if ReaperConfig.NO_SOUL[piece.Type] then return end

    local match = self.Match
    local soul = {Id = match.NextSoulId, Type = piece.Type, Column = piece.Column, Row = piece.Row}
    match.NextSoulId += 1
    self.Souls[soul.Id] = soul

    self.Side:Send("SoulAdded", soul.Id, soul.Type, soul.Column, soul.Row)
    match:SendTo(match:GetOpponent(self.Side), "SoulAdded", soul.Id, soul.Type, soul.Column, soul.Row, true)
end

function ReaperClass:RemoveSouls(ids, isAbsorbed)
    self.Side:Send("SoulsRemoved", ids, isAbsorbed)
    self.Match:SendTo(self.Match:GetOpponent(self.Side), "SoulsRemoved", ids)
end

-- payload.SoulId; the bonus move doesn't use up the king's own move, so it works before or after it
function ReaperClass:Special(payload)
    if not ArgumentRules.IsWholeNumber(payload.SoulId) then return false end

    local soul = self.Souls[payload.SoulId]
    if not soul then return false end

    self.Souls[soul.Id] = nil
    self.AssimilatedType = soul.Type

    self:RemoveSouls({soul.Id})

    return true
end

function ReaperClass:GetMoveType()
    return self.AssimilatedType
end

function ReaperClass:OnKingMoved()
    self.AssimilatedType = nil
end

-- An unused Assimilate expires with the turn
function ReaperClass:OnPlayerTurnStart()
    self.AssimilatedType = nil
end

function ReaperClass:Ultimate()
    local count = self:CountSouls()
    if count == 0 then return false end

    local high = ReaperConfig.ReapersHigh
    local side = self.Side
    local absorbed = {}

    for id in pairs(self.Souls) do
        table.insert(absorbed, id)
    end

    self.Souls = {}

    side.King:Heal(high.HealPerSoul * count)
    side.NextShotBonus += high.DamagePerSoul * count

    self:RemoveSouls(absorbed, true)
    side:Send("KingHealed", side.King.Health)
    self.Match:ShowDamage(side.King, side)

    return true
end

function ReaperClass:GetState()
    return {Assimilate = self.AssimilatedType, Souls = self:CountSouls()}
end

return ReaperClass
