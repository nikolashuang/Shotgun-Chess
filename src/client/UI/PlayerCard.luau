local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ProgressionConfig = require(ReplicatedStorage.Shared.Player.ProgressionConfig)
local ProgressionRules = require(ReplicatedStorage.Shared.Player.ProgressionRules)

-- The player info card (avatar, name, level, XP and gold) shown on the main menu, Armory and Shop
local PlayerCard = {}

-- Level, Exp and Gold are player attributes set by the server profile
function PlayerCard.Bind(card)
    local player = Players.LocalPlayer

    card.Username.Text = player.Name

    task.spawn(function()
        local ok, image = pcall(function()
            return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
        end)

        if ok then
            card.AvatarFrame.Avatar.Image = image
        end
    end)

    local function UpdateProgress()
        local level = player:GetAttribute("Level") or ProgressionConfig.START_LEVEL
        local exp = player:GetAttribute("Exp") or 0
        local needed = ProgressionRules.GetExpToLevel(level)

        card.Level.Text = "Lv " .. level
        card.Exp.Text = string.format("%d/%d XP", exp, needed)
        card.ExpBar.Fill.Size = UDim2.fromScale(math.clamp(exp / needed, 0, 1), 1)
    end

    local function UpdateGold()
        card.Gold.Text = (player:GetAttribute("Gold") or 0) .. " Gold"
    end

    player:GetAttributeChangedSignal("Level"):Connect(UpdateProgress)
    player:GetAttributeChangedSignal("Exp"):Connect(UpdateProgress)
    player:GetAttributeChangedSignal("Gold"):Connect(UpdateGold)
    UpdateProgress()
    UpdateGold()
end

return PlayerCard
