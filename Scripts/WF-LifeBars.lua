-- -----------------------------------------------------------------------
-- Waterfall lifebars.
--
-- Three lifebars run at the same time: Easy, Normal and Hard. They react to
-- each judgment (and Easy/Normal slowly regenerate when low). A player fails
-- when the Easy lifebar runs out; the hardest lifebar still standing at the
-- end of the song decides their lifebar clear (see WF.GetClearType).
--
-- The engine's own lifebar is left untouched (SL.Metrics.Waterfall sets every
-- LifePercentChange to 0), so these are the only lifebars that matter.
--
-- Messages broadcast:
--   WFLifeChanged    {pn, ind, newlife, delta, regenflag}
--   WFLifeBarFailed  {pn, ind}
--   WFDanger         {pn, ind, event = "In" | "Out" | "Dead"}
--   WFFailed         {pn}
-- pn is the player number (1 or 2), ind the lifebar index (1 = Easy ... 3 = Hard).

WF = {}

WF.LifeBarNames = { "Easy", "Normal", "Hard" }

-- used for the lifebar display and graphs
WF.LifeBarColors = { {0,1,0.70,1}, {1,1,1,1}, {1,0.39,0,1} }

WF.LifeBarMetrics = {
	{
		-- Easy
		InitialValue = 1000,
		MaxValue = 1000,
		LifeChangeW1 = 12,
		LifeChangeW2 = 12,
		LifeChangeW3 = 12,
		LifeChangeW4 = 12,
		LifeChangeW5 = -40,
		LifeChangeMiss = -80,
		LifeChangeHitMine = -40,
		LifeChangeHeld = 10,
		LifeChangeLetGo = -40,

		ComboToRegainLifeInitialValue = 0,
		ComboAfterMiss = 0,
		MaxComboAfterMiss = 0,

		UseAutoRegen = true,
		RegenWaitTime = 400,
		RegenThreshold = 500,
		RegenTickTime = 0.01,
		RegenLifeChangeAddTime = 100,
		RegenTickLifeInc = 1
	},
	{
		-- Normal
		InitialValue = 1000,
		MaxValue = 1000,
		LifeChangeW1 = 10,
		LifeChangeW2 = 10,
		LifeChangeW3 = 10,
		LifeChangeW4 = 5,
		LifeChangeW5 = -50,
		LifeChangeMiss = -100,
		LifeChangeHitMine = -50,
		LifeChangeHeld = 10,
		LifeChangeLetGo = -100,

		ComboToRegainLifeInitialValue = 0,
		ComboAfterMiss = 5,
		MaxComboAfterMiss = 5,

		UseAutoRegen = true,
		RegenWaitTime = 500,
		RegenThreshold = 350,
		RegenTickTime = 0.01,
		RegenLifeChangeAddTime = 100,
		RegenTickLifeInc = 3
	},
	{
		-- Hard
		InitialValue = 1000,
		MaxValue = 1000,
		LifeChangeW1 = 8,
		LifeChangeW2 = 8,
		LifeChangeW3 = 4,
		LifeChangeW4 = 0,
		LifeChangeW5 = -100,
		LifeChangeMiss = -125,
		LifeChangeHitMine = -100,
		LifeChangeHeld = 0,
		LifeChangeLetGo = -125,

		ComboToRegainLifeInitialValue = 0,
		ComboAfterMiss = 10,
		MaxComboAfterMiss = 10,

		UseAutoRegen = false
	}
}

-- Failing the Easy lifebar fails the player.
WF.LowestLifeBarToFail = 1

-- Below these values a lifebar is "in danger" (about 2.5 misses from failing).
WF.DangerThreshold = {200, 250, 315}

-- per player (indexed by player number) state
WF.LifeBarValues = {{}, {}}
-- {life, songtime} pairs for each lifebar, for the evaluation screen's life graph
WF.LifeBarChanges = {{}, {}}
-- The lifebar shown during gameplay: the player's preferred one, dropping to
-- the next easier one when it fails.
WF.PreferredLifeBar = {3, 3}
WF.VisibleLifeBar = {3, 3}

WF.InitializeLifeBars = function()
	for pn = 1, 2 do
		WF.LifeBarValues[pn] = {}
		WF.LifeBarChanges[pn] = {}
		for ind = 1, #WF.LifeBarNames do
			WF.LifeBarChanges[pn][ind] = {}
			WF.LifeBarValues[pn][ind] = {
				CurrentLife = WF.LifeBarMetrics[ind].InitialValue,
				ComboToRegainLife = WF.LifeBarMetrics[ind].ComboToRegainLifeInitialValue,
				Failed = false,
				RegenState = 0,
				RegenTimer = 0,
			}
		end
		local preferred = SL["P"..pn].ActiveModifiers.PreferredLifeBar
		WF.PreferredLifeBar[pn] = FindInTable(preferred, WF.LifeBarNames) or 3
		WF.VisibleLifeBar[pn] = WF.PreferredLifeBar[pn]
	end
