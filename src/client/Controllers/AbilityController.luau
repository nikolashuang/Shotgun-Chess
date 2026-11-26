local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)
local BoardRules = require(ReplicatedStorage.Shared.Board.BoardRules)
local ShotgunRules = require(ReplicatedStorage.Shared.Combat.ShotgunRules)
local ClassConfig = require(ReplicatedStorage.Shared.Combat.ClassConfig)
local CombatConfig = require(ReplicatedStorage.Shared.Combat.CombatConfig)
local PieceController = require(script.Parent.PieceController)
local BoardEffectsController = require(script.Parent.BoardEffectsController)

local BoardRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BoardRemote")

local ActionCost = CombatConfig.ActionCost
local Classes = ClassConfig.Classes

local CHOICE_COLOR = Color3.fromHex("F1D4AC")
local PICKED_COLOR = Color3.fromHex("E6C47C")
local AREA_COLOR = Color3.fromHex("E9E3D6")
local ENEMY_COLOR = Color3.fromHex("C8644F")
local OUTLINE_COLOR = Color3.fromHex("332A35")

local board = nil

-- Tiles or piece ids picked so far for multi-pick abilities (traps, bounty marks)
local picks = {}

-- Targeting, previews and requests for each class's Special and Ultimate
-- The server checks everything again; this only decides what the player can click
local AbilityController = {}

local function TileKey(column, row)
    return column * 100 + row
end

local function GetEnemies()
    return PieceController.GetTeamPieces("Black")
end

local function CanSpecial()
    return board.CanAct(ActionCost.Special, "Special")
end

local function CanUltimate()
    local state = board.GetTurnState()
    if not board.CanAct(ActionCost.Ultimate, "Ultimate") then return false end

    return state.UltimateCharge >= state.MaxUltimateCharge
end

local function Send(action, payload)
    picks = {}
    BoardRemote:FireServer(action, payload)
    board.ClearSelection()
end

--TARGET RULES--

local function IsTrapTile(column, row)
    local kingColumn, kingRow = board.GetKingTile()
    if not BoardRules.IsOnBoard(column, row) then return false end
    if BoardRules.GetDistance(kingColumn, kingRow, column, row) > Classes.Hunter.Traps.Range then return false end
    if board.IsOccupied(column, row) then return false end

    return BoardEffectsController.GetTrapAt(column, row) == nil
end

local function IsSmokeTile(column, row)
    local kingColumn, kingRow = board.GetKingTile()

    return BoardRules.IsOnBoard(column, row) and BoardRules.GetDistance(kingColumn, kingRow, column, row) <= Classes.Outlaw.Conceal.Range
end

local function IsAmbushTile(column, row)
    if not BoardRules.IsOnBoard(column, row) then return false end
    if board.IsOccupied(column, row) then return false end

    for _, enemy in pairs(GetEnemies()) do
        if BoardRules.GetDistance(column, row, enemy.Rig.Column, enemy.Rig.Row) <= Classes.Outlaw.Ambush.MaxEnemyDistance then return true end
    end

    return false
end

local function ForEachTile(callback)
    for column = 1, BoardConfig.SIZE do
        for row = 1, BoardConfig.SIZE do
            callback(column, row)
        end
    end
end

-- How many picks finish a multi-pick ability: the full count, or fewer when there aren't enough choices
local function GetPickGoal(full, choices)
    return math.min(full, choices)
end

--PREVIEWS--

local function DrawSpecial(className)
    if className == "Hunter" then
        ForEachTile(function(column, row)
            if picks[TileKey(column, row)] then
                board.HighlightTile(column, row, PICKED_COLOR, 0.2, true, OUTLINE_COLOR)
            elseif IsTrapTile(column, row) then
                board.HighlightTile(column, row, CHOICE_COLOR, 0.55, true, OUTLINE_COLOR)
            end
        end)
    elseif className == "Outlaw" then
        local hovered = board.GetHoveredTile()
        local radius = Classes.Outlaw.Conceal.Radius

        ForEachTile(function(column, row)
            if hovered and IsSmokeTile(hovered.Column, hovered.Row) and BoardRules.GetDistance(hovered.Column, hovered.Row, column, row) <= radius then
                board.HighlightTile(column, row, AREA_COLOR, 0.35, true, OUTLINE_COLOR)
            elseif IsSmokeTile(column, row) then
                board.HighlightTile(column, row, CHOICE_COLOR, 0.7, true, OUTLINE_COLOR)
            end
        end)
    elseif className == "Reaper" then
        for _, soul in pairs(BoardEffectsController.GetSouls()) do
            if not soul.IsRival then
                board.HighlightTile(soul.Column, soul.Row, CHOICE_COLOR, 0.45, true)
            end
        end
    end
end

local function DrawUltimate(className)
    if className == "Gunslinger" then
        for _, enemy in pairs(GetEnemies()) do
            local isPicked = picks[enemy.Id]
            board.HighlightTile(enemy.Rig.Column, enemy.Rig.Row, isPicked and PICKED_COLOR or ENEMY_COLOR, isPicked and 0.2 or 0.45, true)
        end
    elseif className == "Outlaw" then
        ForEachTile(function(column, row)
            if IsAmbushTile(column, row) then
                board.HighlightTile(column, row, CHOICE_COLOR, 0.55, true, OUTLINE_COLOR)
            end
        end)
    end
end

-- Picking the Ultimate before it can be used would leave it selected, and the next press would toggle it off
function AbilityController.CanUseUltimate()
    return board ~= nil and board.GetTurnState() ~= nil and CanUltimate()
end

