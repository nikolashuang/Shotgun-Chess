local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

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
local BoardSkinController = require(script.Parent.BoardSkinController)
local ShotgunController = require(script.Parent.ShotgunController)
local SummonPanelController = require(script.Parent.SummonPanelController)
local CombatHudController = require(script.Parent.CombatHudController)
local SpeedController = require(script.Parent.SpeedController)

local BoardRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BoardRemote")

local ActionCost = CombatConfig.ActionCost
local FanConfig = ClassConfig.Classes.Gunslinger.FanTheHammer
local HuntingStrikeConfig = ClassConfig.Classes.Hunter.HuntingStrike
local OutlawConfig = ClassConfig.Classes.Outlaw

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

-- Arrow tints: gold over allies being commanded, red over enemies being targeted
local ALLY_ARROW_COLOR = Color3.new(1, 1, 1)
local ENEMY_ARROW_COLOR = Color3.fromRGB(245, 80, 100)

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
-- Piece id -> damage about to be dealt, from the shotgun's aim and from the commanded piece
local shotDamage = {}
local commandDamage = {}
local previewedDamage = {}

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

-- Text over the top of the board: boss Kings calling out abilities, and red warnings for the player
local BOSS_CALL_TIME = 1.6
local BOSS_CALL_FONT = Font.new("rbxasset://fonts/families/Fondamento.json")
local CALL_COLOR = Color3.fromHex("F1D4AC")
local WARNING_COLOR = Color3.fromRGB(220, 60, 60)

local warningLabel = nil

local function ShowBoardCall(text, color)
    local label = Instance.new("TextLabel")
    label.Name = "BossCall"
    label.AnchorPoint = Vector2.new(0.5, 0.5)
    label.Position = UDim2.fromScale(0.5, 0.12)
    label.Size = UDim2.fromScale(0.8, 0.09)
    label.BackgroundTransparency = 1
    label.FontFace = BOSS_CALL_FONT
    label.TextScaled = true
    label.TextColor3 = color or CALL_COLOR
    label.Text = text
    label.ZIndex = 50

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromHex("1E1820")
    stroke.Thickness = 3
    stroke.Parent = label
    label.Parent = board

    local fade = TweenInfo.new(0.4)
    task.delay(BOSS_CALL_TIME, function()
        TweenService:Create(label, fade, {TextTransparency = 1}):Play()
        TweenService:Create(stroke, fade, {Transparency = 1}):Play()
        task.wait(0.4)
        label:Destroy()
    end)

    return label
end

-- Repeated clicks replace the warning instead of stacking copies
local function ShowWarning(text)
    if warningLabel then
        warningLabel:Destroy()
    end

    warningLabel = ShowBoardCall(text, WARNING_COLOR)
end

-- CanAct for an actual attempt: tells the player when energy is what's stopping them
local function TryAct(cost, action)
    if CanAct(cost, action) then return true end

    if IsMyTurn() and not turnState.UsedActions[action] then
        ShowWarning("Not Enough Energy")
    end

    return false
end

-- Assimilate's bonus move is still open after the king's own move
local function IsAssimilating()
    return turnState.Ability ~= nil and turnState.Ability.Assimilate ~= nil
end

-- The King's step costs energy like any action; Assimilate's bonus moves are free
local function CanMove()
    if not IsMyTurn() then return false end
    if IsAssimilating() then return true end

    return not turnState.HasMoved and turnState.Energy >= ActionCost.Move
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

-- Longer commands cost more, so tiles the player can't pay for are left out
local function FilterAffordable(piece, tiles)
    local energy = turnState and turnState.Energy or 0
    local affordable = {}

    for _, tile in pairs(tiles) do
        if BoardRules.GetCommandCost(piece.Rig.Column, piece.Rig.Row, tile.Column, tile.Row) <= energy then
            table.insert(affordable, tile)
        end
    end

    return affordable
end

local function GetCommandMoves(piece)
    return FilterAffordable(piece, PieceRules.GetMoves(piece.Type, piece.Team, piece.Rig.Column, piece.Rig.Row, IsOccupied))
