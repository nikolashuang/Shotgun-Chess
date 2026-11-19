local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardRules = require(ReplicatedStorage.Shared.Board.BoardRules)
local ClassConfig = require(ReplicatedStorage.Shared.Combat.ClassConfig)
local ArgumentRules = require(script.Parent.Parent.ArgumentRules)

local OutlawConfig = ClassConfig.Classes.Outlaw

-- Opportunist adds damage against lone enemies, Conceal throws smoke enemies can't attack into,
-- Ambush jumps the king next to an enemy and powers up the next shot
local OutlawClass = {}

OutlawClass.__index = OutlawClass

function OutlawClass.new(side)
    local self = setmetatable({}, OutlawClass)

    self.Side = side
    self.Match = side.Match

    -- {Column, Row, Turns} of the smoke cloud's center, or nil
    self.Smoke = nil

    return self
end

-- An enemy is isolated when no other enemy stands next to it
function OutlawClass:GetHitBonus(piece)
    for _, other in pairs(self.Match.Pieces) do
        if other ~= piece and other.Team == piece.Team and BoardRules.GetDistance(piece.Column, piece.Row, other.Column, other.Row) <= 1 then
            return 0
        end
    end

    return OutlawConfig.Opportunist.Damage
end

-- payload.Column, payload.Row is the cloud's center
function OutlawClass:Special(payload)
    local column, row = payload.Column, payload.Row
    if not ArgumentRules.IsTile(column, row) then return false end
    if not BoardRules.IsOnBoard(column, row) then return false end

    local conceal = OutlawConfig.Conceal
    local king = self.Side.King
    if BoardRules.GetDistance(king.Column, king.Row, column, row) > conceal.Range then return false end

    self.Smoke = {Column = column, Row = row, Turns = conceal.Turns}
    self.Match:SendAll("SmokeChanged", column, row, conceal.Radius)

    return true
end

-- Enemies can't attack or shoot anything inside the smoke
function OutlawClass:IsProtected(column, row)
    local smoke = self.Smoke
    if not smoke then return false end

    return BoardRules.GetDistance(smoke.Column, smoke.Row, column, row) <= OutlawConfig.Conceal.Radius
end

function OutlawClass:OnEnemyTurnEnd()
    if not self.Smoke then return end

    self.Smoke.Turns -= 1
    if self.Smoke.Turns > 0 then return end

    self.Smoke = nil
    self.Match:SendAll("SmokeChanged", nil)
end

-- Any empty tile next to an enemy
function OutlawClass:IsAmbushTile(column, row)
    if not BoardRules.IsOnBoard(column, row) then return false end
    if self.Match:IsOccupied(column, row) then return false end

    for _, piece in pairs(self.Match.Pieces) do
        if piece.Team == self.Side.EnemyTeam and BoardRules.GetDistance(column, row, piece.Column, piece.Row) <= OutlawConfig.Ambush.MaxEnemyDistance then
            return true
        end
    end

    return false
end

-- payload.Column, payload.Row is where the king lands; it doesn't use up the turn's move
function OutlawClass:Ultimate(payload)
    local column, row = payload.Column, payload.Row
    if not ArgumentRules.IsTile(column, row) then return false end
    if not self:IsAmbushTile(column, row) then return false end

    local side = self.Side
    side.King:SetTile(column, row)
    side.NextShotBonus += OutlawConfig.Ambush.Damage

    self.Match:SendKingMoved(side, "KingAmbushed")
    self.Match:OnUnitMoved(side.King)

    return true
end

function OutlawClass:GetState()
    return {}
end

return OutlawClass
