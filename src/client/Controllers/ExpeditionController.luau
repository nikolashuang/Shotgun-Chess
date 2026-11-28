local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local ExpeditionConfig = require(ReplicatedStorage.Shared.Expedition.ExpeditionConfig)
local ExpeditionRules = require(ReplicatedStorage.Shared.Expedition.ExpeditionRules)
local ExpeditionArt = require(ReplicatedStorage.Shared.Expedition.ExpeditionArt)
local ArmoryArt = require(ReplicatedStorage.Shared.UI.ArmoryArt)
local SpriteConfig = require(ReplicatedStorage.Shared.Sprites.SpriteConfig)
local DevConfig = require(ReplicatedStorage.Shared.Player.DevConfig)
local ProfileController = require(script.Parent.ProfileController)

local ExpeditionRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ExpeditionRemote")

local HIGHLIGHT_COLOR = Color3.fromHex("F1D4AC")
local LOCKED_TEXT_COLOR = Color3.fromHex("7A6E73")

local MapConfig = ExpeditionConfig.Map
local MysteryConfig = ExpeditionConfig.Mystery
local TreasureConfig = MysteryConfig.Treasure

local ACT_NAMES = {"Act I", "Act II", "Act III"}

-- Map canvas height compared to the visible window
local CANVAS_HEIGHT = 3.5
-- Canvas heights of layer 1 and the Boss, and the columns' spread across the paper
local BOTTOM_Y = 0.93
local BOSS_Y = 0.07
local LEFT_X = 0.21
local RIGHT_X = 0.79
-- Seeded wobble so routes don't look ruled
local JITTER_X = 0.015
local JITTER_Y = 0.012

-- Node size as a share of the paper's width
local NODE_SIZE = 0.11
local BOSS_NODE_SIZE = 0.18
local SELECTED_SCALE = 1.18
local PULSE_SCALE = 1.1
local PULSE_TIME = 0.6
-- Locked nodes and unwalked routes fade into the paper; visited badges are dimmed
local LOCKED_TRANSPARENCY = 0.45
local LOCKED_COLOR = Color3.fromRGB(190, 190, 190)
local CLEARED_COLOR = Color3.fromRGB(150, 150, 150)
local FAINT_TRANSPARENCY = 0.2

-- Route line thickness and the gap left before each badge, in pixels; walked routes are drawn bolder
local PATH_THICKNESS = 3
local WALKED_THICKNESS = 5
local PATH_GAP = 3

-- Treasure Hunt board colors per region: light tiles, dark tiles
local TREASURE_COLORS = {
    KingsThrone = {Color3.fromHex("E6DFCF"), Color3.fromHex("C9BFA6")},
    Overgrowth = {Color3.fromHex("7E9A5C"), Color3.fromHex("5E7A44")},
    Cliffside = {Color3.fromHex("C99A6B"), Color3.fromHex("A67A50")},
    Outskirts = {Color3.fromHex("C2A878"), Color3.fromHex("9E8558")},
    Gravehollow = {Color3.fromHex("6E6378"), Color3.fromHex("534A5E")},
}
local DUG_COLOR = Color3.fromHex("4A3B33")
local TREASURE_COLOR = Color3.fromHex("F1D4AC")

local REST_TEXT = {
    Rest = "You rest by the fire and recover %d health.",
    GunMaintenance = "You service your shotgun. +1 ammo capacity.",
}

-- Encounter panels: title, body, and choices left to right as {Choice, Label, Note, Extra}
local ENCOUNTER_TEXT = {
    Gunsmith = {
        Title = "Wandering Gunsmith",
        Body = "A mysterious gunsmith offers to upgrade your weapon.",
        Choices = {
            {"Upgrade", string.format("Upgrade (%d Silver)", MysteryConfig.Gunsmith.COST), "+1 shotgun damage, fall-off included"},
            {"Leave", "Leave", ""},
        },
    },
    Ambush = {
        Title = "Ambush!",
        Body = string.format("Enemy pieces burst out of hiding. You take %d damage before you can react.", MysteryConfig.Ambush.DAMAGE),
        Choices = {
            {"Fight", "Fight", "Start surrounded in the middle of the board"},
        },
    },
    Altar = {
        Title = "Queen's Altar",
        Body = "An altar to a fallen Queen asks for an offering.",
        Choices = {
            {"Blood", "Blood Offering", string.format("-%d health, +%d max health", MysteryConfig.Altar.BLOOD_COST, MysteryConfig.Altar.BLOOD_HEALTH)},
            {"Royal", "Royal Sacrifice", string.format("-%d health, +%d shotgun damage", MysteryConfig.Altar.ROYAL_COST, MysteryConfig.Altar.ROYAL_DAMAGE)},
            {"Leave", "Leave", ""},
        },
    },
    Barracks = {
        Title = "Abandoned Barracks",
        Body = "The King finds an abandoned barracks still stocked with weapons and armor.",
        Choices = {
            {"Armor", "Reinforced Armor", string.format("+%d max health for every summoned piece", MysteryConfig.Barracks.HEALTH)},
            {"Weapons", "Weapons Training", string.format("+%d damage for every summoned piece", MysteryConfig.Barracks.DAMAGE)},
        },
    },
    Doctor = {
        Title = "Wandering Doctor",
        Body = "A wandering doctor offers the King treatment.",
        Choices = {
            {"Treatment", "Treatment", "Restore health to full"},
            {"Vitality", "Vitality", string.format("+%d max health and +%d health", MysteryConfig.Doctor.VITALITY, MysteryConfig.Doctor.VITALITY)},
        },
    },
    HolyRook = {
        Title = "Statue of a Holy Rook",
        Body = "A weathered statue offers one of two blessings.",
        Choices = {
            {"Power", "Blessing of Power", string.format("Start battles with %d Ultimate charge, -%d max health", MysteryConfig.HolyRook.POWER_CHARGE, MysteryConfig.HolyRook.POWER_HEALTH)},
            {"Vitality", "Blessing of Vitality", string.format("Heal %d after every battle, -%d max energy", MysteryConfig.HolyRook.VITALITY_HEAL, MysteryConfig.HolyRook.VITALITY_ENERGY)},
        },
    },
    Gambler = {
        Title = "Gambler",
        Body = "A suspicious stranger offers to double your Silver. Or take it.",
        Choices = {
            {"Wager", string.format("Wager %d", MysteryConfig.Gambler.WAGERS[1]), "50% double, 50% lose", 1},
            {"Wager", string.format("Wager %d", MysteryConfig.Gambler.WAGERS[2]), "50% double, 50% lose", 2},
            {"Wager", string.format("Wager %d", MysteryConfig.Gambler.WAGERS[3]), "50% double, 50% lose", 3},
            {"Leave", "Leave", ""},
        },
    },
    FallenKnight = {
        Title = "Fallen Knight",
        Body = "Loyalty keeps him on his dead King's throne, but that could change...",
        Choices = {
            {"Challenge", "Challenge the Knight", "He and his army fight to the end"},
            {"Leave", "Continue walking", ""},
        },
    },
}

