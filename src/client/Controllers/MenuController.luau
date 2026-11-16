local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local ProgressionConfig = require(ReplicatedStorage.Shared.Player.ProgressionConfig)

local HOVER_OFFSET = 0.02
local HOVER_TIME = 0.12

local HOVER_STROKE = Color3.fromHex("E6C47C")
local DEFAULT_STROKE = Color3.fromHex("354867")

local MenuController = {}

local function BindHover(button)
    local restPosition = button.Position
    local hoverPosition = restPosition + UDim2.fromScale(HOVER_OFFSET, 0)
    local stroke = button:FindFirstChildOfClass("UIStroke")
    local tweenInfo = TweenInfo.new(HOVER_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    button.MouseEnter:Connect(function()
        TweenService:Create(button, tweenInfo, {Position = hoverPosition}):Play()
        stroke.Color = HOVER_STROKE
    end)

    button.MouseLeave:Connect(function()
        TweenService:Create(button, tweenInfo, {Position = restPosition}):Play()
        stroke.Color = DEFAULT_STROKE
    end)
end

-- Level and Exp are read from player attributes once a progression system sets them
local function BindProfile(profile)
    local player = Players.LocalPlayer

    profile.Username.Text = string.upper(player.Name)

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

        profile.Level.Text = "LV " .. level
        profile.Exp.Text = string.format("%d/%d XP", exp, ProgressionConfig.EXP_PER_LEVEL)
        profile.ExpBar.Fill.Size = UDim2.fromScale(math.clamp(exp / ProgressionConfig.EXP_PER_LEVEL, 0, 1), 1)
    end

    player:GetAttributeChangedSignal("Level"):Connect(UpdateProgress)
    player:GetAttributeChangedSignal("Exp"):Connect(UpdateProgress)
    UpdateProgress()
end

local init = false
function MenuController.Init(startMatch)
    if init then return end
    init = true

    local playerGui = Players.LocalPlayer.PlayerGui
    local menu = playerGui:WaitForChild("MainMenu")
    local hud = playerGui:WaitForChild("GameHUD")
    local root = menu:WaitForChild("Root")

    BindProfile(root:WaitForChild("Profile"))

    for _, button in pairs(root:GetChildren()) do
        if not button:IsA("TextButton") then continue end

        local option = button:GetAttribute("Menu")

        BindHover(button)

        button.Activated:Connect(function()
            if option == "Campaign" or option == "Duels" then
                menu.Enabled = false
                hud.Enabled = true
                startMatch()
            end
        end)
    end
end

return MenuController
