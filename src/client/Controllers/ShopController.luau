local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")

local ShotgunConfig = require(ReplicatedStorage.Shared.Combat.ShotgunConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Shop.ShopConfig)
local SpriteConfig = require(ReplicatedStorage.Shared.Sprites.SpriteConfig)
local SkinConfig = require(ReplicatedStorage.Shared.Skins.SkinConfig)
local AtlasImage = require(script.Parent.Parent.UI.AtlasImage)
local PlayerCard = require(script.Parent.Parent.UI.PlayerCard)
local ProfileController = require(script.Parent.ProfileController)
local BoardSkinController = require(script.Parent.BoardSkinController)

local LoadoutRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("LoadoutRemote")
local CrateRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CrateRemote")

local AFFORDABLE_COLOR = Color3.fromHex("F1D4AC")
local OWNED_COLOR = Color3.fromHex("D49A77")
local LOCKED_COLOR = Color3.fromHex("C8644F")
local NOTICE_TIME = 1.5
local SINGLE_CELL = UDim2.fromScale(0.3, 1)
local MULTI_CELL = UDim2.fromScale(0.18, 0.48)
local PULSE_SCALE = 1.18
local PULSE_TIME = 0.5
-- Pulsing tags become a tilted sale badge hanging off the card's top right corner
local BADGE_COLOR = Color3.fromHex("C8644F")
local BADGE_TEXT_COLOR = Color3.fromHex("F1D4AC")
local BADGE_STROKE_COLOR = Color3.fromHex("271F29")
local BADGE_TILT = 12
-- Shotgun row width over height, so rows keep their shape at any screen size
local ROW_ASPECT = 11

local player = Players.LocalPlayer
local rows = {}
local boostCards = {}
local crateIndex = 1
local crates = nil
local crateResult = nil
local resultTemplate = nil

-- The shop is one scrolling page: featured skins and skin crates, shotguns, gold packs, 2x boosts and donations
-- Crates are rolled on the server; the results popup shows each drop and any duplicate refund
-- Shotguns are bought with gold (the server checks price and ownership); everything with a Robux price is a Developer Product
local ShopController = {}

local function FormatNumber(number)
    local text = tostring(number)

    while true do
        local formatted, count = string.gsub(text, "^(%d+)(%d%d%d)", "%1,%2")
        text = formatted
        if count == 0 then return text end
    end
end

local function FormatTime(seconds)
    seconds = math.ceil(seconds)

    return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- Briefly swaps a label's text, then puts it back
local function Flash(label, text)
    local original = label:GetAttribute("Original") or label.Text
    label:SetAttribute("Original", original)
    label.Text = text

    task.delay(NOTICE_TIME, function()
        label.Text = original
    end)
end

-- Products without an id haven't been created on the experience yet
local function Prompt(item, label)
    if item.ProductId == 0 then
        Flash(label, "Coming Soon")
        return
    end

    MarketplaceService:PromptProductPurchase(player, item.ProductId)
end

local function RefreshShotguns()
    local gold = player:GetAttribute("Gold") or 0

    for name, row in pairs(rows) do
        local weapon = ShotgunConfig.Shotguns[name]

        if ProfileController.Data.Shotguns[name] then
            row.Tag.Text = "Owned"
            row.Tag.TextColor3 = OWNED_COLOR
        elseif gold >= weapon.Price then
            row.Tag.Text = "Buy"
            row.Tag.TextColor3 = AFFORDABLE_COLOR
        else
            row.Tag.Text = "Locked"
            row.Tag.TextColor3 = LOCKED_COLOR
        end
    end
end

local function RefreshBoosts()
    for kind, card in pairs(boostCards) do
        local left = player:GetAttribute(kind .. "Boost") or 0

        card.Status.Text = left > 0 and "Active: " .. FormatTime(left) .. " left" or "Not active"
        card.Status.TextColor3 = left > 0 and AFFORDABLE_COLOR or OWNED_COLOR
    end
end

local function BuildShotguns(list, template)
    for i, name in ipairs(ShotgunConfig.ORDER) do
        local weapon = ShotgunConfig.Shotguns[name]

        local row = template:Clone()
        row.Name = name
        row.Label.Text = weapon.DisplayName
        row.Price.Text = weapon.Price > 0 and FormatNumber(weapon.Price) .. " Gold" or "Starter"
        row.LayoutOrder = i
        AtlasImage.SetRect(row.Icon, SpriteConfig.Guns[name].Rect)
        row.Visible = true
        row.Parent = list

        row.Activated:Connect(function()
            if ProfileController.Data.Shotguns[name] then return end
            if (player:GetAttribute("Gold") or 0) < weapon.Price then return end

            LoadoutRemote:FireServer("Buy", "Shotgun", name)
        end)

        rows[name] = row
    end
