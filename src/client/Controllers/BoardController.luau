local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)
local BoardRules = require(ReplicatedStorage.Shared.Board.BoardRules)
local PieceRules = require(ReplicatedStorage.Shared.Board.PieceRules)
local ShotgunRules = require(ReplicatedStorage.Shared.Combat.ShotgunRules)
local PieceConfig = require(ReplicatedStorage.Shared.Board.PieceConfig)
local CombatConfig = require(ReplicatedStorage.Shared.Combat.CombatConfig)
local ClassConfig = require(ReplicatedStorage.Shared.Combat.ClassConfig)
local PieceRigClass = require(script.Parent.Parent.UI.PieceRigClass)
local PieceController = require(script.Parent.PieceController)
local AbilityController = require(script.Parent.AbilityController)
local BoardEffectsController = require(script.Parent.BoardEffectsController)
local ShotgunController = require(script.Parent.ShotgunController)
local SummonPanelController = require(script.Parent.SummonPanelController)

local BoardRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BoardRemote")

local ActionCost = CombatConfig.ActionCost
local FanConfig = ClassConfig.Classes.Gunslinger.FanTheHammer
local HuntingStrikeConfig = ClassConfig.Classes.Hunter.HuntingStrike

-- Seconds between Fan the Hammer shots, and how long the revolver stays out after the last
local FAN_SHOT_INTERVAL = 0.12
local REVOLVER_HOLD_TIME = 0.4
-- Seconds between the blasts of a multi-blast shotgun
local BLAST_INTERVAL = 0.18

local MOVE_COLOR = Color3.fromHex("9C574B")
local SUMMON_COLOR = Color3.fromHex("F1D4AC")
local SELECT_COLOR = Color3.fromHex("F1D4AC")
local ATTACK_COLOR = Color3.fromHex("C8644F")
-- Light fill so commanded moves stand out on both tile colors
local COMMAND_MOVE_COLOR = Color3.fromHex("E9E3D6")
local COMMAND_OUTLINE_COLOR = Color3.fromHex("332A35")
local MOVE_OUTLINE_COLOR = Color3.fromHex("F1D4AC")

-- In pixels
local MOVE_OUTLINE_THICKNESS = 2
local MOVE_OUTLINE_INSET = 3

-- Thicker border on the highlighted tile under the cursor, with a dark inner line so it shows on any fill
local HOVER_COLOR = Color3.fromHex("F1D4AC")
local HOVER_INNER_COLOR = Color3.fromHex("332A35")
local HOVER_THICKNESS = 3

local board = nil
local actionPanel = nil
local kingRig = nil
local kingColumn = nil
local kingRow = nil
local previewTiles = {}

local turnState = nil
local commandPieceId = nil
local hoveredRig = nil
local hoveredTile = nil
local hoverOutline = nil

local BoardController = {}

local function GetTile(column, row)
    return board:FindFirstChild(BoardRules.GetTileName(column, row))
end

local function IsOccupied(column, row)
    if column == kingColumn and row == kingRow then return true end

    return PieceController.GetAt(column, row) ~= nil
end

local function IsEnemyTile(column, row)
    local piece = PieceController.GetAt(column, row)
    return piece ~= nil and piece.Team ~= "White"
end

local function IsMyTurn()
    return turnState ~= nil and turnState.Phase == "PlayerTurn"
end

local function CanAct(cost, action)
    if not IsMyTurn() then return false end
    if turnState.UsedActions[action] then return false end

    return turnState.Energy >= cost
end

local function CanMove()
    return IsMyTurn() and not turnState.HasMoved
end

local function SetOverlay(tile, color, transparency)
    local overlay = tile and tile:FindFirstChild("Overlay")
    if not overlay then return end

    overlay.Visible = color ~= nil

    if color then
        overlay.BackgroundColor3 = color
        overlay.BackgroundTransparency = transparency
    end
end

local function GetMoveOutline(tile)
    local outline = tile:FindFirstChild("MoveOutline")

    if not outline then
        local inset = MOVE_OUTLINE_INSET

        outline = Instance.new("Frame")
        outline.Name = "MoveOutline"
        outline.BackgroundTransparency = 1
        outline.Position = UDim2.fromOffset(inset, inset)
        outline.Size = UDim2.new(1, -inset * 2, 1, -inset * 2)
        outline.ZIndex = 2
        outline.Interactable = false
        outline.Visible = false
        outline.Parent = tile

        local stroke = Instance.new("UIStroke")
        stroke.Color = MOVE_OUTLINE_COLOR
        stroke.Thickness = MOVE_OUTLINE_THICKNESS
        stroke.LineJoinMode = Enum.LineJoinMode.Miter
        stroke.Parent = outline
    end

    return outline
