local MemoryStoreService = game:GetService("MemoryStoreService")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local DuelConfig = require(ReplicatedStorage.Shared.Duel.DuelConfig)
local ProfileService = require(ServerScriptService.Player.ProfileService)

local DuelRemote = ReplicatedStorage.Remotes.DuelRemote

-- Shared across every server of the experience
-- Queue entries are keyed by UserId and sorted by when the player joined
local queueStore = MemoryStoreService:GetSortedMap("DuelQueue1v1")
-- UserId -> {AccessCode} once the coordinator has matched the player
local assignmentStore = MemoryStoreService:GetHashMap("DuelAssignments")
-- Reserved server id -> {Mode, Players}, read by the duel place when it starts
local matchStore = MemoryStoreService:GetHashMap("DuelMatches")
-- The coordinator's lease: the JobId of the server matching players right now
local leaseStore = MemoryStoreService:GetHashMap("DuelCoordinator")
-- UserId -> true for players the duel place sent back to be queued again
local requeueStore = MemoryStoreService:GetHashMap("DuelRequeue")

local LEASE_KEY = "1v1"

-- 1v1 global matchmaking across every public server
-- Each server keeps its own players' queue entries alive and teleports them once they're matched
-- One server at a time holds the coordinator lease and does the matching; the first server with someone queued
-- claims it, and when that server stops renewing (nobody left in its queue, or it shut down) the lease lapses and
-- the next server with players queued takes over
local GlobalQueueService = {}

-- Player -> true while this server has them in the global queue
local queued = {}
local isCoordinator = false

local function SendState(player, isQueued)
    if player.Parent then
        DuelRemote:FireClient(player, "QueueState", isQueued)
    end
end

local function Retry(callback)
    for attempt = 1, 3 do
        local ok, result = pcall(callback)
        if ok then return true, result end

        warn("[GlobalQueueService] " .. tostring(result))
        task.wait(attempt)
    end

    return false, nil
end

--QUEUE--

function GlobalQueueService.IsQueued(player)
    return queued[player] == true
end

function GlobalQueueService.Join(player)
    if queued[player] then return end

    queued[player] = true
    SendState(player, true)

    task.spawn(function()
        local ok = Retry(function()
            queueStore:SetAsync(tostring(player.UserId), {UserId = player.UserId}, DuelConfig.QUEUE_ENTRY_TIME, DateTime.now().UnixTimestampMillis)
        end)

        if ok then return end

        queued[player] = nil
        SendState(player, false)
    end)
end

-- Cancelling is best effort: a player the coordinator already claimed is sent to their duel anyway
function GlobalQueueService.Leave(player)
    if not queued[player] then return end

    task.spawn(function()
        local key = tostring(player.UserId)
        local isClaimed = false

        local ok = Retry(function()
            queueStore:UpdateAsync(key, function(entry, sortKey)
                if not entry then return nil end

                if entry.MatchId then
                    isClaimed = true
                    return nil
                end

                entry.Cancelled = true
                return entry, sortKey
            end, DuelConfig.QUEUE_ENTRY_TIME)
        end)

        if not ok or isClaimed then return end

        Retry(function()
            queueStore:RemoveAsync(key)
        end)

        queued[player] = nil
        SendState(player, false)
    end)
end

-- Entries expire unless their server keeps them alive, so a server that goes down leaves nothing behind
-- A claim the coordinator never finished is dropped so the player can be matched again
local function RefreshEntries()
    for player in pairs(queued) do
        pcall(function()
            queueStore:UpdateAsync(tostring(player.UserId), function(entry, sortKey)
                if not entry then return nil end

                if entry.MatchId and os.time() - entry.ClaimedAt > DuelConfig.CLAIM_TIMEOUT then
                    entry.MatchId = nil
                    entry.ClaimedAt = nil
                end

                return entry, sortKey
            end, DuelConfig.QUEUE_ENTRY_TIME)
        end)
    end
end

--MATCHING--

-- Claiming marks the entry so a cancel can't remove it; returns false if it was cancelled or already taken
local function Claim(key, matchId)
    local isClaimed = false

    pcall(function()
        queueStore:UpdateAsync(key, function(entry, sortKey)
            if not entry or entry.Cancelled or entry.MatchId then return nil end

            entry.MatchId = matchId
            entry.ClaimedAt = os.time()
            isClaimed = true

            return entry, sortKey
        end, DuelConfig.QUEUE_ENTRY_TIME)
    end)

    return isClaimed
end

local function Release(key, matchId)
    pcall(function()
        queueStore:UpdateAsync(key, function(entry, sortKey)
            if not entry or entry.MatchId ~= matchId then return nil end

            entry.MatchId = nil
            entry.ClaimedAt = nil

            return entry, sortKey
        end, DuelConfig.QUEUE_ENTRY_TIME)
    end)
end

