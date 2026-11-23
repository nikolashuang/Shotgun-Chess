local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local ProgressionConfig = require(ReplicatedStorage.Shared.Player.ProgressionConfig)
local MenuArt = require(ReplicatedStorage.Shared.UI.MenuArt)
local PlayerCard = require(script.Parent.Parent.UI.PlayerCard)

local HOVER_OFFSET = 0.02
local HOVER_TIME = 0.12

-- Dark text so the label reads on the gold ribbon
local HOVER_COLOR = Color3.fromHex("332A35")

-- The ribbon opens from its middle outward behind the label
local RIBBON_TIME = 0.2
-- Ribbon height as a fraction of the button's, and the gap left of and right of the text as a fraction of the ribbon's height
local RIBBON_HEIGHT = 1.3
local RIBBON_PADDING = 1.1
-- Pixels of the ribbon image that stretch with the text; the tails outside it keep their shape
local RIBBON_SLICE = Rect.new(24, 0, 90, 34)

local hoverResets = {}
local root = nil

local MenuController = {}

-- Shows the middle `amount` (0 to 1) of the ribbon by fading out everything left and right of it
local function SetRibbonReveal(ribbon, amount)
    ribbon.Visible = amount > 0.01

    if not ribbon.Visible then return end

    if amount >= 0.99 then
        ribbon.UIGradient.Transparency = NumberSequence.new(0)
        return
    end

    local left = 0.5 - amount / 2
    local right = 0.5 + amount / 2

    ribbon.UIGradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(left, 1),
        NumberSequenceKeypoint.new(left + 0.001, 0),
        NumberSequenceKeypoint.new(right - 0.001, 0),
        NumberSequenceKeypoint.new(right, 1),
        NumberSequenceKeypoint.new(1, 1),
    })
end

local function NewRibbon(button, label)
    local ribbon = Instance.new("ImageLabel")
    ribbon.Name = "Ribbon"
    ribbon.BackgroundTransparency = 1
    ribbon.Image = MenuArt.RIBBON
    ribbon.ResampleMode = Enum.ResamplerMode.Pixelated
    ribbon.ScaleType = Enum.ScaleType.Slice
    ribbon.SliceCenter = RIBBON_SLICE
    ribbon.AnchorPoint = Vector2.new(0.5, 0.5)
    ribbon.ZIndex = label.ZIndex
    ribbon.Interactable = false
    ribbon.Visible = false
    ribbon.Parent = button

    Instance.new("UIGradient").Parent = ribbon

    -- The label draws over the ribbon
    label.ZIndex += 1

    return ribbon
end

-- Fits the ribbon around the label's text at the button's current size
local function FitRibbon(ribbon, button, label)
    local height = button.AbsoluteSize.Y * RIBBON_HEIGHT
    local textWidth = label.TextBounds.X
    local textCenter = label.AbsolutePosition.X - button.AbsolutePosition.X + textWidth / 2

    -- Lines the band (not the whole image) up with the middle of the text
    local imageHeight = MenuArt.RIBBON_SIZE.Y
    local bandOffset = (imageHeight / 2 - MenuArt.RIBBON_BAND_CENTER) / imageHeight * height
    local textMiddle = label.AbsolutePosition.Y - button.AbsolutePosition.Y + label.AbsoluteSize.Y / 2

    ribbon.Size = UDim2.fromOffset(textWidth + height * RIBBON_PADDING * 2, height)
    ribbon.Position = UDim2.fromOffset(textCenter, textMiddle + bandOffset)
    -- Tails scale with the height so their pixels stay square
    ribbon.SliceScale = height / MenuArt.RIBBON_SIZE.Y
end

