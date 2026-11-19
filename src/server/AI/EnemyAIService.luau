local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardRules = require(ReplicatedStorage.Shared.Board.BoardRules)
local PieceConfig = require(ReplicatedStorage.Shared.Board.PieceConfig)
local PieceRules = require(ReplicatedStorage.Shared.Board.PieceRules)
local ShotgunRules = require(ReplicatedStorage.Shared.Combat.ShotgunRules)
local ShotgunConfig = require(ReplicatedStorage.Shared.Combat.ShotgunConfig)
local AIConfig = require(script.Parent.AIConfig)

local Weights = AIConfig.Weights

local NEIGHBORS = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {1, -1}, {-1, 1}, {-1, -1}}

-- Plans the enemy turn: which Black pieces act and what each one does
-- Every plan is made against the same board snapshot, then MatchClass runs them all together
local EnemyAIService = {}

local function GetKey(column, row)
    return column * 100 + row
end

--BOARD SNAPSHOT--

-- Tiles a piece standing on column, row could hit next turn; ignoreKey is the piece's own current tile
local function GetControlledTiles(context, pieceType, team, column, row, ignoreKey)
    local tiles = {}

    if pieceType == "Pawn" then
        local forward = PieceRules.GetForward(team)
        tiles[GetKey(column - 1, row + forward)] = true
        tiles[GetKey(column + 1, row + forward)] = true
        return tiles
    end

    -- Enemy Kings shoot, so they control everything in shotgun range
    if pieceType == "King" and team == "Black" then
        local range = context.KingWeapon.MaxRange

        for deltaColumn = -range, range do
            for deltaRow = -range, range do
                tiles[GetKey(column + deltaColumn, row + deltaRow)] = true
            end
        end

        return tiles
    end

    local function IsBlocked(blockColumn, blockRow)
        local key = GetKey(blockColumn, blockRow)
        if key == ignoreKey then return false end

        return context.Occupied[key] == true
    end

    for _, move in pairs(PieceRules.GetMoves(pieceType, team, column, row, IsBlocked)) do
        tiles[GetKey(move.Column, move.Row)] = true
    end

    -- The first piece in each sliding line, or a knight's landing tile, can be hit too
    for _, attack in pairs(PieceRules.GetAttacks(pieceType, team, column, row, IsBlocked, IsBlocked)) do
        tiles[GetKey(attack.Column, attack.Row)] = true
    end

    return tiles
end

local function BuildContext(match)
    local king = match.King

    local context = {
        Match = match,
        PlayerKing = {isKing = true, Column = king.Column, Row = king.Row},
        PlayerWeapon = king.Shotgun,
        KingWeapon = ShotgunRules.GetWeapon(ShotgunConfig.ENEMY_KING),
        EnemyKing = nil,

        Whites = {},
        Blacks = {},

        Occupied = {},
        Reserved = {},
        Targets = {},

        -- Health left on each white target after the attacks planned so far
        Health = {},
        -- Tiles each white piece can hit next turn
        Threats = {},
        -- Tiles each black piece controls from its planned tile
        Coverage = {},
        Positions = {},

        EscapeTiles = {},
        KingThreats = {},
    }

    context.Health[context.PlayerKing] = king.Health
    context.Occupied[GetKey(king.Column, king.Row)] = true
    context.Targets[GetKey(king.Column, king.Row)] = context.PlayerKing
    table.insert(context.Whites, context.PlayerKing)

    for _, piece in pairs(match.Pieces) do
        local key = GetKey(piece.Column, piece.Row)
        context.Occupied[key] = true

        if piece.Team == "White" then
            local target = {Piece = piece, Type = piece.Type, Column = piece.Column, Row = piece.Row}

            context.Health[target] = piece.Health
            context.Targets[key] = target
            table.insert(context.Whites, target)
        else
            if piece.Type == "King" then
                context.EnemyKing = piece
            end

            context.Positions[piece] = {Column = piece.Column, Row = piece.Row}
            table.insert(context.Blacks, piece)
        end
    end

    for _, target in ipairs(context.Whites) do
        if not target.isKing then
            context.Threats[target] = GetControlledTiles(context, target.Type, "White", target.Column, target.Row)
        end
    end

    for _, piece in ipairs(context.Blacks) do
        context.Coverage[piece] = GetControlledTiles(context, piece.Type, piece.Team, piece.Column, piece.Row)
    end

    -- Empty tiles the player's king could step to
    for _, offset in ipairs(NEIGHBORS) do
        local column = king.Column + offset[1]
        local row = king.Row + offset[2]

        if BoardRules.IsOnBoard(column, row) and not context.Occupied[GetKey(column, row)] then
            table.insert(context.EscapeTiles, GetKey(column, row))
        end
    end

    -- Whatever could hit the enemy King next turn
    local enemyKing = context.EnemyKing

    if enemyKing then
        local kingKey = GetKey(enemyKing.Column, enemyKing.Row)

        if BoardRules.GetDistance(king.Column, king.Row, enemyKing.Column, enemyKing.Row) <= king.Shotgun.MaxRange + 1 then
            table.insert(context.KingThreats, context.PlayerKing)
        end

        for target, tiles in pairs(context.Threats) do
            if tiles[kingKey] then
                table.insert(context.KingThreats, target)
            end
        end
    end

    return context
