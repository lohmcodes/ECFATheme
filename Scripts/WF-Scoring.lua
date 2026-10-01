-- -----------------------------------------------------------------------
-- Waterfall scoring helpers (ported from Waterfall Expanded).
--
-- The engine judges with Waterfall's windows (SL.Preferences.Waterfall), and its
-- percent dance points are the Waterfall score. On top of that this file tracks:
--   * a simulated ITG play: every tap's offset re-judged with ITG's windows,
--     with ITG's lifebar, giving the secondary ITG and EX scores
--   * FA+ counts: Masterfuls within 10ms and 12.5ms
--   * Waterfall clear types
--
-- Everything is indexed by player number (1 or 2).

-- ITG windows in seconds, including ITG's +1.5ms TimingWindowAdd.
-- Fantastic+ (15ms) is the EX "blue" window.
WF.ITGWindows = {
	FantasticPlus = 0.015,
	Fantastic = 0.023,
	Excellent = 0.0445,
	Great = 0.1035,
	Decent = 0.1365,
	WayOff = 0.1815,
}

-- Simply Love's ITG life changes and regen behavior.
local ITGLifeChange = { W1 = 0.008, W2 = 0.008, W3 = 0.004, W4 = 0, W5 = -0.05, Miss = -0.1, HitMine = -0.05, Held = 0.008, LetGo = -0.08 }
local ITGRegenComboAfterMiss = 5
local ITGMaxRegenComboAfterMiss = 10
WF.ITGDangerThreshold = 0.25

WF.ITGLife = {0.5, 0.5}
WF.ITGRegenCombo = {0, 0}
WF.ITGFailed = {false, false}
-- Masterfuls within {10ms, 12.5ms}
WF.FAPlusCount = {{0, 0}, {0, 0}}

-- Call at the start of ScreenGameplay.
WF.InitScoring = function()
	for pn = 1, 2 do
		WF.ITGLife[pn] = 0.5
		WF.ITGRegenCombo[pn] = 0
		WF.ITGFailed[pn] = false
		WF.FAPlusCount[pn] = {0, 0}
	end
end

-- The ITG judgment for an engine judgment, as an ex_counts key:
-- "W0" (Fantastic within 15ms), "W1".."W5", "Miss", "HitMine", "Held" or "LetGo".
-- Returns nil for judgments that don't count (dodged mines and the like).
-- Hits outside Waterfall's 160ms Fault window are already misses, so ITG's
-- widest window (181.5ms) is approximated.
WF.SimulateITGJudgment = function(params)
	if params.HoldNoteScore then
		local hns = ToEnumShortString(params.HoldNoteScore)
		if hns == "Held" then return "Held" end
		if hns == "LetGo" or hns == "MissedHold" then return "LetGo" end
		return nil
	end
	if not params.TapNoteScore then return nil end
	local tns = ToEnumShortString(params.TapNoteScore)
	if tns == "HitMine" or tns == "Miss" then return tns end
	if tns == "AvoidMine" or not params.TapNoteOffset then return nil end
	if not tns:match("^W%d$") then return nil end

	local offset = math.abs(params.TapNoteOffset)
	local w = WF.ITGWindows
	if offset <= w.FantasticPlus then return "W0" end
	if offset <= w.Fantastic then return "W1" end
	if offset <= w.Excellent then return "W2" end
	if offset <= w.Great then return "W3" end
	if offset <= w.Decent then return "W4" end
	return "W5"
end

