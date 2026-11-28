local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardRules = require(ReplicatedStorage.Shared.Board.BoardRules)
local PieceRules = require(ReplicatedStorage.Shared.Board.PieceRules)
local ShotgunRules = require(ReplicatedStorage.Shared.Combat.ShotgunRules)
local ShotgunConfig = require(ReplicatedStorage.Shared.Combat.ShotgunConfig)
local ClassConfig = require(ReplicatedStorage.Shared.Combat.ClassConfig)
local AIConfig = require(script.Parent.AIConfig)
local AIBoard = require(script.Parent.AIBoard)

local BossConfig = AIConfig.Boss
local GetKey = AIBoard.GetKey

local BossAbilityService = {}

local Classes = {}

-- Every Black piece but the King, the ones Monarch abilities affect
local function GetAllies(match)
    local allies = {}

    for _, piece in pairs(match.Pieces) do
        if piece.Team == "Black" and piece.Type ~= "King" then
            table.insert(allies, piece)
        end
    end

    return allies
end

-- The player's king or a white piece on the tile
local function GetWhiteAt(match, column, row)
    local king = match.King
    if king:IsAlive() and king.Column == column and king.Row == row then return king end

    local piece = match:GetPieceAt(column, row)
    return piece and piece.Team == "White" and piece or nil
end

local function GetKingPlan(boss, plans)
    for _, plan in ipairs(plans) do
        if plan.PieceId == boss.King.Id then return plan end
    end

    return nil
end

local function CountSouls(boss, exceptId)
    local count = 0

    for id in pairs(boss.Souls) do
        if id ~= exceptId then
            count += 1
        end
    end

    return count
end

--MONARCH--

local MonarchConfig = ClassConfig.Classes.Monarch

Classes.Monarch = {Timing = {Special = "Before", Ultimate = "Before"}}

-- Special: shield allies that end the turn where the player can hit them
-- Ultimate: once unlocked, spend it on a turn where allies are attacking so the extra damage lands
function Classes.Monarch.Decide(boss, context, plans)
    local trapped = 0
    local attacks = 0

    for piece, position in pairs(context.Positions) do
        if piece ~= boss.King and AIBoard.GetDanger(context, position.Column, position.Row, piece) > 0 then
            trapped += 1
        end
    end

    for _, plan in ipairs(plans) do
        if plan.Type == "Attack" then
            attacks += 1
        end
    end

    return {
        Special = trapped >= BossConfig.MONARCH_SHIELD_MIN and {} or nil,
        Ultimate = attacks > 0 and {} or nil,
    }
end

function Classes.Monarch.Use(boss, kind)
    local match = boss.Match
    local allies = GetAllies(match)
    if #allies == 0 then return false end

    if kind == "Special" then
        for _, piece in ipairs(allies) do
            piece.Shield = MonarchConfig.Morale.Shield
            boss.Shielded[piece.Id] = true
            match:SendAll("PieceShielded", piece.Id, piece.Shield)
        end
    else
        boss.DamageBonus = MonarchConfig.Unyielding.Damage
    end

    return true
end

--REAPER--

local ReaperConfig = ClassConfig.Classes.Reaper

-- Reaper's High goes first so its damage reaches this turn's shot; Assimilate is the getaway after the shot
Classes.Reaper = {Timing = {Special = "After", Ultimate = "Before"}}

-- Reap: every piece that dies leaves a soul, allies included (shown as red flames)
function Classes.Reaper.OnPieceKilled(boss, piece)
    if ReaperConfig.NO_SOUL[piece.Type] then return end
    -- Pieces a Necromancer raised don't drop a second soul
    if piece.isRaised then return end

    local match = boss.Match
    local soul = {Id = match.NextSoulId, Type = piece.Type, Column = piece.Column, Row = piece.Row}
    match.NextSoulId += 1
    boss.Souls[soul.Id] = soul

    match:SendAll("SoulAdded", soul.Id, soul.Type, soul.Column, soul.Row, true)
end