end

local function GetCrateId()
    return SkinConfig.CRATE_ORDER[crateIndex]
end

local function ShowCrate()
    local crateId = GetCrateId()
    local crate = SkinConfig.Crates[crateId]

    crates.Title.Text = crate.DisplayName
    crates.OpenOne.Label.Text = "1 Crate - " .. FormatNumber(crate.Price) .. " Gold"
    crates.OpenTen.Label.Text = "10 Crates - " .. FormatNumber(crate.TenPrice) .. " Gold"

    if SkinConfig.CanOpen(crateId) then
        local odds = {}

        for _, rarity in ipairs(SkinConfig.RARITY_ORDER) do
            table.insert(odds, SkinConfig.Rarities[rarity].DisplayName .. " " .. SkinConfig.Rarities[rarity].Weight .. "%")
        end

        -- Two rarities per line
        crates.Body.Text = odds[1] .. "   " .. odds[2] .. "\n" .. odds[3] .. "   " .. odds[4]
    else
        crates.Body.Text = "Coming Soon"
    end
end

local function OpenCrate(count, label)
    local crateId = GetCrateId()
    local crate = SkinConfig.Crates[crateId]
    local price = count == 1 and crate.Price or crate.TenPrice

    if not SkinConfig.CanOpen(crateId) then
        Flash(label, "Coming Soon")
    elseif (player:GetAttribute("Gold") or 0) < price then
        Flash(label, "Not enough Gold")
    else
        CrateRemote:FireServer("Open", crateId, count)
    end
end

local function ShowResults(crateId, results)
    for _, card in pairs(crateResult.Panel.Results:GetChildren()) do
        if card:IsA("GuiObject") then
            card:Destroy()
        end
    end

    -- A single drop gets one big card; a 10-pack fills two rows
    crateResult.Panel.Results.UIGridLayout.CellSize = #results == 1 and SINGLE_CELL or MULTI_CELL

    local refund = 0

    for i, result in ipairs(results) do
        local skin = SkinConfig.Skins[SkinConfig.Crates[crateId].Kind][result.Name]
        local rarity = SkinConfig.Rarities[skin.Rarity]

        local card = resultTemplate:Clone()
        card.LayoutOrder = i
        card.SkinName.Text = skin.DisplayName
        card.Rarity.Text = rarity.DisplayName
        card.Rarity.TextColor3 = rarity.Color
        card.UIStroke.Color = rarity.Color
        card.Note.Text = result.Duplicate and "Duplicate +" .. FormatNumber(result.Refund) .. " Gold" or "New!"
        card.Note.TextColor3 = result.Duplicate and OWNED_COLOR or AFFORDABLE_COLOR
        BoardSkinController.BuildPreview(card.Preview, result.Name)
        card.Parent = crateResult.Panel.Results

        refund += result.Refund
    end

    crateResult.Panel.Title.Text = SkinConfig.Crates[crateId].DisplayName
    crateResult.Panel.Summary.Text = refund > 0 and "Duplicates refunded " .. FormatNumber(refund) .. " Gold" or "Equip new boards in the Armory"
    crateResult.Visible = true
end

local function BuildCards(container, template, items, fill)
    for i, item in ipairs(items) do
        local card = template:Clone()
        card.Name = item.Id
        card.LayoutOrder = i
        card.Visible = true
        fill(card, item)
        card.Parent = container

        card.Buy.Activated:Connect(function()
            Prompt(item, card.Buy.Label)
        end)
    end
end

-- Sections are sized from the page's width (each has an Aspect attribute), and the canvas follows the layout
local function BindPage(page, shotgunList)
    local layout = page:WaitForChild("UIListLayout")
    local padding = page:WaitForChild("UIPadding")
    local listLayout = shotgunList:WaitForChild("UIListLayout")

    local function Resize()
        local width = page.AbsoluteSize.X - padding.PaddingLeft.Offset - padding.PaddingRight.Offset - page.ScrollBarThickness

        for _, section in pairs(page:GetChildren()) do
            local aspect = section:GetAttribute("Aspect")

            if aspect then
                section.Size = UDim2.new(1, 0, 0, width / aspect)
            end
        end

        local rowHeight = width / ROW_ASPECT
        local count = #ShotgunConfig.ORDER

        for _, row in pairs(rows) do
            row.Size = UDim2.new(1, 0, 0, rowHeight)
        end

        shotgunList.Size = UDim2.new(1, 0, 0, rowHeight * count + listLayout.Padding.Offset * (count - 1))
    end

    local function UpdateCanvas()
        page.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + padding.PaddingTop.Offset + padding.PaddingBottom.Offset)
    end

    page.AutomaticCanvasSize = Enum.AutomaticSize.None
    page:GetPropertyChangedSignal("AbsoluteSize"):Connect(Resize)
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(UpdateCanvas)
    Resize()
    UpdateCanvas()
