local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardRules = require(ReplicatedStorage.Shared.Board.BoardRules)
local PieceConfig = require(ReplicatedStorage.Shared.Board.PieceConfig)
local PieceRules = require(ReplicatedStorage.Shared.Board.PieceRules)
local ShotgunRules = require(ReplicatedStorage.Shared.Combat.ShotgunRules)
local AIConfig = require(script.Parent.AIConfig)
local AIBoard = require(script.Parent.AIBoard)
local AIDebug = require(script.Parent.AIDebug)
local BossAbilityService = require(script.Parent.BossAbilityService)

local Weights = AIConfig.Weights
local GetKey = AIBoard.GetKey

local PAWNS = {Pawn = true, FallenPawn = true}

-- Plans the enemy turn: which Black pieces act and what each one does
-- Each piece scores every option against all its directives (weight x how well the option serves it, minus risk),
-- picks the best, and commits it to the shared board before the next piece plans; MatchClass then runs them all
local EnemyAIService = {}

--WEIGHTS--

local function GetBaseWeights(context, piece)
    if piece.Type == "King" then return Weights.King end
    if PAWNS[piece.Type] then return Weights.Pawn end

    if piece.Type == "Queen" then
        -- Once only the King and Queen are left, guarding the King comes first
        if context.EnemyKing and #context.Blacks == 2 then return Weights.Default end

        return Weights.Queen
    end

    return Weights[piece.Type] or Weights.Default
end

-- The board shifts the weights: a King in danger needs defending, a weak player king invites the attack,
-- and a lone King that keeps backing off gets tired of running
local function AdjustWeights(context, piece)
    local weights = table.clone(GetBaseWeights(context, piece))
    local king = context.EnemyKing

    if king and piece ~= king then
        local position = context.Positions[king]
        local kingRisk = AIBoard.GetRisk(king, AIBoard.GetDanger(context, position.Column, position.Row, king))

        weights.Defend *= 1 + AIConfig.KING_DANGER_DEFEND * kingRisk
    end

    -- Expedition regions lean on different directives
    local region = context.Match.RegionAI

    if region and region.AIWeights then
        for directive, scale in pairs(region.AIWeights) do
            weights[directive] *= scale
        end
    end

    local playerHealth = math.max(context.Health[context.PlayerKing], 0)
    weights.Attack *= 1 + AIConfig.LOW_KING_ATTACK * (1 - playerHealth / context.PlayerMaxHealth)

    -- A piece that hasn't gone anywhere for a while gets pushed forward, so nobody sits still all fight
    local memory = context.Memory[piece.Id]

    if memory and piece ~= king and not PAWNS[piece.Type] then
        weights.Advance *= 1 + AIConfig.IDLE_ADVANCE * math.min(memory.IdleTurns or 0, AIConfig.IDLE_TURNS_MAX)
    end

    if piece == king and #context.Blacks == 1 then
        local retreats = memory and memory.RetreatTurns or 0

        weights.Evade *= math.max(1 - AIConfig.KING_FATIGUE * retreats, 0)
        weights.Attack *= AIConfig.ISOLATED_KING_ATTACK
    end

    return weights
end

--DIRECTIVES--

-- Pieces press the attack until they're hurt enough, then start evading
local function GetEvadeThreshold(piece)
    return AIConfig.EVADE_HEALTH[piece.Type] or AIConfig.EVADE_HEALTH.Default
end

local function IsEvading(piece)
    return piece.Health < piece.MaxHealth * GetEvadeThreshold(piece)
end

-- 1 at the evade threshold, up to EVADE_MAX_URGENCY at 0 health
local function GetUrgency(piece)
    local threshold = GetEvadeThreshold(piece)
    local missing = (threshold - piece.Health / piece.MaxHealth) / threshold

    return 1 + (AIConfig.EVADE_MAX_URGENCY - 1) * math.clamp(missing, 0, 1)
end

