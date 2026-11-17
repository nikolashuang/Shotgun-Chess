local DevConfig = {
    -- Only these accounts see the dev panel, and the server ignores dev requests from anyone else
    USER_IDS = {
        74246257, -- Snoothe3rd
    },

    GOLD_GRANT = 1000,
}

function DevConfig.IsDev(player)
    return table.find(DevConfig.USER_IDS, player.UserId) ~= nil
end

return DevConfig