end

local function GetCommandAttacks(piece)
    return FilterAffordable(piece, PieceRules.GetAttacks(piece.Type, piece.Team, piece.Rig.Column, piece.Rig.Row, IsOccupied, IsEnemyTile))
end

-- 2v2: ids of the teammate's summons, which only the teammate can command while they're still in
local teammatePieces = {}

-- The campaign's Fallen Knight fights on his own, so only summoned pieces take commands
local function IsCommandable(piece)
    if piece.Team ~= "White" then return false end
    if piece.Type == "FallenKnight" or piece.Type == "King" then return false end

    return not teammatePieces[piece.Id]
end

-- Moves and attacks share the Command action; attacks target enemy tiles
local function GetCommandTargets(piece)
    local targets = GetCommandMoves(piece)

    for _, attack in pairs(GetCommandAttacks(piece)) do
        table.insert(targets, attack)
    end

    return targets
end

-- Marks every previewed hit on its target's health bar
local function ApplyDamagePreview()
    local damageById = table.clone(shotDamage)

    for id, damage in pairs(commandDamage) do
        damageById[id] = (damageById[id] or 0) + damage
    end

    for id in pairs(previewedDamage) do
        local piece = PieceController.Get(id)

        if piece and not damageById[id] then
            piece.Rig:SetDamagePreview(0)
        end
    end

    for id, damage in pairs(damageById) do
        local piece = PieceController.Get(id)

        if piece then
            -- A Morale shield soaks up the first hits before health, like on the server
            piece.Rig:SetDamagePreview(math.max(damage - piece.Rig.Shield, 0))
        end
    end

    previewedDamage = damageById
end

-- Opportunist (Outlaw): enemies with no ally next to them take extra damage
local function IsIsolated(piece)
    for _, other in pairs(PieceController.GetTeamPieces(piece.Team)) do
        if other ~= piece and BoardRules.GetDistance(piece.Rig.Column, piece.Rig.Row, other.Rig.Column, other.Rig.Row) <= 1 then
            return false
        end
    end

    return true
end

-- Mirrors MatchClass:Fire's damage; smoke's hit roll isn't shown
local function GetShotDamage(piece, weapon, shotType)
    local column, row = piece.Rig.Column, piece.Rig.Row
    local damage = ShotgunRules.GetHitDamage(weapon, shotType, BoardRules.GetDistance(kingColumn, kingRow, column, row))

    damage += turnState.NextShotBonus or 0
    damage += (turnState.DamageBonus or 0) * (shotType == "Knife" and 1 or weapon.Blasts)

    if turnState.Class == "Outlaw" and IsIsolated(piece) then
        damage += OutlawConfig.Opportunist.Damage
    end

    if weapon.Pierces and shotType ~= "Knife" then
        local originX, originY = ShotgunRules.GetKingOrigin(kingColumn, kingRow)
        damage -= ShotgunRules.CountBlockers(originX, originY, column, row, IsEnemyTile) * weapon.PierceDamageLoss
    end

    return math.max(damage, 0)
end

local function OnShotPreviewChanged(hitTiles, shotType)
    shotDamage = {}

    if hitTiles and turnState and kingColumn then
        local weapon = ShotgunController.GetWeapon()

        for _, tile in pairs(hitTiles) do
            local piece = IsEnemyTile(tile.Column, tile.Row) and PieceController.GetAt(tile.Column, tile.Row)

            if piece then
                shotDamage[piece.Id] = GetShotDamage(piece, weapon, shotType)
            end
        end
    end

    ApplyDamagePreview()
end

