local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local BoardConfig = require(ReplicatedStorage.Shared.Board.BoardConfig)
local KingClass = require(ServerScriptService.Match.KingClass)

local BoardRemote = ReplicatedStorage.Remotes.BoardRemote

local Kings = {}

local function IsTileArgument(column, row)
    if typeof(column) ~= "number" or typeof(row) ~= "number" then return false end
    if column % 1 ~= 0 or row % 1 ~= 0 then return false end

    return true
end

BoardRemote.OnServerEvent:Connect(function(player, action, column, row)
    if action == "StartMatch" then
        local king = KingClass.new(player, BoardConfig.KING_START_COLUMN, BoardConfig.KING_START_ROW)
        Kings[player] = king

        BoardRemote:FireClient(player, "KingMoved", king.Column, king.Row)
        return
    end

    local king = Kings[player]
    if not king then return end
    if not IsTileArgument(column, row) then return end

    if action == "Move" then
        if king:MoveTo(column, row) then
            BoardRemote:FireClient(player, "KingMoved", king.Column, king.Row)
        end
    elseif action == "Fire" then
        local tiles = king:Fire(column, row)

        if tiles then
            BoardRemote:FireClient(player, "ShotFired", tiles)
        end
    end
end)

Players.PlayerRemoving:Connect(function(player)
    Kings[player] = nil
end)
