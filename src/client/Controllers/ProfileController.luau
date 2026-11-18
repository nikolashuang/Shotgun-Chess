local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ProfileRemote")

local listeners = {}

-- Latest snapshot of the server profile; Gold, Level and Exp are read from player attributes instead
local ProfileController = {}

ProfileController.Data = {
    Shotguns = {},
    Classes = {},
    Nodes = {},
    Settings = {},
}

function ProfileController.OnChanged(callback)
    table.insert(listeners, callback)
end

local init = false
function ProfileController.Init()
    if init then return end
    init = true

    ProfileRemote.OnClientEvent:Connect(function(action, data)
        if action ~= "Profile" then return end

        ProfileController.Data = data

        for _, callback in ipairs(listeners) do
            callback()
        end
    end)

    ProfileRemote:FireServer("Request")
end

return ProfileController
