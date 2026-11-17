local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)
local BoardRules = require(ReplicatedStorage.Shared.Board.BoardRules)
local PieceRules = require(ReplicatedStorage.Shared.Board.PieceRules)
local ShotgunRules = require(ReplicatedStorage.Shared.Combat.ShotgunRules)
local PieceConfig = require(ReplicatedStorage.Shared.Board.PieceConfig)
local PieceRigClass = require(script.Parent.Parent.UI.PieceRigClass)
local PieceController = require(script.Parent.PieceController)
local ShotgunController = require(script.Parent.ShotgunController)
local SummonPanelController = require(script.Parent.SummonPanelController)

local BoardRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BoardRemote")

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

local function CanAct()
    return IsMyTurn() and not turnState.HasActed
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

function BoardController.RefreshPreview()
    ClearPreview()

    local selectedAction = actionPanel.SelectedAction

    if selectedAction ~= "Summon" then
        SummonPanelController.ClearSelection()
    end

    SummonPanelController.SetOpen(selectedAction == "Summon")

    if selectedAction ~= "Command" then
        commandPieceId = nil
    end

    ShotgunController.SetActive(selectedAction == "Fire" and CanAct())

    if not kingColumn then return end

    if selectedAction == nil then
        if not CanMove() then return end

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
        if not CanAct() then return end
        if not SummonPanelController.SelectedPiece then return end
        if turnState.Energy < PieceConfig.Cost[SummonPanelController.SelectedPiece] then return end

        local range = BoardConfig.SUMMON_RANGE

        for columnOffset = -range, range do
            for rowOffset = -range, range do
                local column = kingColumn + columnOffset
                local row = kingRow + rowOffset

                if IsSummonTile(column, row) then
                    HighlightTile(column, row, SUMMON_COLOR, 0.5)
                end
            end
        end
    elseif selectedAction == "Command" then
        if not CanAct() then return end

        local selectedPiece = commandPieceId and PieceController.Get(commandPieceId)

        if not selectedPiece then
            for _, piece in pairs(PieceController.GetTeamPieces("White")) do
                HighlightTile(piece.Rig.Column, piece.Rig.Row, SELECT_COLOR, 0.65)
            end
            return
        end

        HighlightTile(selectedPiece.Rig.Column, selectedPiece.Rig.Row, SELECT_COLOR, 0.35)

        for _, move in pairs(GetCommandMoves(selectedPiece)) do
            HighlightTile(move.Column, move.Row, COMMAND_MOVE_COLOR, 0.35, true, COMMAND_OUTLINE_COLOR)
        end

        for _, attack in pairs(PieceRules.GetAttacks(selectedPiece.Type, selectedPiece.Team, selectedPiece.Rig.Column, selectedPiece.Rig.Row, IsOccupied, IsEnemyTile)) do
            HighlightTile(attack.Column, attack.Row, ATTACK_COLOR, 0.3, true)
        end
    end
end

local function OnTileClicked(column, row)
    if not kingColumn then return end
    if not IsMyTurn() then return end

    local selectedAction = actionPanel.SelectedAction

    if selectedAction == "Fire" then
        if not CanAct() then return end

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
    elseif selectedAction == "Summon" then
        local pieceType = SummonPanelController.SelectedPiece

        if not pieceType then return end
        if not CanAct() then return end
        if not IsSummonTile(column, row) then return end

        BoardRemote:FireServer("Summon", pieceType, column, row)
        actionPanel.ClearSelection()
    elseif selectedAction == "Command" then
        if not CanAct() then return end

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
        if not BoardRules.IsValidKingMove(kingColumn, kingRow, column, row) then return end
        if IsOccupied(column, row) then return end

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
    end)

    tile.MouseLeave:Connect(function()
        if hoveredTile ~= tile then return end

        hoveredTile = nil
        SetHoveredRig(nil)
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

local function OnShotFired(pellets, hitTiles, damaged)
    kingRig.Sprite:Play("Recoil")

    local damageByTile = {}

    for _, result in pairs(damaged) do
        local piece = PieceController.Get(result.Id)

        if piece then
            damageByTile[BoardRules.GetTileName(piece.Rig.Column, piece.Rig.Row)] = result
        end
    end

    ShotgunController.PlayShot(pellets, hitTiles, function(column, row)
        local result = damageByTile[BoardRules.GetTileName(column, row)]
        if not result then return end

        PieceController.ApplyDamage(result.Id, result.Health)
    end)
end

local init = false
function BoardController.Init(actionPanelController)
    if init then return end
    init = true

    actionPanel = actionPanelController
    actionPanel.OnSelectionChanged = function()
        -- Reload happens on select instead of waiting for a tile click
        if actionPanel.SelectedAction == "Reload" then
            if CanAct() and turnState.Ammo < turnState.MaxAmmo then
                BoardRemote:FireServer("Reload")
            end

            actionPanel.ClearSelection()
            return
        end

        BoardController.RefreshPreview()
    end

    SummonPanelController.OnCardSelected = function()
        actionPanel.SelectAction("Summon")
        BoardController.RefreshPreview()
    end

    local hud = Players.LocalPlayer.PlayerGui:WaitForChild("GameHUD")
    board = hud:WaitForChild("Root"):WaitForChild("BoardFrame"):WaitForChild("Board")

    PieceController.Init(board)
    ShotgunController.Init(board, function()
        return kingColumn, kingRow
    end, IsEnemyTile)

    for _, tile in pairs(board:GetChildren()) do
        BindTile(tile)
    end

    BoardRemote.OnClientEvent:Connect(function(action, ...)
        if action == "MatchStarted" then
            PieceController.Clear()
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
        elseif action == "PieceDamaged" then
            PieceController.ApplyDamage(...)
        elseif action == "PieceAttacked" then
            PieceController.Attack(...)
            BoardController.RefreshPreview()
        elseif action == "TurnState" then
            turnState = ...
            ShotgunController.SetWeapon(turnState.Shotgun)
            actionPanel.SetClassActionsVisible(turnState.Class ~= nil)

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
    BoardController.RefreshPreview()
end

-- mode is "Duel" or "Campaign" (with the region and node ids)
function BoardController.StartMatch(mode, regionId, nodeId)
    BoardRemote:FireServer("StartMatch", mode, regionId, nodeId)
end

return BoardController
