local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.Combat.CombatConfig)

local EnergyConfig = CombatConfig.Energy

-- One player's half of a match: their king, energy, ultimate, class and turn usage
-- Campaign matches have a single White side; duels have a White and a Black side, 2v2 two of each
local SideClass = {}

SideClass.__index = SideClass

function SideClass.new(match, player, team, king, className)
    local self = setmetatable({}, SideClass)

    self.Match = match
    self.Player = player
    -- Key in match.Sides: the team, or "White2"/"Black2" for the second 2v2 player
    self.Key = team

    self.Team = team
    self.EnemyTeam = team == "White" and "Black" or "White"

    self.King = king
    self.ClassName = className
    -- Class component, set by the match once the side exists
    self.Ability = nil

    self.HasMoved = false
    -- Each action can be used once per turn
    self.UsedActions = {}

    self.Energy = EnergyConfig.START_ENERGY
    self.UltimateCharge = 0
    -- Extra damage on every hit of the next shot (Reaper's High, Ambush)
    self.NextShotBonus = 0

    -- Seconds left on the duel chess clock; nil outside duels
    self.Clock = nil
    -- A stunned duel King's turn is being skipped
    self.isSkipping = false

    -- 2v2: the player ended their part of the team's turn, is out (king dead, clock out or left), left the match,
    -- or voted to surrender
    self.hasEndedTurn = false
    self.isOut = false
    self.isDisconnected = false
    self.wantsSurrender = false

    -- Practice AI sides only: AIConfig rating key and the piece it is saving energy for
    self.AIRating = nil
    self.AISummonGoal = nil

    return self
end

function SideClass:AddEnergy(amount)
    self.Energy = math.min(self.Energy + amount, EnergyConfig.MAX_ENERGY)
end

function SideClass:GainEnergy()
    self:AddEnergy(EnergyConfig.ENERGY_PER_TURN)
end

-- Sends to this side's player only
function SideClass:Send(action, ...)
    self.Match:SendTo(self, action, ...)
end

return SideClass