end

WF.InitializeLifeBars()

WF.GetCurrentLife = function(pn, ind)
	return WF.LifeBarValues[pn][ind].CurrentLife
end
WF.IsLifeBarFailed = function(pn, ind)
	return WF.LifeBarValues[pn][ind].Failed
end
-- life on a scale from 0 to 1
WF.GetLifePercent = function(pn, ind)
	return WF.GetCurrentLife(pn, ind) / WF.LifeBarMetrics[ind].MaxValue
end
-- final values of all three lifebars, e.g. {1000, 820, 0}
WF.GetLifeBarValues = function(pn)
	local t = {}
	for ind = 1, #WF.LifeBarNames do t[ind] = WF.GetCurrentLife(pn, ind) end
	return t
end

WF.TrackLifeChange = function(pn, ind, newlife, songtime)
	table.insert(WF.LifeBarChanges[pn][ind], { newlife, songtime })
end

local LifeBarHitZero = function(pn, ind)
	WF.LifeBarValues[pn][ind].Failed = true
	if ind == WF.VisibleLifeBar[pn] and ind > WF.LowestLifeBarToFail then
		WF.VisibleLifeBar[pn] = WF.VisibleLifeBar[pn] - 1
	end
	MESSAGEMAN:Broadcast("WFLifeBarFailed", {pn = pn, ind = ind})
	if ind == WF.LowestLifeBarToFail then
		WF.FailPlayer(pn)
	end
end

local BroadcastDanger = function(pn, ind, oldlife, newlife)
	if newlife <= 0 and oldlife > 0 then
		MESSAGEMAN:Broadcast("WFDanger", {pn = pn, ind = ind, event = "Dead"})
	elseif newlife <= WF.DangerThreshold[ind] and oldlife > WF.DangerThreshold[ind] then
		MESSAGEMAN:Broadcast("WFDanger", {pn = pn, ind = ind, event = "In"})
	elseif newlife > WF.DangerThreshold[ind] and oldlife <= WF.DangerThreshold[ind] then
		MESSAGEMAN:Broadcast("WFDanger", {pn = pn, ind = ind, event = "Out"})
	end
end

-- Sets lifebar `ind` of player `pn` to `amount` (clamped to 0..MaxValue).
-- regenflag marks changes made by auto regen, so the regen logic can ignore them.
WF.SetLife = function(pn, ind, amount, regenflag)
	local bar = WF.LifeBarValues[pn][ind]
	if bar.Failed then return end
	local oldlife = bar.CurrentLife
	bar.CurrentLife = math.max(0, math.min(WF.LifeBarMetrics[ind].MaxValue, amount))
	local newlife = bar.CurrentLife
	if newlife ~= oldlife then
		MESSAGEMAN:Broadcast("WFLifeChanged", {pn = pn, ind = ind, newlife = newlife, delta = newlife - oldlife, regenflag = regenflag})
	end
	if newlife <= 0 then LifeBarHitZero(pn, ind) end
	BroadcastDanger(pn, ind, oldlife, newlife)
end

WF.ChangeLife = function(pn, ind, amount, regenflag)
	WF.SetLife(pn, ind, WF.GetCurrentLife(pn, ind) + amount, regenflag)
end

-- Fails the player: empties every lifebar and tells the engine.
WF.FailPlayer = function(pn)
	for ind = #WF.LifeBarNames, 1, -1 do
		local bar = WF.LifeBarValues[pn][ind]
		if not bar.Failed then
			bar.CurrentLife = 0
			bar.Failed = true
			MESSAGEMAN:Broadcast("WFLifeChanged", {pn = pn, ind = ind, newlife = 0, regenflag = false})
			MESSAGEMAN:Broadcast("WFLifeBarFailed", {pn = pn, ind = ind})
		end
	end
	STATSMAN:GetCurStageStats():GetPlayerStageStats("PlayerNumber_P"..pn):FailPlayer()
	MESSAGEMAN:Broadcast("WFFailed", {pn = pn})
	-- The engine's own lifebar never empties, so tell everything that listens
	-- for the engine's fail message (fail time, step statistics, ...).
	MESSAGEMAN:Broadcast("HealthStateChanged", {PlayerNumber = "PlayerNumber_P"..pn, HealthState = "HealthState_Dead"})
end

