local PixelSprite = {}

function PixelSprite.Draw(parent, mask, palette)
    local rows = #mask
    local columns = #mask[1]

    local ratio = Instance.new("UIAspectRatioConstraint")
    ratio.AspectRatio = columns / rows
    ratio.Parent = parent

    for r, line in ipairs(mask) do
        local c = 1

        while c <= columns do
            local char = line:sub(c, c)
            local runEnd = c

            while runEnd < columns and line:sub(runEnd + 1, runEnd + 1) == char do
                runEnd += 1
            end

            local color = palette[char]
            if color then
                local pixel = Instance.new("Frame")
                pixel.Name = "Pixel"
                pixel.BorderSizePixel = 0
                pixel.BackgroundColor3 = color
                pixel.Position = UDim2.fromScale((c - 1) / columns, (r - 1) / rows)
                pixel.Size = UDim2.fromScale((runEnd - c + 1) / columns, 1 / rows)
                pixel.Parent = parent
            end

            c = runEnd + 1
        end
    end
end

return PixelSprite