-- The commanded piece's attack on the enemy under the cursor
local function UpdateCommandDamage()
    commandDamage = {}

    local selectedPiece = commandPieceId and PieceController.Get(commandPieceId)
    local column = hoveredTile and hoveredTile:GetAttribute("Column")
    local row = hoveredTile and hoveredTile:GetAttribute("Row")

    if selectedPiece and column and actionPanel.SelectedAction == "Command" and CanAct(ActionCost.Command, "Command") then
        local target = IsEnemyTile(column, row) and PieceController.GetAt(column, row)

        if target then
            for _, attack in pairs(GetCommandAttacks(selectedPiece)) do
                if attack.Column == column and attack.Row == row then
                    -- Unyielding (Monarch) adds to every allied attack this turn
                    local bonus = turnState.Ability and turnState.Ability.AllyDamageBonus or 0
                    commandDamage[target.Id] = (PieceConfig.Damage[selectedPiece.Type] or 0) + bonus
                end
            end
        end
    end

    ApplyDamagePreview()
end

-- Whites out the energy the hovered or selected action is about to spend
local function UpdateEnergyPreview()
    local action = actionPanel.HoveredAction or actionPanel.SelectedAction
    local cost = 0

    if action == "Summon" then
        local pieceType = SummonPanelController.SelectedPiece
        cost = pieceType and SummonPanelController.GetCost(pieceType) or 0
    elseif action == "Command" then
        cost = ActionCost.Command

        -- Once a piece is picked, the tile under the cursor sets the real cost
        local selectedPiece = commandPieceId and PieceController.Get(commandPieceId)
        local column = hoveredTile and hoveredTile:GetAttribute("Column")
        local row = hoveredTile and hoveredTile:GetAttribute("Row")

        if action == actionPanel.SelectedAction and selectedPiece and column then
            for _, target in pairs(GetCommandTargets(selectedPiece)) do
                if target.Column == column and target.Row == row then
                    cost = BoardRules.GetCommandCost(selectedPiece.Rig.Column, selectedPiece.Rig.Row, column, row)
                end
            end
        end
    elseif action == "Reload" then
        cost = turnState and turnState.Ammo < turnState.MaxAmmo and ActionCost.Reload or 0
    elseif action then
        cost = ActionCost[action] or 0
    end

    if action and not CanAct(cost, action) then
        cost = 0
    end

    CombatHudController.SetEnergyPreview(cost)
end

