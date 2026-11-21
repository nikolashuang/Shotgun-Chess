local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local CampaignConfig = require(ReplicatedStorage.Shared.Campaign.CampaignConfig)
local CampaignRules = require(ReplicatedStorage.Shared.Campaign.CampaignRules)
local CampaignArt = require(ReplicatedStorage.Shared.Campaign.CampaignArt)
local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)
local ClassConfig = require(ReplicatedStorage.Shared.Combat.ClassConfig)
local ArmoryArt = require(ReplicatedStorage.Shared.UI.ArmoryArt)
local ProfileController = require(script.Parent.ProfileController)

local CampaignRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CampaignRemote")

local HIGHLIGHT_COLOR = Color3.fromHex("F1D4AC")
local MUTED_COLOR = Color3.fromHex("D49A77")
local ACCENT_COLOR = Color3.fromHex("9C574B")
local LOCKED_COLOR = Color3.fromHex("7A6E73")
local INK_COLOR = Color3.fromHex("332A35")
-- Routes not walked yet are drawn faint on the paper
local FAINT_INK_TRANSPARENCY = 0.6

-- Treasure Hunt board colors per region: light tiles, dark tiles
local TREASURE_COLORS = {
    Training = {Color3.fromHex("D9C9A3"), Color3.fromHex("B8A47E")},
    Forest = {Color3.fromHex("7E9A5C"), Color3.fromHex("5E7A44")},
    Cliffside = {Color3.fromHex("C99A6B"), Color3.fromHex("A67A50")},
    Outskirts = {Color3.fromHex("C2A878"), Color3.fromHex("9E8558")},
    Gravehollow = {Color3.fromHex("6E6378"), Color3.fromHex("534A5E")},
}
local DUG_COLOR = Color3.fromHex("4A3B33")
local TREASURE_COLOR = Color3.fromHex("F1D4AC")

local REST_RESULTS = {
    Rest = "You rest by the fire. Health restored.",
    Train = "You train. +2 max health.",
    Maintenance = "You clean your shotgun. +1 damage.",
}

local LEGEND_ORDER = {"Combat", "Rest", "Treasure", "Queen", "King"}

-- Scale of the world canvas compared to the visible window, and how wide each island is
local WORLD_CANVAS_HEIGHT = 2.8
local ISLAND_WIDTH = 0.34
local ISLAND_COLUMNS = {0.32, 0.68}
-- Canvas heights of the top and bottom islands, leaving room for the art above and the names below
local ISLAND_TOP = 0.12
local ISLAND_BOTTOM = 0.86
-- Paths leave from the middle of the island art, which sits a little above the holder's center
local ISLAND_CENTER_Y = -0.02

-- In pixels
local PATH_DOT_SIZE = 6
local PATH_DOT_SPACING = 18

-- Islands drift up and down by this fraction of their height
local BOB_HEIGHT = 0.025
local BOB_TIME = 1.6

-- Node badge size as a fraction of the map height
local NODE_SIZE = 0.15
local BOSS_NODE_SIZE = 0.22
local SELECTED_SCALE = 1.15
local PULSE_SCALE = 1.08
local PULSE_TIME = 0.6

local menu = nil
local hud = nil
local screen = nil
local header = nil
local backButton = nil
local singleplayer = nil

local worldView = nil
local worldCanvas = nil
local areaView = nil
local scene = nil
local map = nil
local info = nil
local playButton = nil
local runInfo = nil
local pouch = nil

local restPanel = nil
local treasurePanel = nil
local treasureGrid = nil
local tileTemplate = nil
local treasureTiles = {}
-- Waiting on the server's answer to a dig
local isDigging = false

local islandTemplate = nil
local nodeTemplate = nil
local lineTemplate = nil

local resultOverlay = nil
local resultTitle = nil
local resultRewards = nil

local startMatch = nil
local leaveMatch = nil

local currentRegion = nil
local selectedNode = nil
local lastMatchRegion = nil
local nodeButtons = {}

-- Regions already shown as unlocked this session, so a newly opened one gets the unlock animation
local knownUnlocked = nil
local isAnimating = false
local pendingRedraw = false

local CampaignController = {}

local function GetCleared()
    return ProfileController.Data.Nodes
end