end

--SCORING--

-- Expected damage the player could deal to a piece on this tile next turn
local function GetDanger(context, column, row)
    local player = context.PlayerKing
    local weapon = context.PlayerWeapon
    local danger = 0

    -- The player's king can step once before firing
    local distance = BoardRules.GetDistance(player.Column, player.Row, column, row)

    if distance <= weapon.MaxRange + 1 then
        danger += ShotgunRules.GetDamage(math.max(distance - 1, 1), weapon) * weapon.Blasts
    end

    local key = GetKey(column, row)

    for target, tiles in pairs(context.Threats) do
        if tiles[key] and context.Health[target] > 0 then
            danger += PieceConfig.Damage[target.Type]
        end
    end

    return danger
end

local function GetRisk(context, piece, column, row)
    return math.min(GetDanger(context, column, row) * AIConfig.RISK_SCALE / piece.MaxHealth, 1)
end

local function GetAttackValue(context, option)
    local value = 0

    for _, hit in ipairs(option.Hits) do
        local health = context.Health[hit.Target]

        if health > 0 then
            value += 0.5 + 0.5 * math.min(hit.Damage / health, 1)

            if hit.Target.isKing then
                value += AIConfig.KING_TARGET_BONUS
            end
        end
    end

    return value
end

local function GetDefendValue(context, piece, option)
    local king = context.EnemyKing
    if not king or piece == king then return 0 end
    if #context.KingThreats == 0 then return 0 end

    -- Taking out whatever threatens the King is the best defense
    if option.Hits then
        for _, hit in ipairs(option.Hits) do
            if context.Health[hit.Target] > 0 and table.find(context.KingThreats, hit.Target) then return 1 end
        end

        return 0
    end

    -- Otherwise stand next to the King on the threat's side
    if BoardRules.GetDistance(option.Column, option.Row, king.Column, king.Row) > 1 then return 0 end

    for _, threat in ipairs(context.KingThreats) do
        local kingDistance = BoardRules.GetDistance(king.Column, king.Row, threat.Column, threat.Row)

        if BoardRules.GetDistance(option.Column, option.Row, threat.Column, threat.Row) < kingDistance then
            return 0.6
        end
    end

    return 0
end

-- Returns how many escape tiles are covered, and how many of those no ally covers
local function CountCovered(context, piece, controlled)
    local covered = 0
    local fresh = 0

    for _, key in ipairs(context.EscapeTiles) do
        if controlled[key] then
            covered += 1

            local isShared = false

            for other, tiles in pairs(context.Coverage) do
                if other ~= piece and tiles[key] then
                    isShared = true
                    break
                end
            end

            if not isShared then
                fresh += 1
            end
        end
    end

    return covered, fresh
