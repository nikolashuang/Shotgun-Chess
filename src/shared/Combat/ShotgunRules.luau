local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)
local ShotgunConfig = require(ReplicatedStorage.Shared.Combat.ShotgunConfig)

local ShotgunRules = {}

local function IsInsideBoard(x, y)
    return x >= 0 and x < BoardConfig.SIZE and y >= 0 and y < BoardConfig.SIZE
end

function ShotgunRules.GetKingOrigin(column, row)
    return column - 0.5, row - 0.5
end

function ShotgunRules.GetAim(originX, originY, targetX, targetY)
    local deltaX = targetX - originX
    local deltaY = targetY - originY
    local distance = math.sqrt(deltaX * deltaX + deltaY * deltaY)

    if distance < 0.01 then return nil end

    local angle = math.atan2(deltaY, deltaX)
    local radius = math.clamp(distance, ShotgunConfig.MIN_RANGE, ShotgunConfig.MAX_RANGE)

    return angle, radius
end

function ShotgunRules.GetPelletAngles(angle)
    local halfArc = math.rad(ShotgunConfig.ARC_DEGREES) / 2
    local count = ShotgunConfig.PELLET_COUNT

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

function ShotgunRules.GetDamage(tileDistance)
    local range = ShotgunConfig.MAX_RANGE - ShotgunConfig.MIN_RANGE
    local alpha = (math.clamp(tileDistance, ShotgunConfig.MIN_RANGE, ShotgunConfig.MAX_RANGE) - ShotgunConfig.MIN_RANGE) / range

    return ShotgunConfig.MAX_DAMAGE + (ShotgunConfig.MIN_DAMAGE - ShotgunConfig.MAX_DAMAGE) * alpha
end

-- isBlocking(column, row) returns true for tiles that stop pellets
function ShotgunRules.GetShot(originX, originY, angle, radius, isBlocking)
    local kingColumn = math.floor(originX) + 1
    local kingRow = math.floor(originY) + 1

    local hitTiles = {}
    local marked = {}

    local function MarkTile(column, row)
        if column == kingColumn and row == kingRow then return false end

        local key = column * 100 + row
        if not marked[key] then
            marked[key] = true
            table.insert(hitTiles, {Column = column, Row = row})
        end

        return isBlocking ~= nil and isBlocking(column, row)
    end

    -- Everything inside the arc is hit
    local halfArc = math.rad(ShotgunConfig.ARC_DEGREES) / 2
    local rayCount = math.max(2, math.ceil(radius * halfArc * 2 / ShotgunConfig.COVERAGE_SPACING))

    for i = 0, rayCount do
        local rayAngle = angle - halfArc + halfArc * 2 * i / rayCount
        ShotgunRules.TracePellet(originX, originY, rayAngle, radius, MarkTile)
    end

    -- Pellets keep travelling past the arc up to max range
    local pellets = {}

    for _, pelletAngle in pairs(ShotgunRules.GetPelletAngles(angle)) do
        local x, y = ShotgunRules.TracePellet(originX, originY, pelletAngle, ShotgunConfig.MAX_RANGE, MarkTile)
        table.insert(pellets, {X = x, Y = y})
    end

    return pellets, hitTiles
end

return ShotgunRules
