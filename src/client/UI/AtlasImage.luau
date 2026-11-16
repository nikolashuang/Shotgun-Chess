local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SpriteConfig = require(ReplicatedStorage.Shared.Sprites.SpriteConfig)

-- UI ImageLabels that show one rect from the sprite atlas, keeping its aspect ratio
local AtlasImage = {}

function AtlasImage.SetRect(image, rectName)
    local rect = SpriteConfig.Rects[rectName]

    image.Image = SpriteConfig.ASSET_ID
    image.ImageRectOffset = Vector2.new(rect[1], rect[2])
    image.ImageRectSize = Vector2.new(rect[3], rect[4])
    image.ResampleMode = Enum.ResamplerMode.Pixelated

    local ratio = image:FindFirstChildOfClass("UIAspectRatioConstraint")
    if not ratio then
        ratio = Instance.new("UIAspectRatioConstraint")
        ratio.Parent = image
    end

    ratio.AspectRatio = rect[3] / rect[4]
end

function AtlasImage.New(name, rectName)
    local image = Instance.new("ImageLabel")
    image.Name = name
    image.BackgroundTransparency = 1
    image.Size = UDim2.fromScale(1, 1)
    AtlasImage.SetRect(image, rectName)

    return image
end

return AtlasImage
