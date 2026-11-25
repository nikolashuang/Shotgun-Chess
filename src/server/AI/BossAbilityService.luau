local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClassConfig = require(ReplicatedStorage.Shared.Combat.ClassConfig)
local AIConfig = require(script.Parent.AIConfig)

local BossConfig = AIConfig.Boss

-- Campaign boss Kings using their class's special and ultimate on the enemy turn
-- Bosses have no energy or charge: the special comes back after a cooldown, the ultimate unlocks once at low health
-- Each class has a Decide (picks what to use from the turn's plans) and Use (applies it) pair in Classes
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

--MONARCH--

local MonarchConfig = ClassConfig.Classes.Monarch

Classes.Monarch = {}

-- Special: shield allies that end the turn near the player and can't get away
-- Ultimate: once unlocked, spend it on a turn where allies are attacking so the extra damage lands
function Classes.Monarch.Decide(boss, info)
    return {
        Special = info.TrappedAllies >= BossConfig.MONARCH_SHIELD_MIN,
        Ultimate = info.AllyAttacks > 0,
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
                DamageBonus = 0,
                Shielded = {},
            }
        end
    end

    return nil
end

-- Start of the enemy turn: the last Morale shield runs out
function BossAbilityService.StartTurn(boss)
    for id in pairs(boss.Shielded) do
        local piece = boss.Match.Pieces[id]

        if piece then
            piece.Shield = 0
            boss.Match:SendAll("PieceShielded", id, 0)
        end
    end

    boss.Shielded = {}
end

-- info holds what the turn's plans add up to (see EnemyAIService); returns {Special, Ultimate} to use this turn
function BossAbilityService.Decide(boss, info)
    local king = boss.King
    if not boss.Match.Pieces[king.Id] then return nil end

    local wants = Classes[boss.ClassName].Decide(boss, info)
    local isSpecialReady = boss.Match.Turn >= boss.SpecialReadyTurn
    local isUltimateReady = not boss.hasUsedUltimate and king.Health <= king.MaxHealth * BossConfig.ULTIMATE_HEALTH

    return {
        Special = wants.Special and isSpecialReady,
        Ultimate = wants.Ultimate and isUltimateReady,
    }
end

-- Runs before the enemy plans so shields and damage bonuses are in place for the attacks
function BossAbilityService.Use(boss, decision)
    if not decision then return end

    local match = boss.Match
    local abilities = ClassConfig.Classes[boss.ClassName]

    for _, kind in ipairs({"Special", "Ultimate"}) do
        if decision[kind] and Classes[boss.ClassName].Use(boss, kind) then
            if kind == "Special" then
                boss.SpecialReadyTurn = match.Turn + BossConfig.SPECIAL_COOLDOWN
            else
                boss.hasUsedUltimate = true
            end

            -- The ability's name is the text before the colon in ClassConfig
            local name = string.match(abilities[kind], "^(.-):") or kind
            match:SendAll("BossAbility", boss.King.Id, name)
        end
    end
end

-- Extra damage every Black piece's attack deals this turn
function BossAbilityService.GetDamageBonus(boss)
    return boss and boss.DamageBonus or 0
end

-- End of the enemy turn: turn-long bonuses wear off
function BossAbilityService.EndTurn(boss)
    boss.DamageBonus = 0
end

return BossAbilityService
