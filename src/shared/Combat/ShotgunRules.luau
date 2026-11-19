local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)
local BoardRules = require(ReplicatedStorage.Shared.Board.BoardRules)
local ShotgunConfig = require(ReplicatedStorage.Shared.Combat.ShotgunConfig)
local ClassConfig = require(ReplicatedStorage.Shared.Combat.ClassConfig)

local DIRECTION_STEP = math.pi / 4

-- Class-tuned copies of each shotgun, made once so the same weapon table is always returned
local classWeapons = {}

local ShotgunRules = {}

local function IsInsideBoard(x, y)
    return x >= 0 and x < BoardConfig.SIZE and y >= 0 and y < BoardConfig.SIZE
end

local function GetNeighbor(column, row, directionIndex)
    local direction = directionIndex * DIRECTION_STEP

    return column + math.round(math.cos(direction)), row + math.round(math.sin(direction))
end

-- className tunes the shotgun for class passives (Gunslinger's Deadly Rounds); nil gives the base weapon
function ShotgunRules.GetWeapon(shotgunName, className)
    local weapon = ShotgunConfig.Shotguns[shotgunName]
    if not weapon or className ~= "Gunslinger" then return weapon end

    classWeapons[shotgunName] = classWeapons[shotgunName] or (function()
        local deadlyRounds = ClassConfig.Classes.Gunslinger.DeadlyRounds
        local tuned = table.clone(weapon)

        tuned.Pierces = true
        tuned.PierceDamageLoss = deadlyRounds.DamageLossPerEnemy

        return tuned
    end)()

    return classWeapons[shotgunName]
end

function ShotgunRules.GetKingOrigin(column, row)
    return column - 0.5, row - 0.5
end

function ShotgunRules.GetAim(originX, originY, targetX, targetY, weapon)
    local deltaX = targetX - originX
    local deltaY = targetY - originY
    local distance = math.sqrt(deltaX * deltaX + deltaY * deltaY)

    if distance < 0.01 then return nil end

    local angle = math.atan2(deltaY, deltaX)
    local radius = math.clamp(distance, ShotgunConfig.MIN_RANGE, weapon.MaxRange)

    return angle, radius
end

function ShotgunRules.GetPelletAngles(angle, weapon)
    local halfArc = math.rad(weapon.ArcDegrees) / 2
    local count = weapon.PelletCount

    if count == 1 then return {angle} end

    local angles = {}
    for i = 0, count - 1 do
        table.insert(angles, angle - halfArc + halfArc * 2 * i / (count - 1))
    end

    return angles
end

function ShotgunRules.TracePellet(originX, originY, angle, length, onTile)
    local directionX = math.cos(angle)
    local directionY = math.sin(angle)
    local stepCount = math.ceil(length / ShotgunConfig.TRACE_STEP)

    local x, y = originX, originY

    for i = 1, stepCount do
        local travelled = math.min(i * ShotgunConfig.TRACE_STEP, length)
        local nextX = originX + directionX * travelled
        local nextY = originY + directionY * travelled

        if not IsInsideBoard(nextX, nextY) then break end

        x, y = nextX, nextY

        -- onTile returns true when the tile stops the pellet
        if onTile and onTile(math.floor(x) + 1, math.floor(y) + 1) then break end
    end

    return x, y
end

function ShotgunRules.GetDamage(tileDistance, weapon)
    local range = weapon.MaxRange - ShotgunConfig.MIN_RANGE
    local alpha = (math.clamp(tileDistance, ShotgunConfig.MIN_RANGE, weapon.MaxRange) - ShotgunConfig.MIN_RANGE) / range

    return weapon.MaxDamage + (weapon.MinDamage - weapon.MaxDamage) * alpha
end

-- True when the line from the origin to the tile's center crosses no blocking tile on the way
function ShotgunRules.HasLineOfSight(originX, originY, column, row, isBlocking)
    return ShotgunRules.CountBlockers(originX, originY, column, row, isBlocking) == 0
end

-- Number of different blocking tiles the line from the origin to the tile's center crosses on the way
function ShotgunRules.CountBlockers(originX, originY, column, row, isBlocking)
    local targetX = column - 0.5
    local targetY = row - 0.5
    local deltaX = targetX - originX
    local deltaY = targetY - originY
    local stepCount = math.ceil(math.sqrt(deltaX * deltaX + deltaY * deltaY) / ShotgunConfig.TRACE_STEP)
    local margin = ShotgunConfig.LINE_OF_SIGHT_MARGIN

    local startColumn = math.floor(originX) + 1
    local startRow = math.floor(originY) + 1
    local counted = {}
    local count = 0

    for i = 1, stepCount - 1 do
        local x = originX + deltaX * i / stepCount
        local y = originY + deltaY * i / stepCount
        local stepColumn = math.floor(x) + 1
        local stepRow = math.floor(y) + 1

        local isEndpoint = (stepColumn == column and stepRow == row) or (stepColumn == startColumn and stepRow == startRow)
        local isInside = x % 1 > margin and x % 1 < 1 - margin and y % 1 > margin and y % 1 < 1 - margin

        local key = stepColumn * 100 + stepRow

        if not isEndpoint and isInside and not counted[key] and isBlocking(stepColumn, stepRow) then
            counted[key] = true
            count += 1
        end
    end

    return count
end

-- isBlocking(column, row) returns true for tiles that stop pellets
-- Tiles shielded by an enemy are never hit, so nothing behind an enemy takes damage
function ShotgunRules.GetShot(originX, originY, angle, radius, isBlocking, weapon)
    local kingColumn = math.floor(originX) + 1
    local kingRow = math.floor(originY) + 1

    local hitTiles = {}
    local marked = {}
    local shielded = {}

    local function MarkTile(column, row)
        if column == kingColumn and row == kingRow then return false end

        local key = column * 100 + row

        -- Shielded tiles are skipped but don't stop the ray, only enemy tiles do
        if not marked[key] and not shielded[key] then
            if isBlocking and not ShotgunRules.HasLineOfSight(originX, originY, column, row, isBlocking) then
                shielded[key] = true
            else
                marked[key] = true
                table.insert(hitTiles, {Column = column, Row = row})
            end
        end

        if shielded[key] then return false end

        return isBlocking ~= nil and isBlocking(column, row)
    end

    -- Everything inside the arc is hit
    local halfArc = math.rad(weapon.ArcDegrees) / 2
    local rayCount = math.max(2, math.ceil(radius * halfArc * 2 / ShotgunConfig.COVERAGE_SPACING))

    for i = 0, rayCount do
        local rayAngle = angle - halfArc + halfArc * 2 * i / rayCount
        ShotgunRules.TracePellet(originX, originY, rayAngle, radius, MarkTile)
    end

    -- Pellets keep travelling past the arc up to max range
    local pellets = {}

    for _, pelletAngle in pairs(ShotgunRules.GetPelletAngles(angle, weapon)) do
        local x, y = ShotgunRules.TracePellet(originX, originY, pelletAngle, weapon.MaxRange, MarkTile)
        table.insert(pellets, {X = x, Y = y})
    end

    return pellets, hitTiles
end

--POINT BLANK--

-- Returns the adjacent enemy tile the shot is pointed into, if any
function ShotgunRules.GetPointBlankTarget(kingColumn, kingRow, targetX, targetY, isBlocking)
    if not isBlocking then return nil end

    -- Cursor directly on an adjacent enemy
    local column = math.floor(targetX) + 1
    local row = math.floor(targetY) + 1
    local isAdjacent = math.max(math.abs(column - kingColumn), math.abs(row - kingRow)) == 1

    if isAdjacent and isBlocking(column, row) then
        return column, row
    end

    -- Otherwise the neighbor in the aim direction, snapped to the nearest of 8 directions
    local originX, originY = ShotgunRules.GetKingOrigin(kingColumn, kingRow)
    local angle = math.atan2(targetY - originY, targetX - originX)

    column, row = GetNeighbor(kingColumn, kingRow, math.round(angle / DIRECTION_STEP))

    if not BoardRules.IsOnBoard(column, row) then return nil end
    if not isBlocking(column, row) then return nil end

    return column, row
end

-- Every pellet lands inside the one target tile
function ShotgunRules.GetPointBlankShot(originX, originY, column, row, weapon)
    local centerX = column - 0.5
    local centerY = row - 0.5
    local angle = math.atan2(centerY - originY, centerX - originX)

    local count = weapon.PelletCount
    local pellets = {}

    for i = 1, count do
        local spread = (i - (count + 1) / 2) * ShotgunConfig.POINT_BLANK_SPREAD
        table.insert(pellets, {
            X = centerX - math.sin(angle) * spread,
            Y = centerY + math.cos(angle) * spread,
        })
    end

    return pellets, {{Column = column, Row = row}}
end

--ALT MODES--

-- Straight line snapped to the nearest of 8 directions, pierces everything
function ShotgunRules.GetPreciseShot(kingColumn, kingRow, targetX, targetY, range)
    local originX, originY = ShotgunRules.GetKingOrigin(kingColumn, kingRow)
    local angle = math.atan2(targetY - originY, targetX - originX)
    local index = math.round(angle / DIRECTION_STEP)
    local stepColumn, stepRow = GetNeighbor(0, 0, index)

    local hitTiles = {}

    for step = 1, range do
        local column = kingColumn + stepColumn * step
        local row = kingRow + stepRow * step

        if not BoardRules.IsOnBoard(column, row) then break end

        table.insert(hitTiles, {Column = column, Row = row})
    end

    if #hitTiles == 0 then return nil end

    local last = hitTiles[#hitTiles]

    return {{X = last.Column - 0.5, Y = last.Row - 0.5}}, hitTiles
end

-- The adjacent tile the swing points at, plus the neighbor it sweeps toward
function ShotgunRules.GetKnifeTiles(kingColumn, kingRow, targetX, targetY)
    local originX, originY = ShotgunRules.GetKingOrigin(kingColumn, kingRow)
    local angle = math.atan2(targetY - originY, targetX - originX)
    local index = math.round(angle / DIRECTION_STEP)

    -- Cursor directly on an adjacent tile picks that tile
    local column = math.floor(targetX) + 1
    local row = math.floor(targetY) + 1

    if math.max(math.abs(column - kingColumn), math.abs(row - kingRow)) == 1 then
        index = math.round(math.atan2(row - kingRow, column - kingColumn) / DIRECTION_STEP)
    end

    local offset = (angle - index * DIRECTION_STEP + math.pi) % (math.pi * 2) - math.pi
    local side = offset >= 0 and 1 or -1

    local hitTiles = {}

    for _, directionIndex in pairs({index, index + side}) do
        local tileColumn, tileRow = GetNeighbor(kingColumn, kingRow, directionIndex)

        if BoardRules.IsOnBoard(tileColumn, tileRow) then
            table.insert(hitTiles, {Column = tileColumn, Row = tileRow})
        end
    end

    return hitTiles
end

--FIRING--

function ShotgunRules.GetAmmoCost(weapon, mode)
    if mode == "Alt" and weapon.AltMode == "Knife" then return 0 end

    return weapon.AmmoPerShot
end

-- Returns pellets, hitTiles and the shot type, or nil when the aim is invalid
function ShotgunRules.GetFireResult(kingColumn, kingRow, targetX, targetY, weapon, mode, isBlocking)
    if mode == "Alt" then
        if weapon.AltMode == "Knife" then
            return {}, ShotgunRules.GetKnifeTiles(kingColumn, kingRow, targetX, targetY), "Knife"
        end

        return nil
    end

    local originX, originY = ShotgunRules.GetKingOrigin(kingColumn, kingRow)

    local pointBlankColumn, pointBlankRow = ShotgunRules.GetPointBlankTarget(kingColumn, kingRow, targetX, targetY, isBlocking)
    if pointBlankColumn then
        local pellets, hitTiles = nil, nil

        -- Piercing blasts go through the adjacent enemy and on in a straight line to max range
        if weapon.Pierces then
            hitTiles = select(2, ShotgunRules.GetPreciseShot(kingColumn, kingRow, pointBlankColumn - 0.5, pointBlankRow - 0.5, weapon.MaxRange))

            local last = hitTiles[#hitTiles]
            pellets = ShotgunRules.GetPointBlankShot(originX, originY, last.Column, last.Row, weapon)
        else
            pellets, hitTiles = ShotgunRules.GetPointBlankShot(originX, originY, pointBlankColumn, pointBlankRow, weapon)
        end

        return pellets, hitTiles, "PointBlank"
    end

    local angle, radius = ShotgunRules.GetAim(originX, originY, targetX, targetY, weapon)
    if not angle then return nil end

    -- Piercing blasts aren't shielded or stopped by anything
    local pellets, hitTiles = ShotgunRules.GetShot(originX, originY, angle, radius, not weapon.Pierces and isBlocking or nil, weapon)

    return pellets, hitTiles, "Spread"
end

function ShotgunRules.GetHitDamage(weapon, shotType, tileDistance)
    if shotType == "Knife" then return weapon.Knife.Damage end

    return ShotgunRules.GetDamage(tileDistance, weapon) * weapon.Blasts
end

return ShotgunRules
