local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local KeybindConfig = require(ReplicatedStorage.Shared.Player.KeybindConfig)
local SettingsConfig = require(ReplicatedStorage.Shared.Player.SettingsConfig)
local CrtController = require(script.Parent.CrtController)
local ProfileController = require(script.Parent.ProfileController)

local ProfileRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ProfileRemote")

local WAITING_COLOR = Color3.fromHex("F1D4AC")
local DEFAULT_COLOR = Color3.fromHex("9C574B")
-- Slider settings, each driving the SoundGroup of the same name
local VOLUMES = {"Sound", "Music"}

local input = nil
local overlay = nil
local settingsPage = nil
local keybindsPage = nil
local rows = {}
local sliders = {}
local volumes = {}
local crtValue = nil
local capturingAction = nil
local draggingSlider = nil

-- Settings overlay shared by the main menu and matches: volumes, CRT filter and a keybinds page
-- Keybinds only last for the session until they are saved to a profile; the other settings are saved
local SettingsController = {}

local function Refresh()
    for _, row in pairs(rows) do
        local action = row.Name
        local isCapturing = action == capturingAction

        row.Key.Text = isCapturing and "Press a key" or input.GetKeyLabel(input.GetBinding(action))
        row.Key.UIStroke.Color = isCapturing and WAITING_COLOR or DEFAULT_COLOR
    end
end

local function StopCapture()
    capturingAction = nil
    input.CancelCapture()
    Refresh()
end

-- Escape cancels; reserved keys are ignored
local function StartCapture(action)
    capturingAction = action
    Refresh()

    input.CaptureNextKey(function(keyCode)
        if keyCode ~= Enum.KeyCode.Escape then
            input.SetBinding(action, keyCode)
        end

        StopCapture()
    end)
end

local function BindKeybinds(page)
    local template = page:WaitForChild("Template")

    for i, action in ipairs(KeybindConfig.ORDER) do
        local row = template:Clone()
        row.Name = action
        row.Label.Text = KeybindConfig.DisplayNames[action]
        row.LayoutOrder = i
        row.Visible = true
        row.Parent = page.List

        row.Key.Activated:Connect(function()
            if capturingAction == action then
                StopCapture()
            else
                StartCapture(action)
            end
        end)

        table.insert(rows, row)
    end

    page:WaitForChild("ResetButton").Activated:Connect(function()
        StopCapture()
        input.ResetBindings()
    end)

    -- Closing the page mid-capture shouldn't leave a key waiting
    page:GetPropertyChangedSignal("Visible"):Connect(function()
        if not page.Visible and capturingAction then
            StopCapture()
        end
    end)
end

local function ShowPage(page)
    settingsPage.Visible = page == settingsPage
    keybindsPage.Visible = page == keybindsPage
end

local function SetVolume(name, value)
    volumes[name] = value

    local group = SoundService:FindFirstChild(name)
    if group then
        group.Volume = value
    end

    local row = sliders[name]
    row.Track.Fill.Size = UDim2.fromScale(value, 1)
    row.Track.Knob.Position = UDim2.fromScale(value, 0.5)
    row.Value.Text = tostring(math.round(value * 100))
end

local function DragSlider(name, x)
    local track = sliders[name].Track
    local value = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)

    SetVolume(name, math.round(value * 100) / 100)
end

-- Volumes save when the drag ends, not on every step
local function BindSliders()
    for _, name in ipairs(VOLUMES) do
        sliders[name] = settingsPage:WaitForChild(name)

        sliders[name].Track.InputBegan:Connect(function(inputObject)
            if inputObject.UserInputType ~= Enum.UserInputType.MouseButton1 and inputObject.UserInputType ~= Enum.UserInputType.Touch then return end

            draggingSlider = name
            DragSlider(name, inputObject.Position.X)
        end)

        SetVolume(name, SettingsConfig.DEFAULTS[name])
    end

    UserInputService.InputChanged:Connect(function(inputObject)
        if not draggingSlider then return end
        if inputObject.UserInputType ~= Enum.UserInputType.MouseMovement and inputObject.UserInputType ~= Enum.UserInputType.Touch then return end

        DragSlider(draggingSlider, inputObject.Position.X)
    end)

    UserInputService.InputEnded:Connect(function(inputObject)
        if not draggingSlider then return end
        if inputObject.UserInputType ~= Enum.UserInputType.MouseButton1 and inputObject.UserInputType ~= Enum.UserInputType.Touch then return end

        ProfileRemote:FireServer("SetSetting", draggingSlider, volumes[draggingSlider])
        draggingSlider = nil
    end)
end

-- Both arrows flip the filter since it only has two states
local function BindCrt()
    local row = settingsPage:WaitForChild("Crt")
    crtValue = row:WaitForChild("Value")

    local function Toggle()
        CrtController.SetEnabled(not CrtController.isEnabled)
        ProfileRemote:FireServer("SetSetting", "CRT", CrtController.isEnabled)
    end

    row:WaitForChild("Previous").Activated:Connect(Toggle)
    row:WaitForChild("Next").Activated:Connect(Toggle)

    local function RefreshCrt(isEnabled)
        crtValue.Text = isEnabled and "On" or "Off"
    end

    CrtController.OnChanged(RefreshCrt)
    RefreshCrt(CrtController.isEnabled)
end

function SettingsController.Open()
    ShowPage(settingsPage)
    overlay.Enabled = true
end

function SettingsController.Close()
    overlay.Enabled = false
    ShowPage(nil)
end

local init = false
function SettingsController.Init(inputController)
    if init then return end
    init = true

    input = inputController

    overlay = Players.LocalPlayer.PlayerGui:WaitForChild("SettingsOverlay")
    settingsPage = overlay:WaitForChild("SettingsPage")
    keybindsPage = overlay:WaitForChild("KeybindsPage")

    BindKeybinds(keybindsPage)
    BindSliders()
    BindCrt()

    settingsPage:WaitForChild("CloseButton").Activated:Connect(SettingsController.Close)
    settingsPage:WaitForChild("KeybindsButton").Activated:Connect(function()
        ShowPage(keybindsPage)
    end)
    keybindsPage:WaitForChild("BackButton").Activated:Connect(function()
        ShowPage(settingsPage)
    end)

    input.OnBindingsChanged = Refresh
    Refresh()

    -- Saved choices arrive with the profile
    ProfileController.OnChanged(function()
        local saved = ProfileController.Data.Settings

        if saved.CRT ~= nil and saved.CRT ~= CrtController.isEnabled then
            CrtController.SetEnabled(saved.CRT)
        end

        for _, name in ipairs(VOLUMES) do
            if typeof(saved[name]) == "number" then
                SetVolume(name, saved[name])
            end
        end
    end)
end

return SettingsController
