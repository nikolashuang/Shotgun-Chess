local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IndexConfig = require(ReplicatedStorage.Shared.UI.IndexConfig)
local PieceConfig = require(ReplicatedStorage.Shared.Board.PieceConfig)
local PieceRules = require(ReplicatedStorage.Shared.Board.PieceRules)
local ShotgunConfig = require(ReplicatedStorage.Shared.Combat.ShotgunConfig)
local ClassConfig = require(ReplicatedStorage.Shared.Combat.ClassConfig)
local CampaignConfig = require(ReplicatedStorage.Shared.Campaign.CampaignConfig)
local AnimatedSpriteClass = require(script.Parent.Parent.UI.AnimatedSpriteClass)

local SELECTED_COLOR = Color3.fromHex("F1D4AC")
local CARD_STROKE_COLOR = Color3.fromHex("9C574B")
local EMPTY_TILE_COLORS = {Color3.fromHex("D49A77"), Color3.fromHex("9C574B")}
local PIECE_TILE_COLOR = Color3.fromHex("332A35")
local MOVE_COLOR = Color3.fromHex("F1D4AC")
local ATTACK_COLOR = Color3.fromHex("C8453A")
local BOTH_COLOR = Color3.fromHex("E8843C")
-- The movement diagram is GRID_SIZE tiles across, centered on a piece standing at the middle of the board
local GRID_SIZE = 7
local CENTER = 5
-- Sliding pieces capture along the same rays they move on
local SLIDERS = {Rook = true, Bishop = true, Queen = true}

local cards = {}
local selectedId = nil
local info = nil
local portrait = nil
local gridTiles = {}

-- Turns the Index card grid and info panel into the enemy encyclopedia in the Armory
local IndexController = {}

local function GetKingWeapon()
    return ShotgunConfig.Shotguns[ShotgunConfig.ENEMY_KING]
end

local function GetDamageText(entry)
    if entry.Piece == "King" then
        local weapon = GetKingWeapon()
        return string.format("%d up close to %d at %d tiles (%s)", weapon.MaxDamage, weapon.MinDamage, weapon.MaxRange, weapon.DisplayName)
    end

    return tostring(PieceConfig.Damage[entry.Piece])
end

local function GetNotes(entry)
    if entry.Notes then return entry.Notes end

    -- Regional Kings: everything comes from the region and the class they hand out
    local region = CampaignConfig.Regions[entry.Region]
    local class = ClassConfig.Classes[entry.Outfit]
    local weapon = GetKingWeapon()

    return string.format("Rules %s and steps one tile in any direction. Shoots with a %s. Beat him to unlock the %s class.",
        region.DisplayName, weapon.DisplayName, class.DisplayName)
end

local function GetWhere(entry)
    if entry.Region then
        return "King fight: " .. CampaignConfig.Regions[entry.Region].DisplayName
    end

    return entry.Where
end

-- "Move", "Attack", "Both" or nil for each tile of the diagram, keyed by "column,row" on the board
local function GetTileStates(entry)
    local states = {}
    local pieceType = entry.Piece

    local function Mark(column, row, state)
        local key = column .. "," .. row
        local current = states[key]
        states[key] = (current and current ~= state) and "Both" or state
    end

    local function IsNever()
        return false
    end

    local function IsAlways()
        return true
    end

    for _, move in ipairs(PieceRules.GetMoves(pieceType, "Black", CENTER, CENTER, IsNever)) do
        Mark(move.Column, move.Row, "Move")

        if SLIDERS[pieceType] then
            Mark(move.Column, move.Row, "Attack")
        end
    end

    if pieceType == "King" then
        -- Kings shoot instead of capturing: anything within the shotgun's range can be hit
        local range = GetKingWeapon().MaxRange

        for column = CENTER - range, CENTER + range do
            for row = CENTER - range, CENTER + range do
                if column ~= CENTER or row ~= CENTER then
                    Mark(column, row, "Attack")
                end
            end
        end
    else
        for _, attack in ipairs(PieceRules.GetAttacks(pieceType, "Black", CENTER, CENTER, IsNever, IsAlways)) do
            Mark(attack.Column, attack.Row, "Attack")
        end
    end

    return states