-- Special: after acting in place, spend a soul to move like its piece to the safest tile it reaches
-- Ultimate: absorb the souls when the heal or the extra damage on this turn's shot is worth it
function Classes.Reaper.Decide(boss, context, plans, ready)
    local king = boss.King
    local position = context.Positions[king]
    local plan = GetKingPlan(boss, plans)
    local decision = {}

    if ready.Special and (not plan or plan.Type == "Shoot") then
        local before = AIBoard.GetDanger(context, position.Column, position.Row, king)
        local best = nil

        local function IsBlocked(column, row)
            return context.Occupied[GetKey(column, row)] == true
        end

        for id, soul in pairs(boss.Souls) do
            for _, move in pairs(PieceRules.GetMoves(soul.Type, "Black", position.Column, position.Row, IsBlocked)) do
                local danger = AIBoard.GetDanger(context, move.Column, move.Row, king)

                if not best or danger < best.Danger then
                    best = {SoulId = id, Column = move.Column, Row = move.Row, Danger = danger}
                end
            end
        end

        if best and before - best.Danger >= BossConfig.REAPER_RETREAT_MIN then
            decision.Special = best
        end
    end

    -- The soul kept for Assimilate isn't absorbed
    local reserved = decision.Special and decision.Special.SoulId
    local count = CountSouls(boss, reserved)

    if ready.Ultimate and count > 0 then
        local high = ReaperConfig.ReapersHigh
        local heal = math.min(high.HealPerSoul * count, high.MaxHeal, king.MaxHealth - king.Health)
        local isShooting = plan and plan.Type == "Shoot"
        local value = heal / high.HealPerSoul + (isShooting and count or 0)

        if value >= BossConfig.REAPERS_HIGH_MIN then
            decision.Ultimate = {Reserved = reserved}
        end
    end

    return decision
end