-- Draws the clickable choices for the selected Special or Ultimate
function AbilityController.DrawPreview(action)
    local state = board.GetTurnState()
    if not state or not state.Class then return end

    if action == "Special" then
        if not CanSpecial() then return end

        DrawSpecial(state.Class)
    elseif action == "Ultimate" then
        if not CanUltimate() then return end

        DrawUltimate(state.Class)
    end
end

-- Hunting Strike aims like a shotgun, so the board shows the Double Barrel cone instead of tile choices
function AbilityController.IsThrowingBolas()
    if not board then return false end

    local state = board.GetTurnState()
    if not state or state.Class ~= "Hunter" then return false end

    return board.IsSelected("Ultimate") and CanUltimate()
end

-- Abilities that are aimed by clicking enemies directly (High Noon's Bounty)
function AbilityController.TargetsEnemies(action)
    if not board then return false end

    local state = board.GetTurnState()
    if not state or state.Class ~= "Gunslinger" then return false end

    return action == "Ultimate" and CanUltimate()
end

-- Ids of the enemies picked so far by an enemy-targeting ability
function AbilityController.GetPickedEnemies(action)
    local ids = {}
    if not AbilityController.TargetsEnemies(action) then return ids end

    for id in pairs(picks) do
        table.insert(ids, id)
    end

    return ids
end

-- Area previews (smoke) follow the cursor
function AbilityController.WantsHoverRefresh(action)
    local state = board.GetTurnState()

    return action == "Special" and state ~= nil and state.Class == "Outlaw"
end

--CLICKS--

local function ClickSpecial(className, column, row)
    if className == "Hunter" then
        local key = TileKey(column, row)

        if picks[key] then
            picks[key] = nil
            board.RefreshPreview()
            return
        end

        if not IsTrapTile(column, row) then return end

        picks[key] = {Column = column, Row = row}

        -- Choices left plus picks made so far decide when the set is complete
        local tiles = {}
        local choices = 0

        for _, tile in pairs(picks) do
            table.insert(tiles, tile)
        end

        ForEachTile(function(choiceColumn, choiceRow)
            if IsTrapTile(choiceColumn, choiceRow) and not picks[TileKey(choiceColumn, choiceRow)] then
                choices += 1
            end
        end)

        if #tiles >= GetPickGoal(Classes.Hunter.Traps.Count, #tiles + choices) then
            Send("Special", {Tiles = tiles})
            return
        end

        board.RefreshPreview()
    elseif className == "Outlaw" then
        if not IsSmokeTile(column, row) then return end

        Send("Special", {Column = column, Row = row})
    elseif className == "Reaper" then
        local soul = BoardEffectsController.GetSoulAt(column, row)
        if not soul then return end

        Send("Special", {SoulId = soul.Id})
    end
end

-- Bolas only go out when the Hunting Strike spread would catch an enemy they can stun
-- (not campaign Kings; duels, which have a clock, let them stun the rival King)
local function ClickHuntingStrike()
    local canStunKing = board.GetTurnState().Clock ~= nil
    local kingColumn, kingRow = board.GetKingTile()
    local targetX, targetY = board.GetAimPosition()
    local weapon = ShotgunRules.GetWeapon(Classes.Hunter.HuntingStrike.Weapon)
    local _, hitTiles = ShotgunRules.GetFireResult(kingColumn, kingRow, targetX, targetY, weapon, "Normal", board.IsEnemyTile)

    for _, tile in pairs(hitTiles or {}) do
        local enemy = PieceController.GetAt(tile.Column, tile.Row)

        if enemy and enemy.Team == "Black" and (enemy.Type ~= "King" or canStunKing) then
            Send("Ultimate", {X = targetX, Y = targetY})
            return
        end
    end
end

local function ClickUltimate(className, column, row)
    if className == "Hunter" then
        ClickHuntingStrike()
    elseif className == "Gunslinger" then
        local enemy = PieceController.GetAt(column, row)
        if not enemy or enemy.Team ~= "Black" then return end

        picks[enemy.Id] = not picks[enemy.Id] or nil

        local targets = {}

        for id in pairs(picks) do
            table.insert(targets, id)
        end

        if #targets >= GetPickGoal(Classes.Gunslinger.Bounty.Marks, #GetEnemies()) then
            Send("Ultimate", {Targets = targets})
            return
        end

        board.RefreshPreview()
    elseif className == "Outlaw" then
        if not IsAmbushTile(column, row) then return end

        Send("Ultimate", {Column = column, Row = row})
    end
end

-- Returns true when the click was used by an ability
function AbilityController.OnTileClicked(action, column, row)
    local state = board.GetTurnState()
    if not state or not state.Class then return false end

    if action == "Special" then
        if not board.TryAct(ActionCost.Special, "Special") then return true end

        ClickSpecial(state.Class, column, row)
        return true
    elseif action == "Ultimate" then
        if not CanUltimate() then return true end

        ClickUltimate(state.Class, column, row)
        return true
    end

    return false
end

-- Abilities with no target fire as soon as they're selected, like Reload:
-- Reaper's High, and Monarch's Morale and Unyielding
function AbilityController.OnSelected(action)
    picks = {}

    local state = board.GetTurnState()
    if not state then return false end

    if action == "Special" then
        if state.Class ~= "Monarch" or not board.TryAct(ActionCost.Special, "Special") then return false end
        if #PieceController.GetTeamPieces("White") == 0 then return false end

        Send("Special", {})
        return true
    end

    if action ~= "Ultimate" or not CanUltimate() then return false end

    if state.Class == "Reaper" then
        Send("Ultimate", {})
        return true
    end

    if state.Class == "Monarch" and #PieceController.GetTeamPieces("White") > 0 then
        Send("Ultimate", {})
        return true
    end

    return false
end

local init = false
function AbilityController.Init(boardApi)
    if init then return end
    init = true

    board = boardApi
end

return AbilityController