-- Call from a JudgmentMessageCommand with the message's params.
WF.LifeBarProcessJudgment = function(params)
	local pn = tonumber(params.Player:sub(-1))
	if (params.TapNoteScore == "TapNoteScore_AvoidMine") or (params.HoldNoteScore == "HoldNoteScore_MissedHold") then
		return
	end

	local name
	if params.HoldNoteScore then
		name = params.HoldNoteScore:gsub("HoldNoteScore_", "")
	elseif params.TapNoteScore then
		name = params.TapNoteScore:gsub("TapNoteScore_", "")
	end

	-- "Combo to regain life": after a miss, a lifebar needs a few combo
	-- judgments before it starts gaining life again.
	if name == "W1" or name == "W2" or name == "W3" or name == "W4" or name == "Held" then
		for ind, bar in ipairs(WF.LifeBarValues[pn]) do
			if not bar.Failed then
				if bar.ComboToRegainLife > 0 and name ~= "Held" then
					bar.ComboToRegainLife = bar.ComboToRegainLife - 1
				end
				if bar.ComboToRegainLife <= 0 then
					WF.ChangeLife(pn, ind, WF.LifeBarMetrics[ind]["LifeChange"..name])
				end
			end
		end
	elseif name == "W5" or name == "Miss" or name == "HitMine" or name == "LetGo" then
		for ind, bar in ipairs(WF.LifeBarValues[pn]) do
			if not bar.Failed then
				local m = WF.LifeBarMetrics[ind]
				bar.ComboToRegainLife = math.min(m.MaxComboAfterMiss, bar.ComboToRegainLife + m.ComboAfterMiss)
				WF.ChangeLife(pn, ind, m["LifeChange"..name])
			end
		end
	end
end

-- -----------------------------------------------------------------------
-- auto regen: once a lifebar drops below RegenThreshold and the player stops
-- losing life for RegenWaitTime ticks, it refills to the threshold.

WF.ResetLifeRegenState = function(pn, ind)
	if not WF.LifeBarMetrics[ind].UseAutoRegen then return end
	WF.LifeBarValues[pn][ind].RegenState = 0
	WF.LifeBarValues[pn][ind].RegenTimer = WF.LifeBarMetrics[ind].RegenWaitTime
end

WF.LifeChangedAddRegenTime = function(pn, ind)
	if not WF.LifeBarMetrics[ind].UseAutoRegen then return end
	local m = WF.LifeBarMetrics[ind]
	WF.LifeBarValues[pn][ind].RegenTimer = math.min(WF.LifeBarValues[pn][ind].RegenTimer + m.RegenLifeChangeAddTime, m.RegenWaitTime)
end

-- actor is a (hidden) actor that keeps the regen ticking via RegenTickCommand.
WF.LifeRegenTick = function(pn, ind, actor)
	local m = WF.LifeBarMetrics[ind]
	if WF.IsLifeBarFailed(pn, ind) or not m.UseAutoRegen or GAMESTATE:IsCourseMode() then return end

	if WF.GetCurrentLife(pn, ind) >= m.RegenThreshold then
		WF.ResetLifeRegenState(pn, ind)
		return
	end

	local bar = WF.LifeBarValues[pn][ind]
	if bar.RegenTimer > 0 then
		bar.RegenTimer = bar.RegenTimer - 1
	elseif m.RegenThreshold - WF.GetCurrentLife(pn, ind) > m.RegenTickLifeInc then
		WF.ChangeLife(pn, ind, m.RegenTickLifeInc, true)
	else
		WF.SetLife(pn, ind, m.RegenThreshold, true)
	end

	actor:sleep(m.RegenTickTime):queuecommand("RegenTick")
end

-- -----------------------------------------------------------------------
-- vertices for an ActorMultiVertex life graph of lifebar `ind` (evaluation screen)

WF.GetLifeGraphVertices = function(pn, ind, graphwidth, graphheight, songstart, songend)
	local m = WF.LifeBarMetrics[ind]
	local clr = WF.LifeBarColors[ind]
	local timescale = math.max(songend - songstart, 0.001) / graphwidth
	local verts = {}
	local t = songstart
	local py = (1 - m.InitialValue / m.MaxValue) * graphheight
	local skipped = {0, 0}

	table.insert(verts, {{0, py, 0}, clr})
	for v in ivalues(WF.LifeBarChanges[pn][ind]) do
		if v[2] - t >= timescale or v[1] == 0 or v[1] == m.MaxValue then
			-- average values that were too close together to draw separately
			local life = (v[1] == 0 or v[1] == m.MaxValue) and v[1] or (skipped[1] + v[1]) / (skipped[2] + 1)
			local x = (v[2] - songstart) / timescale
			local y = (1 - life / m.MaxValue) * graphheight
			-- keep the line flat across long gaps
			if v[2] - t >= timescale * 4 then
				table.insert(verts, {{x - 1, py, 0}, clr})
			end
			table.insert(verts, {{x, y, 0}, clr})
			t = v[2]
			py = y
			skipped = {0, 0}
		else
			skipped[1] = skipped[1] + v[1]
			skipped[2] = skipped[2] + 1
		end
	end
	table.insert(verts, {{graphwidth, py, 0}, clr})
	return verts
end