end

local init = false
function ShopController.Init()
    if init then return end
    init = true

    local screen = player.PlayerGui:WaitForChild("ShopScreen")
    local root = screen:WaitForChild("Root")
    local page = root:WaitForChild("Page")
    local templates = root:WaitForChild("Templates")

    -- Arrows cycle the crate types; crates without skins yet say Coming Soon
    crates = page:WaitForChild("TopRow"):WaitForChild("Crates")
    crateResult = screen:WaitForChild("CrateResult")
    resultTemplate = templates:WaitForChild("ResultCard")

    crates.Prev.Activated:Connect(function()
        crateIndex = (crateIndex - 2) % #SkinConfig.CRATE_ORDER + 1
        ShowCrate()
    end)

    crates.Next.Activated:Connect(function()
        crateIndex = crateIndex % #SkinConfig.CRATE_ORDER + 1
        ShowCrate()
    end)

    crates.OpenOne.Activated:Connect(function()
        OpenCrate(1, crates.OpenOne.Label)
    end)

    crates.OpenTen.Activated:Connect(function()
        OpenCrate(10, crates.OpenTen.Label)
    end)

    crateResult.Panel.Close.Activated:Connect(function()
        crateResult.Visible = false
    end)

    CrateRemote.OnClientEvent:Connect(function(action, crateId, results)
        if action == "Opened" then
            ShowResults(crateId, results)
        end
    end)

    ShowCrate()

    local shotgunList = page:WaitForChild("ShotgunList")
    BuildShotguns(shotgunList, templates:WaitForChild("ShotgunRow"))

    BuildCards(page:WaitForChild("GoldRow"), templates:WaitForChild("GoldCard"), ShopConfig.GoldPacks, function(card, item)
        card.Amount.Text = FormatNumber(item.Gold) .. " Gold"
        card.Tag.Text = item.Tag or ""

        if item.Pulse then
            local tag = card.Tag

            -- Anchored at its center so the pulse grows and shrinks in place
            tag.AnchorPoint = Vector2.new(0.5, 0.5)
            tag.Position = UDim2.fromScale(0.8, 0.03)
            tag.Size = UDim2.fromScale(0.62, 0.15)
            tag.Rotation = BADGE_TILT
            tag.ZIndex = 3
            -- Drawn above the next card, which the badge hangs over
            card.ZIndex = 2
            tag.BackgroundColor3 = BADGE_COLOR
            tag.BackgroundTransparency = 0
            tag.TextColor3 = BADGE_TEXT_COLOR
            tag.TextXAlignment = Enum.TextXAlignment.Center

            local stroke = Instance.new("UIStroke")
            stroke.Color = BADGE_STROKE_COLOR
            stroke.Thickness = 2
            stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            stroke.Parent = tag

            local padding = Instance.new("UIPadding")
            padding.PaddingTop = UDim.new(0.12, 0)
            padding.PaddingBottom = UDim.new(0.12, 0)
            padding.Parent = tag

            local scale = Instance.new("UIScale")
            scale.Parent = tag

            TweenService:Create(scale, TweenInfo.new(PULSE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
                Scale = PULSE_SCALE,
            }):Play()
        end
        card.Buy.Label.Text = "R$ " .. FormatNumber(item.Robux)
    end)

    BuildCards(page:WaitForChild("BoostRow"), templates:WaitForChild("BoostCard"), ShopConfig.Boosts, function(card, item)
        card.Title.Text = item.DisplayName
        card.Duration.Text = ShopConfig.BOOST_SECONDS // 3600 .. " hour of play time"
        card.Buy.Label.Text = "R$ " .. FormatNumber(item.Robux)
        boostCards[item.Kind] = card
    end)

    BuildCards(page:WaitForChild("DonationRow"), templates:WaitForChild("DonationCard"), ShopConfig.Donations, function(card, item)
        card.Buy.Label.Text = "R$ " .. FormatNumber(item.Robux)
    end)

    BindPage(page, shotgunList)

    player:GetAttributeChangedSignal("Gold"):Connect(RefreshShotguns)
    player:GetAttributeChangedSignal("GoldBoost"):Connect(RefreshBoosts)
    player:GetAttributeChangedSignal("ExpBoost"):Connect(RefreshBoosts)
    ProfileController.OnChanged(RefreshShotguns)
    RefreshShotguns()
    RefreshBoosts()

    PlayerCard.Bind(screen:WaitForChild("Profile"))
end

return ShopController