function Classes.Reaper.Use(boss, kind, payload)
    local match = boss.Match
    local king = boss.King

    if kind == "Special" then
        local soul = boss.Souls[payload.SoulId]
        if not soul or match:IsOccupied(payload.Column, payload.Row) then return false end

        boss.Souls[soul.Id] = nil
        match:SendAll("SoulsRemoved", {soul.Id})

        king.Column = payload.Column
        king.Row = payload.Row
        match:SendAll("PieceMoved", king.Id, king.Column, king.Row)
        match:OnUnitMoved(king)

        return true
    end

    local high = ReaperConfig.ReapersHigh
    local absorbed = {}

    for id in pairs(boss.Souls) do
        if id ~= payload.Reserved then
            table.insert(absorbed, id)
        end
    end

    if #absorbed == 0 then return false end

    for _, id in ipairs(absorbed) do
        boss.Souls[id] = nil
    end

    king.Health = math.min(king.Health + math.min(high.HealPerSoul * #absorbed, high.MaxHeal), king.MaxHealth)
    boss.ShotBonus += high.DamagePerSoul * #absorbed

    -- The souls fly into the boss, then he heals
    match:SendAll("SoulsRemoved", absorbed, true, king.Column, king.Row)
    match:SendAll("PieceHealed", king.Id, king.Health)

    return true
end

--HUNTER--

local HunterConfig = ClassConfig.Classes.Hunter
local TrapConfig = HunterConfig.Traps

-- Both go off after the pieces move, so traps avoid the tiles they end on and the bolas fly from the King's last tile
Classes.Hunter = {Timing = {Special = "After", Ultimate = "After"}}

local function GetTrapAt(boss, column, row)
    for _, trap in pairs(boss.Traps) do
        if trap.Column == column and trap.Row == row then return trap end
    end

    return nil
end

-- Special: lay traps on the tiles in reach the player is most likely to come through, closest to the player first,
-- and tiles a white piece could step onto
-- Ultimate: throw bolas when they catch the player's king or enough pieces
function Classes.Hunter.Decide(boss, context, _, ready)
    local position = context.Positions[boss.King]
    local player = context.PlayerKing
    local decision = {}

    if ready.Special then
        local tiles = {}
        local range = TrapConfig.Range

        for column = position.Column - range, position.Column + range do
            for row = position.Row - range, position.Row + range do
                local key = GetKey(column, row)

                if BoardRules.IsOnBoard(column, row) and not context.Occupied[key] and not GetTrapAt(boss, column, row) then
                    local value = 1 / (1 + BoardRules.GetDistance(column, row, player.Column, player.Row))

                    for target, threat in pairs(context.Threats) do
                        if threat[key] and context.Health[target] > 0 then
                            value += BossConfig.TRAP_PATH_VALUE
                            break
                        end
                    end

                    table.insert(tiles, {Column = column, Row = row, Value = value})
                end
            end
        end

        table.sort(tiles, function(a, b)
            return a.Value > b.Value
        end)

        local picked = {}

        for i = 1, math.min(TrapConfig.Count, #tiles) do
            table.insert(picked, {Column = tiles[i].Column, Row = tiles[i].Row})
        end

        if #picked > 0 then
            decision.Special = {Tiles = picked}
        end
    end

    if ready.Ultimate then
        local weapon = ShotgunRules.GetWeapon(HunterConfig.HuntingStrike.Weapon)
        local best = nil

        local function IsBlocking(column, row)
            local target = context.Targets[GetKey(column, row)]
            return target ~= nil and context.Health[target] > 0
        end

        for _, target in ipairs(context.Whites) do
            if context.Health[target] > 0 and BoardRules.GetDistance(position.Column, position.Row, target.Column, target.Row) <= weapon.MaxRange then
                local aimX, aimY = target.Column - 0.5, target.Row - 0.5
                local _, hitTiles = ShotgunRules.GetFireResult(position.Column, position.Row, aimX, aimY, weapon, "Normal", IsBlocking)
                local value = 0

                for _, tile in pairs(hitTiles or {}) do
                    local hit = context.Targets[GetKey(tile.Column, tile.Row)]

                    if hit and context.Health[hit] > 0 then
                        value += hit.isKing and BossConfig.BOLAS_KING_VALUE or 1
                    end
                end

                if not best or value > best.Value then
                    best = {X = aimX, Y = aimY, Value = value}
                end
            end
        end

        if best and best.Value >= BossConfig.BOLAS_MIN then
            decision.Ultimate = best
        end
    end

    return decision
end

function Classes.Hunter.Use(boss, kind, payload)
    local match = boss.Match

    if kind == "Special" then
        local placed = 0

        -- Hidden: the player only finds out when one snaps shut
        for _, tile in ipairs(payload.Tiles) do
            if not match:IsOccupied(tile.Column, tile.Row) and not GetTrapAt(boss, tile.Column, tile.Row) then
                local trap = {Id = boss.NextTrapId, Column = tile.Column, Row = tile.Row}
                boss.NextTrapId += 1
                boss.Traps[trap.Id] = trap
                placed += 1
            end
        end

        return placed > 0
    end

    local strike = HunterConfig.HuntingStrike
    local king = boss.King
    local weapon = ShotgunRules.GetWeapon(strike.Weapon)

    local function IsWhiteTile(column, row)
        return GetWhiteAt(match, column, row) ~= nil
    end

    local _, hitTiles = ShotgunRules.GetFireResult(king.Column, king.Row, payload.X, payload.Y, weapon, "Normal", IsWhiteTile)
    if not hitTiles then return false end

    local targets = {}

    for _, tile in pairs(hitTiles) do
        local unit = GetWhiteAt(match, tile.Column, tile.Row)

        if unit then
            table.insert(targets, unit)
        end
    end

    -- Nothing to stun means the ultimate isn't spent
    if #targets == 0 then return false end

    for _, unit in ipairs(targets) do
        match:StunPiece(unit, unit == match.King and strike.KingStunTurns or strike.StunTurns, "Bolas")
    end

    return true
end

-- The player's units walk (or get knocked) right into traps they can't see
function Classes.Hunter.OnUnitMoved(boss, unit)
    if unit.Team ~= "White" then return end

    local trap = GetTrapAt(boss, unit.Column, unit.Row)
    if not trap then return end

    boss.Traps[trap.Id] = nil

    local match = boss.Match
    local health, targetId = match:DamageWhiteTile(unit.Column, unit.Row, TrapConfig.Damage)

    -- Shown only now, then snapped shut
    match:SendAll("TrapsPlaced", {trap})
    match:SendAll("TrapSprung", trap.Id, targetId, health)

    if not targetId then
        match:SendAll("KingAttacked", nil, health)
    end

    if health and health > 0 then
        match:StunPiece(unit, TrapConfig.StunTurns, "Stars")
    end
end

-- A commanded piece whose straight line crosses a trap stops there and springs it; knights jump over them
function Classes.Hunter.InterceptPath(boss, piece, column, row)
    if piece.Type == "Knight" then return false end

    local columnStep = math.sign(column - piece.Column)
    local rowStep = math.sign(row - piece.Row)
    local columnDistance = math.abs(column - piece.Column)
    local rowDistance = math.abs(row - piece.Row)

    if columnDistance ~= 0 and rowDistance ~= 0 and columnDistance ~= rowDistance then return false end

    for step = 1, math.max(columnDistance, rowDistance) - 1 do
        local trap = GetTrapAt(boss, piece.Column + columnStep * step, piece.Row + rowStep * step)

        if trap then
            piece.Column = trap.Column
            piece.Row = trap.Row

            boss.Match:SendAll("PieceMoved", piece.Id, trap.Column, trap.Row)
            Classes.Hunter.OnUnitMoved(boss, piece)

            return true
        end
    end

    return false
end

--BANDIT--

local OutlawConfig = ClassConfig.Classes.Outlaw

-- Smoke goes up after the pieces move so it covers where they end up; Ambush happens before anyone plans (Prepare)
Classes.Outlaw = {Timing = {Special = "After"}}

-- Opportunist: extra damage on a target with no ally next to it
function Classes.Outlaw.GetHitBonus(boss, column, row)
    local match = boss.Match
    local target = GetWhiteAt(match, column, row)
    if not target then return 0 end

    local king = match.King

    if target ~= king and king:IsAlive() and BoardRules.GetDistance(column, row, king.Column, king.Row) <= 1 then return 0 end

    for _, piece in pairs(match.Pieces) do
        if piece ~= target and piece.Team == "White" and BoardRules.GetDistance(column, row, piece.Column, piece.Row) <= 1 then
            return 0
        end
    end

    return OutlawConfig.Opportunist.Damage
end

function Classes.Outlaw.GetHitChance(boss, column, row)
    local smoke = boss.Smoke
    if not smoke then return 1 end

    return BoardRules.GetDistance(smoke.Column, smoke.Row, column, row) <= OutlawConfig.Conceal.Radius
        and OutlawConfig.Conceal.HitChance or 1
end

-- Special: smoke the spot where the most value is in danger, the King's own tile counting most when it's threatened
function Classes.Outlaw.Decide(boss, context, _, ready)
    if not ready.Special then return {} end

    local conceal = OutlawConfig.Conceal
    local position = context.Positions[boss.King]
    local risks = {}

    for piece, piecePosition in pairs(context.Positions) do
        local danger = AIBoard.GetDanger(context, piecePosition.Column, piecePosition.Row, piece)

        if danger > 0 then
            table.insert(risks, {Position = piecePosition, Value = AIBoard.GetRisk(piece, danger) * AIBoard.GetValue(piece.Type)})
        end
    end

    local best = nil

    for column = position.Column - conceal.Range, position.Column + conceal.Range do
        for row = position.Row - conceal.Range, position.Row + conceal.Range do
            if BoardRules.IsOnBoard(column, row) then
                local value = 0

                for _, risk in ipairs(risks) do
                    if BoardRules.GetDistance(column, row, risk.Position.Column, risk.Position.Row) <= conceal.Radius then
                        value += risk.Value * (1 - conceal.HitChance)
                    end
                end

                if not best or value > best.Value then
                    best = {Column = column, Row = row, Value = value}
                end
            end
        end
    end

    return {Special = best and best.Value >= BossConfig.CONCEAL_MIN and best or nil}
end

function Classes.Outlaw.Use(boss, _, payload)
    boss.Smoke = {Column = payload.Column, Row = payload.Row}
    boss.Match:SendAll("SmokeChanged", payload.Column, payload.Row, OutlawConfig.Conceal.Radius)

    return true
end

-- Ultimate, before the turn is planned: jump next to the player's king when the point blank shot from there kills,
-- or hits hard enough (Opportunist included) without landing somewhere the King would die
function Classes.Outlaw.Prepare(boss)
    local match = boss.Match
    local king = boss.King
    local player = match.King

    local context = AIBoard.BuildContext(match)
    context.KingWeapon = BossAbilityService.GetKingWeapon(boss)

    local function IsWhiteTile(column, row)
        return GetWhiteAt(match, column, row) ~= nil
    end

    local best = nil

    for column = player.Column - OutlawConfig.Ambush.MaxEnemyDistance, player.Column + OutlawConfig.Ambush.MaxEnemyDistance do
        for row = player.Row - OutlawConfig.Ambush.MaxEnemyDistance, player.Row + OutlawConfig.Ambush.MaxEnemyDistance do
            if BoardRules.IsOnBoard(column, row) and not match:IsOccupied(column, row) then
                local _, _, shotType = ShotgunRules.GetFireResult(column, row, player.Column - 0.5, player.Row - 0.5, context.KingWeapon, "Normal", IsWhiteTile)

                if shotType then
                    local distance = BoardRules.GetDistance(column, row, player.Column, player.Row)
                    local damage = ShotgunRules.GetHitDamage(context.KingWeapon, shotType, distance)
                        + BossAbilityService.GetShotBonus(boss, player.Column, player.Row)
                    local danger = AIBoard.GetDanger(context, column, row, king)

                    local isWorth = damage >= player.Health or (damage >= BossConfig.AMBUSH_MIN_DAMAGE and danger < king.Health)

                    if isWorth and (not best or damage - danger > best.Value) then
                        best = {Column = column, Row = row, Value = damage - danger}
                    end
                end
            end
        end
    end

    if not best then return false end

    king.Column = best.Column
    king.Row = best.Row
    match:SendAll("PieceMoved", king.Id, king.Column, king.Row)
    match:OnUnitMoved(king)

    return true
end

--GUNSLINGER--

local GunslingerConfig = ClassConfig.Classes.Gunslinger

-- Fan the Hammer follows the King's shotgun blast so it can finish what the blast leaves standing
Classes.Gunslinger = {Timing = {Special = "After", Ultimate = "Before"}}

-- Special: fan down the line where six shots do the most, counting the health the turn's other attacks already took
-- Ultimate: mark the white pieces closest to dying; each one that dies brings Fan the Hammer straight back
function Classes.Gunslinger.Decide(boss, context, _, ready)
    local position = context.Positions[boss.King]
    local decision = {}

    if ready.Special then
        local fan = GunslingerConfig.FanTheHammer
        local best = nil

        for _, target in ipairs(context.Whites) do
            if context.Health[target] > 0 and BoardRules.GetDistance(position.Column, position.Row, target.Column, target.Row) <= fan.Range then
                local aimX, aimY = target.Column - 0.5, target.Row - 0.5
                local _, lineTiles = ShotgunRules.GetPreciseShot(position.Column, position.Row, aimX, aimY, fan.Range)
                local damageLeft = fan.Shots * fan.HitChance * fan.Damage
                local value = 0

                -- Each shot hits the first white unit still standing in the line
                for _, tile in ipairs(lineTiles or {}) do
                    local hit = context.Targets[GetKey(tile.Column, tile.Row)]
                    local health = hit and context.Health[hit] or 0

                    if health > 0 and damageLeft > 0 then
                        local dealt = math.min(damageLeft, health)
                        damageLeft -= dealt

                        value += dealt / health
                        if hit.isKing then
                            value += BossConfig.FAN_KING_VALUE
                        end
                    end
                end

                if not best or value > best.Value then
                    best = {X = aimX, Y = aimY, Value = value}
                end
            end
        end

        if best and best.Value >= BossConfig.FAN_MIN then
            decision.Special = best
        end
    end

    if ready.Ultimate then
        local candidates = {}

        for _, target in ipairs(context.Whites) do
            if not target.isKing and context.Health[target] > 0 and not boss.Marks[target.Piece.Id] then
                table.insert(candidates, target)
            end
        end

        table.sort(candidates, function(a, b)
            return context.Health[a] / a.Piece.MaxHealth < context.Health[b] / b.Piece.MaxHealth
        end)

        local ids = {}

        for i = 1, math.min(GunslingerConfig.Bounty.Marks, #candidates) do
            table.insert(ids, candidates[i].Piece.Id)
        end

        if #ids > 0 then
            decision.Ultimate = {Ids = ids}
        end
    end

    return decision
end

function Classes.Gunslinger.Use(boss, kind, payload)
    local match = boss.Match

    if kind == "Ultimate" then
        local marked = 0

        for _, id in ipairs(payload.Ids) do
            if match.Pieces[id] then
                boss.Marks[id] = true
                match:SendAll("PieceMarked", id, true)
                marked += 1
            end
        end

        return marked > 0
    end

    local fan = GunslingerConfig.FanTheHammer
    local king = boss.King
    local _, lineTiles = ShotgunRules.GetPreciseShot(king.Column, king.Row, payload.X, payload.Y, fan.Range)
    if not lineTiles or #lineTiles == 0 then return false end

    local lastTile = lineTiles[#lineTiles]
    local pellets = {}
    local hitTiles = {}
    local damaged = {}

    for _ = 1, fan.Shots do
        local target = nil

        for _, tile in ipairs(lineTiles) do
            target = GetWhiteAt(match, tile.Column, tile.Row)
            if target then break end
        end

        -- Each shot rolls its own hit chance, and again for a target inside the player's smoke
        if target and match.Random:NextNumber() < fan.HitChance and match:RollHit(target.Column, target.Row) then
            local column, row = target.Column, target.Row
            local health, targetId = match:DamageWhiteTile(column, row, fan.Damage)

            table.insert(pellets, {X = column - 0.5, Y = row - 0.5})
            table.insert(hitTiles, {Column = column, Row = row})
            damaged[GetKey(column, row)] = {Id = targetId, Column = column, Row = row, Health = health}
        else
            table.insert(pellets, {X = lastTile.Column - 0.5, Y = lastTile.Row - 0.5})
        end
    end

    local results = {}

    for _, result in pairs(damaged) do
        table.insert(results, result)
    end

    match:SendAll("EnemyShotFired", king.Id, pellets, hitTiles, results)

    return true
end

-- A marked piece dying brings the special back right away (the boss's version of the bounty's energy)
function Classes.Gunslinger.OnPieceKilled(boss, piece)
    if not boss.Marks[piece.Id] then return end

    boss.Marks[piece.Id] = nil
    boss.SpecialReadyTurn = boss.Match.Turn
end

--SHARED--

-- Called once the match has placed its enemies; returns nil unless a Black King with a class we can play is there
function BossAbilityService.New(match)
    for _, piece in pairs(match.Pieces) do
        if piece.Team == "Black" and piece.Type == "King" and Classes[piece.ClassName] then
            return {
                Match = match,
                King = piece,
                ClassName = piece.ClassName,
                -- The first special is ready on the first enemy turn
                SpecialReadyTurn = 1,
                hasUsedUltimate = false,

                -- Monarch
                DamageBonus = 0,
                Shielded = {},
                -- Reaper: souls on the board, and extra damage on the King's next shot
                Souls = {},
                ShotBonus = 0,
                -- Hunter: hidden traps; ids start high so they never clash with the player's own Hunter traps
                Traps = {},
                NextTrapId = BossConfig.TRAP_ID_START,
                -- Bandit: {Column, Row} of the smoke cloud's center
                Smoke = nil,
                -- Gunslinger: white piece ids under High Noon's Bounty
                Marks = {},
            }
        end
    end

    return nil
end

local function IsAlive(boss)
    return boss and boss.Match.Pieces[boss.King.Id] ~= nil
end

local function IsUltimateReady(boss)
    local king = boss.King
    return not boss.hasUsedUltimate and king.Health <= king.MaxHealth * BossConfig.ULTIMATE_HEALTH
end

local function Announce(boss, kind)
    local abilities = ClassConfig.Classes[boss.ClassName]

    -- The ability's name is the text before the colon in ClassConfig
    local name = string.match(abilities[kind], "^(.-):") or kind
    boss.Match:SendAll("BossAbility", boss.King.Id, name)
end

-- Start of the enemy turn: the last Morale shield and the last smoke run out
function BossAbilityService.StartTurn(boss)
    for id in pairs(boss.Shielded) do
        local piece = boss.Match.Pieces[id]

        if piece then
            piece.Shield = 0
            boss.Match:SendAll("PieceShielded", id, 0)
        end
    end

    boss.Shielded = {}

    if boss.Smoke then
        boss.Smoke = nil
        boss.Match:SendAll("SmokeChanged", nil)
    end
end

-- Before the turn is planned: ultimates that change where the King plans from (Bandit's Ambush)
function BossAbilityService.PrepareTurn(boss)
    if not IsAlive(boss) or boss.King:IsStunned() then return end

    local class = Classes[boss.ClassName]
    if not class.Prepare or not IsUltimateReady(boss) then return end

    if class.Prepare(boss) then
        boss.hasUsedUltimate = true
        Announce(boss, "Ultimate")
    end
end

-- Once every piece has planned; returns {Special = payload, Ultimate = payload} for whatever is ready and worth using
function BossAbilityService.Decide(boss, context, plans, isActing)
    if not IsAlive(boss) or not isActing then return nil end

    local ready = {
        Special = boss.Match.Turn >= boss.SpecialReadyTurn,
        Ultimate = IsUltimateReady(boss),
    }

    if not ready.Special and not ready.Ultimate then return nil end

    local wants = Classes[boss.ClassName].Decide(boss, context, plans, ready)

    return {
        Special = ready.Special and wants.Special or nil,
        Ultimate = ready.Ultimate and wants.Ultimate or nil,
    }
end

-- timing is "Before" (ahead of the pieces' attacks) or "After" (once everyone has moved)
function BossAbilityService.Use(boss, decision, timing)
    if not decision or not IsAlive(boss) then return end

    local class = Classes[boss.ClassName]

    for _, kind in ipairs({"Special", "Ultimate"}) do
        local payload = decision[kind]
        local kindTiming = class.Timing and class.Timing[kind] or "Before"

        if payload and kindTiming == timing and class.Use(boss, kind, payload) then
            if kind == "Special" then
                boss.SpecialReadyTurn = boss.Match.Turn + BossConfig.SPECIAL_COOLDOWN
            else
                boss.hasUsedUltimate = true
            end

            Announce(boss, kind)
        end
    end
end

-- Extra damage every Black piece's attack deals this turn
function BossAbilityService.GetDamageBonus(boss)
    return boss and boss.DamageBonus or 0
end

-- The enemy King's shotgun, tuned for the boss's class passive (Gunslinger's Deadly Rounds)
function BossAbilityService.GetKingWeapon(boss)
    return ShotgunRules.GetWeapon(ShotgunConfig.ENEMY_KING, boss and boss.ClassName)
end

-- Extra damage on each hit of the boss King's shot on the tile (Reaper's High, Opportunist)
function BossAbilityService.GetShotBonus(boss, column, row)
    if not boss then return 0 end

    local class = Classes[boss.ClassName]
    return boss.ShotBonus + (class.GetHitBonus and class.GetHitBonus(boss, column, row) or 0)
end

-- Reaper's High lasts until the King's next shot
function BossAbilityService.ConsumeShotBonus(boss)
    if boss then
        boss.ShotBonus = 0
    end
end

-- Chance an attack from the player's side lands on the tile (Bandit's smoke)
function BossAbilityService.GetHitChance(boss, column, row)
    if not boss then return 1 end

    local class = Classes[boss.ClassName]
    return class.GetHitChance and class.GetHitChance(boss, column, row) or 1
end

function BossAbilityService.OnPieceKilled(boss, piece)
    if not boss then return end

    local class = Classes[boss.ClassName]

    if class.OnPieceKilled then
        class.OnPieceKilled(boss, piece)
    end
end

-- A unit ended up on a new tile (Hunter traps catch the player's)
function BossAbilityService.OnUnitMoved(boss, unit)
    if not IsAlive(boss) then return end

    local class = Classes[boss.ClassName]

    if class.OnUnitMoved then
        class.OnUnitMoved(boss, unit)
    end
end

-- Returns true when a commanded white piece was caught on the way
function BossAbilityService.InterceptPath(boss, piece, column, row)
    if not IsAlive(boss) or piece.Team ~= "White" then return false end

    local class = Classes[boss.ClassName]
    return class.InterceptPath ~= nil and class.InterceptPath(boss, piece, column, row)
end

-- End of the enemy turn: turn-long bonuses wear off
function BossAbilityService.EndTurn(boss)
    boss.DamageBonus = 0
end

return BossAbilityService
