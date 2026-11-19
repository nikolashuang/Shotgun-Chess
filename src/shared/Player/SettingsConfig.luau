-- Player settings saved in the profile; the server only accepts names listed here
local SettingsConfig = {
    DEFAULTS = {
        CRT = true,
        -- Volumes from 0 to 1, applied to the SoundGroups of the same name in SoundService
        Sound = 1,
        Music = 1,
        -- Animation speed in matches; enemy thinking time is never sped up
        Speed = "Normal",
    },

    -- Text settings only accept these values, in the order the arrows cycle through them
    OPTIONS = {
        Speed = {"Normal", "Fast"},
    },

    -- Animation time is divided by this
    SPEEDS = {
        Normal = 1,
        Fast = 2,
    },
}

return SettingsConfig