local function GetRun(regionId)
    local runs = ProfileController.Data.Runs

    return runs and runs[regionId]
end

local function ClearChildren(container)
    for _, child in pairs(container:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end
end

local function Tween(instance, time, goal, style, direction)
    local tween = TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
    tween:Play()

    return tween
end

-- A dotted pixel path, returns the dots so the unlock animation can light them up
local function DrawPath(container, from, to, color)
    local size = container.AbsoluteSize
    local dx = (to[1] - from[1]) * size.X
    local dy = (to[2] - from[2]) * size.Y
    local count = math.floor(math.sqrt(dx * dx + dy * dy) / PATH_DOT_SPACING)
    local dots = {}

    for i = 1, count - 1 do
        local t = i / count

        local dot = lineTemplate:Clone()
        dot.Position = UDim2.fromScale(from[1] + (to[1] - from[1]) * t, from[2] + (to[2] - from[2]) * t)
        dot.Size = UDim2.fromOffset(PATH_DOT_SIZE, PATH_DOT_SIZE)
        dot.Rotation = 0
        dot.BackgroundColor3 = color
        dot.Visible = true
        dot.Parent = container

        table.insert(dots, dot)
    end

    return dots
end

local function SetAtlasRect(image, column, row)
    local size = CampaignArt.ISLAND_SIZE

    image.Image = CampaignArt.ISLANDS
    image.ImageRectOffset = Vector2.new(column * size, row * size)
    image.ImageRectSize = Vector2.new(size, size)
end

local function FormatReward(regionId, nodeId)
    local node = CampaignConfig.Regions[regionId].Nodes[nodeId]
    if node.Type == "Treasure" then return "Up to " .. CampaignConfig.Treasure.Rewards[1] .. " Gold" end
    if node.Type == "Rest" then return "Checkpoint" end

    local gold, exp = CampaignRules.GetReward(regionId, nodeId)

    return string.format("%d Gold   %d XP to pouch", gold, exp)
end

-- Health, upgrades and pouch of the run in progress
local function UpdateRunInfo(regionId)
    local run = GetRun(regionId)
    local isReplay = CampaignRules.IsRegionComplete(GetCleared(), regionId)
    local replayText = isReplay and "   (Replay: pouch pays 20%)" or ""

    pouch.Gold.Text = string.format("%d Gold", run and run.Gold or 0)
    pouch.Exp.Text = string.format("%d XP", run and run.Exp or 0)

    if not run or #run.Path == 0 then
        runInfo.Text = "New run" .. replayText
        return
    end

    local parts = {string.format("Health %d/%d", run.Health, run.MaxHealth)}

    if run.DamageBonus > 0 then
        table.insert(parts, string.format("+%d Damage", run.DamageBonus))
    end

    if run.HasCheckpoint then
        table.insert(parts, "Checkpoint saved")
    end

    runInfo.Text = table.concat(parts, "     ") .. replayText
end

local function ShowView(isWorld)
    worldView.Visible = isWorld
    areaView.Visible = not isWorld
    backButton.Label.Text = isWorld and "Back" or "World Map"

    if isWorld then
        restPanel.Visible = false
        treasurePanel.Visible = false
    end
end

--WORLD MAP--

-- Islands climb from the bottom of the canvas, alternating sides
local function GetIslandPosition(index)
    local t = (index - 1) / (#CampaignConfig.ORDER - 1)

    return {ISLAND_COLUMNS[(index - 1) % 2 + 1], ISLAND_BOTTOM + (ISLAND_TOP - ISLAND_BOTTOM) * t}
end

local function GetPathPoint(index)
    local position = GetIslandPosition(index)

    return {position[1], position[2] + ISLAND_CENTER_Y}
end

local function ScrollTo(index, time)
    local canvasHeight = worldView.AbsoluteCanvasSize.Y
    local windowHeight = worldView.AbsoluteWindowSize.Y
    local target = GetIslandPosition(index)[2] * canvasHeight - windowHeight / 2
    local position = Vector2.new(0, math.clamp(target, 0, math.max(canvasHeight - windowHeight, 0)))

    if time then
        Tween(worldView, time, {CanvasPosition = position}, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
    else
        worldView.CanvasPosition = position
    end
end

local function StartBob(island)
    local art = island.Art
    local tweenInfo = TweenInfo.new(BOB_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

    -- Offset each island's phase so they don't bob in step
    task.delay(math.random() * BOB_TIME, function()
        if not art.Parent then return end

        TweenService:Create(art, tweenInfo, {Position = UDim2.fromScale(0.5, 0.5 - BOB_HEIGHT)}):Play()
    end)
end

local function SetIslandLocked(island, isLocked, requirement)
    local art = island.Art

    art.Gray.ImageTransparency = isLocked and 0 or 1
    art.ChainA.Visible = isLocked
    art.ChainB.Visible = isLocked
    art.Lock.Visible = isLocked
    island.Title.TextColor3 = isLocked and LOCKED_COLOR or HIGHLIGHT_COLOR
    island.Subtitle.Text = isLocked and ("Clear " .. requirement .. " first") or island:GetAttribute("Subtitle")
end

local function NewIsland(index, regionId, showLocked)
    local region = CampaignConfig.Regions[regionId]
    local position = GetIslandPosition(index)
    local column = CampaignArt.IslandColumn[regionId]

    local island = islandTemplate:Clone()
    island.Name = regionId
    island.Position = UDim2.fromScale(position[1], position[2])
    island.Size = UDim2.fromScale(ISLAND_WIDTH, 1)
    island.Title.Text = region.DisplayName
    island:SetAttribute("Subtitle", region.Subtitle)

    local art = island.Art
    SetAtlasRect(art.Color, column, 0)
    SetAtlasRect(art.Gray, column, 1)
    SetAtlasRect(art.ChainA, CampaignArt.LockColumn.ChainA, 2)
    SetAtlasRect(art.ChainB, CampaignArt.LockColumn.ChainB, 2)
    SetAtlasRect(art.Lock, CampaignArt.LockColumn.Lock, 2)

    local names = {}

    for _, required in ipairs(region.Requires) do
        table.insert(names, CampaignConfig.Regions[required].DisplayName)
    end

    SetIslandLocked(island, showLocked, table.concat(names, " and "))

    island.Visible = true
    island.Parent = worldCanvas

    island.Activated:Connect(function()
        if isAnimating then return end
        if not CampaignRules.IsRegionUnlocked(GetCleared(), regionId) then return end

        CampaignController.ShowRegion(regionId)
    end)

    if not showLocked then
        StartBob(island)
    end

    return island
end

-- Chains slide off, the padlock shakes and drops, and the island fades from gray into color
local function PlayUnlock(island, dots, index)
    isAnimating = true

    local art = island.Art
    local scale = art.UIScale

    ScrollTo(index, 0.7)
    task.wait(0.8)

    for _, angle in ipairs({-14, 14, -10, 10, -5, 0}) do
        Tween(art.Lock, 0.06, {Rotation = angle})
        task.wait(0.06)
    end

    task.wait(0.15)

    Tween(art.Lock, 0.5, {Position = UDim2.fromScale(0.5, 0.95), Rotation = 30, ImageTransparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    Tween(art.ChainA, 0.55, {Position = UDim2.fromScale(0.3, 0.75), ImageTransparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    Tween(art.ChainB, 0.55, {Position = UDim2.fromScale(0.7, 0.75), ImageTransparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    task.wait(0.35)

    Tween(art.Gray, 0.7, {ImageTransparency = 1})
    Tween(island.Title, 0.7, {TextColor3 = HIGHLIGHT_COLOR})
    Tween(scale, 0.25, {Scale = 1.12}, Enum.EasingStyle.Back)

    for i, dot in ipairs(dots) do
        task.delay(i * 0.03, function()
            Tween(dot, 0.2, {BackgroundColor3 = HIGHLIGHT_COLOR})
        end)
    end

    local banner = island.UnlockText
    banner.Visible = true
    banner.TextTransparency = 1
    banner.TextStrokeTransparency = 1
    Tween(banner, 0.3, {TextTransparency = 0, TextStrokeTransparency = 0})

    task.wait(0.3)
    Tween(scale, 0.35, {Scale = 1}, Enum.EasingStyle.Back)
    island.Subtitle.Text = island:GetAttribute("Subtitle")
    task.wait(1.2)

    Tween(banner, 0.6, {TextTransparency = 1, TextStrokeTransparency = 1, Position = banner.Position - UDim2.fromScale(0, 0.08)})
    art.ChainA.Visible = false
    art.ChainB.Visible = false
    art.Lock.Visible = false
    StartBob(island)

    task.wait(0.6)
    isAnimating = false

    if pendingRedraw then
        pendingRedraw = false
        CampaignController.ShowWorld(false)
    end
end

function CampaignController.ShowWorld(shouldScroll)
    currentRegion = nil
    selectedNode = nil

    header.Text = "Campaign"
    ShowView(true)
    ClearChildren(worldCanvas)

    local cleared = GetCleared()
    local isFirstDraw = knownUnlocked == nil
    local newlyUnlocked = nil
    knownUnlocked = knownUnlocked or {}

    -- The animation is for one region opening up; several at once (like a dev unlock) just appear unlocked
    local newCount = 0

    for _, regionId in ipairs(CampaignConfig.ORDER) do
        if CampaignRules.IsRegionUnlocked(cleared, regionId) and not knownUnlocked[regionId] then
            newCount += 1
        end
    end

    local canAnimate = not isFirstDraw and newCount == 1

    local dotsByIndex = {}

    for i = 2, #CampaignConfig.ORDER do
        local regionId = CampaignConfig.ORDER[i]
        local isOpen = CampaignRules.IsRegionUnlocked(cleared, regionId) and (not canAnimate or knownUnlocked[regionId])
        dotsByIndex[i] = DrawPath(worldCanvas, GetPathPoint(i - 1), GetPathPoint(i), isOpen and HIGHLIGHT_COLOR or ACCENT_COLOR)
    end

    local islands = {}

    for i, regionId in ipairs(CampaignConfig.ORDER) do
        local isUnlocked = CampaignRules.IsRegionUnlocked(cleared, regionId)
        local isNew = isUnlocked and canAnimate and not knownUnlocked[regionId]

        -- A newly unlocked region starts locked so the animation can open it
        islands[i] = NewIsland(i, regionId, not isUnlocked or isNew)

        if isNew and not newlyUnlocked then
            newlyUnlocked = i
        end

        knownUnlocked[regionId] = isUnlocked
    end

    if newlyUnlocked then
        -- Set now so a redraw before the animation starts can't skip it
        isAnimating = true
        task.defer(PlayUnlock, islands[newlyUnlocked], dotsByIndex[newlyUnlocked] or {}, newlyUnlocked)
    elseif shouldScroll then
        -- Always start at King's Training at the bottom so players see where the campaign begins
        task.defer(ScrollTo, 1)
    end
end

--AREA MAP--

local function SelectNode(nodeId)
    if selectedNode and nodeButtons[selectedNode] then
        nodeButtons[selectedNode].Icon.UIScale.Scale = 1
    end

    selectedNode = nodeId
    nodeButtons[nodeId].Icon.UIScale.Scale = SELECTED_SCALE

    local region = CampaignConfig.Regions[currentRegion]
    local node = region.Nodes[nodeId]
    local state = CampaignRules.GetNodeState(GetRun(currentRegion), currentRegion, nodeId)

    local text = CampaignConfig.TypeNames[node.Type] .. "\n" .. FormatReward(currentRegion, nodeId)

    if node.Type == "King" and region.Class then
        text ..= "\nUnlocks " .. ClassConfig.Classes[region.Class].DisplayName
    end

    if state == "Locked" then
        text ..= "\nLocked"
    elseif state == "Cleared" then
        text ..= "\nVisited"
    end

    info.Text = text
    playButton.Visible = state == "Available" and not restPanel.Visible and not treasurePanel.Visible

    if node.Type == "Rest" then
        playButton.Label.Text = "Rest"
    elseif node.Type == "Treasure" then
        playButton.Label.Text = "Dig"
    else
        playButton.Label.Text = "Fight"
    end
end

local function NewNodeButton(nodeId, node, state)
    local size = (node.Type == "Queen" or node.Type == "King") and BOSS_NODE_SIZE or NODE_SIZE
    local tile = CampaignArt.NODE_TILE

    local button = nodeTemplate:Clone()
    button.Name = nodeId
    button.Position = UDim2.fromScale(node.Position[1], node.Position[2])
    button.Size = UDim2.fromScale(size, size)

    local icon = button.Icon
    icon.Image = CampaignArt.NODE_ICONS
    icon.ImageRectOffset = Vector2.new(CampaignArt.NodeOrder[node.Type] * tile, 0)
    icon.ImageRectSize = Vector2.new(tile, tile)

    button.Check.Visible = state == "Cleared"

    if state == "Locked" then
        icon.ImageColor3 = LOCKED_COLOR
    elseif state == "Cleared" then
        icon.ImageColor3 = Color3.new(0.75, 0.75, 0.75)
    else
        local tweenInfo = TweenInfo.new(PULSE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
        TweenService:Create(button.PulseScale, tweenInfo, {Scale = PULSE_SCALE}):Play()
    end

    button.Visible = true
    button.Parent = map

    button.Activated:Connect(function()
        SelectNode(nodeId)
    end)

    nodeButtons[nodeId] = button
end

function CampaignController.ShowRegion(regionId)
    currentRegion = regionId

    local region = CampaignConfig.Regions[regionId]
    local run = GetRun(regionId)
    local path = run and run.Path or {}

    header.Text = region.DisplayName
    info.Text = region.Subtitle .. "\nSelect a node"
    playButton.Visible = false
    ShowView(false)
    UpdateRunInfo(regionId)

    ClearChildren(map)
    nodeButtons = {}

    for nodeId, node in pairs(region.Nodes) do
        for _, link in ipairs(node.Links) do
            -- Only the route this run walked is inked in
            local isOpen = table.find(path, nodeId) ~= nil and table.find(path, link) ~= nil

            for _, dot in ipairs(DrawPath(map, node.Position, region.Nodes[link].Position, isOpen and ACCENT_COLOR or INK_COLOR)) do
                dot.BackgroundTransparency = isOpen and 0 or FAINT_INK_TRANSPARENCY
            end
        end
    end

    for nodeId, node in pairs(region.Nodes) do
        NewNodeButton(nodeId, node, CampaignRules.GetNodeState(run, regionId, nodeId))
    end

    if selectedNode and region.Nodes[selectedNode] then
        SelectNode(selectedNode)
    else
        selectedNode = nil
    end
end

local function BuildLegend(legend, entryTemplate)
    local tile = CampaignArt.NODE_TILE

    for i, nodeType in ipairs(LEGEND_ORDER) do
        local entry = entryTemplate:Clone()
        entry.Name = nodeType
        entry.LayoutOrder = i
        entry.Icon.Image = CampaignArt.NODE_ICONS
        entry.Icon.ImageRectOffset = Vector2.new(CampaignArt.NodeOrder[nodeType] * tile, 0)
        entry.Icon.ImageRectSize = Vector2.new(tile, tile)
        entry.Label.Text = CampaignConfig.TypeNames[nodeType]
        entry.Visible = true
        entry.Parent = legend
    end
end

local function Redraw()
    if not screen.Enabled then return end

    if isAnimating then
        pendingRedraw = true
        return
    end

    if currentRegion then
        CampaignController.ShowRegion(currentRegion)
    else
        CampaignController.ShowWorld(false)
    end
end

--REST AND TREASURE--

local function ShowRestPanel()
    restPanel.Visible = true
    playButton.Visible = false
end

local function ChooseRest(choice)
    if not currentRegion or not selectedNode then return end

    restPanel.Visible = false
    CampaignRemote:FireServer("Rest", currentRegion, selectedNode, choice)
end

local function GetTileColor(column, row)
    local colors = TREASURE_COLORS[currentRegion] or TREASURE_COLORS.Training

    return colors[(column + row) % 2 + 1]
end

local function MarkDug(column, row)
    for _, tile in ipairs(CampaignRules.GetDigTiles(column, row)) do
        local button = treasureTiles[tile[1] .. "," .. tile[2]]
        button.BackgroundColor3 = DUG_COLOR
    end
end

local function SetDigsLeft(digsLeft)
    treasurePanel.Digs.Text = digsLeft == 1 and "1 dig left" or (digsLeft .. " digs left")
end

local function Dig(column, row)
    if isDigging or treasurePanel.CloseButton.Visible then return end

    isDigging = true
    CampaignRemote:FireServer("Dig", currentRegion, selectedNode, column, row)
end

-- Row 1 is drawn at the bottom, like the battle board
local function BuildTreasureBoard(digs)
    ClearChildren(treasureGrid)
    treasureTiles = {}

    local size = BoardConfig.SIZE

    for column = 1, size do
        for row = 1, size do
            local tile = tileTemplate:Clone()
            tile.Name = column .. "," .. row
            tile.Position = UDim2.fromScale((column - 1) / size, (size - row) / size)
            tile.Size = UDim2.fromScale(1 / size, 1 / size)
            tile.BackgroundColor3 = GetTileColor(column, row)
            tile.Visible = true
            tile.Parent = treasureGrid

            tile.Activated:Connect(function()
                Dig(column, row)
            end)

            treasureTiles[tile.Name] = tile
        end
    end

    for _, dug in ipairs(digs) do
        MarkDug(dug[1], dug[2])
    end

    SetDigsLeft(CampaignConfig.Treasure.DIGS - #digs)
    treasurePanel.Message.Text = "Pick a tile to dig. Each dig uncovers a 3x3 area."
    treasurePanel.CloseButton.Visible = false
    treasurePanel.Visible = true
    playButton.Visible = false
    isDigging = false
end

local function ShowDig(result)
    isDigging = false
    MarkDug(result.Column, result.Row)
    SetDigsLeft(result.DigsLeft)

    if not result.Done then
        treasurePanel.Message.Text = "Nothing here. Keep digging."
        return
    end

    local treasureTile = treasureTiles[result.TreasureColumn .. "," .. result.TreasureRow]
    treasureTile.BackgroundColor3 = TREASURE_COLOR
    treasureTile.Mark.Text = "$"
    treasureTile.Mark.TextColor3 = DUG_COLOR

    treasurePanel.CloseButton.Visible = true
end

local function Play()
    if not currentRegion or not selectedNode then return end

    local node = CampaignConfig.Regions[currentRegion].Nodes[selectedNode]

    if node.Type == "Rest" then
        ShowRestPanel()
        return
    elseif node.Type == "Treasure" then
        CampaignRemote:FireServer("StartTreasure", currentRegion, selectedNode)
        return
    end

    lastMatchRegion = currentRegion
    screen.Enabled = false
    hud.Enabled = true
    startMatch("Campaign", currentRegion, selectedNode)
end

--RESULTS--

local function ShowResult(summary)
    local lines = {}

    if summary.Victory then
        if summary.Gold > 0 or summary.Exp > 0 then
            table.insert(lines, string.format("+%d Gold  +%d XP to pouch", summary.Gold, summary.Exp))
        end

        -- Beating a King opens the pouch and sends the player to the world map to see the next island unlock
        if summary.RegionComplete then
            table.insert(lines, string.format("Pouch opened: +%d Gold  +%d XP", summary.PaidGold, summary.PaidExp))

            if summary.Replay then
                table.insert(lines, "Replay: pouch paid 20%")
            end

            lastMatchRegion = nil
        end

        if summary.Class then
            table.insert(lines, ClassConfig.Classes[summary.Class].DisplayName .. " class unlocked")
        end
    elseif summary.Checkpoint then
        table.insert(lines, "Back to your last Rest Site")
    else
        table.insert(lines, "Region restarted, pouch lost")
    end

    -- Rest and treasure resolve on the map, battle results show over the board
    if not hud.Enabled then
        if summary.Type == "Rest" then
            info.Text = (REST_RESULTS[summary.Choice] or "") .. "\nCheckpoint saved"
        else
            local title = summary.Found and "Treasure found!" or "No luck. A few coins for your trouble."
            treasurePanel.Message.Text = title .. "\n" .. table.concat(lines, "\n")
            info.Text = title
        end

        playButton.Visible = false
        return
    end

    resultTitle.Text = summary.Victory and "Victory!" or "Defeat"
    resultRewards.Text = table.concat(lines, "\n")
    resultOverlay.Visible = true
end

-- Brings the player back to the area map they left from, or the world map after beating a King
function CampaignController.ReturnToMap(toWorld)
    if not lastMatchRegion and not toWorld then return end

    currentRegion = lastMatchRegion
    lastMatchRegion = nil
    menu.Enabled = false
    screen.Enabled = true
end

-- Back steps out one level: area map -> world map -> singleplayer screen
local function Back()
    if isAnimating then return end

    if currentRegion then
        CampaignController.ShowWorld(false)
        return
    end

    screen.Enabled = false
    singleplayer.Enabled = true
end

local init = false
function CampaignController.Init(startMatchCallback, leaveMatchCallback)
    if init then return end
    init = true

    startMatch = startMatchCallback
    leaveMatch = leaveMatchCallback

    local player = Players.LocalPlayer
    local playerGui = player.PlayerGui
    menu = playerGui:WaitForChild("MainMenu")
    hud = playerGui:WaitForChild("GameHUD")
    screen = playerGui:WaitForChild("CampaignScreen")
    singleplayer = playerGui:WaitForChild("SingleplayerScreen")

    local root = screen:WaitForChild("Root")
    header = root:WaitForChild("Header")
    backButton = root:WaitForChild("BackButton")

    worldView = root:WaitForChild("WorldView")
    worldCanvas = worldView:WaitForChild("Canvas")
    worldView.CanvasSize = UDim2.fromScale(0, WORLD_CANVAS_HEIGHT)

    areaView = root:WaitForChild("AreaView")
    scene = areaView:WaitForChild("Scene")
    scene.Image = CampaignArt.PAPER
    map = areaView:WaitForChild("Map")

    runInfo = areaView:WaitForChild("RunInfo")
    pouch = areaView:WaitForChild("Pouch")
    ArmoryArt.SetIcon(pouch:WaitForChild("Icon"), "Pouch")

    restPanel = areaView:WaitForChild("RestPanel")
    treasurePanel = areaView:WaitForChild("TreasurePanel")
    treasureGrid = treasurePanel:WaitForChild("Grid")
    tileTemplate = treasurePanel:WaitForChild("TileTemplate")

    for choice in pairs(REST_RESULTS) do
        restPanel:WaitForChild(choice).Activated:Connect(function()
            ChooseRest(choice)
        end)
    end

    restPanel:WaitForChild("CloseButton").Activated:Connect(function()
        restPanel.Visible = false
        playButton.Visible = true
    end)

    treasurePanel:WaitForChild("CloseButton").Activated:Connect(function()
        treasurePanel.Visible = false
    end)

    local infoBar = areaView:WaitForChild("InfoBar")
    info = infoBar:WaitForChild("Info")
    playButton = infoBar:WaitForChild("PlayButton")
    BuildLegend(infoBar:WaitForChild("Legend"), infoBar:WaitForChild("LegendEntryTemplate"))

    islandTemplate = root:WaitForChild("IslandTemplate")
    nodeTemplate = root:WaitForChild("NodeTemplate")
    lineTemplate = root:WaitForChild("LineTemplate")

    resultOverlay = hud:WaitForChild("ResultOverlay")
    local resultPanel = resultOverlay:WaitForChild("ResultPanel")
    resultTitle = resultPanel:WaitForChild("Title")
    resultRewards = resultPanel:WaitForChild("Rewards")

    backButton.Activated:Connect(Back)
    playButton.Activated:Connect(Play)

    local returnToWorld = false

    CampaignRemote.OnClientEvent:Connect(function(action, data)
        if action == "Treasure" then
            if data.Region == currentRegion and data.Node == selectedNode then
                BuildTreasureBoard(data.Digs)
            end
        elseif action == "Dig" then
            ShowDig(data)
        elseif action == "Result" then
            returnToWorld = data.RegionComplete == true
            ShowResult(data)
        end
    end)

    resultPanel:WaitForChild("ContinueButton").Activated:Connect(function()
        resultOverlay.Visible = false
        leaveMatch()
        hud.Enabled = false
        menu.Enabled = true
        CampaignController.ReturnToMap(returnToWorld)
        returnToWorld = false
    end)

    -- Opening the screen fresh scrolls the world map to the bottom
    screen:GetPropertyChangedSignal("Enabled"):Connect(function()
        if not screen.Enabled then return end

        if currentRegion then
            CampaignController.ShowRegion(currentRegion)
        else
            CampaignController.ShowWorld(true)
        end
    end)

    worldCanvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(Redraw)
    map:GetPropertyChangedSignal("AbsoluteSize"):Connect(Redraw)
    ProfileController.OnChanged(Redraw)
end

return CampaignController
