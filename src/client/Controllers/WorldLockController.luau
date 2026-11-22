local Players = game:GetService("Players")

-- Fixed camera distance in studs, so the camera can never go first person and lock the cursor to the middle
local CAMERA_DISTANCE = 12

local player = Players.LocalPlayer

-- The game is all screen UI, but Roblox still spawns a character in the 3D world behind it
-- The character stays frozen in place so the game's keybinds (W, A, Space...) never walk or jump it
local WorldLockController = {}

local function Freeze(character)
    local humanoid = character:WaitForChild("Humanoid")
    local root = character:WaitForChild("HumanoidRootPart")

    root.Anchored = true
    humanoid.WalkSpeed = 0
    humanoid.UseJumpPower = true
    humanoid.JumpPower = 0
end

local init = false
function WorldLockController.Init()
    if init then return end
    init = true

    player.CameraMinZoomDistance = CAMERA_DISTANCE
    player.CameraMaxZoomDistance = CAMERA_DISTANCE

    if player.Character then
        task.spawn(Freeze, player.Character)
    end

    player.CharacterAdded:Connect(Freeze)
end

return WorldLockController