-- Applies one simulated ITG judgment ("W0".."W5", "Miss", "HitMine", "Held", "LetGo")
-- to player pn's simulated ITG lifebar. Broadcasts ITGLifeChanged and ITGFailed.
WF.UpdateITGLife = function(pn, judgment)
	if WF.ITGFailed[pn] then return end
	local change = ITGLifeChange[judgment == "W0" and "W1" or judgment]
	if not change then return end

	local oldlife = WF.ITGLife[pn]
	if change < 0 then
		WF.ITGRegenCombo[pn] = math.min(WF.ITGRegenCombo[pn] + ITGRegenComboAfterMiss, ITGMaxRegenComboAfterMiss)
	else
		WF.ITGRegenCombo[pn] = math.max(WF.ITGRegenCombo[pn] - 1, 0)
	end

	if not (WF.ITGRegenCombo[pn] > 0 and change > 0) then
		-- "harsh hot life penalty": losing life from full life costs 10%
		if WF.ITGLife[pn] == 1 and change < 0 then change = -0.1 end
		WF.ITGLife[pn] = math.min(WF.ITGLife[pn] + change, 1)
		if WF.ITGLife[pn] <= 0.00001 then
			WF.ITGLife[pn] = 0
			WF.ITGFailed[pn] = true
			MESSAGEMAN:Broadcast("ITGFailed", { pn = pn })
		end
	end

	if WF.ITGLife[pn] ~= oldlife then
		MESSAGEMAN:Broadcast("ITGLifeChanged", { pn = pn, oldlife = oldlife, newlife = WF.ITGLife[pn] })
	end
end

-- Counts Masterfuls within 10ms / 12.5ms. Call from a JudgmentMessageCommand.
WF.TrackFAPlus = function(pn, params)
	if params.HoldNoteScore or params.TapNoteScore ~= "TapNoteScore_W1" or not params.TapNoteOffset then return end
	local offset = math.abs(params.TapNoteOffset)
	if offset <= 0.010 then WF.FAPlusCount[pn][1] = WF.FAPlusCount[pn][1] + 1 end
	if offset <= 0.0125 then WF.FAPlusCount[pn][2] = WF.FAPlusCount[pn][2] + 1 end
end

-- -----------------------------------------------------------------------
-- clear types

-- Best first, matching ECFA Cloud's CLEAR_TYPES (lib/scoring.ts) in reverse.
WF.ClearTypes = { "Mastery", "Awesome Combo", "Solid Combo", "Full Combo", "Hard Clear", "Clear", "Easy Clear", "Fail" }
WF.ClearTypesShort = { "★", "AC", "SC", "FC", "HCL", "CL", "ECL", "F" }

-- Colors for each clear type, in the same order.
WF.ClearTypeColor = function(ct)
	local i = type(ct) == "string" and FindInTable(ct, WF.ClearTypes) or ct
	if not i then return Color.White end
	if i <= 4 then return SL.JudgmentColors.Waterfall[i] end
	if i <= 7 then
		local c = WF.LifeBarColors[8 - i]
		return color(("%f,%f,%f,1"):format(c[1], c[2], c[3]))
	end
	return color("#B00000")
end

-- Clear type (index into WF.ClearTypes) of player's current stage.
-- Full combo tiers come from the judgments; otherwise the hardest lifebar left.
WF.GetClearType = function(player)
	local pn = tonumber(ToEnumShortString(player):sub(-1))
	local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats(player)
	if pss:GetFailed() then return #WF.ClearTypes end

	local tap = function(w) return pss:GetTapNoteScores("TapNoteScore_"..w) end
	local hold = function(w) return pss:GetHoldNoteScores("HoldNoteScore_"..w) end
	local judged = tap("W1") + tap("W2") + tap("W3") + tap("W4") + tap("W5") + tap("Miss")
	local possible = pss:GetRadarPossible():GetValue("RadarCategory_TapsAndHolds")
	local broken = tap("W5") > 0 or tap("Miss") > 0 or tap("HitMine") > 0 or hold("LetGo") > 0 or hold("MissedHold") > 0

	if judged == possible and not broken then
		for i = 4, 2, -1 do
			if tap("W"..i) > 0 then return i end
		end
		return 1
	end
	for ind = #WF.LifeBarNames, 1, -1 do
		if WF.GetCurrentLife(pn, ind) > 0 then
			-- Hard -> "Hard Clear" (5), Normal -> "Clear" (6), Easy -> "Easy Clear" (7)
			return 8 - ind
		end
	end
	return #WF.ClearTypes
end