end

local function HighlightTile(column, row, color, transparency, isOutlined, outlineColor)
    local tile = GetTile(column, row)
    if not tile then return end

    local outline = GetMoveOutline(tile)
    outline.Visible = isOutlined == true
    outline.UIStroke.Color = outlineColor or MOVE_OUTLINE_COLOR

    SetOverlay(tile, color, transparency)
    table.insert(previewTiles, tile)
end

local function GetHoverOutline()
    if hoverOutline then return hoverOutline end

    hoverOutline = Instance.new("Frame")
    hoverOutline.Name = "HoverOutline"
    hoverOutline.BackgroundTransparency = 1
    hoverOutline.Position = UDim2.fromOffset(HOVER_THICKNESS, HOVER_THICKNESS)
    hoverOutline.Size = UDim2.new(1, -HOVER_THICKNESS * 2, 1, -HOVER_THICKNESS * 2)
    hoverOutline.ZIndex = 3
    hoverOutline.Interactable = false
    hoverOutline.Visible = false

    local stroke = Instance.new("UIStroke")
    stroke.Color = HOVER_COLOR
    stroke.Thickness = HOVER_THICKNESS
    stroke.LineJoinMode = Enum.LineJoinMode.Miter
    stroke.Parent = hoverOutline

    local inner = Instance.new("Frame")
    inner.Name = "Inner"
    inner.BackgroundTransparency = 1
    inner.Position = UDim2.fromOffset(HOVER_THICKNESS, HOVER_THICKNESS)
    inner.Size = UDim2.new(1, -HOVER_THICKNESS * 2, 1, -HOVER_THICKNESS * 2)
    inner.Interactable = false
    inner.Parent = hoverOutline

    local innerStroke = Instance.new("UIStroke")
    innerStroke.Color = HOVER_INNER_COLOR
    innerStroke.Thickness = 1
    innerStroke.LineJoinMode = Enum.LineJoinMode.Miter
    innerStroke.Parent = inner

    return hoverOutline
end

-- Borders the tile under the cursor when it's one of the highlighted choices, so it's clear where a click lands
-- Aiming the shotgun has its own preview, so it's left out
local function UpdateHoverOutline()
    local outline = GetHoverOutline()
    local isChoice = hoveredTile ~= nil and table.find(previewTiles, hoveredTile) ~= nil

    local isAiming = actionPanel.SelectedAction == "Fire"
        or (actionPanel.SelectedAction == "Special" and turnState ~= nil and turnState.Class == "Gunslinger")
        or AbilityController.IsThrowingBolas()

    outline.Visible = isChoice and not isAiming

    if outline.Visible then
        outline.Parent = hoveredTile
    end
end

local function ClearPreview()
    for _, tile in pairs(previewTiles) do
        SetOverlay(tile, nil)
        GetMoveOutline(tile).Visible = false
    end

    previewTiles = {}
end

local function IsSummonTile(column, row)
    if not BoardRules.IsOnBoard(column, row) then return false end
    if BoardRules.GetDistance(kingColumn, kingRow, column, row) > BoardConfig.SUMMON_RANGE then return false end
    if IsOccupied(column, row) then return false end

    return true
end

local function GetCommandMoves(piece)
    return PieceRules.GetMoves(piece.Type, piece.Team, piece.Rig.Column, piece.Rig.Row, IsOccupied)
end

-- Moves and attacks share the Command action; attacks target enemy tiles
local function GetCommandTargets(piece)
    local targets = GetCommandMoves(piece)

    for _, attack in pairs(PieceRules.GetAttacks(piece.Type, piece.Team, piece.Rig.Column, piece.Rig.Row, IsOccupied, IsEnemyTile)) do
        table.insert(targets, attack)
    end

    return targets
end