end

local function IsNearAlly(context, piece, column, row)
    for other, position in pairs(context.Positions) do
        if other ~= piece and BoardRules.GetDistance(column, row, position.Column, position.Row) <= AIConfig.TEAMWORK_RANGE then
            return true
        end
    end

    return false
end

local function ScoreOption(context, piece, weights, option)
    local score = weights.Defend * GetDefendValue(context, piece, option)

    -- An attack scores Position, Teamwork and Advance from the tile it ends on: its own, or the captured one
    -- Attacking outranks Evade unless the piece's weights say otherwise
    if option.Hits then
        score += weights.Attack * GetAttackValue(context, option)

        if AIConfig.EVADE_BEFORE_ATTACK[piece.Type] then
            score -= weights.Evade * GetRisk(context, piece, option.Column, option.Row)
        end
    else
        score -= weights.Evade * GetRisk(context, piece, option.Column, option.Row)
    end

    local player = context.PlayerKing
    local controlled = GetControlledTiles(context, piece.Type, piece.Team, option.Column, option.Row, GetKey(piece.Column, piece.Row))

    -- Position: line up an attack on the king's tile and close off the tiles it could step to
    if controlled[GetKey(player.Column, player.Row)] then
        score += weights.Position * AIConfig.KING_LINE_VALUE
    end

    local escapeCount = #context.EscapeTiles

    if escapeCount > 0 then
        local covered, fresh = CountCovered(context, piece, controlled)

        score += weights.Position * (1 - AIConfig.KING_LINE_VALUE) * covered / escapeCount

        if IsNearAlly(context, piece, option.Column, option.Row) then
            score += weights.Teamwork * fresh / escapeCount
        end
    end

    local before = BoardRules.GetDistance(piece.Column, piece.Row, player.Column, player.Row)
    local after = BoardRules.GetDistance(option.Column, option.Row, player.Column, player.Row)

    score += weights.Advance * math.clamp((before - after) / AIConfig.ADVANCE_STEP, -1, 1)

    return score
end

local function GetWeights(context, piece)
    if piece.Type == "King" then return Weights.King end

    if piece.Type == "Queen" then
        -- Once only the King and Queen are left, guarding the King comes first
        if context.EnemyKing and #context.Blacks == 2 then return Weights.Default end

        return Weights.Queen
    end

    return Weights.Default
end

--OPTIONS--

-- Enemy Kings aim straight at every white target in range
local function AddShots(context, piece, options)
    local weapon = context.KingWeapon

    local function IsBlocking(column, row)
        return context.Targets[GetKey(column, row)] ~= nil
    end

    for _, target in ipairs(context.Whites) do
        if BoardRules.GetDistance(piece.Column, piece.Row, target.Column, target.Row) <= weapon.MaxRange then
            local aimX = target.Column - 0.5
            local aimY = target.Row - 0.5
            local _, hitTiles, shotType = ShotgunRules.GetFireResult(piece.Column, piece.Row, aimX, aimY, weapon, "Normal", IsBlocking)

            if hitTiles then
                local hits = {}

                for _, tile in pairs(hitTiles) do
                    local hitTarget = context.Targets[GetKey(tile.Column, tile.Row)]

                    -- Blasts into the Outlaw's smoke only land part of the time, so they count for less
                    local hitChance = context.Match:GetShotHitChance(tile.Column, tile.Row)

                    if hitTarget and hitChance > 0 then
                        local distance = BoardRules.GetDistance(piece.Column, piece.Row, tile.Column, tile.Row)
                        table.insert(hits, {Target = hitTarget, Damage = ShotgunRules.GetHitDamage(weapon, shotType, distance) * hitChance})
                    end
                end

                if #hits > 0 then
                    table.insert(options, {Type = "Shoot", Column = piece.Column, Row = piece.Row, AimX = aimX, AimY = aimY, Hits = hits})
                end
            end
        end
    end
