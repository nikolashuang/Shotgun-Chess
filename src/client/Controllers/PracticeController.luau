local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DuelConfig = require(ReplicatedStorage.Shared.Duel.DuelConfig)
local ShotgunConfig = require(ReplicatedStorage.Shared.Combat.ShotgunConfig)
local ClassConfig = require(ReplicatedStorage.Shared.Combat.ClassConfig)

local DuelRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DuelRemote")

local CLASS_OPTIONS = {"None", table.unpack(ClassConfig.ORDER)}

local panel = nil

-- Index into each picker's options
local picks = {
    Rating = table.find(DuelConfig.PRACTICE_RATINGS, DuelConfig.PRACTICE_DEFAULT_RATING) or 1,
    Shotgun = 1,
    Class = 1,
}

-- Choose Difficulty for a practice duel against the AI: its rating, shotgun and class
local PracticeController = {}

local function Update()
    local shotgunName = ShotgunConfig.ORDER[picks.Shotgun]
    local className = CLASS_OPTIONS[picks.Class]

    panel.RatingPicker.Value.Text = tostring(DuelConfig.PRACTICE_RATINGS[picks.Rating])
    panel.ShotgunPicker.Value.Text = ShotgunConfig.Shotguns[shotgunName].DisplayName
    panel.ClassPicker.Value.Text = className == "None" and "None" or ClassConfig.Classes[className].DisplayName
end

-- Arrows wrap around the option list
local function BindPicker(picker, key, count)
    local function Step(amount)
        picks[key] = (picks[key] - 1 + amount) % count + 1
        Update()
    end

    picker.LeftButton.Activated:Connect(function()
        Step(-1)
    end)

    picker.RightButton.Activated:Connect(function()
        Step(1)
    end)
end

-- The match itself starts when the server answers with DuelStarted (handled by MultiplayerController)
local function Start()
    DuelRemote:FireServer(
        "Practice",
        DuelConfig.PRACTICE_RATINGS[picks.Rating],
        ShotgunConfig.ORDER[picks.Shotgun],
        CLASS_OPTIONS[picks.Class]
    )
end

local init = false
function PracticeController.Init(practiceView)
    if init then return end
    init = true

    panel = practiceView:WaitForChild("Panel")

    BindPicker(panel:WaitForChild("RatingPicker"), "Rating", #DuelConfig.PRACTICE_RATINGS)
    BindPicker(panel:WaitForChild("ShotgunPicker"), "Shotgun", #ShotgunConfig.ORDER)
    BindPicker(panel:WaitForChild("ClassPicker"), "Class", #CLASS_OPTIONS)
    panel:WaitForChild("StartButton").Activated:Connect(Start)

    Update()
end

return PracticeController