local function DrawPreview()
    ClearPreview()

    local selectedAction = actionPanel.SelectedAction

    if selectedAction ~= "Summon" then
        SummonPanelController.ClearSelection()
    end

    SummonPanelController.SetOpen(selectedAction == "Summon")

    if selectedAction ~= "Command" then
        commandPieceId = nil
    end

    PieceController.SetArrow(commandPieceId)

    local isFanning = selectedAction == "Special" and turnState ~= nil and turnState.Class == "Gunslinger" and CanAct(ActionCost.Special, "Special")
    local isThrowing = AbilityController.IsThrowingBolas()

    ShotgunController.SetLineAim(isFanning and FanConfig.Range or nil)
    ShotgunController.SetRevolverAimed(isFanning)
    ShotgunController.SetAimWeapon(isThrowing and HuntingStrikeConfig.Weapon or nil)
    ShotgunController.SetActive(isFanning or isThrowing or (selectedAction == "Fire" and CanAct(ActionCost.Fire, "Fire")))

    if not kingColumn then return end

    if selectedAction == nil then
        if not CanMove() then return end

        -- Assimilate (Reaper) swaps the king's step for another piece's movement
        local moveType = turnState.Ability and turnState.Ability.Assimilate

        if moveType then
            for _, move in pairs(PieceRules.GetMoves(moveType, "White", kingColumn, kingRow, IsOccupied)) do
                HighlightTile(move.Column, move.Row, MOVE_COLOR, 0.45, true)
            end
            return
        end

        for columnOffset = -1, 1 do
            for rowOffset = -1, 1 do
                local column = kingColumn + columnOffset
                local row = kingRow + rowOffset

                if BoardRules.IsValidKingMove(kingColumn, kingRow, column, row) and not IsOccupied(column, row) then
                    HighlightTile(column, row, MOVE_COLOR, 0.45, true)
                end
            end
        end
    elseif selectedAction == "Summon" then
        if not SummonPanelController.SelectedPiece then return end
        if not CanAct(PieceConfig.Cost[SummonPanelController.SelectedPiece], "Summon") then return end

        local range = BoardConfig.SUMMON_RANGE

        for columnOffset = -range, range do
            for rowOffset = -range, range do
                local column = kingColumn + columnOffset
                local row = kingRow + rowOffset

                if IsSummonTile(column, row) then
                    HighlightTile(column, row, SUMMON_COLOR, 0.5, true, COMMAND_OUTLINE_COLOR)
                end
            end
        end
    elseif selectedAction == "Command" then
        if not CanAct(ActionCost.Command, "Command") then return end

        local selectedPiece = commandPieceId and PieceController.Get(commandPieceId)

        if not selectedPiece then
            for _, piece in pairs(PieceController.GetTeamPieces("White")) do
                HighlightTile(piece.Rig.Column, piece.Rig.Row, SELECT_COLOR, 0.65, true)
            end
            return
        end

        HighlightTile(selectedPiece.Rig.Column, selectedPiece.Rig.Row, SELECT_COLOR, 0.35, true)

        for _, move in pairs(GetCommandMoves(selectedPiece)) do
            HighlightTile(move.Column, move.Row, COMMAND_MOVE_COLOR, 0.35, true, COMMAND_OUTLINE_COLOR)
        end

        for _, attack in pairs(PieceRules.GetAttacks(selectedPiece.Type, selectedPiece.Team, selectedPiece.Rig.Column, selectedPiece.Rig.Row, IsOccupied, IsEnemyTile)) do
            HighlightTile(attack.Column, attack.Row, ATTACK_COLOR, 0.3, true)
        end
    elseif selectedAction == "Special" or selectedAction == "Ultimate" then
        AbilityController.DrawPreview(selectedAction)
    end
end

function BoardController.RefreshPreview()
    DrawPreview()
    UpdateHoverOutline()
end

