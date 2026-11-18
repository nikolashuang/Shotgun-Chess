local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardRules = require(ReplicatedStorage.Shared.Board.BoardRules)
local ShotgunRules = require(ReplicatedStorage.Shared.Combat.ShotgunRules)
local ClassConfig = require(ReplicatedStorage.Shared.Combat.ClassConfig)
local ArgumentRules = require(script.Parent.Parent.ArgumentRules)

local HunterConfig = ClassConfig.Classes.Hunter
local TrapConfig = HunterConfig.Traps

-- Collector can drop energy from kills, Trap Layout lays hidden bear traps,
-- Hunting Strike stuns everything nearby with bolas
local HunterClass = {}

HunterClass.__index = HunterClass

function HunterClass.new(match)
    local self = setmetatable({}, HunterClass)

    self.Match = match

    self.Traps = {}
    self.NextTrapId = 1

    return self
end

function HunterClass:GetTrapAt(column, row)
    for _, trap in pairs(self.Traps) do
        if trap.Column == column and trap.Row == row then return trap end
    end

    return nil
end

function HunterClass:OnEnemyKilled(piece)
    local collector = HunterConfig.Collector
    if self.Match.Random:NextNumber() >= collector.Chance then return end

    self.Match:AddEnergy(collector.Energy)
    self.Match:Send("EnergyDropped", piece.Column, piece.Row, collector.Energy)
end

-- payload.Tiles is a list of {Column, Row}: up to Traps.Count empty, trap-free tiles near the king
function HunterClass:Special(payload)
    local tiles = payload.Tiles
    if typeof(tiles) ~= "table" then return false end
    if #tiles < 1 or #tiles > TrapConfig.Count then return false end

    local king = self.Match.King
    local seen = {}

    for _, tile in ipairs(tiles) do
        if typeof(tile) ~= "table" then return false end

        local column, row = tile.Column, tile.Row
        if not ArgumentRules.IsTile(column, row) then return false end
        if not BoardRules.IsOnBoard(column, row) then return false end
        if BoardRules.GetDistance(king.Column, king.Row, column, row) > TrapConfig.Range then return false end
        if self.Match:IsOccupied(column, row) then return false end
        if self:GetTrapAt(column, row) then return false end
        if seen[column * 100 + row] then return false end

        seen[column * 100 + row] = true
    end

    local placed = {}

    for _, tile in ipairs(tiles) do
        local trap = {Id = self.NextTrapId, Column = tile.Column, Row = tile.Row}
        self.NextTrapId += 1
        self.Traps[trap.Id] = trap

        table.insert(placed, trap)
    end

    self.Match:Send("TrapsPlaced", placed)

    return true
end

-- Enemies don't know where traps are, so they walk (or get knocked) right into them
function HunterClass:OnEnemyMoved(piece)
    local trap = self:GetTrapAt(piece.Column, piece.Row)
    if not trap then return end

    self.Traps[trap.Id] = nil

    local match = self.Match
    match:DamagePiece(piece, TrapConfig.Damage)
    match:Send("TrapSprung", trap.Id, piece.Id, piece.Health)

    if piece:IsAlive() then
        match:StunPiece(piece, TrapConfig.StunTurns, "Stars")
    end
end

-- A move or attack whose straight line crosses a trap stops on the trap's square and springs it
-- Returns true when the piece was caught, which cancels the rest of its move or attack
-- Knights jump over traps they cross; only landing on one catches them
function HunterClass:InterceptPath(piece, column, row)
    if piece.Type == "Knight" then return false end

    local columnStep = math.sign(column - piece.Column)
    local rowStep = math.sign(row - piece.Row)
    local columnDistance = math.abs(column - piece.Column)
    local rowDistance = math.abs(row - piece.Row)

    if columnDistance ~= 0 and rowDistance ~= 0 and columnDistance ~= rowDistance then return false end

    for step = 1, math.max(columnDistance, rowDistance) - 1 do
        local trap = self:GetTrapAt(piece.Column + columnStep * step, piece.Row + rowStep * step)

        if trap then
            piece.Column = trap.Column
            piece.Row = trap.Row

            self.Match:Send("PieceMoved", piece.Id, trap.Column, trap.Row)
            self:OnEnemyMoved(piece)

            return true
        end
    end

    return false
end

-- payload.X, payload.Y is the aim; the bolas cover exactly what a Double Barrel shot would hit there
function HunterClass:Ultimate(payload)
    if not ArgumentRules.IsFiniteNumber(payload.X) or not ArgumentRules.IsFiniteNumber(payload.Y) then return false end

    local strike = HunterConfig.HuntingStrike
    local match = self.Match
    local king = match.King

    local function IsEnemyTile(column, row)
        local piece = match:GetPieceAt(column, row)
        return piece ~= nil and piece.Team ~= "White"
    end

    local weapon = ShotgunRules.GetWeapon(strike.Weapon)
    local _, hitTiles = ShotgunRules.GetFireResult(king.Column, king.Row, payload.X, payload.Y, weapon, "Normal", IsEnemyTile)
    if not hitTiles then return false end

    local targets = {}

    for _, tile in pairs(hitTiles) do
        local piece = match:GetPieceAt(tile.Column, tile.Row)

        if piece and piece.Team == "Black" and piece.Type ~= "King" then
            table.insert(targets, piece)
        end
    end

    -- Nothing to stun means the charge isn't spent
    if #targets == 0 then return false end

    -- The client throws a bolas at each piece stunned with the "Bolas" look
    for _, piece in ipairs(targets) do
        self.Match:StunPiece(piece, strike.StunTurns, "Bolas")
    end

    return true
end

function HunterClass:GetState()
    return {}
end

return HunterClass
