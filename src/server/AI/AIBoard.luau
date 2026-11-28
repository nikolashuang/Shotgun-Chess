local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardRules = require(ReplicatedStorage.Shared.Board.BoardRules)
local PieceConfig = require(ReplicatedStorage.Shared.Board.PieceConfig)
local PieceRules = require(ReplicatedStorage.Shared.Board.PieceRules)
local ShotgunRules = require(ReplicatedStorage.Shared.Combat.ShotgunRules)
local ShotgunConfig = require(ReplicatedStorage.Shared.Combat.ShotgunConfig)
local CombatConfig = require(ReplicatedStorage.Shared.Combat.CombatConfig)
local AIConfig = require(script.Parent.AIConfig)

local ActionCost = CombatConfig.ActionCost
local EnergyConfig = CombatConfig.Energy

local NEIGHBORS = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {1, -1}, {-1, 1}, {-1, -1}}

-- The enemy AI's view of the board: what it is allowed to know, kept up to date as each piece commits its plan
-- Only things the player could see are read (positions, health, ammo, energy), never their inputs
local AIBoard = {}

function AIBoard.GetKey(column, row)
    return column * 100 + row
end

local GetKey = AIBoard.GetKey

function AIBoard.GetValue(pieceType)
    return AIConfig.PieceValue[pieceType] or 1
end

-- Furthest a hurt slider can move, or nil for a full slide
function AIBoard.GetLowHealthRange(piece)
    if not AIConfig.LOW_HEALTH_SLIDERS[piece.Type] then return nil end

    local share = piece.Health / piece.MaxHealth

    for _, tier in ipairs(AIConfig.LOW_HEALTH_RANGE) do
        if share <= tier.Health then return tier.Range end
    end

    return nil
end

-- Tiles a piece standing on column, row could hit next turn; ignoreKey is the piece's own current tile
function AIBoard.GetControlledTiles(context, pieceType, team, column, row, ignoreKey)
    local tiles = {}

    if pieceType == "Pawn" or pieceType == "FallenPawn" then
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

-- What the player's next turn allows: energy comes in at the start of it, and each action is once per turn
local function GetPlayerActions(match, king)
    local side = match.Sides.White
    local weapon = king.Shotgun
    local energy = math.min(side.Energy + EnergyConfig.ENERGY_PER_TURN, side.MaxEnergy)

    local actions = {Energy = energy, ShotCost = nil, canKnife = false, canCommand = energy >= ActionCost.Command}

    -- A stunned king can't fire, but its pieces can still be commanded
    if king:IsStunned() then return actions end

    -- Out of shells means a reload first
    if king.Ammo >= weapon.AmmoPerShot then
        actions.ShotCost = ActionCost.Fire
    elseif energy >= ActionCost.Fire + ActionCost.Reload then
        actions.ShotCost = ActionCost.Fire + ActionCost.Reload
    end

    if actions.ShotCost and energy < actions.ShotCost then
        actions.ShotCost = nil
    end

    actions.canKnife = weapon.AltMode == "Knife" and energy >= ActionCost.Fire

    return actions
end