local function OnTileClicked(column, row)
    if not kingColumn then return end
    if not IsMyTurn() then return end

    local selectedAction = actionPanel.SelectedAction

    if selectedAction == "Fire" then
        if not CanAct(ActionCost.Fire, "Fire") then return end

        local weapon = ShotgunController.GetWeapon()
        local mode = ShotgunController.GetMode()
        local targetX, targetY = ShotgunController.GetMouseBoardPosition()

        if turnState.Ammo < ShotgunRules.GetAmmoCost(weapon, mode) then return end

        local _, hitTiles, shotType = ShotgunRules.GetFireResult(kingColumn, kingRow, targetX, targetY, weapon, mode, IsEnemyTile)
        if not hitTiles then return end

        if shotType == "Knife" then
            local hasEnemy = false

            for _, tile in pairs(hitTiles) do
                if IsEnemyTile(tile.Column, tile.Row) then
                    hasEnemy = true
                end
            end

            if not hasEnemy then return end
        end

        BoardRemote:FireServer("Fire", targetX, targetY, mode)
        actionPanel.ClearSelection()
    elseif selectedAction == "Special" and turnState.Class == "Gunslinger" then
        if not CanAct(ActionCost.Special, "Special") then return end

        local targetX, targetY = ShotgunController.GetMouseBoardPosition()
        if not ShotgunRules.GetPreciseShot(kingColumn, kingRow, targetX, targetY, FanConfig.Range) then return end

        BoardRemote:FireServer("Special", {X = targetX, Y = targetY})
        actionPanel.ClearSelection()
    elseif selectedAction == "Special" or selectedAction == "Ultimate" then
        AbilityController.OnTileClicked(selectedAction, column, row)
    elseif selectedAction == "Summon" then
        local pieceType = SummonPanelController.SelectedPiece

        if not pieceType then return end
        if not CanAct(PieceConfig.Cost[pieceType], "Summon") then return end
        if not IsSummonTile(column, row) then return end

        BoardRemote:FireServer("Summon", pieceType, column, row)
        actionPanel.ClearSelection()
    elseif selectedAction == "Command" then
        if not CanAct(ActionCost.Command, "Command") then return end

        local clickedPiece = PieceController.GetAt(column, row)

        if clickedPiece and clickedPiece.Team == "White" then
            commandPieceId = clickedPiece.Id
            BoardController.RefreshPreview()
            return
        end

        local selectedPiece = commandPieceId and PieceController.Get(commandPieceId)
        if not selectedPiece then return end

        for _, target in pairs(GetCommandTargets(selectedPiece)) do
            if target.Column == column and target.Row == row then
                BoardRemote:FireServer("Command", selectedPiece.Id, column, row)
                actionPanel.ClearSelection()
                return
            end
        end
    elseif selectedAction == nil then
        if not CanMove() then return end
        if IsOccupied(column, row) then return end

        local moveType = turnState.Ability and turnState.Ability.Assimilate

        if moveType then
            if not PieceRules.IsValidMove(moveType, "White", kingColumn, kingRow, column, row, IsOccupied) then return end
        elseif not BoardRules.IsValidKingMove(kingColumn, kingRow, column, row) then
            return
        end

        BoardRemote:FireServer("Move", column, row)
    end
end

local function GetRigAt(column, row)
    if column == kingColumn and row == kingRow then return kingRig end

    local piece = PieceController.GetAt(column, row)
    return piece and piece.Rig
end

local function SetHoveredRig(rig)
    if hoveredRig == rig then return end

    if hoveredRig then
        hoveredRig:SetHovered(false)
    end

    hoveredRig = rig

    if rig then
        rig:SetHovered(true)
    end
end

local function BindTile(tile)
    local column = tile:GetAttribute("Column")
    local row = tile:GetAttribute("Row")
    if not column or not row then return end

    tile.MouseEnter:Connect(function()
        hoveredTile = tile
        SetHoveredRig(GetRigAt(column, row))

        if AbilityController.WantsHoverRefresh(actionPanel.SelectedAction) then
            BoardController.RefreshPreview()
        else
            UpdateHoverOutline()
        end
    end)

    tile.MouseLeave:Connect(function()
        if hoveredTile ~= tile then return end

        hoveredTile = nil
        SetHoveredRig(nil)
        UpdateHoverOutline()
    end)

    tile.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

        OnTileClicked(column, row)
    end)
end

local function PlaceKing(column, row)
    kingColumn = column
    kingRow = row

    if not kingRig then
        kingRig = PieceRigClass.new(board, "King", "White")
        kingRig:SetHealth(PieceConfig.Health.King, PieceConfig.Health.King)
        ShotgunController.AttachGun(kingRig.Rig)
    end

    kingRig:HopTo(column, row)
    BoardController.RefreshPreview()
end