local MAX_CHOICES = 4

-- The King's face from the sprite atlas, as on the combat HUD's health card
local PORTRAIT_SIZE = 12
local PORTRAIT_INSET = 10
-- Cream fill split by notches in the bar's color, like the King's health on the board
local HEALTH_FILL_COLOR = Color3.fromHex("F1D4AC")
local HEALTH_DIVIDER_COLOR = Color3.fromHex("171219")

local LEGEND_FONT = Font.new("rbxasset://fonts/families/Fondamento.json", Enum.FontWeight.Bold)

local hud = nil
local menu = nil
local screen = nil
local singleplayer = nil
local header = nil

local startView = nil
local mapView = nil
local scroll = nil
local canvas = nil
local paperLayer = nil
local routeLayer = nil
local nodeLayer = nil
local legend = nil
local legendList = nil
local legendPaper = nil
local info = nil
local rewards = nil
local playButton = nil
local runPanel = nil
local artifactPrompt = nil
local noticePanel = nil
local abandonPanel = nil
local shopPanel = nil

local restPanel = nil
local restFire = nil
local mysteryPanel = nil
local mysteryBackground = nil
local gunsmith = nil
local eyeGlow = nil
local mysteryFade = nil
local treasurePanel = nil
local treasureGrid = nil
local tileTemplate = nil
local treasureTiles = {}

local nodeTemplate = nil
local dotTemplate = nil
local legendEntryTemplate = nil

local resultOverlay = nil
local resultTitle = nil
local resultRewards = nil

local startMatch = nil
local leaveMatch = nil

local selectedNode = nil
local nodeButtons = {}
-- The encounter shown in the mystery panel, and the node it belongs to
local encounterName = nil
local encounterNode = nil
local isEncounterBusy = false
local isDigging = false
-- Set while a battle from this screen is running, so the map comes back afterward
local isInBattle = false
-- The Act whose map was last drawn, so a new Act scrolls back to the bottom
local drawnAct = nil

-- Dev map browser: a stand-in run that shows one region's map without touching the real run
local devBar = nil
local devMapsButton = nil
local previewRun = nil
local previewRegions = {}
local previewIndex = 1

local ExpeditionController = {}

local function GetRun()
    return previewRun or ProfileController.Data.Expedition
end

local function GetTheme(run)
    return ExpeditionArt.Themes[run.Regions[run.Act]]
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

local function SetIcon(image, nodeType)
    local tile = ExpeditionArt.NODE_TILE

    image.Image = ExpeditionArt.NODE_ICONS
    image.ImageRectOffset = Vector2.new(ExpeditionArt.NodeOrder[nodeType] * tile, 0)
    image.ImageRectSize = Vector2.new(tile, tile)
    image.ResampleMode = Enum.ResamplerMode.Pixelated
end

--PAPER--

local function NewPaperPiece(parent, name, image, zIndex)
    local piece = Instance.new("ImageLabel")
    piece.Name = name
    piece.BackgroundTransparency = 1
    piece.Image = image
    piece.ScaleType = Enum.ScaleType.Tile
    piece.ResampleMode = Enum.ResamplerMode.Pixelated
    piece.ZIndex = zIndex
    piece.Parent = parent

    return piece
end

-- Lays a region's parchment over the container, then its trim (if it has one): edge strips down both sides, border
-- strips across top and bottom, and a corner in each corner. The map (isMap) gets the tall parchment it scrolls
-- through; anything else gets the single page. scale shrinks everything
-- for small slips like the legend
local function BuildPaper(container, theme, scale, isMap)
    ClearChildren(container)

    if isMap then
        local total = 0
        for _, piece in ipairs(ExpeditionArt.PARCHMENT_TALL) do
            total += piece.Height
        end

        local top = 0
        for i, piece in ipairs(ExpeditionArt.PARCHMENT_TALL) do
            local part = NewPaperPiece(container, "Parchment" .. i, piece.Image, 1)
            part.ScaleType = Enum.ScaleType.Stretch
            part.ResampleMode = Enum.ResamplerMode.Default
            part.Position = UDim2.fromScale(0, top / total)
            part.Size = UDim2.fromScale(1, piece.Height / total)
            top += piece.Height
        end
    else
        local parchment = NewPaperPiece(container, "Parchment", ExpeditionArt.PARCHMENT, 1)
        parchment.Size = UDim2.fromScale(1, 1)
        parchment.ScaleType = Enum.ScaleType.Slice
        parchment.SliceCenter = ExpeditionArt.PARCHMENT_SLICE
        parchment.SliceScale = ExpeditionArt.PARCHMENT_SLICE_SCALE * scale
        -- Painted, not pixel art, and shown smaller than it was drawn
        parchment.ResampleMode = Enum.ResamplerMode.Default
    end

    local trim = theme.Trim
    if not trim then return end

    local edge = math.floor(ExpeditionArt.TRIM_EDGE * scale)
    local inset = math.floor(trim.INSET * scale)
    local cornerSize = math.floor(edge * 1.5)
    local clear = trim.CLEAR_CORNERS and cornerSize or 0

    local frame = Instance.new("Frame")
    frame.Name = "Trim"
    frame.BackgroundTransparency = 1
    frame.Position = UDim2.fromOffset(inset, inset)
    frame.Size = UDim2.new(1, -inset * 2, 1, -inset * 2)
    frame.ZIndex = 2
    frame.Parent = container

    -- Strips are 3 times as long as they are wide in the art
    local left = NewPaperPiece(frame, "EdgeLeft", trim.Edge, 1)
    left.Position = UDim2.fromOffset(0, clear)
    left.Size = UDim2.new(0, edge, 1, -clear * 2)
    left.TileSize = UDim2.fromOffset(edge, edge * 3)

    local right = left:Clone()
    right.Name = "EdgeRight"
    right.AnchorPoint = Vector2.new(1, 0)
    right.Position = UDim2.new(1, 0, 0, clear)
    right.Rotation = 180
    right.Parent = frame

    local top = NewPaperPiece(frame, "BorderTop", trim.Border, 1)
    top.Position = UDim2.fromOffset(clear, 0)
    top.Size = UDim2.new(1, -clear * 2, 0, edge)
    top.TileSize = UDim2.fromOffset(edge * 3, edge)

    local bottom = top:Clone()
    bottom.Name = "BorderBottom"
    bottom.AnchorPoint = Vector2.new(0, 1)
    bottom.Position = UDim2.new(0, clear, 1, 0)
    bottom.Rotation = 180
    bottom.Parent = frame

    local corners = {
        {Vector2.new(0, 0), 0},
        {Vector2.new(1, 0), 90},
        {Vector2.new(1, 1), 180},
        {Vector2.new(0, 1), 270},
    }

    for i, corner in ipairs(corners) do
        local piece = NewPaperPiece(frame, "Corner" .. i, trim.Corner, 3)
        piece.ScaleType = Enum.ScaleType.Stretch
        piece.AnchorPoint = corner[1]
        piece.Position = UDim2.fromScale(corner[1].X, corner[1].Y)
        piece.Size = UDim2.fromOffset(cornerSize, cornerSize)
        piece.Rotation = corner[2]
    end