local function GetAttackValue(context, option)
    local value = 0

    for _, hit in ipairs(option.Hits) do
        local health = context.Health[hit.Target]

        if health > 0 then
            value += 0.5 + 0.5 * math.min(hit.Damage / health, 1)

            if hit.Target.isKing then
                value += AIConfig.KING_TARGET_BONUS
            elseif hit.Damage >= health then
                value += AIConfig.KILL_VALUE * AIBoard.GetValue(hit.Target.Type)
            end
        end
    end

    return value
end

local function KillsPlayerKing(context, option)
    for _, hit in ipairs(option.Hits) do
        if hit.Target.isKing and hit.Damage >= context.Health[hit.Target] then return true end
    end

    return false
end

-- How much of a threat to the allied King a white piece still is with this piece standing on the option's tile
local function IsLineBlocked(context, piece, option, threat)
    local king = context.EnemyKing
    local kingPosition = context.Positions[king]
    local oldKey = GetKey(context.Positions[piece].Column, context.Positions[piece].Row)
    local newKey = GetKey(option.Column, option.Row)
    if oldKey == newKey then return 0 end

    -- Try the piece on its new tile, then put the board back
    local wasOccupied = context.Occupied[newKey]
    local wasBlack = context.BlackTiles[newKey]

    context.Occupied[oldKey] = nil
    context.Occupied[newKey] = true
    context.BlackTiles[oldKey] = nil
    context.BlackTiles[newKey] = piece

    local blocked = 0

    if threat.isKing then
        -- Share of the open line's damage the piece soaks up
        local open = context.KingLineDamage or 0

        if open > 0 then
            local damage = AIBoard.GetKingDamage(context, kingPosition.Column, kingPosition.Row, king)
            blocked = math.clamp(1 - damage / open, 0, 1)
        end
    else
        local tiles = AIBoard.GetControlledTiles(context, threat.Type, "White", threat.Column, threat.Row)
        blocked = tiles[GetKey(kingPosition.Column, kingPosition.Row)] and 0 or 1
    end

    context.Occupied[newKey] = wasOccupied
    context.Occupied[oldKey] = true
    context.BlackTiles[newKey] = wasBlack
    context.BlackTiles[oldKey] = piece

    return blocked
end

local function GetDefendValue(context, piece, option)
    local king = context.EnemyKing
    if not king or piece == king then return 0 end
    if #context.KingThreats == 0 then return 0 end

    -- Taking out whatever threatens the King is the best defense
    if option.Hits then
        for _, hit in ipairs(option.Hits) do
            local health = context.Health[hit.Target]

            if health > 0 and table.find(context.KingThreats, hit.Target) then
                return hit.Damage >= health and AIConfig.DEFEND_KILL or AIConfig.DEFEND_KILL * 0.5
            end
        end

        return 0
    end

    local value = 0
    local kingPosition = context.Positions[king]

    for _, threat in ipairs(context.KingThreats) do
        if context.Health[threat] > 0 then
            -- Step into the line of fire
            value = math.max(value, AIConfig.DEFEND_BLOCK * IsLineBlocked(context, piece, option, threat))

            -- Or stand next to the King on the threat's side
            local kingDistance = BoardRules.GetDistance(kingPosition.Column, kingPosition.Row, threat.Column, threat.Row)

            if BoardRules.GetDistance(option.Column, option.Row, kingPosition.Column, kingPosition.Row) <= 1
                and BoardRules.GetDistance(option.Column, option.Row, threat.Column, threat.Row) < kingDistance then
                value = math.max(value, AIConfig.DEFEND_GUARD)
            end
        end
    end

    return value
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

-- Which of the 8 directions around the player's king a tile sits in
local function GetSide(context, column, row)
    local player = context.PlayerKing
    return math.sign(column - player.Column) * 3 + math.sign(row - player.Row)
end

local function IsNewFlank(context, piece, column, row)
    local player = context.PlayerKing
    if BoardRules.GetDistance(column, row, player.Column, player.Row) > AIConfig.FLANK_RANGE then return false end

    local side = GetSide(context, column, row)
    local hasAllyNear = false

    for other, position in pairs(context.Positions) do
        if other ~= piece and BoardRules.GetDistance(position.Column, position.Row, player.Column, player.Row) <= AIConfig.FLANK_RANGE then
            hasAllyNear = true

            if GetSide(context, position.Column, position.Row) == side then return false end
        end
    end

    -- A flank needs someone on the other side
    return hasAllyNear
