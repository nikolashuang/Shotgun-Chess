local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SettingsConfig = require(ReplicatedStorage.Shared.Player.SettingsConfig)

local listeners = {}

-- Match animation speed from the Speed setting; animation code divides its timings through Scale
local SpeedController = {}

SpeedController.Mode = SettingsConfig.DEFAULTS.Speed
SpeedController.Speed = SettingsConfig.SPEEDS[SpeedController.Mode]

function SpeedController.SetMode(mode)
    if not SettingsConfig.SPEEDS[mode] then return end

    SpeedController.Mode = mode
    SpeedController.Speed = SettingsConfig.SPEEDS[mode]

    for _, callback in ipairs(listeners) do
        callback(mode)
    end
end

-- Seconds an animation should take at the current speed
function SpeedController.Scale(seconds)
    return seconds / SpeedController.Speed
end

function SpeedController.OnChanged(callback)
    table.insert(listeners, callback)
end

return SpeedController