function AIBoard.BuildContext(match)
    local king = match.King

    local context = {
        Match = match,
        Memory = match.AIMemory,
        PlayerKing = {isKing = true, Type = "King", Column = king.Column, Row = king.Row},
        PlayerHealth = king.Health,
        PlayerMaxHealth = king.MaxHealth,
        PlayerWeapon = king.Shotgun,
        PlayerDamageBonus = (king.DamageBonus or 0) + (match.Sides.White.NextShotBonus or 0),
        PlayerActions = GetPlayerActions(match, king),
        KingWeapon = ShotgunRules.GetWeapon(ShotgunConfig.ENEMY_KING),
        EnemyKing = nil,

        Whites = {},
        Blacks = {},

        -- Tiles at the start of the turn: attacks resolve before anyone moves, so they're checked against this
        StartOccupied = {},
        -- Tiles after the plans so far: movers free their old tile and claim their new one
        Occupied = {},
        Targets = {},
        -- Black pieces by their planned tile, for what blocks the player's pellets
        BlackTiles = {},

        -- Health left on each white target after the attacks planned so far
        Health = {},
        -- White targets an ally already planned to hit this turn
        Damaged = {},
        -- Tiles each white piece can hit next turn
        Threats = {},
        -- Tiles each black piece controls from its planned tile
        Coverage = {},
        Positions = {},

        -- Tiles the player's king could fire from next turn: its own and every empty tile it could step to
        PlayerReach = {},
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
            context.BlackTiles[key] = piece
            table.insert(context.Blacks, piece)
        end
    end

    context.StartOccupied = table.clone(context.Occupied)

    for _, target in ipairs(context.Whites) do
        -- Stunned pieces can't be commanded next turn
        if not target.isKing and not target.Piece:IsStunned() then
            context.Threats[target] = AIBoard.GetControlledTiles(context, target.Type, "White", target.Column, target.Row)
        end
    end

    for _, piece in ipairs(context.Blacks) do
        context.Coverage[piece] = AIBoard.GetControlledTiles(context, piece.Type, piece.Team, piece.Column, piece.Row)
    end

    table.insert(context.PlayerReach, {Column = king.Column, Row = king.Row})

    -- Empty tiles the player's king could step to
    for _, offset in ipairs(NEIGHBORS) do
        local column = king.Column + offset[1]
        local row = king.Row + offset[2]

        if BoardRules.IsOnBoard(column, row) and not context.Occupied[GetKey(column, row)] then
            table.insert(context.EscapeTiles, GetKey(column, row))
            table.insert(context.PlayerReach, {Column = column, Row = row})
        end
    end

    -- Whatever could hit the enemy King next turn
    local enemyKing = context.EnemyKing

    if enemyKing then
        local kingKey = GetKey(enemyKing.Column, enemyKing.Row)

        if AIBoard.GetKingDamage(context, enemyKing.Column, enemyKing.Row, enemyKing) > 0 then
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

--DANGER--

-- Most the player's king could deal to a piece on this tile next turn: step once, then blast or slash
-- Non-piercing pellets stop at the first black piece, so a tile behind an ally is safe from them
function AIBoard.GetKingDamage(context, column, row, ignorePiece)
    local actions = context.PlayerActions
    if not actions.ShotCost and not actions.canKnife then return 0 end

    local weapon = context.PlayerWeapon
    local ignoreKey = ignorePiece and context.Positions[ignorePiece]
        and GetKey(context.Positions[ignorePiece].Column, context.Positions[ignorePiece].Row)

    local function IsBlocking(blockColumn, blockRow)
        local key = GetKey(blockColumn, blockRow)
        return key ~= ignoreKey and context.BlackTiles[key] ~= nil
    end

    local best = 0

    for i, tile in ipairs(context.PlayerReach) do
        local distance = BoardRules.GetDistance(tile.Column, tile.Row, column, row)
        -- The first reach tile is where the King stands; any other costs a move first
        local stepCost = i == 1 and 0 or ActionCost.Move
        local canShoot = actions.ShotCost ~= nil and actions.Energy >= actions.ShotCost + stepCost
        local canKnife = actions.canKnife and actions.Energy >= ActionCost.Fire + stepCost

        if distance >= 1 then
            if canShoot and distance <= weapon.MaxRange then
                local originX, originY = ShotgunRules.GetKingOrigin(tile.Column, tile.Row)
                local damage = ShotgunRules.GetDamage(distance, weapon) * weapon.Blasts + context.PlayerDamageBonus

                if weapon.Pierces then
                    local blockers = ShotgunRules.CountBlockers(originX, originY, column, row, IsBlocking)
                    damage -= blockers * (weapon.PierceDamageLoss or 0)
                elseif not ShotgunRules.HasLineOfSight(originX, originY, column, row, IsBlocking) then
                    damage = 0
                end

                best = math.max(best, damage)
            end

            if canKnife and distance == 1 then
                best = math.max(best, weapon.Knife.Damage + context.PlayerDamageBonus)
            end
        end
    end

    return best
end

-- Most one commanded white piece could deal there (one command per turn)
local function GetPieceDamage(context, key)
    if not context.PlayerActions.canCommand then return 0 end

    local best = 0

    for target, tiles in pairs(context.Threats) do
        if tiles[key] and context.Health[target] > 0 then
            best = math.max(best, target.GetDamage and target:GetDamage() or PieceConfig.Damage[target.Type] or 0)
        end
    end

    return best
end

-- Expected damage the player could deal to a piece on this tile next turn
function AIBoard.GetDanger(context, column, row, ignorePiece)
    local kingDamage = AIBoard.GetKingDamage(context, column, row, ignorePiece)
    local pieceDamage = GetPieceDamage(context, GetKey(column, row))

    -- Both only fit in one turn if there's energy for the shot and the command
    local actions = context.PlayerActions
    local shotCost = actions.ShotCost or ActionCost.Fire

    if kingDamage > 0 and pieceDamage > 0 and actions.Energy >= shotCost + ActionCost.Command then
        return kingDamage + pieceDamage
    end

    return math.max(kingDamage, pieceDamage)
end

-- 0 to 1: how much of the piece's health the tile could take (scaled up so half health already counts as full risk)
function AIBoard.GetRisk(piece, danger)
    return math.min(danger * AIConfig.RISK_SCALE / piece.MaxHealth, 1)
end

-- 0 to 1: rough chance the piece dies on the tile; climbs steeply toward a sure kill
function AIBoard.GetDeathChance(piece, danger)
    local health = piece.Health + (piece.Shield or 0)
    if danger >= health then return 1 end

    return (danger / health) ^ 2
end

-- 0 to 1: share of the piece's health the tile could take
function AIBoard.GetHealthShare(piece, danger)
    return math.min(danger / (piece.Health + (piece.Shield or 0)), 1)
end

-- Allies within 1 tile of the tile that the player could also hit
function AIBoard.CountExposedNeighbors(context, piece, column, row)
    local count = 0

    for other, position in pairs(context.Positions) do
        if other ~= piece and BoardRules.GetDistance(column, row, position.Column, position.Row) <= 1
            and AIBoard.GetKingDamage(context, position.Column, position.Row, other) > 0 then
            count += 1
        end
    end

    return count
end

--PLANS--

-- Updates the board with a piece's chosen option so the next piece plans around it
function AIBoard.Commit(context, piece, option)
    local oldKey = GetKey(piece.Column, piece.Row)
    local newKey = GetKey(option.Column, option.Row)

    if option.Hits then
        for _, hit in ipairs(option.Hits) do
            context.Health[hit.Target] -= hit.Damage
            context.Damaged[hit.Target] = true
        end
    end

    if newKey ~= oldKey then
        context.Occupied[oldKey] = nil
        context.Occupied[newKey] = true
        context.BlackTiles[oldKey] = nil
        context.BlackTiles[newKey] = piece

        -- Every coverage line through either tile may have changed
        for other, position in pairs(context.Positions) do
            if other ~= piece then
                context.Coverage[other] = AIBoard.GetControlledTiles(context, other.Type, other.Team, position.Column, position.Row)
            end
        end
    end

    context.Positions[piece] = {Column = option.Column, Row = option.Row}
    context.Coverage[piece] = AIBoard.GetControlledTiles(context, piece.Type, piece.Team, option.Column, option.Row)
end

return AIBoard