-- Hovering slides the button right and opens a gold ribbon behind its label from the middle outward
local function BindHover(button)
    local restPosition = button.Position
    local hoverPosition = restPosition + UDim2.fromScale(HOVER_OFFSET, 0)
    local label = button.Label
    local restColor = label.TextColor3
    local tweenInfo = TweenInfo.new(HOVER_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local ribbonInfo = TweenInfo.new(RIBBON_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local tween = nil
    local ribbonTween = nil

    local ribbon = NewRibbon(button, label)
    local reveal = Instance.new("NumberValue")

    reveal.Changed:Connect(function(amount)
        SetRibbonReveal(ribbon, amount)
    end)

    local function TweenTo(position, amount)
        if tween then
            tween:Cancel()
        end

        if ribbonTween then
            ribbonTween:Cancel()
        end

        tween = TweenService:Create(button, tweenInfo, {Position = position})
        tween:Play()

        ribbonTween = TweenService:Create(reveal, ribbonInfo, {Value = amount})
        ribbonTween:Play()
    end

    button.MouseEnter:Connect(function()
        FitRibbon(ribbon, button, label)
        TweenTo(hoverPosition, 1)
        label.TextColor3 = HOVER_COLOR
    end)

    button.MouseLeave:Connect(function()
        TweenTo(restPosition, 0)
        label.TextColor3 = restColor
    end)

    local function Reset()
        if tween then
            tween:Cancel()
        end

        if ribbonTween then
            ribbonTween:Cancel()
        end

        button.Position = restPosition
        label.TextColor3 = restColor
        reveal.Value = 0
    end

    -- Clicking closes the ribbon and slides the label back, even while the cursor is still on it
    button.Activated:Connect(Reset)

    -- MouseLeave never fires when the menu hides under the cursor, so this snaps the button back
    table.insert(hoverResets, Reset)
end

local function CloseAllPanels(root)
    for _, child in pairs(root:GetChildren()) do
        if child:IsA("GuiObject") and child.Name:sub(-5) == "Panel" then
            child.Visible = false
        end
    end
end

local function IsMultiplayerUnlocked()
    local level = Players.LocalPlayer:GetAttribute("Level") or ProgressionConfig.START_LEVEL

    return level >= ProgressionConfig.MULTIPLAYER_UNLOCK_LEVEL
end

local function UpdateMultiplayerLock(button)
    local isUnlocked = IsMultiplayerUnlocked()

    button.Label.Text = isUnlocked and "Multiplayer" or "Multiplayer [Lv " .. ProgressionConfig.MULTIPLAYER_UNLOCK_LEVEL .. "]"
    button.Label.TextTransparency = isUnlocked and 0 or 0.5
end


-- Background art covers the whole screen at any aspect ratio, cropping toward its Focus point
local function BindBackground(background)
    local art = background:WaitForChild("Art")
    local sourceSize = art:GetAttribute("SourceSize")
    local focus = art:GetAttribute("Focus")

    art.AnchorPoint = focus
    art.Position = UDim2.fromScale(focus.X, focus.Y)

    local function Fit()
        local screenSize = background.AbsoluteSize
        local scale = math.max(screenSize.X / sourceSize.X, screenSize.Y / sourceSize.Y)

        art.Size = UDim2.fromOffset(math.ceil(sourceSize.X * scale), math.ceil(sourceSize.Y * scale))
    end

    background:GetPropertyChangedSignal("AbsoluteSize"):Connect(Fit)
    Fit()
end

-- The campfire in the background art plays its frames while the menu is open
local function BindFire(menu, fire)
    local frameSize = MenuArt.FIRE_FRAME

    local fireRect = MenuArt.FIRE_RECT

    fire.Image = MenuArt.FIRE
    fire.ImageRectSize = frameSize
    fire.Position = UDim2.fromScale(fireRect[1], fireRect[2])
    fire.Size = UDim2.fromScale(fireRect[3], fireRect[4])

    -- Reopening the menu mid-frame starts a new loop, so the old one stops on its next frame
    local playing = 0

    local function Play()
        playing += 1
        local id = playing
        local frame = 0

        while menu.Enabled and id == playing do
            fire.ImageRectOffset = Vector2.new(frame % MenuArt.FIRE_COLUMNS * frameSize.X, frame // MenuArt.FIRE_COLUMNS * frameSize.Y)

            frame = (frame + 1) % MenuArt.FIRE_FRAMES
            task.wait(MenuArt.FIRE_TIME)
        end
    end

    menu:GetPropertyChangedSignal("Enabled"):Connect(function()
        if menu.Enabled then
            task.spawn(Play)
        end
    end)
    task.spawn(Play)
end

local init = false
-- openSettings shows the settings overlay over whatever screen is open, openPatchNotes the patch notes overlay
function MenuController.Init(openSettings, openPatchNotes)
    if init then return end
    init = true

    local player = Players.LocalPlayer
    local playerGui = player.PlayerGui
    local menu = playerGui:WaitForChild("MainMenu")
    root = menu:WaitForChild("Root")

    local background = menu:WaitForChild("Background")
    BindBackground(background)
    BindFire(menu, background.Art:WaitForChild("Fire"))
    PlayerCard.Bind(menu:WaitForChild("Profile"))

    local multiplayerButton = root:WaitForChild("MultiplayerButton")
    player:GetAttributeChangedSignal("Level"):Connect(function()
        UpdateMultiplayerLock(multiplayerButton)
    end)
    UpdateMultiplayerLock(multiplayerButton)

    -- Options with a <Option>Screen ScreenGui open it in place of the menu; its Menu button comes back
    local screens = {}

    for _, option in ipairs({"Singleplayer", "Multiplayer", "Armory", "Shop"}) do
        local screen = playerGui:WaitForChild(option .. "Screen")
        screens[option] = screen

        -- Screens with their own sub-views (Multiplayer) step back through them themselves
        if screen:GetAttribute("HandlesBack") then continue end

        screen:WaitForChild("BackButton").Activated:Connect(function()
            screen.Enabled = false
            menu.Enabled = true
        end)
    end

    -- Every screen keeps Settings beside its Menu button at the bottom right screen edge; Singleplayer wires its own
    for _, name in ipairs({"MultiplayerScreen", "ArmoryScreen", "ShopScreen", "CampaignScreen"}) do
        playerGui:WaitForChild(name):WaitForChild("SettingsButton").Activated:Connect(openSettings)
    end

    for _, button in pairs(root:GetChildren()) do
        if not button:IsA("TextButton") then continue end

        local option = button:GetAttribute("Menu")

        BindHover(button)

        button.Activated:Connect(function()
            if option == "Settings" then
                openSettings()
                return
            elseif option == "PatchNotes" then
                openPatchNotes()
                return
            end

            if option == "Multiplayer" and not IsMultiplayerUnlocked() then return end

            local screen = screens[option]
            if screen then
                menu.Enabled = false
                screen.Enabled = true
                return
            end

            -- Options with a matching panel toggle it and close the others
            local panel = root:FindFirstChild(option .. "Panel")
            if not panel then return end

            local isOpen = panel.Visible

            CloseAllPanels(root)
            panel.Visible = not isOpen
        end)
    end

    -- Leaving the menu resets it so returning from a match shows it fresh
    -- (done on hide so a panel opened on return, like the campaign map, isn't closed by this deferred handler)
    menu:GetPropertyChangedSignal("Enabled"):Connect(function()
        if menu.Enabled then return end

        for _, reset in pairs(hoverResets) do
            reset()
        end

        CloseAllPanels(root)
    end)
end

return MenuController
