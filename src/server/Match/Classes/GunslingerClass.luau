local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShotgunRules = require(ReplicatedStorage.Shared.Combat.ShotgunRules)
local ClassConfig = require(ReplicatedStorage.Shared.Combat.ClassConfig)
local ArgumentRules = require(script.Parent.Parent.ArgumentRules)

local GunslingerConfig = ClassConfig.Classes.Gunslinger

-- Deadeye is applied to the shotgun itself (ShotgunRules.GetWeapon); Fan the Hammer fires a revolver
-- down a line, High Noon's Bounty marks enemies that pay energy when they die
local GunslingerClass = {}

GunslingerClass.__index = GunslingerClass

function GunslingerClass.new(match)
    local self = setmetatable({}, GunslingerClass)

    self.Match = match
    self.Marks = {}

    return self
end

-- payload.X, payload.Y is the aim; every shot hits the first enemy still standing in the line, or misses
function GunslingerClass:Special(payload)
    if not ArgumentRules.IsFiniteNumber(payload.X) or not ArgumentRules.IsFiniteNumber(payload.Y) then return false end

    local match = self.Match
    local fan = GunslingerConfig.FanTheHammer
    local _, lineTiles = ShotgunRules.GetPreciseShot(match.King.Column, match.King.Row, payload.X, payload.Y, fan.Range)
    if not lineTiles then return false end

    local lastTile = lineTiles[#lineTiles]
    local shots = {}

    for _ = 1, fan.Shots do
        local target = nil

        for _, tile in ipairs(lineTiles) do
            local piece = match:GetPieceAt(tile.Column, tile.Row)

            if piece and piece.Team ~= "White" then
                target = piece
                break
            end
        end

        if target and match.Random:NextNumber() < fan.HitChance then
            local column, row = target.Column, target.Row
            match:DamagePiece(target, fan.Damage)

            table.insert(shots, {Column = column, Row = row, Id = target.Id, Health = target.Health})
        else
            table.insert(shots, {Column = lastTile.Column, Row = lastTile.Row})
        end
    end

    match:Send("FanFired", shots)

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
        if not piece or piece.Team ~= "Black" then return false end
        if table.find(pieces, piece) then return false end

        table.insert(pieces, piece)
    end

    for _, piece in ipairs(pieces) do
        self.Marks[piece.Id] = true
        self.Match:Send("PieceMarked", piece.Id, true)
    end

    return true
end

function GunslingerClass:OnEnemyKilled(piece)
    if not self.Marks[piece.Id] then return end

    self.Marks[piece.Id] = nil

    local energy = GunslingerConfig.Bounty.Energy
    self.Match:AddEnergy(energy)
    self.Match:Send("EnergyDropped", piece.Column, piece.Row, energy)
end

function GunslingerClass:GetState()
    return {}
end

return GunslingerClass