-- Arrows point at the commanded piece, the ally or enemy under the cursor, and enemies already picked
local function UpdateArrows()
    local arrows = {}
    local selectedAction = actionPanel.SelectedAction

    if commandPieceId then
        arrows[commandPieceId] = ALLY_ARROW_COLOR
    end

    for _, id in pairs(AbilityController.GetPickedEnemies(selectedAction)) do
        arrows[id] = ENEMY_ARROW_COLOR
    end

    local hoveredPiece = hoveredTile and PieceController.GetAt(hoveredTile:GetAttribute("Column"), hoveredTile:GetAttribute("Row"))

    if hoveredPiece then
        if IsCommandable(hoveredPiece) and selectedAction == "Command" and CanAct(ActionCost.Command, "Command") then
            arrows[hoveredPiece.Id] = ALLY_ARROW_COLOR
        elseif hoveredPiece.Team == "Black" and AbilityController.TargetsEnemies(selectedAction) then
            arrows[hoveredPiece.Id] = ENEMY_ARROW_COLOR
        end
    end

    PieceController.SetArrows(arrows)
    UpdateCommandDamage()
    UpdateEnergyPreview()
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

    UpdateArrows()

    local isFanning = selectedAction == "Special" and turnState ~= nil and turnState.Class == "Gunslinger" and CanAct(ActionCost.Special, "Special")
    local isThrowing = AbilityController.IsThrowingBolas()

    ShotgunController.SetLineAim(isFanning and FanConfig.Range or nil)
    ShotgunController.SetRevolverAimed(isFanning)
    ShotgunController.SetAimWeapon(isThrowing and HuntingStrikeConfig.Weapon or nil)
    ShotgunController.SetActive(isFanning or isThrowing or (selectedAction == "Fire" and CanAct(ActionCost.Fire, "Fire")))

    if not kingColumn then return end

    -- Picking Move does the same as having nothing picked: the King's steps show and a click moves him
    if selectedAction == nil or selectedAction == "Move" then
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
        if not CanAct(SummonPanelController.GetCost(SummonPanelController.SelectedPiece), "Summon") then return end
        if SummonPanelController.IsMaxed(SummonPanelController.SelectedPiece) then return end

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
                if IsCommandable(piece) then
                    HighlightTile(piece.Rig.Column, piece.Rig.Row, SELECT_COLOR, 0.65, true)
                end
            end
            return
        end

        HighlightTile(selectedPiece.Rig.Column, selectedPiece.Rig.Row, SELECT_COLOR, 0.35, true)

        for _, move in pairs(GetCommandMoves(selectedPiece)) do
            HighlightTile(move.Column, move.Row, COMMAND_MOVE_COLOR, 0.35, true, COMMAND_OUTLINE_COLOR)
        end

        for _, attack in pairs(GetCommandAttacks(selectedPiece)) do
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
        if not TryAct(ActionCost.Fire, "Fire") then return end

        local weapon = ShotgunController.GetWeapon()
        local mode = ShotgunController.GetMode()
        local targetX, targetY = ShotgunController.GetMouseBoardPosition()

        if turnState.Ammo < ShotgunRules.GetAmmoCost(weapon, mode) then
            ShowWarning("No Ammo")
            return
        end

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
        if not TryAct(ActionCost.Special, "Special") then return end

        local targetX, targetY = ShotgunController.GetMouseBoardPosition()
        if not ShotgunRules.GetPreciseShot(kingColumn, kingRow, targetX, targetY, FanConfig.Range) then return end

        BoardRemote:FireServer("Special", {X = targetX, Y = targetY})
        actionPanel.ClearSelection()
    elseif selectedAction == "Special" or selectedAction == "Ultimate" then
        AbilityController.OnTileClicked(selectedAction, column, row)
    elseif selectedAction == "Summon" then
        local pieceType = SummonPanelController.SelectedPiece

        if not pieceType then return end
        if not TryAct(SummonPanelController.GetCost(pieceType), "Summon") then return end
        if SummonPanelController.IsMaxed(pieceType) then return end
        if not IsSummonTile(column, row) then return end

        BoardRemote:FireServer("Summon", pieceType, column, row)
        actionPanel.ClearSelection()
    elseif selectedAction == "Command" then
        if not TryAct(ActionCost.Command, "Command") then return end

        local clickedPiece = PieceController.GetAt(column, row)

        if clickedPiece and IsCommandable(clickedPiece) then
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
    elseif selectedAction == nil or selectedAction == "Move" then
        if IsOccupied(column, row) then return end

        local moveType = turnState.Ability and turnState.Ability.Assimilate

        if moveType then
            if not PieceRules.IsValidMove(moveType, "White", kingColumn, kingRow, column, row, IsOccupied) then return end
        elseif not BoardRules.IsValidKingMove(kingColumn, kingRow, column, row) then
            return
        elseif turnState.HasMoved or not TryAct(ActionCost.Move, "Move") then
            -- Only a click on a step the King could take warns about energy
            return
        end

        BoardRemote:FireServer("Move", column, row)

        if selectedAction == "Move" then
            actionPanel.ClearSelection()
        end
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
        UpdateArrows()

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
        UpdateArrows()
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
        kingRig = PieceRigClass.new(board, "King", "White", turnState and turnState.Class)
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
        task.delay(SpeedController.Scale((blast - 1) * BLAST_INTERVAL), function()
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
    ShotgunController.ShowRevolver(SpeedController.Scale(#shots * FAN_SHOT_INTERVAL + REVOLVER_HOLD_TIME))

    for index, shot in ipairs(shots) do
        task.delay(SpeedController.Scale((index - 1) * FAN_SHOT_INTERVAL), function()
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
    CombatHudController.SetKingHealth(health)
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

-- Reaper's High: the heal lands once the last soul reaches the King
local function OnKingHealed(health)
    task.delay(BoardEffectsController.GetAbsorbWait(), function()
        if not kingRig then return end

        kingRig:SetHealth(health)
        CombatHudController.SetKingHealth(health)
        kingRig:ShowHealth()
        kingRig:HideHealth()
        kingRig:PlayHeal()
    end)
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

local function OnBossAbility(_, abilityName)
    ShowBoardCall(abilityName .. "!")
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

-- Other Kings fight with a shotgun like the player's king, so they hold one
-- shotgunName is the real shotgun in duels (rivals and the 2v2 teammate); campaign Kings leave it out
local function OnPieceAdded(id, pieceType, team, column, row, _health, _maxHealth, shotgunName, isTeammates)
    if isTeammates then
        teammatePieces[id] = true
    end

    if pieceType ~= "King" then return end
    if team ~= "Black" and not shotgunName then return end

    ShotgunController.AttachEnemyGun(PieceController.Get(id).Rig.Rig, column, row, shotgunName)
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
    end, shooter.Rig.Column, shooter.Rig.Row, shooter.Rig.Rig)
end

local init = false
function BoardController.Init(actionPanelController)
    if init then return end
    init = true

    actionPanel = actionPanelController
    actionPanel.OnSelectionChanged = function()
        -- Reload happens on select instead of waiting for a tile click
        if actionPanel.SelectedAction == "Reload" then
            if turnState.Ammo < turnState.MaxAmmo and TryAct(ActionCost.Reload, "Reload") then
                BoardRemote:FireServer("Reload")
            end

            actionPanel.ClearSelection()
            return
        end

        if actionPanel.SelectedAction == "Ultimate" and not AbilityController.CanUseUltimate() then
            actionPanel.ClearSelection()
            return
        end

        -- Untargeted ultimates fire as soon as they're selected
        if AbilityController.OnSelected(actionPanel.SelectedAction) then return end

        BoardController.RefreshPreview()
    end

    actionPanel.OnHoverChanged = UpdateEnergyPreview

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
    ShotgunController.OnPreviewChanged = OnShotPreviewChanged
    BoardEffectsController.Init(board, GetKingTile)
    BoardSkinController.Init(board)

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
        TryAct = TryAct,
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
            teammatePieces = {}
            PieceController.Clear()
            BoardEffectsController.Clear()

            -- The king rig carries over between matches, so a stun from the last one comes off
            if kingRig then
                kingRig:SetStunned(false)
            end
        elseif action == "KingMoved" then
            PlaceKing(...)
        elseif action == "PieceAdded" then
            PieceController.Add(...)
            OnPieceAdded(...)
            BoardController.RefreshPreview()
        elseif action == "PieceMoved" then
            PieceController.Move(...)
            BoardController.RefreshPreview()
        elseif action == "PiecePromoted" then
            PieceController.Promote(...)
        elseif action == "ShotFired" then
            OnShotFired(...)
        elseif action == "FanFired" then
            OnFanFired(...)
        elseif action == "PieceStunned" then
            OnPieceStunned(...)
        elseif action == "PieceShielded" then
            PieceController.SetShield(...)
        elseif action == "BossAbility" then
            OnBossAbility(...)
        elseif action == "KingStunned" then
            -- Duels only: the player's own King is stunned (stars, or wrapped in bolas)
            if kingRig then
                kingRig:SetStunned(...)
            end
        elseif action == "TeammatePiecesFreed" then
            teammatePieces = {}
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
        elseif action == "PieceHealed" then
            -- A rival or boss Reaper healing, once his souls have reached him
            task.delay(BoardEffectsController.GetAbsorbWait(), PieceController.Heal, ...)
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
            -- Loyalty (Monarch) makes the first Queen cheaper until one is summoned
            local queenCost = turnState.Ability and turnState.Ability.QueenCost
            SummonPanelController.SetCostOverrides(queenCost and {Queen = queenCost} or {})

            if kingRig then
                kingRig:SetHealth(turnState.KingHealth, turnState.KingMaxHealth)
                -- The King wears the equipped class's outfit
                kingRig:SetOutfit(turnState.Class)
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

-- mode is "Campaign" (with the region and node ids); duels are started by the server
function BoardController.StartMatch(mode, regionId, nodeId)
    BoardRemote:FireServer("StartMatch", mode, regionId, nodeId)
end

return BoardController
