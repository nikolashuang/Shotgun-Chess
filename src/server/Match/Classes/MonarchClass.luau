local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClassConfig = require(ReplicatedStorage.Shared.Combat.ClassConfig)

local MonarchConfig = ClassConfig.Classes.Monarch

-- Loyalty makes the first Queen each match cheaper, Morale shields every allied piece until the next turn,
-- Unyielding gives every allied piece extra damage for the rest of the turn
local MonarchClass = {}

MonarchClass.__index = MonarchClass

function MonarchClass.new(side)
    local self = setmetatable({}, MonarchClass)

    self.Side = side
    self.Match = side.Match

    self.hasSummonedQueen = false
    self.isUnyielding = false
    -- Ids of pieces holding a Morale shield, so it can be taken off next turn
    self.Shielded = {}

    return self
end

function MonarchClass:GetAllies()
    local allies = {}

    for _, piece in pairs(self.Match.Pieces) do
        if piece.Team == self.Side.Team and piece.Type ~= "King" then
            table.insert(allies, piece)
        end
    end

    return allies
end

function MonarchClass:GetSummonCost(pieceType)
    if pieceType == "Queen" and not self.hasSummonedQueen then
        return MonarchConfig.Loyalty.QueenCost
    end

    return nil
end

function MonarchClass:OnSummoned(pieceType)
    if pieceType == "Queen" then
        self.hasSummonedQueen = true
    end
end

function MonarchClass:SetShield(piece, amount)
    piece.Shield = amount
    self.Shielded[piece.Id] = amount > 0 or nil
    self.Match:SendAll("PieceShielded", piece.Id, amount)
end

-- Needs at least one piece to shield, so it can't be wasted
function MonarchClass:Special()
    local allies = self:GetAllies()
    if #allies == 0 then return false end

    for _, piece in ipairs(allies) do
        self:SetShield(piece, MonarchConfig.Morale.Shield)
    end

    return true
end

function MonarchClass:Ultimate()
    if #self:GetAllies() == 0 then return false end

    self.isUnyielding = true

    return true
end

function MonarchClass:GetAllyDamageBonus()
    return self.isUnyielding and MonarchConfig.Unyielding.Damage or 0
end

-- Shields and Unyielding both last until the start of the Monarch's next turn
function MonarchClass:OnPlayerTurnStart()
    self.isUnyielding = false

    for id in pairs(self.Shielded) do
        local piece = self.Match.Pieces[id]

        if piece then
            self:SetShield(piece, 0)
        end
    end

    self.Shielded = {}
end

function MonarchClass:GetState()
    return {
        QueenCost = not self.hasSummonedQueen and MonarchConfig.Loyalty.QueenCost or nil,
        AllyDamageBonus = self:GetAllyDamageBonus(),
    }
end

return MonarchClass