end

local function GetOptions(context, piece)
    local options = {{Type = "Stay", Column = piece.Column, Row = piece.Row}}

    local function IsBlocked(column, row)
        return context.Occupied[GetKey(column, row)] == true
    end

    local function IsTarget(column, row)
        return context.Targets[GetKey(column, row)] ~= nil and not context.Match:IsProtected(column, row)
    end

    if piece.Type == "King" then
        AddShots(context, piece, options)
    else
        for _, attack in pairs(PieceRules.GetAttacks(piece.Type, piece.Team, piece.Column, piece.Row, IsBlocked, IsTarget)) do
            local target = context.Targets[GetKey(attack.Column, attack.Row)]
            local damage = PieceConfig.Damage[piece.Type]

            -- A kill on a summoned piece captures its square, so the attacker ends the turn there
            local isCapture = not target.isKing and damage >= context.Health[target]

            table.insert(options, {
                Type = "Attack",
                Column = isCapture and attack.Column or piece.Column,
                Row = isCapture and attack.Row or piece.Row,
                TargetColumn = attack.Column,
                TargetRow = attack.Row,
                Hits = {{Target = target, Damage = damage}},
            })
        end
    end

    -- Destinations already claimed by pieces earlier in the order are off limits
    local function IsMoveBlocked(column, row)
        local key = GetKey(column, row)
        return context.Occupied[key] == true or context.Reserved[key] == true
    end

    for _, move in pairs(PieceRules.GetMoves(piece.Type, piece.Team, piece.Column, piece.Row, IsMoveBlocked)) do
        table.insert(options, {Type = "Move", Column = move.Column, Row = move.Row})
    end

    return options
end

--PLANNING--

local function CanMakeMistake(match, rating)
    if rating.MaxMistakes and match.AIMistakes >= rating.MaxMistakes then return false end

    return match.Random:NextNumber() < rating.MistakeChance
end

local function ChooseOption(context, piece, rating)
    local weights = GetWeights(context, piece)
    local options = GetOptions(context, piece)

    for _, option in ipairs(options) do
        option.Score = ScoreOption(context, piece, weights, option)
    end

    table.sort(options, function(a, b)
        return a.Score > b.Score
    end)

    -- A mistake is any option other than the best one
    if #options > 1 and CanMakeMistake(context.Match, rating) then
        context.Match.AIMistakes += 1

        return options[context.Match.Random:NextInteger(2, #options)]
    end

    return options[1]
end

local function Commit(context, piece, option)
    option.PieceId = piece.Id

    if option.Hits then
        for _, hit in ipairs(option.Hits) do
            context.Health[hit.Target] -= hit.Damage
        end
    end

    if option.Type == "Move" then
        context.Reserved[GetKey(option.Column, option.Row)] = true
    end

    context.Positions[piece] = {Column = option.Column, Row = option.Row}
    context.Coverage[piece] = GetControlledTiles(context, piece.Type, piece.Team, option.Column, option.Row, GetKey(piece.Column, piece.Row))
end

-- Ticks every Black piece's stun and returns the plans of the ones that act
function EnemyAIService.PlanTurn(match)
    local acting = {}

    for _, piece in pairs(match.Pieces) do
        if piece.Team == "Black" and piece:TickStun() then
            table.insert(acting, piece)
        end
    end

    if #acting == 0 then return {} end

    table.sort(acting, function(a, b)
        return a.Id < b.Id
    end)

    local context = BuildContext(match)
    local rating = AIConfig.Ratings[match.AIRating]
    local plans = {}

    -- Conveyor order: the piece that reserves first moves down one place every enemy turn
    local offset = (match.Turn - 1) % #acting

    for i = 1, #acting do
        local piece = acting[(i + offset - 1) % #acting + 1]
        local option = ChooseOption(context, piece, rating)

        Commit(context, piece, option)

        if option.Type ~= "Stay" then
            table.insert(plans, option)
        end
    end

    return plans
end

return EnemyAIService