end

local function ApplyFont(theme)
    for _, label in ipairs({legend.Title, info, runPanel.Region}) do
        label.FontFace = LEGEND_FONT
    end

    legend.Title.TextColor3 = theme.Ink

    -- Entries get a paper-colored outline so they read over the paper's grain
    for _, entry in ipairs(legendList:GetChildren()) do
        if entry:IsA("Frame") then
            entry.Label.FontFace = LEGEND_FONT
            entry.Label.TextColor3 = theme.Ink
            entry.Label.TextStrokeColor3 = theme.Paper
            entry.Label.TextStrokeTransparency = 0.2
        end
    end
end

--MAP--

-- Canvas position of a node: layer 1 at the bottom, the Boss at the top, columns spread across with a wobble
local function GetNodePosition(run, nodeId, node)
    if node.Type == "Boss" then
        return {0.5, BOSS_Y}
    end

    local random = Random.new(run.Seeds[run.Act] + node.Layer * 31 + node.Column * 7)
    local layerShare = (node.Layer - 1) / MapConfig.LAYERS
    local columnShare = (node.Column - 1) / (MapConfig.WIDTH - 1)

    return {
        LEFT_X + (RIGHT_X - LEFT_X) * columnShare + (random:NextNumber() * 2 - 1) * JITTER_X,
        BOTTOM_Y - (BOTTOM_Y - BOSS_Y - 0.06) * layerShare + (random:NextNumber() * 2 - 1) * JITTER_Y,
    }
end

-- A dotted line of ink between two nodes
local function GetNodeSize(node)
    return node.Type == "Boss" and BOSS_NODE_SIZE or NODE_SIZE
end

-- A solid line of ink between two nodes, stopping short of each badge so it reads as leading into it
-- fromSize and toSize are the badges' sizes as a share of the paper's width
local function DrawPath(from, to, fromSize, toSize, color, transparency, thickness)
    local size = canvas.AbsoluteSize
    local x0, y0 = from[1] * size.X, from[2] * size.Y
    local x1, y1 = to[1] * size.X, to[2] * size.Y
    local dx, dy = x1 - x0, y1 - y0
    local length = math.sqrt(dx * dx + dy * dy)
    if length == 0 then return end

    -- Trim both ends back to the badge rims plus a small gap
    local startGap = fromSize * size.X / 2 + PATH_GAP
    local endGap = toSize * size.X / 2 + PATH_GAP
    local visible = length - startGap - endGap
    if visible <= 0 then return end

    local midShare = (startGap + visible / 2) / length

    local line = dotTemplate:Clone()
    line.AnchorPoint = Vector2.new(0.5, 0.5)
    line.Position = UDim2.fromOffset(x0 + dx * midShare, y0 + dy * midShare)
    line.Size = UDim2.fromOffset(visible, thickness)
    line.Rotation = math.deg(math.atan2(dy, dx))
    line.BorderSizePixel = 0
    line.BackgroundColor3 = color
    line.BackgroundTransparency = transparency
    line.ZIndex = 4
    line.Visible = true
    line.Parent = routeLayer
end

local function FormatNode(run, node)
    local typeName = ExpeditionConfig.TypeNames[node.Type]

    if ExpeditionRules.IsBattle(node.Type) then
        local points = ExpeditionRules.GetPoints(run, node.Type)
        local text = string.format("%s\n%d point army", typeName, points)

        if node.Type == "Elite" then
            text ..= "\nDrops an Artifact"
        end

        return text
    end

    if node.Type == "Rest" then
        return typeName .. (run.Mode == "Normal" and "\nCheckpoint" or "\nNo checkpoints in Elite")
    end

    if node.Type == "Shop" then return typeName .. "\nArtifacts for Silver" end

    return typeName .. "\nSomething waits down this road..."
end

local function SelectNode(nodeId)
    local run = GetRun()
    if not run then return end

    if selectedNode and nodeButtons[selectedNode] then
        nodeButtons[selectedNode].Icon.UIScale.Scale = 1
    end

    selectedNode = nodeId
    if not nodeButtons[nodeId] then return end

    nodeButtons[nodeId].Icon.UIScale.Scale = SELECTED_SCALE

    local node = ExpeditionRules.GetNode(run, nodeId)
    local state = ExpeditionRules.GetNodeState(run, nodeId)
    local text = FormatNode(run, node)

    if state == "Locked" then
        text ..= "\nOut of reach"
    elseif state == "Cleared" then
        text ..= "\nVisited"
    end

    info.Text = text

    -- Battles show what they pay as icons under the text
    rewards.Visible = ExpeditionRules.IsBattle(node.Type)
    if rewards.Visible then
        local gold, exp, silver = ExpeditionRules.GetReward(run, node.Type)
        rewards.Gold.Amount.Text = tostring(gold)
        rewards.Silver.Amount.Text = tostring(silver)
        rewards.Exp.Amount.Text = tostring(exp)
    end
    playButton.Visible = (state == "Available" or state == "Current") and not run.PendingArtifact and not previewRun

    if ExpeditionRules.IsBattle(node.Type) then
        playButton.Label.Text = "Fight"
    elseif state == "Current" then
        playButton.Label.Text = "Return"
    else
        playButton.Label.Text = "Enter"
    end
end

