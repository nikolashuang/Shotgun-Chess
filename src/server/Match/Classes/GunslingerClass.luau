local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShotgunRules = require(ReplicatedStorage.Shared.Combat.ShotgunRules)
local ClassConfig = require(ReplicatedStorage.Shared.Combat.ClassConfig)
local ArgumentRules = require(script.Parent.Parent.ArgumentRules)

local GunslingerConfig = ClassConfig.Classes.Gunslinger

-- Deadly Rounds is applied to the shotgun itself (ShotgunRules.GetWeapon); Fan the Hammer fires a revolver
-- down a line, High Noon's Bounty marks enemies that pay energy when they die
local GunslingerClass = {}

GunslingerClass.__index = GunslingerClass

function GunslingerClass.new(side)
    local self = setmetatable({}, GunslingerClass)

    self.Side = side
    self.Match = side.Match
    self.Marks = {}

    return self
end

-- payload.X, payload.Y is the aim; every shot hits the first enemy still standing in the line, or misses
function GunslingerClass:Special(payload)
    if not ArgumentRules.IsFiniteNumber(payload.X) or not ArgumentRules.IsFiniteNumber(payload.Y) then return false end

    local match = self.Match
    local side = self.Side
    local fan = GunslingerConfig.FanTheHammer
    local _, lineTiles = ShotgunRules.GetPreciseShot(side.King.Column, side.King.Row, payload.X, payload.Y, fan.Range)
    if not lineTiles then return false end

    local lastTile = lineTiles[#lineTiles]
    local shots = {}

    for _ = 1, fan.Shots do
        local target = nil

        for _, tile in ipairs(lineTiles) do
            local piece = match:GetPieceAt(tile.Column, tile.Row)

            if piece and piece.Team ~= side.Team then
                target = piece
                break
            end
        end

        -- Each shot rolls its own hit chance, and again for a target inside smoke
        if target and match.Random:NextNumber() < fan.HitChance and match:RollHit(target.Column, target.Row, side) then
            local column, row = target.Column, target.Row
            match:DamagePiece(target, fan.Damage, side, true)
            match:ShowDamage(target, side)

            table.insert(shots, {Column = column, Row = row, Id = target.Id, Health = target.Health})
        else
            table.insert(shots, {Column = lastTile.Column, Row = lastTile.Row})
        end
    end

    side:Send("FanFired", shots)

    return true
end

-- payload.Targets is a list of enemy piece ids; up to Bounty.Marks of them
function GunslingerClass:Ultimate(payload)
    local targets = payload.Targets
    if typeof(targets) ~= "table" then return false end
    if #targets < 1 or #targets > GunslingerConfig.Bounty.Marks then return false end

    local pieces = {}

    for _, id in ipairs(targets) do
        local piece = ArgumentRules.IsWholeNumber(id) and self.Match.Pieces[id]
        if not piece or piece.Team ~= self.Side.EnemyTeam then return false end
        if table.find(pieces, piece) then return false end

        table.insert(pieces, piece)
    end

    for _, piece in ipairs(pieces) do
        self.Marks[piece.Id] = true
        self.Side:Send("PieceMarked", piece.Id, true)
    end

    return true
end

function GunslingerClass:OnEnemyKilled(piece)
    if not self.Marks[piece.Id] then return end

    self.Marks[piece.Id] = nil

    local energy = GunslingerConfig.Bounty.Energy
    self.Side:AddEnergy(energy)
    self.Side:Send("EnergyDropped", piece.Column, piece.Row, energy)
end

function GunslingerClass:GetState()
    return {}
end

return GunslingerClass
