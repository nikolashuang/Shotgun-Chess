local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local BoardRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BoardRemote")

local GLOW_COLOR = Color3.fromHex("E6C47C")
local DEFAULT_STROKE = Color3.fromHex("354867")
local DEFAULT_BACKGROUND = Color3.fromHex("1F2740")
local GLOW_BACKGROUND = Color3.fromHex("4A4128")
local CARD_TEXT_COLOR = Color3.fromHex("F0E9D8")
local EMPTY_TEXT_COLOR = Color3.fromHex("698FA9")

local PULSE_SPEED = 5

local slots = {}
local glowing = {}

local InterruptController = {}

local function Update(state)
    for i, slot in ipairs(slots) do
        local card = state.InterruptCards[i]
        local label = slot:FindFirstChildOfClass("TextLabel")
        local stroke = slot:FindFirstChildOfClass("UIStroke")

        label.Text = card and string.upper(card) or "EMPTY"
        label.TextColor3 = card and CARD_TEXT_COLOR or EMPTY_TEXT_COLOR

        glowing[i] = state.CanInterrupt and card ~= false and card ~= nil

        if not glowing[i] then
            stroke.Color = DEFAULT_STROKE
            stroke.Thickness = 2
            slot.BackgroundColor3 = DEFAULT_BACKGROUND
        end
    end
end

local function Flash(slot)
    slot.BackgroundColor3 = CARD_TEXT_COLOR

    TweenService:Create(slot, TweenInfo.new(0.3), {BackgroundColor3 = DEFAULT_BACKGROUND}):Play()
end

local init = false
function InterruptController.Init()
    if init then return end
    init = true

    local hud = Players.LocalPlayer.PlayerGui:WaitForChild("GameHUD")
    local slotFrame = hud:WaitForChild("Root"):WaitForChild("RightPanel"):WaitForChild("InterruptSlots")

    for i = 1, 3 do
        local slot = slotFrame:WaitForChild("Slot" .. i)
        slots[i] = slot

        slot.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
            if not glowing[i] then return end

            BoardRemote:FireServer("Interrupt", i)
        end)
    end

    BoardRemote.OnClientEvent:Connect(function(action, first)
        if action == "TurnState" then
            Update(first)
        elseif action == "InterruptUsed" then
            glowing[first] = false
            Flash(slots[first])
        end
    end)

    RunService.RenderStepped:Connect(function()
        local pulse = (math.sin(time() * PULSE_SPEED) + 1) / 2

        for i, slot in ipairs(slots) do
            if glowing[i] then
                local stroke = slot:FindFirstChildOfClass("UIStroke")
                stroke.Color = GLOW_COLOR
                stroke.Thickness = 2 + pulse * 2
                slot.BackgroundColor3 = DEFAULT_BACKGROUND:Lerp(GLOW_BACKGROUND, pulse)
            end
        end
    end)
end

return InterruptController