end

-- True when the option threatens a white piece that threatens an ally
local function ProtectsAlly(context, piece, controlled)
    for target, tiles in pairs(context.Threats) do
        if context.Health[target] > 0 and controlled[GetKey(target.Column, target.Row)] then
            for other, position in pairs(context.Positions) do
                if other ~= piece and tiles[GetKey(position.Column, position.Row)] then return true end
            end
        end
    end

    return false
end

local function GetTeamworkValue(context, piece, option, controlled, fresh)
    local value = 0
    local escapeCount = #context.EscapeTiles

    -- Close off escape tiles nobody else holds yet
    if escapeCount > 0 and IsNearAlly(context, piece, option.Column, option.Row) then
        value += fresh / escapeCount
    end

    -- Finish what an ally started
    if option.Hits then
        for _, hit in ipairs(option.Hits) do
            if context.Damaged[hit.Target] and context.Health[hit.Target] > 0 then
                value += AIConfig.FOCUS_VALUE
                break
            end
        end
    end

    if IsNewFlank(context, piece, option.Column, option.Row) then
        value += AIConfig.FLANK_VALUE
    end

    if ProtectsAlly(context, piece, controlled) then
        value += AIConfig.PROTECT_VALUE
    end

    return value
end

local function GetPositionValue(context, piece, controlled, covered, option)
    local player = context.PlayerKing
    local value = 0

    -- Line up an attack on the king's tile and close off the tiles it could step to
    if controlled[GetKey(player.Column, player.Row)] then
        value += AIConfig.KING_LINE_VALUE
    end

    local escapeCount = #context.EscapeTiles

    if escapeCount > 0 then
        value += (1 - AIConfig.KING_LINE_VALUE) * covered / escapeCount
    end

    local range = AIConfig.PREFERRED_RANGE[piece.Type]

    if range then
        local distance = BoardRules.GetDistance(option.Column, option.Row, player.Column, player.Row)

        if distance >= range.Min and distance <= range.Max then
            value += range.Value
        end
    end

    return value
end

local function GetAdvanceValue(context, piece, option)
    local value

    -- A Necromancer with a raise ready walks toward the nearest fallen ally instead of the player
    local fallen = piece.Type == "Necromancer" and context.Match:GetNearestFallen(piece)

    -- Pawns advance toward promotion: every row stepped forward counts fully, wherever the player is
    if fallen then
        local before = BoardRules.GetDistance(piece.Column, piece.Row, fallen.Column, fallen.Row)
        local after = BoardRules.GetDistance(option.Column, option.Row, fallen.Column, fallen.Row)

        value = math.clamp((before - after) / AIConfig.ADVANCE_STEP, -1, 1)
    elseif PAWNS[piece.Type] then
        local rowsGained = (option.Row - piece.Row) * PieceRules.GetForward(piece.Team)
        value = math.clamp(rowsGained, 0, 1)
    else
        local player = context.PlayerKing
        local before = BoardRules.GetDistance(piece.Column, piece.Row, player.Column, player.Row)
        local after = BoardRules.GetDistance(option.Column, option.Row, player.Column, player.Row)

        value = math.clamp((before - after) / AIConfig.ADVANCE_STEP, -1, 1)
    end

    return value
end

