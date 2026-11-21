local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PatchNotes = require(ReplicatedStorage.Shared.UI.PatchNotes)

-- Notes text height as a fraction of the page's height, so it scales with the screen
local TEXT_SCALE = 0.04

local overlay = nil

-- The patch notes overlay opened from the main menu, one entry per release in a scrolling list,
-- and the version label that sits over every screen
local PatchNotesController = {}

local function FormatRelease(release)
    local lines = {string.format("<b>v%s - %s</b>", release.Version, release.Title)}

    for _, note in ipairs(release.Notes) do
        table.insert(lines, "• " .. note)
    end

    return table.concat(lines, "\n")
end

function PatchNotesController.Open()
    overlay.Enabled = true
end

function PatchNotesController.Close()
    overlay.Enabled = false
end

local init = false
function PatchNotesController.Init()
    if init then return end
    init = true

    local playerGui = Players.LocalPlayer.PlayerGui

    playerGui:WaitForChild("VersionGui"):WaitForChild("Version").Text = "v" .. PatchNotes.VERSION

    overlay = playerGui:WaitForChild("PatchNotesOverlay")
    local page = overlay:WaitForChild("Page")
    local list = page:WaitForChild("List")
    local template = page:WaitForChild("EntryTemplate")
    local entries = {}

    for i, release in ipairs(PatchNotes.Releases) do
        local entry = template:Clone()
        entry.Name = release.Version
        entry.LayoutOrder = i
        entry.Text = FormatRelease(release)
        entry.Visible = true
        entry.Parent = list

        table.insert(entries, entry)
    end

    local function Resize()
        local size = math.max(math.floor(page.AbsoluteSize.Y * TEXT_SCALE), 10)

        for _, entry in ipairs(entries) do
            entry.TextSize = size
        end
    end

    page:GetPropertyChangedSignal("AbsoluteSize"):Connect(Resize)
    Resize()

    page:WaitForChild("CloseButton").Activated:Connect(PatchNotesController.Close)
end

return PatchNotesController
