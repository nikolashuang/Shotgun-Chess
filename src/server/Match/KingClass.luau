local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardRules = require(ReplicatedStorage.Shared.Board.BoardRules)
local ShotgunRules = require(ReplicatedStorage.Shared.Combat.ShotgunRules)

local KingClass = {}

KingClass.__index = KingClass

function KingClass.new(player, column, row, shotgunName, className)
    local self = setmetatable({}, KingClass)

    self.Player = player

    self.Column = column
    self.Row = row

    self.MaxHealth = 15
    self.Health = 15

    self.ShotgunName = shotgunName
    self.Shotgun = ShotgunRules.GetWeapon(shotgunName, className)
    self.Ammo = self.Shotgun.MaxAmmo

    return self
end

-- Returns the health actually lost
function KingClass:TakeDamage(amount)
    local dealt = math.min(amount, self.Health)
    self.Health -= dealt

    return dealt
end

function KingClass:IsAlive()
    return self.Health > 0
end

function KingClass:Heal(amount)
    self.Health = math.min(self.Health + amount, self.MaxHealth)
end

-- Places the king without checking king movement (abilities that move it their own way)
function KingClass:SetTile(column, row)
    self.Column = column
    self.Row = row
end

function KingClass:MoveTo(column, row)
    if not BoardRules.IsValidKingMove(self.Column, self.Row, column, row) then return false end

    self.Column = column
    self.Row = row

    return true
end

function KingClass:CanFire(mode)
    if mode == "Alt" and not self.Shotgun.AltMode then return false end
    if self.Ammo < ShotgunRules.GetAmmoCost(self.Shotgun, mode) then return false end

    return true
end

-- Returns pellets, hitTiles and shot type without spending ammo
function KingClass:GetShot(targetX, targetY, mode, isBlocking)
    return ShotgunRules.GetFireResult(self.Column, self.Row, targetX, targetY, self.Shotgun, mode, isBlocking)
end

function KingClass:SpendAmmo(mode)
    self.Ammo -= ShotgunRules.GetAmmoCost(self.Shotgun, mode)
end

function KingClass:Reload()
    if self.Ammo >= self.Shotgun.MaxAmmo then return false end

    self.Ammo = self.Shotgun.MaxAmmo

    return true
end

return KingClass