-- Expected cost of ending the turn on a tile: damage taken, the piece's value times its chance of dying,
-- and allies close enough to share the blast
-- A bait trade counts the share of health lost instead of the death chance: a Rook blasted to 2 HP for a pawn is
-- most of a Rook gone
local function GetLoss(context, piece, column, row, danger, isBait)
    if danger <= 0 then return 0 end

    local lost = isBait and AIBoard.GetHealthShare(piece, danger) or AIBoard.GetDeathChance(piece, danger)
    local loss = AIConfig.RISK_WEIGHT * AIBoard.GetRisk(piece, danger) + AIConfig.LOSS_WEIGHT * AIBoard.GetValue(piece.Type) * lost

    if isBait then
        loss *= AIConfig.BAIT_MULTIPLIER
    elseif danger < piece.Health + (piece.Shield or 0) then
        -- The player's king only blasts one target a turn, so pieces closing in together each risk less
        -- A tile where the piece would die isn't shared: that's the shot the player takes
        loss /= 1 + AIConfig.SHARED_TARGET * context.ExposedAllies
    end

    loss += AIConfig.CLUSTER_PENALTY * AIBoard.CountExposedNeighbors(context, piece, column, row)

    -- Expedition regions take more or fewer risks (Outskirts trades freely, King's Throne avoids bad trades)
    local region = context.Match.RegionAI

    return loss * (region and region.Risk or 1)
end

-- Danger on the option's tile once its kills are taken off the board
local function GetDangerAfter(context, piece, option)
    local killed = {}

    if option.Hits then
        for _, hit in ipairs(option.Hits) do
            if not hit.Target.isKing and context.Health[hit.Target] > 0 and hit.Damage >= context.Health[hit.Target] then
                killed[hit.Target] = context.Health[hit.Target]
                context.Health[hit.Target] = 0
            end
        end
    end

    local danger = AIBoard.GetDanger(context, option.Column, option.Row, piece)

    for target, health in pairs(killed) do
        context.Health[target] = health
    end

    return danger
end

-- Returns the option's score and its parts by directive, for debugging
local function ScoreOption(context, piece, weights, option)
    local parts = {}

    if weights.Defend > 0 then
        parts.Defend = weights.Defend * GetDefendValue(context, piece, option)
    end

    local isPieceAttack = option.Type == "Attack"

    if option.Hits then
        parts.Attack = weights.Attack * GetAttackValue(context, option)

        if KillsPlayerKing(context, option) then
            parts.Attack += AIConfig.KING_KILL_SCORE
        end
    end

    local dangerAfter = GetDangerAfter(context, piece, option)

    -- Avoiding a bad move: every piece pays for where it ends up
    -- Piece attacks on a cheaper summoned piece are weighed as a trade (bait)
    local isBait = false

    if isPieceAttack then
        local target = option.Hits[1].Target
        isBait = not target.isKing and AIBoard.GetValue(target.Type) < AIBoard.GetValue(piece.Type)
    end

    parts.Risk = -GetLoss(context, piece, option.Column, option.Row, dangerAfter, isBait)

    -- What the tile sets up for next turn only counts if the piece is still around to use it
    local survival = 1 - AIBoard.GetDeathChance(piece, dangerAfter)

    -- Actively retreating: hurt pieces score for getting somewhere safer than where they stand
    if weights.Evade > 0 and IsEvading(piece) then
        local position = context.Positions[piece]
        local before = AIBoard.GetRisk(piece, AIBoard.GetDanger(context, position.Column, position.Row, piece))
        local after = AIBoard.GetRisk(piece, dangerAfter)

        parts.Evade = weights.Evade * GetUrgency(piece) * (before - after)
    end

    -- Position, Teamwork and Advance come from the tile the option ends on: its own, or the captured one
    local controlled = AIBoard.GetControlledTiles(context, piece.Type, piece.Team, option.Column, option.Row, GetKey(piece.Column, piece.Row))
    local covered, fresh = CountCovered(context, piece, controlled)

    if weights.Position > 0 then
        parts.Position = weights.Position * GetPositionValue(context, piece, controlled, covered, option) * survival
    end

    if weights.Teamwork > 0 then
        parts.Teamwork = weights.Teamwork * GetTeamworkValue(context, piece, option, controlled, fresh) * survival
    end

    -- Pawns keep marching whatever is in front of them, so players can read and exploit them
    parts.Advance = weights.Advance * GetAdvanceValue(context, piece, option) * (PAWNS[piece.Type] and 1 or survival)

    -- Stepping straight back to last turn's tile goes nowhere
    local memory = context.Memory[piece.Id]

    if option.Type == "Move" and memory and memory.FromColumn == option.Column and memory.FromRow == option.Row then
        parts.Advance -= AIConfig.BACKTRACK_PENALTY
    end

    local score = 0

    for _, value in pairs(parts) do
        score += value
    end

    return score, parts
end

--OPTIONS--

-- Enemy Kings aim straight at every white target in range
local function AddShots(context, piece, options)
    local weapon = context.KingWeapon
    local boss = context.Match.Boss
    local originX, originY = ShotgunRules.GetKingOrigin(piece.Column, piece.Row)

    local function IsBlocking(column, row)
        local target = context.Targets[GetKey(column, row)]
        return target ~= nil and context.Health[target] > 0
    end

    for _, target in ipairs(context.Whites) do
        if context.Health[target] > 0 and BoardRules.GetDistance(piece.Column, piece.Row, target.Column, target.Row) <= weapon.MaxRange then
            local aimX = target.Column - 0.5
            local aimY = target.Row - 0.5
            local _, hitTiles, shotType = ShotgunRules.GetFireResult(piece.Column, piece.Row, aimX, aimY, weapon, "Normal", IsBlocking)

            if hitTiles then
                local hits = {}

                for _, tile in pairs(hitTiles) do
                    local hitTarget = context.Targets[GetKey(tile.Column, tile.Row)]

                    -- Blasts into the Outlaw's smoke only land part of the time, so they count for less
                    local hitChance = context.Match:GetHitChance(tile.Column, tile.Row)

                    if hitTarget and context.Health[hitTarget] > 0 and hitChance > 0 then
                        local distance = BoardRules.GetDistance(piece.Column, piece.Row, tile.Column, tile.Row)
                        local damage = ShotgunRules.GetHitDamage(weapon, shotType, distance)
                            + BossAbilityService.GetShotBonus(boss, tile.Column, tile.Row)

                        -- Deadly Rounds (Gunslinger boss) loses damage for every white unit passed through
                        if weapon.Pierces then
                            damage -= ShotgunRules.CountBlockers(originX, originY, tile.Column, tile.Row, IsBlocking) * weapon.PierceDamageLoss
                        end

                        if damage > 0 then
                            table.insert(hits, {Target = hitTarget, Damage = damage * hitChance})
                        end
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

    if piece.Type == "King" then
        AddShots(context, piece, options)
    else
        -- Attacks resolve before anyone moves, so their lines are checked against the board at the start of the turn
        local function IsBlocked(column, row)
            return context.StartOccupied[GetKey(column, row)] == true
        end

        local function IsTarget(column, row)
            local target = context.Targets[GetKey(column, row)]
            return target ~= nil and context.Health[target] > 0
        end

        for _, attack in pairs(PieceRules.GetAttacks(piece.Type, piece.Team, piece.Column, piece.Row, IsBlocked, IsTarget)) do
            local target = context.Targets[GetKey(attack.Column, attack.Row)]
            local damage = piece:GetDamage()

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

    -- Moves run in plan order after the attacks, so tiles freed or claimed by earlier pieces are already settled
    local function IsMoveBlocked(column, row)
        return context.Occupied[GetKey(column, row)] == true
    end

    -- Evading sliders don't flee across the whole board
    local moveCap = IsEvading(piece) and AIConfig.SLIDE_CAP[piece.Type] or nil

    for _, move in pairs(PieceRules.GetMoves(piece.Type, piece.Team, piece.Column, piece.Row, IsMoveBlocked)) do
        if not moveCap or BoardRules.GetDistance(piece.Column, piece.Row, move.Column, move.Row) <= moveCap then
            table.insert(options, {Type = "Move", Column = move.Column, Row = move.Row})
        end
    end

    return options
end

--PLANNING--

local function CanMakeMistake(match, rating)
    if rating.MaxMistakes and match.AIMistakes >= rating.MaxMistakes then return false end

    return match.Random:NextNumber() < rating.MistakeChance
end

-- Allies other than the piece that the player's king could hit next turn
local function CountExposedAllies(context, piece)
    local count = 0

    for other, position in pairs(context.Positions) do
        if other ~= piece and AIBoard.GetKingDamage(context, position.Column, position.Row, other) > 0 then
            count += 1
        end
    end

    return count
end

local function ChooseOption(context, piece, rating)
    local weights = AdjustWeights(context, piece)
    context.ExposedAllies = CountExposedAllies(context, piece)
    local options = GetOptions(context, piece)

    for _, option in ipairs(options) do
        option.Score, option.Parts = ScoreOption(context, piece, weights, option)
    end

    table.sort(options, function(a, b)
        return a.Score > b.Score
    end)

    local choice = options[1]
    local isMistake = false

    -- A mistake is any option other than the best one
    if #options > 1 and CanMakeMistake(context.Match, rating) then
        context.Match.AIMistakes += 1

        choice = options[context.Match.Random:NextInteger(2, #options)]
        isMistake = true
    end

    if AIDebug.IsOn() then
        AIDebug.LogPiece(context, piece, weights, options, choice, isMistake)
    end

    return choice
end

-- Notes kept for next turn: where the piece came from, and how long a King has been backing off
local function Remember(context, piece, option)
    local memory = context.Memory[piece.Id] or {RetreatTurns = 0, IdleTurns = 0}
    local hasMoved = option.Column ~= piece.Column or option.Row ~= piece.Row

    memory.FromColumn = hasMoved and piece.Column or nil
    memory.FromRow = hasMoved and piece.Row or nil
    memory.IdleTurns = (hasMoved or option.Hits) and 0 or memory.IdleTurns + 1

    if piece.Type == "King" then
        local player = context.PlayerKing
        local before = BoardRules.GetDistance(piece.Column, piece.Row, player.Column, player.Row)
        local after = BoardRules.GetDistance(option.Column, option.Row, player.Column, player.Row)

        memory.RetreatTurns = after > before and memory.RetreatTurns + 1 or 0
    end

    context.Memory[piece.Id] = memory
end

-- Ticks every Black piece's stun and returns the plans of the ones that act
function EnemyAIService.PlanTurn(match)
    local acting = {}

    for _, piece in pairs(match.Pieces) do
        -- Raised pieces and the Necromancer who raised them sit this turn out
        if piece.Team == "Black" and piece:TickStun() and not piece.isResting then
            table.insert(acting, piece)
        end
    end

    if #acting == 0 then return {} end

    table.sort(acting, function(a, b)
        return a.Id < b.Id
    end)

    local context = AIBoard.BuildContext(match)
    context.KingWeapon = BossAbilityService.GetKingWeapon(match.Boss)
    local rating = AIConfig.Ratings[match.AIRating]
    local plans = {}

    -- How hard the player's king can hit the allied King with no one in the way, for measuring blocks
    local king = context.EnemyKing

    if king then
        context.KingLineDamage = AIBoard.GetKingDamage(context, king.Column, king.Row, king)
    end

    if AIDebug.IsOn() then
        AIDebug.LogTurn(context)
    end

    -- Conveyor order: the piece that reserves first moves down one place every enemy turn
    local offset = (match.Turn - 1) % #acting

    for i = 1, #acting do
        local piece = acting[(i + offset - 1) % #acting + 1]
        local option = ChooseOption(context, piece, rating)

        Remember(context, piece, option)
        AIBoard.Commit(context, piece, option)
        option.PieceId = piece.Id

        if option.Type ~= "Stay" then
            table.insert(plans, option)
        end
    end

    -- Abilities come third for the boss King: once every piece has its plan, score what the turn needs
    -- A stunned boss doesn't act, so it can't use them either
    if match.Boss then
        local isActing = table.find(acting, match.Boss.King) ~= nil
        plans.Boss = BossAbilityService.Decide(match.Boss, context, plans, isActing)

        if AIDebug.IsOn() and plans.Boss then
            AIDebug.LogBoss(match.Boss, plans.Boss)
        end
    end

    return plans
end

return EnemyAIService
