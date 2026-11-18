local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local ProgressionConfig = require(ReplicatedStorage.Shared.Player.ProgressionConfig)
local ProgressionRules = require(ReplicatedStorage.Shared.Player.ProgressionRules)

local HOVER_OFFSET = 0.02
local HOVER_TIME = 0.12

local HOVER_COLOR = Color3.fromHex("F1D4AC")

local hoverResets = {}
local root = nil

local MenuController = {}

-- Menu buttons are plain text: hovering slides the label right and brightens it
local function BindHover(button)
    local restPosition = button.Position
    local hoverPosition = restPosition + UDim2.fromScale(HOVER_OFFSET, 0)
    local label = button.Label
    local restColor = label.TextColor3
    local tweenInfo = TweenInfo.new(HOVER_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local tween = nil

    local function TweenTo(position)
        if tween then
            tween:Cancel()
        end

        tween = TweenService:Create(button, tweenInfo, {Position = position})
        tween:Play()
    end

    button.MouseEnter:Connect(function()
        TweenTo(hoverPosition)
        label.TextColor3 = HOVER_COLOR
    end)

    button.MouseLeave:Connect(function()
        TweenTo(restPosition)
        label.TextColor3 = restColor
    end)

    -- MouseLeave never fires when the menu hides under the cursor, so this snaps the button back
    table.insert(hoverResets, function()
        if tween then
            tween:Cancel()
        end

        button.Position = restPosition
        label.TextColor3 = restColor
    end)
end

local function CloseAllPanels(root)
    for _, child in pairs(root:GetChildren()) do
        if child:IsA("GuiObject") and child.Name:sub(-5) == "Panel" then
            child.Visible = false
        end
    end
end

local function IsDuelsUnlocked()
    local level = Players.LocalPlayer:GetAttribute("Level") or ProgressionConfig.START_LEVEL

    return level >= ProgressionConfig.DUELS_UNLOCK_LEVEL
end

local function UpdateDuelsLock(button)
    local isUnlocked = IsDuelsUnlocked()

    button.Label.Text = isUnlocked and "Duels" or "Duels [Lv " .. ProgressionConfig.DUELS_UNLOCK_LEVEL .. "]"
    button.Label.TextTransparency = isUnlocked and 0 or 0.5
end

-- Level, Exp and Gold are player attributes set by the server profile
local function BindProfile(profile)
    local player = Players.LocalPlayer

    profile.Username.Text = player.Name

    task.spawn(function()
        local ok, image = pcall(function()
            return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
        end)

        if ok then
            profile.AvatarFrame.Avatar.Image = image
        end
    end)

    local function UpdateProgress()
        local level = player:GetAttribute("Level") or ProgressionConfig.START_LEVEL
        local exp = player:GetAttribute("Exp") or 0
        local needed = ProgressionRules.GetExpToLevel(level)

        profile.Level.Text = "Lv " .. level
        profile.Exp.Text = string.format("%d/%d XP", exp, needed)
        profile.ExpBar.Fill.Size = UDim2.fromScale(math.clamp(exp / needed, 0, 1), 1)
    end

    local function UpdateGold()
        profile.Gold.Text = (player:GetAttribute("Gold") or 0) .. " Gold"
    end

    player:GetAttributeChangedSignal("Level"):Connect(UpdateProgress)
    player:GetAttributeChangedSignal("Exp"):Connect(UpdateProgress)
    player:GetAttributeChangedSignal("Gold"):Connect(UpdateGold)
    UpdateProgress()
    UpdateGold()
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

local init = false
function MenuController.Init(startMatch)
    if init then return end
    init = true

    local player = Players.LocalPlayer
    local playerGui = player.PlayerGui
    local menu = playerGui:WaitForChild("MainMenu")
    local hud = playerGui:WaitForChild("GameHUD")
    local campaign = playerGui:WaitForChild("CampaignScreen")
    root = menu:WaitForChild("Root")

    BindBackground(menu:WaitForChild("Background"))
    BindProfile(menu:WaitForChild("Profile"))

    local duelsButton = root:WaitForChild("DuelsButton")
    player:GetAttributeChangedSignal("Level"):Connect(function()
        UpdateDuelsLock(duelsButton)
    end)
    UpdateDuelsLock(duelsButton)

    for _, button in pairs(root:GetChildren()) do
        if not button:IsA("TextButton") then continue end

        local option = button:GetAttribute("Menu")

        BindHover(button)

        button.Activated:Connect(function()
            -- Campaign has its own screen; Duels starts a match once unlocked
            if option == "Campaign" then
                menu.Enabled = false
                campaign.Enabled = true
                return
            elseif option == "Duels" then
                if not IsDuelsUnlocked() then return end

                menu.Enabled = false
                hud.Enabled = true
                startMatch("Duel")
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