end

local function DrawGrid(entry)
    local states = GetTileStates(entry)
    local half = (GRID_SIZE - 1) // 2

    for _, tile in pairs(gridTiles) do
        local column = CENTER - half + tile.X
        local row = CENTER + half - tile.Y
        local state = states[column .. "," .. row]

        if column == CENTER and row == CENTER then
            tile.Frame.BackgroundColor3 = PIECE_TILE_COLOR
        elseif state == "Move" then
            tile.Frame.BackgroundColor3 = MOVE_COLOR
        elseif state == "Attack" then
            tile.Frame.BackgroundColor3 = ATTACK_COLOR
        elseif state == "Both" then
            tile.Frame.BackgroundColor3 = BOTH_COLOR
        else
            tile.Frame.BackgroundColor3 = EMPTY_TILE_COLORS[(tile.X + tile.Y) % 2 + 1]
        end
    end
end

local function Select(entry)
    selectedId = entry.Id

    for id, card in pairs(cards) do
        card.UIStroke.Color = id == selectedId and SELECTED_COLOR or CARD_STROKE_COLOR
        card.UIStroke.Thickness = id == selectedId and 3 or 2
    end

    info.EnemyName.Text = entry.Name
    info.Where.Text = GetWhere(entry)
    info.Stats.Health.Text = "Health: " .. PieceConfig.Health[entry.Piece]
    info.Stats.Damage.Text = "Damage: " .. GetDamageText(entry)
    info.Notes.Text = GetNotes(entry)

    if portrait then
        portrait:Destroy()
    end

    portrait = AnimatedSpriteClass.new(entry.Piece, info.Portrait.Stage, "Black", entry.Outfit)
    portrait.Image.Size = UDim2.fromScale(1, 1)
    portrait.Image.ZIndex = info.Portrait.Stage.ZIndex + 1

    DrawGrid(entry)
end

local function BuildGrid(gridFrame)
    for y = 0, GRID_SIZE - 1 do
        for x = 0, GRID_SIZE - 1 do
            local frame = Instance.new("Frame")
            frame.Name = "Tile"
            frame.BorderSizePixel = 0
            frame.Size = UDim2.fromScale(1 / GRID_SIZE, 1 / GRID_SIZE)
            frame.Position = UDim2.fromScale(x / GRID_SIZE, y / GRID_SIZE)
            frame.ZIndex = gridFrame.ZIndex + 1
            frame.Parent = gridFrame

            table.insert(gridTiles, {X = x, Y = y, Frame = frame})
        end
    end
end

function IndexController.Build(box)
    local list = box:WaitForChild("List")
    local template = box:WaitForChild("EnemyCard")
    local layout = list:WaitForChild("UIGridLayout")
    info = box:WaitForChild("Info")

    BuildGrid(info:WaitForChild("MoveGrid"))

    for i = 1, IndexConfig.SLOTS do
        local entry = IndexConfig.Entries[i]
        local card = template:Clone()
        card.LayoutOrder = i
        card.Visible = true

        if entry then
            card.Name = entry.Id
            card.EnemyName.Text = entry.Name
            card.Unknown.Visible = false

            local sprite = AnimatedSpriteClass.new(entry.Piece, card.Stage, "Black", entry.Outfit)
            sprite.Image.Size = UDim2.fromScale(1, 1)
            sprite.Image.ZIndex = card.Stage.ZIndex + 1

            card.Activated:Connect(function()
                Select(entry)
            end)

            cards[entry.Id] = card
        else
            -- Room for enemies added later
            card.Name = "Empty" .. i
            card.EnemyName.Text = ""
            card.AutoButtonColor = false
        end

        card.Parent = list
    end

    -- Square cards at any screen size
    local function Resize()
        local width = list.AbsoluteSize.X * layout.CellSize.X.Scale
        layout.CellSize = UDim2.new(layout.CellSize.X.Scale, 0, 0, width)
    end

    list:GetPropertyChangedSignal("AbsoluteSize"):Connect(Resize)
    Resize()

    Select(IndexConfig.Entries[1])
end

return IndexController
