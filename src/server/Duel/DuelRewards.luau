local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DuelConfig = require(ReplicatedStorage.Shared.Duel.DuelConfig)
local ProfileService = require(ServerScriptService.Player.ProfileService)

-- What each duel result pays; shared by local duels and the duel place
local DuelRewards = {}

local function Scale(reward, scale)
    return {Gold = math.floor(reward.Gold * scale), Exp = math.floor(reward.Exp * scale)}
end

-- 1v1: the player who forfeited or surrendered gets nothing
function DuelRewards.Get(isWinner, reason)
    if isWinner then return DuelConfig.WIN_REWARD end
    if reason == "Forfeit" or reason == "Surrender" then return nil end

    return DuelConfig.LOSS_REWARD
end

-- 2v2: players who left get nothing, and neither does a surrendering team
function DuelRewards.GetTeam(match, side, isWinner, reason)
    if side.isDisconnected then return nil end

    if not isWinner then
        if reason == "Surrender" or reason == "DisconnectSurrender" then return nil end

        return DuelConfig.LOSS_REWARD
    end

    if reason == "DisconnectSurrender" then
        return Scale(DuelConfig.WIN_REWARD, DuelConfig.DISCONNECT_SURRENDER_SCALE)
    end

    local teammate = match:GetTeammate(side)
    if teammate and teammate.isDisconnected then
        return Scale(DuelConfig.WIN_REWARD, DuelConfig.SOLO_WIN_SCALE)
    end

    return DuelConfig.WIN_REWARD
end

-- Returns what was actually paid, after boosts
function DuelRewards.PayOut(player, reward)
    local gold, exp = ProfileService.AddEarned(player, reward.Gold, reward.Exp)
    ProfileService.Sync(player)

    return {Gold = gold, Exp = exp}
end

return DuelRewards
