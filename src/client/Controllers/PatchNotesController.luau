local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PatchNotes = require(ReplicatedStorage.Shared.UI.PatchNotes)

-- Notes text height as a fraction of the page's height, so it scales with the screen
local TEXT_SCALE = 0.04

local overlay = nil

-- The patch notes overlay opened from the main menu: pick a major version (Version 0, Version 1 ...) and one of
-- its minor versions (0.1, 0.2 ...) to list that minor's releases; plus the version label that sits over every screen
local PatchNotesController = {}

local function FormatRelease(release)
    local header = string.format("<b>v%s - %s</b>", release.Version, release.Title)

    if release.Date then
        header ..= string.format("  <font transparency=\"0.4\">%s</font>", release.Date)
    end

    local lines = {header}

    for _, note in ipairs(release.Notes) do
        table.insert(lines, "• " .. note)
    end

    return table.concat(lines, "\n")
end

-- Majors, each with its minors, each with its releases, all newest first; Releases is already newest first
local function BuildVersions()
    local majors = {}

    for _, release in ipairs(PatchNotes.Releases) do
        local majorKey, minorKey = release.Version:match("^(%d+)%.(%d+)")
        local major = majors[#majors]

        if not major or major.Key ~= majorKey then
            major = {Key = majorKey, Minors = {}}
            table.insert(majors, major)
        end

        local minor = major.Minors[#major.Minors]

        if not minor or minor.Key ~= minorKey then
            minor = {Key = minorKey, Releases = {}}
            table.insert(major.Minors, minor)
        end

        table.insert(minor.Releases, release)
    end

    return majors
end

local showLatest = nil

function PatchNotesController.Open()
    showLatest()
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
    local majorPicker = page:WaitForChild("MajorPicker")
    local minorPicker = page:WaitForChild("MinorPicker")

    local majors = BuildVersions()
    local majorIndex = 1
    local minorIndex = 1
    local entries = {}

    for _, major in ipairs(majors) do
        for _, minor in ipairs(major.Minors) do
            for i, release in ipairs(minor.Releases) do
                local entry = template:Clone()
                entry.Name = release.Version
                entry.LayoutOrder = i
                entry.Text = FormatRelease(release)
                entry.Visible = false
                entry.Parent = list

                entry:SetAttribute("Minor", major.Key .. "." .. minor.Key)
                table.insert(entries, entry)
            end
        end
    end

    -- ◀ steps to newer versions, ▶ to older ones; each arrow hides at its end
    local function DrawPicker(picker, text, index, count)
        picker.Label.Text = text
        picker.PrevButton.Visible = index > 1
        picker.NextButton.Visible = index < count
    end

    local function Show()
        local major = majors[majorIndex]
        local minor = major.Minors[minorIndex]
        local key = major.Key .. "." .. minor.Key

        for _, entry in ipairs(entries) do
            entry.Visible = entry:GetAttribute("Minor") == key
        end

        DrawPicker(majorPicker, "Version " .. major.Key, majorIndex, #majors)
        DrawPicker(minorPicker, "v" .. key, minorIndex, #major.Minors)
        list.CanvasPosition = Vector2.zero
    end

    -- Changing the major opens its newest minor
    local function SetMajor(index)
        majorIndex = math.clamp(index, 1, #majors)
        minorIndex = 1
        Show()
    end

    local function SetMinor(index)
        minorIndex = math.clamp(index, 1, #majors[majorIndex].Minors)
        Show()
    end

    showLatest = function()
        SetMajor(1)
    end

    majorPicker.PrevButton.Activated:Connect(function() SetMajor(majorIndex - 1) end)
    majorPicker.NextButton.Activated:Connect(function() SetMajor(majorIndex + 1) end)
    minorPicker.PrevButton.Activated:Connect(function() SetMinor(minorIndex - 1) end)
    minorPicker.NextButton.Activated:Connect(function() SetMinor(minorIndex + 1) end)

    showLatest()

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