local function NewNodeButton(run, theme, nodeId, node, state)
    local position = GetNodePosition(run, nodeId, node)
    local size = GetNodeSize(node)

    local button = nodeTemplate:Clone()
    button.Name = nodeId
    button.AnchorPoint = Vector2.new(0.5, 0.5)
    button.Position = UDim2.fromScale(position[1], position[2])
    -- Both sides measured off the paper's width, so badges stay round on the tall canvas
    button.SizeConstraint = Enum.SizeConstraint.RelativeXX
    button.Size = UDim2.fromScale(size, size)
    button.ZIndex = 5

    local icon = button.Icon
    SetIcon(icon, node.Type)
    icon.ZIndex = 5

    -- Visited nodes are circled in the route's ink, like the King marked his own map
    button.Check.Visible = state == "Cleared"
    button.Check.TextColor3 = theme.Accent
    button.Check.BackgroundTransparency = 1
    button.Check.FontFace = LEGEND_FONT
    button.Check.ZIndex = 6

    if state == "Locked" then
        icon.ImageTransparency = LOCKED_TRANSPARENCY
        icon.ImageColor3 = LOCKED_COLOR
    elseif state == "Cleared" then
        icon.ImageColor3 = CLEARED_COLOR
    else
        local tweenInfo = TweenInfo.new(PULSE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
        TweenService:Create(button.PulseScale, tweenInfo, {Scale = PULSE_SCALE}):Play()
    end

    button.Visible = true
    button.Parent = nodeLayer

    button.Activated:Connect(function()
        -- A second click on a selected open node goes in
        if selectedNode == nodeId and playButton.Visible then
            ExpeditionController.Play()
            return
        end

        SelectNode(nodeId)
    end)

    nodeButtons[nodeId] = button

    return position
end

-- Keeps the King's place on the map in view; a fresh Act starts at the bottom
local function ScrollToCurrent(run)
    local windowHeight = scroll.AbsoluteWindowSize.Y
    local canvasHeight = scroll.AbsoluteCanvasSize.Y
    local maxScroll = math.max(canvasHeight - windowHeight, 0)
    local current = ExpeditionRules.GetCurrentNode(run)

    if not current then
        scroll.CanvasPosition = Vector2.new(0, maxScroll)
        return
    end

    local position = GetNodePosition(run, current, ExpeditionRules.GetNode(run, current))
    local target = position[2] * canvasHeight - windowHeight * 0.7

    scroll.CanvasPosition = Vector2.new(0, math.clamp(target, 0, maxScroll))
end

-- The King's health beside his portrait, the bar split into one segment per point of max health
local function DrawKingCard(run)
    local card = runPanel.KingCard
    local bar = card.HealthBar

    card.HealthText.Text = string.format("Health %d/%d", run.Health, run.MaxHealth)
    bar.Fill.Size = UDim2.fromScale(math.clamp(run.Health / run.MaxHealth, 0, 1), 1)
    bar.Fill.BackgroundColor3 = HEALTH_FILL_COLOR

    if bar:GetAttribute("Dividers") == run.MaxHealth then return end
    bar:SetAttribute("Dividers", run.MaxHealth)

    for _, child in ipairs(bar:GetChildren()) do
        if child.Name == "Divider" then
            child:Destroy()
        end
    end

    for i = 1, run.MaxHealth - 1 do
        local divider = Instance.new("Frame")
        divider.Name = "Divider"
        divider.BorderSizePixel = 0
        divider.BackgroundColor3 = HEALTH_DIVIDER_COLOR
        divider.AnchorPoint = Vector2.new(0.5, 0)
        divider.Position = UDim2.fromScale(i / run.MaxHealth, 0)
        divider.Size = UDim2.new(0, 1, 1, 0)
        divider.ZIndex = bar.Fill.ZIndex + 1
        divider.Parent = bar
    end
end

local function UpdateRunPanel(run)
    local region = ExpeditionRules.GetRegion(run)
    local upgrades = run.Upgrades

    runPanel.Region.Text = string.format("%s  -  %s", ACT_NAMES[run.Act], region.DisplayName)
    runPanel.Mode.Text = run.Mode == "Elite" and "Elite Expedition" or "Expedition"

    DrawKingCard(run)
    runPanel.Silver.Amount.Text = string.format("%d Silver", run.Silver)

    local lines = {}

    if upgrades.Damage ~= 0 then
        table.insert(lines, string.format("%+d shotgun damage", upgrades.Damage))
    end

    if upgrades.Ammo > 0 then
        table.insert(lines, string.format("+%d Gun Maintenance", upgrades.Ammo))
    end

    if upgrades.SummonHealth > 0 or upgrades.SummonDamage > 0 then
        table.insert(lines, string.format("Summons +%d HP  +%d damage", upgrades.SummonHealth, upgrades.SummonDamage))
    end

    if upgrades.StartCharge > 0 then
        table.insert(lines, string.format("Start with %d Ultimate", upgrades.StartCharge))
    end

    if upgrades.HealAfterBattle > 0 then
        table.insert(lines, string.format("Heal %d after battles", upgrades.HealAfterBattle))
    end

    if upgrades.Energy < 0 then
        table.insert(lines, string.format("%d max energy", upgrades.Energy))
    end

    if run.Companion then
        table.insert(lines, string.format("Fallen Knight %d/%d", run.Companion.Health, run.Companion.MaxHealth))
    end

    if run.HasCheckpoint then
        table.insert(lines, "Checkpoint saved")
    end

    runPanel.Stats.Text = table.concat(lines, "\n")

    runPanel.Artifacts.Text = string.format("Artifacts %d/%d", #run.Artifacts, ExpeditionConfig.Artifacts.MAX)

    -- One slot per Artifact the run can hold; they have no art yet, so a slot shows the name
    for i = 1, ExpeditionConfig.Artifacts.MAX do
        local slot = runPanel.ArtifactSlots["Slot" .. i]
        local name = run.Artifacts[i]
        local artifact = name and ExpeditionConfig.Artifacts.Pool[name]

        slot.Title.Text = name and (artifact and artifact.DisplayName or name) or ""
        slot.BackgroundTransparency = name and 0 or 0.5
    end

    local pouch = runPanel.Pouch
    pouch.Gold.Text = string.format("%d Gold", run.Gold)
    pouch.Exp.Text = string.format("%d XP", run.Exp)
end

local function ShowArtifactPrompt(run)
    artifactPrompt.Visible = run.PendingArtifact ~= nil
    if not run.PendingArtifact then return end

    local artifact = ExpeditionConfig.Artifacts.Pool[run.PendingArtifact]
    artifactPrompt.Body.Text = string.format("You found %s, but your Artifacts are full. Replace one, or leave it behind.",
        artifact and artifact.DisplayName or run.PendingArtifact)

    local slots = artifactPrompt.Slots

    for i = 1, ExpeditionConfig.Artifacts.MAX do
        local slot = slots["Slot" .. i]
        local name = run.Artifacts[i]
        local held = name and ExpeditionConfig.Artifacts.Pool[name]

        slot.Visible = name ~= nil
        slot.Label.Text = held and held.DisplayName or (name or "")
    end
end

local function DrawMap()
    local run = GetRun()

    if not run then
        startView.Visible = true
        mapView.Visible = false
        header.Text = "Expedition"
        return
    end

    startView.Visible = false
    mapView.Visible = true
    header.Text = run.Mode == "Elite" and "Elite Expedition" or "Expedition"

    local theme = GetTheme(run)
    local map = ExpeditionRules.GetMap(run)

    BuildPaper(paperLayer, theme, 1, true)
    BuildPaper(legendPaper, theme, 2 / 3)
    ApplyFont(theme)
    UpdateRunPanel(run)

    ClearChildren(routeLayer)
    ClearChildren(nodeLayer)
    nodeButtons = {}

    local positions = {}

    for nodeId, node in pairs(map.Nodes) do
        positions[nodeId] = NewNodeButton(run, theme, nodeId, node, ExpeditionRules.GetNodeState(run, nodeId))
    end

    for nodeId, node in pairs(map.Nodes) do
        for _, link in ipairs(node.Links) do
            -- Only the route walked this Act is inked in
            local fromIndex = table.find(run.Path, nodeId)
            local isWalked = fromIndex ~= nil and run.Path[fromIndex + 1] == link

            DrawPath(positions[nodeId], positions[link], GetNodeSize(node), GetNodeSize(map.Nodes[link]),
                isWalked and theme.Accent or theme.Ink, isWalked and 0 or FAINT_TRANSPARENCY,
                isWalked and WALKED_THICKNESS or PATH_THICKNESS)
        end
    end

    if drawnAct ~= run.Act then
        drawnAct = run.Act
        selectedNode = nil
        task.defer(ScrollToCurrent, run)
    end

    if selectedNode and map.Nodes[selectedNode] then
        SelectNode(selectedNode)
    else
        selectedNode = nil
        info.Text = "Pick a node to travel to"
        rewards.Visible = false
        playButton.Visible = false
    end

    ShowArtifactPrompt(run)
end

local function Redraw()
    if not screen.Enabled then return end

    DrawMap()
end

local function BuildLegend()
    for i, nodeType in ipairs(ExpeditionArt.LEGEND_ORDER) do
        local entry = legendEntryTemplate:Clone()
        entry.Name = nodeType
        entry.LayoutOrder = i
        SetIcon(entry.Icon, nodeType)
        entry.Label.Text = ExpeditionConfig.TypeNames[nodeType]
        entry.Visible = true
        entry.Parent = legendList
    end
end

--BATTLES--

local function StartBattle(nodeId)
    isInBattle = true
    screen.Enabled = false
    hud.Enabled = true
    startMatch("Expedition", nodeId)
end

--REST--

-- The campfire plays its frames while the Rest Site is open; the Fallen Knight sits by the fire once he has joined
local function ShowRest(run, nodeId)
    local row = ExpeditionArt.RestFireRow[run.Companion and "Knight" or "Party"]
    local frameSize = ExpeditionArt.REST_FIRE_FRAME

    encounterNode = nodeId
    restPanel.Health.Text = string.format("Health %d/%d", run.Health, run.MaxHealth)
    restPanel.Subtitle.Text = run.Mode == "Normal" and "Choosing saves a checkpoint here" or "Elite Expeditions have no checkpoints"
    restPanel.Visible = true

    task.spawn(function()
        local frame = 0

        while restPanel.Visible do
            local column = frame % ExpeditionArt.REST_FIRE_COLUMNS
            local line = row + frame // ExpeditionArt.REST_FIRE_COLUMNS
            restFire.ImageRectOffset = Vector2.new(column * frameSize.X, line * frameSize.Y)

            frame = (frame + 1) % ExpeditionArt.REST_FIRE_FRAMES
            task.wait(ExpeditionArt.REST_FIRE_TIME)
        end
    end)
end

--TREASURE--

local function MarkDug(column, row)
    for _, tile in ipairs(ExpeditionRules.GetDigTiles(column, row)) do
        treasureTiles[tile[1] .. "," .. tile[2]].BackgroundColor3 = DUG_COLOR
    end
end

local function SetDigsLeft(digsLeft)
    treasurePanel.Digs.Text = digsLeft == 1 and "1 dig left" or (digsLeft .. " digs left")
end

-- Row 1 is drawn at the bottom, like the battle board
local function ShowTreasure(run, nodeId, digs)
    encounterNode = nodeId
    ClearChildren(treasureGrid)
    treasureTiles = {}

    local size = TreasureConfig.SIZE
    local colors = TREASURE_COLORS[run.Regions[run.Act]]

    for column = 1, size do
        for row = 1, size do
            local tile = tileTemplate:Clone()
            tile.Name = column .. "," .. row
            tile.Position = UDim2.fromScale((column - 1) / size, (size - row) / size)
            tile.Size = UDim2.fromScale(1 / size, 1 / size)
            tile.BackgroundColor3 = colors[(column + row) % 2 + 1]
            tile.Visible = true
            tile.Parent = treasureGrid

            tile.Activated:Connect(function()
                if isDigging or treasurePanel.CloseButton.Visible then return end

                isDigging = true
                ExpeditionRemote:FireServer("Dig", encounterNode, column, row)
            end)

            treasureTiles[tile.Name] = tile
        end
    end

    for _, dug in ipairs(digs) do
        MarkDug(dug[1], dug[2])
    end

    SetDigsLeft(TreasureConfig.DIGS - #digs)
    treasurePanel.Message.Text = string.format("Pick a tile to dig. Each dig uncovers a %dx%d area.", TreasureConfig.DIG_SIZE, TreasureConfig.DIG_SIZE)
    treasurePanel.CloseButton.Visible = false
    treasurePanel.Visible = true
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
end

--SHOP--

local function ShowShop(run, nodeId, stock)
    encounterNode = nodeId
    shopPanel.Silver.Text = string.format("%d Silver", run.Silver)

    local items = shopPanel.Items
    stock = stock or {}

    for i = 1, ExpeditionConfig.Shop.INVENTORY_SIZE do
        local card = items["Item" .. i]
        local item = stock[i]

        card.Visible = item ~= nil

        if item then
            local artifact = ExpeditionConfig.Artifacts.Pool[item.Name]
            card.Title.Text = artifact and artifact.DisplayName or item.Name
            card.Body.Text = artifact and artifact.Description or ""
            card.BuyButton.Label.Text = item.Sold and "Sold" or string.format("%d Silver", item.Price)
            card.BuyButton:SetAttribute("Enabled", not item.Sold and run.Silver >= item.Price)
            card.BuyButton.Label.TextColor3 = (not item.Sold and run.Silver >= item.Price) and HIGHLIGHT_COLOR or LOCKED_TEXT_COLOR
        end
    end

    -- Artifact designs aren't made yet, so the shelves stay bare until they are
    shopPanel.Empty.Visible = #stock == 0
    shopPanel.Visible = true
end

--ENCOUNTERS--

-- Transparency, then how long it holds, as the Fallen Knight's eye flickers on like he's waking up
local EYE_FLICKER = {{0.4, 0.06}, {1, 0.14}, {0.6, 0.06}, {1, 0.3}}
local EYE_WAKE_HOLD = 1.4

local function PlayEyeGlow()
    eyeGlow.ImageTransparency = 1
    task.wait(0.4)

    for _, step in ipairs(EYE_FLICKER) do
        eyeGlow.ImageTransparency = step[1]
        task.wait(step[2])
    end

    Tween(eyeGlow, 0.35, {ImageTransparency = 0})
    task.wait(0.35 + EYE_WAKE_HOLD)

    Tween(mysteryFade, 0.5, {BackgroundTransparency = 0})
    task.wait(0.5)
end

local function ShowEncounter(run, data)
    local text = ENCOUNTER_TEXT[data.Name]
    if not text then return end

    encounterName = data.Name
    encounterNode = data.Node
    isEncounterBusy = false

    mysteryBackground.Image = ExpeditionArt.MysteryBackgrounds[data.Name] or ExpeditionArt.FALLBACK_BACKGROUND
    mysteryPanel.Title.Text = text.Title
    mysteryPanel.Body.Text = text.Body
    mysteryPanel.Health.Text = string.format("Health %d/%d    %d Silver", run.Health, run.MaxHealth, run.Silver)
    mysteryPanel.CloseButton.Visible = false
    mysteryPanel.Choices.Visible = true
    mysteryFade.BackgroundTransparency = 1
    eyeGlow.ImageTransparency = 1
    gunsmith.Visible = data.Name == "Gunsmith"

    for i = 1, MAX_CHOICES do
        local button = mysteryPanel.Choices["Choice" .. i]
        local choice = text.Choices[i]

        button.Visible = choice ~= nil

        if choice then
            -- An ambush's fight is already decided by the server
            local canChoose, reason = true, nil

            if choice[1] ~= "Fight" then
                canChoose, reason = ExpeditionRules.CanChoose(run, data.Name, choice[1], choice[4])
            end

            button.Label.Text = choice[2]
            button.Label.TextColor3 = canChoose and HIGHLIGHT_COLOR or LOCKED_TEXT_COLOR
            button:SetAttribute("Choice", choice[1])
            button:SetAttribute("Extra", choice[4])
            button:SetAttribute("Enabled", canChoose == true)
            button.Note.Text = canChoose and choice[3] or (reason or "")
        end
    end

    mysteryPanel.Visible = true

    if data.Name == "Gunsmith" then
        task.spawn(function()
            local frame = 0
            local size = ExpeditionArt.GUNSMITH_FRAME

            while mysteryPanel.Visible and encounterName == "Gunsmith" do
                gunsmith.ImageRectOffset = Vector2.new(frame % ExpeditionArt.GUNSMITH_COLUMNS * size.X, frame // ExpeditionArt.GUNSMITH_COLUMNS * size.Y)
                frame = (frame + 1) % ExpeditionArt.GUNSMITH_FRAMES
                task.wait(ExpeditionArt.GUNSMITH_TIME)
            end
        end)
    end
end

local function ChooseEncounter(index)
    local button = mysteryPanel.Choices["Choice" .. index]
    if not button:GetAttribute("Enabled") or mysteryPanel.CloseButton.Visible or isEncounterBusy then return end

    local choice = button:GetAttribute("Choice")

    if choice == "Fight" then
        mysteryPanel.Visible = false
        StartBattle(encounterNode)
        return
    end

    if choice == "Challenge" then
        isEncounterBusy = true
        mysteryPanel.Choices.Visible = false
        PlayEyeGlow()
    end

    ExpeditionRemote:FireServer("Choose", encounterNode, choice, button:GetAttribute("Extra"))
end

-- What an encounter choice did, shown in its panel before it closes
local function DescribeEncounter(summary)
    local name = summary.Encounter
    local choice = summary.Choice

    if name == "Gunsmith" then
        return choice == "Upgrade" and "Your shotgun hits harder. +1 damage." or "You leave the gunsmith behind."
    elseif name == "Altar" then
        if choice == "Blood" then return "The altar drinks your blood. +2 max health." end
        if choice == "Royal" then return "The altar accepts your sacrifice. +2 shotgun damage." end
        return "You walk away from the altar."
    elseif name == "Barracks" then
        return choice == "Armor" and "Your pieces will march in reinforced armor." or "Your pieces will strike harder."
    elseif name == "Doctor" then
        return choice == "Treatment" and "The doctor patches you up. Health restored." or "The doctor's tonic leaves you stronger."
    elseif name == "HolyRook" then
        return choice == "Power" and "Power surges through you, at a cost." or "A calm settles over you, at a cost."
    elseif name == "Gambler" then
        if choice == "Wager" then
            return summary.Won and string.format("You win! +%d Silver.", summary.Wager) or string.format("You lose %d Silver.", summary.Wager)
        end
        return "You keep your Silver to yourself."
    elseif name == "FallenKnight" then
        return "You walk on, leaving the Knight to his throne."
    end

    return ""
end

--RESULTS--

local function GetRewardLines(summary)
    local lines = {}

    if summary.Victory then
        if summary.Gold > 0 or summary.Exp > 0 or summary.Silver > 0 then
            table.insert(lines, string.format("+%d Gold  +%d XP  +%d Silver", summary.Gold, summary.Exp, summary.Silver))
        end

        if summary.Companion then
            table.insert(lines, "The Fallen Knight joins your Expedition")
        end

        if summary.Artifact then
            local artifact = ExpeditionConfig.Artifacts.Pool[summary.Artifact]
            table.insert(lines, "Artifact found: " .. (artifact and artifact.DisplayName or summary.Artifact))
        end

        if summary.ExpeditionComplete then
            table.insert(lines, string.format("Expedition complete! Pouch opened: +%d Gold  +%d XP", summary.PaidGold, summary.PaidExp))
        elseif summary.ActComplete then
            table.insert(lines, string.format("%s complete. Next: %s", ACT_NAMES[summary.Act], ExpeditionConfig.Regions[summary.NextRegion].DisplayName))
        end
    elseif summary.Checkpoint then
        table.insert(lines, "Back to your last Rest Site")
    else
        table.insert(lines, "Expedition lost. Everything in the pouch is gone.")
    end

    return lines
end

local function ShowNotice(title, body)
    noticePanel.Title.Text = title
    noticePanel.Body.Text = body
    noticePanel.Visible = true
end

local function ShowResult(summary)
    local lines = GetRewardLines(summary)

    -- Battle results show over the board
    if hud.Enabled then
        resultTitle.Text = summary.Victory and "Victory!" or "Defeat"
        resultRewards.Text = table.concat(lines, "\n")
        resultOverlay.Visible = true
        return
    end

    -- An encounter's penalty killed the King
    if not summary.Victory then
        mysteryPanel.Visible = false
        restPanel.Visible = false
        treasurePanel.Visible = false
        ShowNotice("Defeat", table.concat(lines, "\n"))
        return
    end

    if summary.Type == "Rest" then
        restPanel.Visible = false
        local text = string.format(REST_TEXT[summary.Choice], summary.Healed or 0)
        ShowNotice("Rest Site", text .. (summary.Checkpoint and "\nCheckpoint saved." or ""))
    elseif summary.Type == "Shop" then
        shopPanel.Visible = false
    elseif summary.Encounter == "Treasure" then
        local title = summary.Found and "Treasure found!" or "No luck. A few coins for your trouble."
        treasurePanel.Message.Text = title .. "\n" .. table.concat(lines, "\n")
        treasurePanel.CloseButton.Visible = true
    else
        mysteryPanel.Body.Text = DescribeEncounter(summary) .. "\n" .. table.concat(lines, "\n")
        mysteryPanel.Choices.Visible = false
        mysteryPanel.CloseButton.Visible = true
    end
end

local function OnEncounter(data)
    local run = GetRun()
    if not run then return end

    selectedNode = data.Node

    if data.Kind == "Rest" then
        ShowRest(run, data.Node)
    elseif data.Kind == "Shop" then
        ShowShop(run, data.Node, data.Stock)
    elseif data.Name == "Treasure" then
        ShowTreasure(run, data.Node, data.Digs or {})
    elseif data.Fight and data.Name ~= "Ambush" then
        -- Coming back to a fight already picked goes straight into it
        StartBattle(data.Node)
    else
        ShowEncounter(run, data)
    end
end

local function ShowPreview(seed)
    local region = previewRegions[previewIndex]
    local act = ExpeditionConfig.Regions[region].Act

    previewRun = ExpeditionRules.NewRun("Normal", Random.new(seed))
    previewRun.Act = act
    previewRun.Regions[act] = region
    previewRun.Seeds[act] = seed
    previewRun.Points = ExpeditionRules.GetStartPoints("Normal", act)

    devBar.Region.Text = ExpeditionConfig.Regions[region].DisplayName
    devBar.Visible = true
    devMapsButton.Visible = false
    runPanel.AbandonButton.Visible = false

    drawnAct = nil
    selectedNode = nil
    DrawMap()
end

local function ExitPreview()
    if not previewRun then return end

    previewRun = nil
    devBar.Visible = false
    devMapsButton.Visible = true
    runPanel.AbandonButton.Visible = true

    drawnAct = nil
    selectedNode = nil
    DrawMap()
end

local function NewPreviewSeed()
    return Random.new():NextInteger(1, 2 ^ 30)
end

local function InitDevMaps(root)
    devMapsButton = root:WaitForChild("DevMapsButton")
    devBar = root:WaitForChild("MapView"):WaitForChild("DevBar")

    if not DevConfig.IsDev(Players.LocalPlayer) then
        devMapsButton:Destroy()
        devBar:Destroy()
        devMapsButton = nil
        devBar = nil
        return
    end

    for _, actConfig in ipairs(ExpeditionConfig.Acts) do
        for _, region in ipairs(actConfig.Pool) do
            table.insert(previewRegions, region)
        end
    end

    devMapsButton.Visible = true

    devMapsButton.Activated:Connect(function()
        ShowPreview(NewPreviewSeed())
    end)

    devBar.PrevButton.Activated:Connect(function()
        previewIndex = (previewIndex - 2) % #previewRegions + 1
        ShowPreview(NewPreviewSeed())
    end)

    devBar.NextButton.Activated:Connect(function()
        previewIndex = previewIndex % #previewRegions + 1
        ShowPreview(NewPreviewSeed())
    end)

    devBar.RerollButton.Activated:Connect(function()
        ShowPreview(NewPreviewSeed())
    end)

    devBar.ExitButton.Activated:Connect(ExitPreview)
end

function ExpeditionController.Play()
    local run = GetRun()
    if not run or not selectedNode then return end

    local node = ExpeditionRules.GetNode(run, selectedNode)
    if not node then return end

    if ExpeditionRules.IsBattle(node.Type) then
        StartBattle(selectedNode)
        return
    end

    ExpeditionRemote:FireServer("Enter", selectedNode)
end

-- Brings the player back to the map after a battle from it
function ExpeditionController.ReturnToMap()
    if not isInBattle then return end

    isInBattle = false
    menu.Enabled = false
    screen.Enabled = true
end

local init = false
function ExpeditionController.Init(startMatchCallback, leaveMatchCallback)
    if init then return end
    init = true

    startMatch = startMatchCallback
    leaveMatch = leaveMatchCallback

    local playerGui = Players.LocalPlayer.PlayerGui
    menu = playerGui:WaitForChild("MainMenu")
    hud = playerGui:WaitForChild("GameHUD")
    screen = playerGui:WaitForChild("ExpeditionScreen")
    singleplayer = playerGui:WaitForChild("SingleplayerScreen")

    local root = screen:WaitForChild("Root")
    header = root:WaitForChild("Header")

    startView = root:WaitForChild("StartView")

    for _, mode in ipairs(ExpeditionConfig.MODES) do
        startView:WaitForChild(mode .. "Card").Activated:Connect(function()
            ExpeditionRemote:FireServer("Start", mode)
        end)
    end

    mapView = root:WaitForChild("MapView")

    local sheet = mapView:WaitForChild("Sheet")
    scroll = sheet:WaitForChild("Scroll")
    scroll.CanvasSize = UDim2.fromScale(0, CANVAS_HEIGHT)
    canvas = scroll:WaitForChild("Canvas")
    paperLayer = canvas:WaitForChild("Paper")
    routeLayer = canvas:WaitForChild("Routes")
    nodeLayer = canvas:WaitForChild("Nodes")

    legend = mapView:WaitForChild("Legend")
    legendPaper = legend:WaitForChild("Paper")
    legendList = legend:WaitForChild("List")
    legendEntryTemplate = legend:WaitForChild("EntryTemplate")

    local infoBar = mapView:WaitForChild("InfoBar")
    info = infoBar:WaitForChild("Info")
    rewards = infoBar:WaitForChild("Rewards")
    playButton = infoBar:WaitForChild("PlayButton")
    playButton.Activated:Connect(ExpeditionController.Play)

    runPanel = mapView:WaitForChild("RunPanel")
    ArmoryArt.SetIcon(runPanel:WaitForChild("Pouch"):WaitForChild("Icon"), "Pouch")

    local portrait = runPanel:WaitForChild("KingCard"):WaitForChild("PortraitFrame"):WaitForChild("Portrait")
    portrait.Image = SpriteConfig.ASSET_ID
    portrait.ImageRectOffset = Vector2.new(SpriteConfig.Teams.White + PORTRAIT_INSET,
        SpriteConfig.Pieces.King.Idle + SpriteConfig.HeadRows.King)
    portrait.ImageRectSize = Vector2.new(PORTRAIT_SIZE, PORTRAIT_SIZE)

    abandonPanel = root:WaitForChild("AbandonPanel")

    runPanel:WaitForChild("AbandonButton").Activated:Connect(function()
        abandonPanel.Visible = true
    end)

    abandonPanel:WaitForChild("ConfirmButton").Activated:Connect(function()
        abandonPanel.Visible = false
        ExpeditionRemote:FireServer("Abandon")
    end)

    abandonPanel:WaitForChild("CancelButton").Activated:Connect(function()
        abandonPanel.Visible = false
    end)

    noticePanel = root:WaitForChild("NoticePanel")
    noticePanel:WaitForChild("CloseButton").Activated:Connect(function()
        noticePanel.Visible = false
    end)

    artifactPrompt = root:WaitForChild("ArtifactPrompt")

    for i = 1, ExpeditionConfig.Artifacts.MAX do
        artifactPrompt:WaitForChild("Slots"):WaitForChild("Slot" .. i).Activated:Connect(function()
            ExpeditionRemote:FireServer("Artifact", "Replace", i)
        end)
    end

    artifactPrompt:WaitForChild("DeclineButton").Activated:Connect(function()
        ExpeditionRemote:FireServer("Artifact", "Decline")
    end)

    shopPanel = root:WaitForChild("ShopPanel")

    for i = 1, ExpeditionConfig.Shop.INVENTORY_SIZE do
        local buyButton = shopPanel:WaitForChild("Items"):WaitForChild("Item" .. i):WaitForChild("BuyButton")

        buyButton.Activated:Connect(function()
            if not buyButton:GetAttribute("Enabled") then return end
            ExpeditionRemote:FireServer("Buy", encounterNode, i)
        end)
    end

    shopPanel:WaitForChild("LeaveButton").Activated:Connect(function()
        ExpeditionRemote:FireServer("LeaveShop", encounterNode)
    end)

    treasurePanel = root:WaitForChild("TreasurePanel")
    treasureGrid = treasurePanel:WaitForChild("Grid")
    tileTemplate = treasurePanel:WaitForChild("TileTemplate")

    treasurePanel:WaitForChild("CloseButton").Activated:Connect(function()
        treasurePanel.Visible = false
    end)

    nodeTemplate = root:WaitForChild("NodeTemplate")
    dotTemplate = root:WaitForChild("LineTemplate")

    -- Rest Site
    restPanel = playerGui:WaitForChild("RestScreen"):WaitForChild("Root")

    -- The camp covers the whole screen and keeps its shape, cropping whichever edges overflow
    local restScene = restPanel:WaitForChild("Scene")

    local function FitRestScene()
        local size = restPanel.AbsoluteSize
        local width = math.max(size.X, size.Y * ExpeditionArt.REST_ASPECT)
        restScene.Size = UDim2.fromOffset(width, width / ExpeditionArt.REST_ASPECT)
    end

    restPanel:GetPropertyChangedSignal("AbsoluteSize"):Connect(FitRestScene)
    FitRestScene()

    restScene:WaitForChild("Background").Image = ExpeditionArt.REST_BACKGROUND
    restFire = restScene:WaitForChild("Fire")
    restFire.Image = ExpeditionArt.REST_FIRE
    restFire.ImageRectSize = ExpeditionArt.REST_FIRE_FRAME
    local fireRect = ExpeditionArt.REST_FIRE_RECT
    restFire.Position = UDim2.fromScale(fireRect[1], fireRect[2])
    restFire.Size = UDim2.fromScale(fireRect[3], fireRect[4])

    local restChoices = restPanel:WaitForChild("Choices")

    for choice in pairs(REST_TEXT) do
        local card = restChoices:WaitForChild(choice)
        card.Image = ExpeditionArt.REST_CARDS
        card.ImageRectSize = ExpeditionArt.REST_CARD_SIZE
        card.ImageRectOffset = Vector2.new(ExpeditionArt.RestCardOrder[choice] * ExpeditionArt.REST_CARD_SIZE.X, 0)

        local cardScale = card:WaitForChild("UIScale")
        card.MouseEnter:Connect(function()
            TweenService:Create(cardScale, TweenInfo.new(0.12), {Scale = 1.06}):Play()
        end)
        card.MouseLeave:Connect(function()
            TweenService:Create(cardScale, TweenInfo.new(0.12), {Scale = 1}):Play()
        end)

        card.Activated:Connect(function()
            cardScale.Scale = 1
            ExpeditionRemote:FireServer("Choose", encounterNode, choice)
        end)
    end

    restPanel:WaitForChild("CloseButton").Activated:Connect(function()
        restPanel.Visible = false
    end)

    -- Mystery encounters
    mysteryPanel = playerGui:WaitForChild("MysteryScreen"):WaitForChild("Root")

    -- Like the camp, each encounter's art covers the whole screen and keeps its shape
    local mysteryScene = mysteryPanel:WaitForChild("Scene")

    local function FitMysteryScene()
        local size = mysteryPanel.AbsoluteSize
        local width = math.max(size.X, size.Y * ExpeditionArt.MYSTERY_ASPECT)
        mysteryScene.Size = UDim2.fromOffset(width, width / ExpeditionArt.MYSTERY_ASPECT)
    end

    mysteryPanel:GetPropertyChangedSignal("AbsoluteSize"):Connect(FitMysteryScene)
    FitMysteryScene()

    mysteryBackground = mysteryScene:WaitForChild("Background")
    gunsmith = mysteryScene:WaitForChild("Gunsmith")
    gunsmith.Image = ExpeditionArt.GUNSMITH_SHEET
    gunsmith.ImageRectSize = ExpeditionArt.GUNSMITH_FRAME
    local smithRect = ExpeditionArt.GUNSMITH_RECT
    gunsmith.Position = UDim2.fromScale(smithRect[1], smithRect[2])
    gunsmith.Size = UDim2.fromScale(smithRect[3], smithRect[4])

    eyeGlow = mysteryScene:WaitForChild("EyeGlow")
    eyeGlow.Image = ExpeditionArt.EYE_WAKE
    local eyeRect = ExpeditionArt.EYE_RECT
    eyeGlow.Position = UDim2.fromScale(eyeRect[1], eyeRect[2])
    eyeGlow.Size = UDim2.fromScale(eyeRect[3], eyeRect[4])
    mysteryFade = mysteryPanel:WaitForChild("Fade")

    for i = 1, MAX_CHOICES do
        mysteryPanel:WaitForChild("Choices"):WaitForChild("Choice" .. i).Activated:Connect(function()
            ChooseEncounter(i)
        end)
    end

    mysteryPanel:WaitForChild("CloseButton").Activated:Connect(function()
        mysteryPanel.Visible = false
    end)

    BuildLegend()

    resultOverlay = hud:WaitForChild("ResultOverlay")
    local resultPanel = resultOverlay:WaitForChild("ResultPanel")
    resultTitle = resultPanel:WaitForChild("Title")
    resultRewards = resultPanel:WaitForChild("Rewards")

    resultPanel:WaitForChild("ContinueButton").Activated:Connect(function()
        resultOverlay.Visible = false
        leaveMatch()
        hud.Enabled = false
        menu.Enabled = true
        ExpeditionController.ReturnToMap()
    end)

    screen:WaitForChild("BackButton").Activated:Connect(function()
        if previewRun then
            ExitPreview()
        end

        screen.Enabled = false
        singleplayer.Enabled = true
    end)

    ExpeditionRemote.OnClientEvent:Connect(function(action, data)
        if action == "Encounter" then
            OnEncounter(data)
        elseif action == "EncounterFight" then
            mysteryPanel.Visible = false
            StartBattle(data.Node)
        elseif action == "Dig" then
            ShowDig(data)
        elseif action == "Result" then
            ShowResult(data)
        elseif action == "Started" then
            drawnAct = nil
            selectedNode = nil
        elseif action == "Abandoned" then
            drawnAct = nil
            ShowNotice("Expedition abandoned", "Your pouch and upgrades are gone.")
        end
    end)

    screen:GetPropertyChangedSignal("Enabled"):Connect(function()
        if not screen.Enabled then return end

        drawnAct = nil
        DrawMap()
    end)

    InitDevMaps(root)

    canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(Redraw)
    ProfileController.OnChanged(Redraw)
end

return ExpeditionController