-- Multi-blast shotguns replay the shot once per blast, each blast dealing an equal share of the damage
local function OnShotFired(pellets, hitTiles, damaged, shotType)
    local weapon = ShotgunController.GetWeapon()
    local blasts = 1

    if shotType == "Spread" or shotType == "PointBlank" then
        blasts = weapon.Blasts
    end

    local damageByTile = {}

    for _, result in pairs(damaged) do
        local piece = PieceController.Get(result.Id)

        if piece then
            damageByTile[BoardRules.GetTileName(piece.Rig.Column, piece.Rig.Row)] = {
                Id = result.Id,
                StartHealth = piece.Rig.Health,
                Health = result.Health,
                KnockColumn = result.KnockColumn,
                KnockRow = result.KnockRow,
            }
        end
    end

    for blast = 1, blasts do
        task.delay((blast - 1) * BLAST_INTERVAL, function()
            if not kingRig then return end

            kingRig.Sprite:Play("Recoil")

            ShotgunController.PlayShot(pellets, hitTiles, function(column, row)
                local result = damageByTile[BoardRules.GetTileName(column, row)]
                if not result then return end

                local health = result.StartHealth - (result.StartHealth - result.Health) * blast / blasts
                PieceController.ApplyDamage(result.Id, blast == blasts and result.Health or health)

                -- Knocked back pieces hop away once the last blast lands
                if blast == blasts and result.KnockColumn then
                    PieceController.Move(result.Id, result.KnockColumn, result.KnockRow)
                    BoardController.RefreshPreview()
                end
            end)
        end)
    end
end