-- Reserves a duel server for the two players and tells their servers where to send them
local function MakeMatch(first, second)
    local matchId = HttpService:GenerateGUID(false)

    if not Claim(first.key, matchId) then return end

    if not Claim(second.key, matchId) then
        Release(first.key, matchId)
        return
    end

    local ok, accessCode, serverId = pcall(function()
        return TeleportService:ReserveServer(DuelConfig.DUEL_PLACE_ID)
    end)

    -- Studio can't reserve real servers and returns no server id
    if not ok or not serverId or serverId == "" then
        warn("[GlobalQueueService] Couldn't reserve a duel server: " .. tostring(ok and "no server id (Studio?)" or accessCode))
        Release(first.key, matchId)
        Release(second.key, matchId)
        return
    end

    local userIds = {first.value.UserId, second.value.UserId}
    local isPosted = Retry(function()
        matchStore:SetAsync(serverId, {Mode = "1v1", Players = userIds}, DuelConfig.ASSIGNMENT_TIME)

        for _, userId in ipairs(userIds) do
            assignmentStore:SetAsync(tostring(userId), {AccessCode = accessCode}, DuelConfig.ASSIGNMENT_TIME)
        end
    end)

    if not isPosted then
        Release(first.key, matchId)
        Release(second.key, matchId)
        return
    end

    for _, entry in ipairs({first, second}) do
        pcall(function()
            queueStore:RemoveAsync(entry.key)
        end)
    end
end

-- Pairs everyone waiting, longest wait first
local function RunMatching()
    local ok, entries = pcall(function()
        return queueStore:GetRangeAsync(Enum.SortDirection.Ascending, 100)
    end)
    if not ok then return end

    local waiting = {}

    for _, entry in ipairs(entries) do
        if not entry.value.Cancelled and not entry.value.MatchId then
            table.insert(waiting, entry)
        end
    end

    for i = 1, #waiting - 1, 2 do
        MakeMatch(waiting[i], waiting[i + 1])
    end
end

-- Servers with players queued try for the lease; the holder renews it only while its own queue isn't empty
local function UpdateLease()
    if not next(queued) then
        isCoordinator = false
        return
    end

    local ok, holder = pcall(function()
        return leaseStore:UpdateAsync(LEASE_KEY, function(current)
            if current and current ~= game.JobId then return nil end

            return game.JobId
        end, DuelConfig.LEASE_TIME)
    end)

    isCoordinator = ok and holder == game.JobId
end

--ASSIGNMENTS--

-- Saves first so the duel place loads the player's latest data
local function SendToDuel(player, assignment)
    queued[player] = nil
    DuelRemote:FireClient(player, "MatchFound")

    local options = Instance.new("TeleportOptions")
    options.ReservedServerAccessCode = assignment.AccessCode

    ProfileService.SaveForTeleport(player)

    local ok, result = pcall(function()
        TeleportService:TeleportAsync(DuelConfig.DUEL_PLACE_ID, {player}, options)
    end)

    if ok then return end

    warn("[GlobalQueueService] Teleport failed for " .. player.Name .. ": " .. tostring(result))
    ProfileService.CancelTeleport(player)
    DuelRemote:FireClient(player, "TeleportFailed")
    SendState(player, false)
end

local function CheckAssignments()
    for player in pairs(queued) do
        local key = tostring(player.UserId)
        local ok, assignment = pcall(function()
            return assignmentStore:GetAsync(key)
        end)

        if ok and assignment then
            pcall(function()
                assignmentStore:RemoveAsync(key)
            end)

            task.spawn(SendToDuel, player, assignment)
        end
    end
end

-- Players the duel place sent back because their rival never arrived go straight back into the queue
local function CheckRequeue(player)
    local key = tostring(player.UserId)
    local ok, isRequeued = pcall(function()
        return requeueStore:GetAsync(key)
    end)
    if not ok or not isRequeued then return end

    pcall(function()
        requeueStore:RemoveAsync(key)
    end)

    -- Wait for the client to be listening for the queue state
    task.wait(3)
    if not player.Parent then return end

    DuelRemote:FireClient(player, "Requeued")
    GlobalQueueService.Join(player)
end

local init = false
function GlobalQueueService.Init()
    if init then return end
    init = true

    Players.PlayerAdded:Connect(CheckRequeue)

    -- A player leaving the game drops their entry; one already claimed becomes a no-show for the duel place
    Players.PlayerRemoving:Connect(function(player)
        if not queued[player] then return end

        queued[player] = nil
        pcall(function()
            queueStore:RemoveAsync(tostring(player.UserId))
        end)
    end)

    TeleportService.TeleportInitFailed:Connect(function(player)
        ProfileService.CancelTeleport(player)
        DuelRemote:FireClient(player, "TeleportFailed")
    end)

    task.spawn(function()
        local lastRefresh = 0

        while true do
            task.wait(DuelConfig.MATCH_INTERVAL)

            UpdateLease()

            if isCoordinator then
                RunMatching()
            end

            CheckAssignments()

            if os.clock() - lastRefresh > DuelConfig.QUEUE_ENTRY_TIME / 3 then
                lastRefresh = os.clock()
                task.spawn(RefreshEntries)
            end
        end
    end)
end

return GlobalQueueService
