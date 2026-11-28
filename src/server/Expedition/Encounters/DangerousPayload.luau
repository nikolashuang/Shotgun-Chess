local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)
local ExpeditionConfig = require(ReplicatedStorage.Shared.Expedition.ExpeditionConfig)
local EncounterRules = require(script.Parent.Parent.EncounterRules)

local Config = ExpeditionConfig.Exclusives.DangerousPayload

-- Outskirts Regional Encounter: a payload rolls up the board one row every few turns while an army of Rooks and Bishops hunts
-- it with no care for themselves, and a new wave of them arrives every few rounds.
-- Delivering it wins; losing it fails the encounter
local DangerousPayload = {}
DangerousPayload.__index = DangerousPayload

-- Rooks and Bishops bought with the allocation, kept off the payload's starting tile
function DangerousPayload.GetEnemies(run)
    return EncounterRules.Generate(run.Points, "Battle", nil, {
        Pool = Config.POOL,
        Taken = {Config.PAYLOAD_TILE, Config.KING_TILE},
    })
end

function DangerousPayload.new(run)
    local self = setmetatable({}, DangerousPayload)

    self.KingTile = Config.KING_TILE
    self.Payload = nil
    self.isDelivered = false
    self.WavePoints = math.max(math.floor(run.Points * Config.WAVE_SHARE), 3)
    -- Enemy turns so far, for timing the waves
    self.Rounds = 0
    self.Random = Random.new()

    return self
end

function DangerousPayload:Hunt(piece)
    if not Config.HUNTERS[piece.Type] then return end

    piece.isReckless = true
    piece.HuntTarget = self.Payload
end

function DangerousPayload:Setup(match)
    local tile = Config.PAYLOAD_TILE

    self.Payload = match:AddPiece("Payload", "White", tile[1], tile[2])
    self.Payload.isPriorityTarget = true
    -- It rolls on its own; the player can't command it
    self.Payload.isEscorted = true

    for _, piece in pairs(match.Pieces) do
        if piece.Team == "Black" then
            self:Hunt(piece)
        end
    end
end

function DangerousPayload:IsAlive(match)
    return self.Payload ~= nil and match.Pieces[self.Payload.Id] ~= nil
end

-- One row at a time; anything standing in front of it holds it up until its next roll
function DangerousPayload:Roll(match)
    local payload = self.Payload

    if payload.Row >= BoardConfig.SIZE then
        self.isDelivered = true
        return
    end

    local row = payload.Row + 1
    if match:IsOccupied(payload.Column, row) then return end

    payload.Row = row
    match:SendAll("PieceMoved", payload.Id, payload.Column, row)
    match:OnUnitMoved(payload)
end

-- A fresh wave of Rooks and Bishops on the back rows, scaled for the Act like the rest of the army
-- They arrive this enemy turn but only start acting on the next
function DangerousPayload:SendWave(match)
    local taken = {}

    for column = 1, BoardConfig.SIZE do
        for row = 1, BoardConfig.SIZE do
            if match:IsOccupied(column, row) then
                table.insert(taken, {column, row})
            end
        end
    end

    local wave = EncounterRules.Generate(self.WavePoints, "Battle", self.Random, {Pool = Config.POOL, Taken = taken})

    for _, enemy in ipairs(wave) do
        local stats = nil

        if match.ScaleEnemy then
            local maxHealth, damageBonus = match.ScaleEnemy(enemy.Type)
            stats = {MaxHealth = maxHealth, DamageBonus = damageBonus}
        end

        local piece = match:AddPiece(enemy.Type, "Black", enemy.Column, enemy.Row, nil, nil, nil, stats)
        piece.isResting = true
        self:Hunt(piece)
    end
end

function DangerousPayload:OnEnemyTurn(match)
    if not self:IsAlive(match) then return end

    self.Rounds += 1

    if self.Rounds % Config.ROLL_TURNS == 0 then
        self:Roll(match)
    end

    if not self.isDelivered and self.Rounds % Config.WAVE_TURNS == 0 then
        self:SendWave(match)
    end
end

function DangerousPayload:CheckResult(match)
    if not self:IsAlive(match) then return "Failed" end
    if self.isDelivered then return "Victory" end

    return nil
end

-- The payload's track up its column, ending at the far row
function DangerousPayload:GetTerrain()
    local tiles = {}
    local column = Config.PAYLOAD_TILE[1]

    for row = Config.PAYLOAD_TILE[2], BoardConfig.SIZE do
        table.insert(tiles, {column, row, row == BoardConfig.SIZE and "Goal" or "Track"})
    end

    return {Tiles = tiles}
end

return DangerousPayload