-- The Gunslinger swaps to a revolver for Fan the Hammer, then back to the shotgun
local function OnFanFired(shots)
    ShotgunController.ShowRevolver(#shots * FAN_SHOT_INTERVAL + REVOLVER_HOLD_TIME)

    for index, shot in ipairs(shots) do
        task.delay((index - 1) * FAN_SHOT_INTERVAL, function()
            if not kingRig then return end

            kingRig.Sprite:Play("Recoil")

            local hitTiles = shot.Id and {{Column = shot.Column, Row = shot.Row}} or {}

            ShotgunController.PlayShot({{X = shot.Column - 0.5, Y = shot.Row - 0.5}}, hitTiles, function()
                PieceController.ApplyDamage(shot.Id, shot.Health)
            end)
        end)
    end
end

local function DamageKing(health)
    if not kingRig then return end

    kingRig:SetHealth(health)
    kingRig.Sprite:Play("Hit")
    kingRig:ShowHealth()
    kingRig:HideHealth()
end

local function OnKingAttacked(attackerId, health)
    local attacker = PieceController.Get(attackerId)

    if not attacker then
        DamageKing(health)
        return
    end

    attacker.Rig:Lunge(kingColumn, kingRow, function()
        DamageKing(health)
    end)
end

local function OnKingHealed(health)
    if not kingRig then return end

    kingRig:SetHealth(health)
    kingRig:ShowHealth()
    kingRig:HideHealth()
end

-- Ambush: the king vanishes and reappears on its new tile without hopping
local function OnKingAmbushed(column, row)
    kingColumn = column
    kingRow = row

    if kingRig then
        kingRig:SetTile(column, row)
        kingRig.Sprite:Play("Hop")
    end

    BoardController.RefreshPreview()
end

local function OnPieceStunned(id, isStunned, kind)
    -- Bolas fly from the king first, then wrap the piece
    if isStunned and kind == "Bolas" then
        BoardEffectsController.ThrowBolas(id)
        return
    end

    PieceController.SetStunned(id, isStunned, kind)
end

local function GetHoveredTile()
    if not hoveredTile then return nil end

    return {Column = hoveredTile:GetAttribute("Column"), Row = hoveredTile:GetAttribute("Row")}
end

local function OnEnemyShotFired(shooterId, pellets, hitTiles, damaged)
    local shooter = PieceController.Get(shooterId)
    if not shooter then return end

    local damageByTile = {}

    for _, result in pairs(damaged) do
        damageByTile[BoardRules.GetTileName(result.Column, result.Row)] = result
    end

    ShotgunController.PlayShot(pellets, hitTiles, function(column, row)
        local result = damageByTile[BoardRules.GetTileName(column, row)]
        if not result then return end

        if result.Id then
            PieceController.ApplyDamage(result.Id, result.Health)
        else
            DamageKing(result.Health)
        end
    end, shooter.Rig.Column, shooter.Rig.Row)
end

local init = false
function BoardController.Init(actionPanelController)
    if init then return end
    init = true

    actionPanel = actionPanelController
    actionPanel.OnSelectionChanged = function()
        -- Reload happens on select instead of waiting for a tile click
        if actionPanel.SelectedAction == "Reload" then
            if CanAct(ActionCost.Reload, "Reload") and turnState.Ammo < turnState.MaxAmmo then
                BoardRemote:FireServer("Reload")
            end

            actionPanel.ClearSelection()
            return
        end

        -- Untargeted ultimates fire as soon as they're selected
        if AbilityController.OnSelected(actionPanel.SelectedAction) then return end

        BoardController.RefreshPreview()
    end

    SummonPanelController.OnCardSelected = function()
        actionPanel.SelectAction("Summon")
        BoardController.RefreshPreview()
    end

    local hud = Players.LocalPlayer.PlayerGui:WaitForChild("GameHUD")
    board = hud:WaitForChild("Root"):WaitForChild("BoardFrame"):WaitForChild("Board")

    local function GetKingTile()
        return kingColumn, kingRow
    end

    PieceController.Init(board)
    ShotgunController.Init(board, GetKingTile, IsEnemyTile)
    BoardEffectsController.Init(board, GetKingTile)

    AbilityController.Init({
        GetTurnState = function()
            return turnState
        end,
        GetKingTile = GetKingTile,
        GetHoveredTile = GetHoveredTile,
        IsSelected = function(action)
            return actionPanel.SelectedAction == action
        end,
        CanAct = CanAct,
        IsOccupied = IsOccupied,
        HighlightTile = HighlightTile,
        IsEnemyTile = IsEnemyTile,
        GetAimPosition = function()
            return ShotgunController.GetMouseBoardPosition()
        end,
        RefreshPreview = function()
            BoardController.RefreshPreview()
        end,
        ClearSelection = function()
            actionPanel.ClearSelection()
        end,
    })

    for _, tile in pairs(board:GetChildren()) do
        BindTile(tile)
    end

    BoardRemote.OnClientEvent:Connect(function(action, ...)
        if action == "MatchStarted" then
            PieceController.Clear()
            BoardEffectsController.Clear()
        elseif action == "KingMoved" then
            PlaceKing(...)
        elseif action == "PieceAdded" then
            PieceController.Add(...)
            BoardController.RefreshPreview()
        elseif action == "PieceMoved" then
            PieceController.Move(...)
            BoardController.RefreshPreview()
        elseif action == "ShotFired" then
            OnShotFired(...)
        elseif action == "FanFired" then
            OnFanFired(...)
        elseif action == "PieceStunned" then
            OnPieceStunned(...)
        elseif action == "PieceMarked" then
            PieceController.SetMarked(...)
        elseif action == "SoulAdded" then
            BoardEffectsController.AddSoul(...)
            BoardController.RefreshPreview()
        elseif action == "SoulsRemoved" then
            BoardEffectsController.RemoveSouls(...)
        elseif action == "TrapsPlaced" then
            BoardEffectsController.AddTraps(...)
        elseif action == "TrapSprung" then
            BoardEffectsController.SpringTrap(...)
        elseif action == "SmokeChanged" then
            BoardEffectsController.SetSmoke(...)
        elseif action == "EnergyDropped" then
            BoardEffectsController.ShowEnergy(...)
        elseif action == "KingHealed" then
            OnKingHealed(...)
        elseif action == "KingAmbushed" then
            OnKingAmbushed(...)
        elseif action == "PieceDamaged" then
            PieceController.ApplyDamage(...)
        elseif action == "PieceAttacked" then
            PieceController.Attack(...)
            BoardController.RefreshPreview()
        elseif action == "KingAttacked" then
            OnKingAttacked(...)
        elseif action == "EnemyShotFired" then
            OnEnemyShotFired(...)
        elseif action == "TurnState" then
            turnState = ...
            ShotgunController.SetWeapon(turnState.Shotgun, turnState.Class)

            if kingRig then
                kingRig:SetHealth(turnState.KingHealth, turnState.KingMaxHealth)
            end
            actionPanel.SetClassActionsVisible(turnState.Class ~= nil)
            actionPanel.SetUsedActions(turnState.UsedActions)

            if not IsMyTurn() then
                actionPanel.ClearSelection()
            end

            BoardController.RefreshPreview()
        end
    end)
end

-- Ends the match on the server and clears the board for the next one
function BoardController.LeaveMatch()
    BoardRemote:FireServer("LeaveMatch")

    turnState = nil
    commandPieceId = nil
    actionPanel.ClearSelection()
    PieceController.Clear()
    BoardEffectsController.Clear()
    BoardController.RefreshPreview()
end

-- mode is "Duel" or "Campaign" (with the region and node ids)
function BoardController.StartMatch(mode, regionId, nodeId)
    BoardRemote:FireServer("StartMatch", mode, regionId, nodeId)
end

return BoardController
