local REASON_TEXT = {
    KingKilled = "King slain",
    Timeout = "Clock ran out",
    Forfeit = "Forfeit",
    Surrender = "Surrender",
    DisconnectSurrender = "Surrender after a disconnect",
}

-- Fills the match result panel with a duel's outcome; used by local duels and the duel place
local DuelResult = {}

-- summary.Returning: the duel place sends the player back on its own, so there's no Continue button
function DuelResult.Show(resultOverlay, summary)
    local panel = resultOverlay.ResultPanel
    local lines = {REASON_TEXT[summary.Reason] or ""}

    if summary.Gold > 0 or summary.Exp > 0 then
        table.insert(lines, string.format("+%d Gold", summary.Gold))
        table.insert(lines, string.format("+%d XP", summary.Exp))
    end

    if summary.Returning then
        table.insert(lines, "Returning to the lobby...")
    end

    panel.Title.Text = summary.Victory and "Victory!" or "Defeat"
    panel.Rewards.Text = table.concat(lines, "\n")
    panel.ContinueButton.Visible = not summary.Returning
    resultOverlay.Visible = true
end

return DuelResult
