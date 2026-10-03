-- Submits each player's score to ECFA Cloud after a song, shows the results (in
-- the results window, Shared/ECFACloudResults.lua, plus PB/WR text and an event
-- summary line), uploads missing pack/song banners, and queues scores that
-- couldn't be submitted for later (Scripts/SL-ECFACloud-Pending.lua).

if GAMESTATE:IsCourseMode() or not ThemePrefs.Get("EnableECFACloud") then return end

-- When ECFA Cloud is unreachable we still queue eligible scores for later.
local online = IsServiceAllowed(SL.ECFACloud.AutoSubmit)

-- Leaderboard rows to ask for (the results window shows the top, keeping the player's own row).
local NumEntries = 10

-- The engine's Waterfall judgments, plus holds/rolls/mines and chart totals.
local GetJudgmentCounts = function(player)
	local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats(player)
	local counts = GetExJudgmentCounts(player)
	local tap = function(w) return pss:GetTapNoteScores("TapNoteScore_"..w) end
	return {
		masterful=tap("W1"),
		awesome=tap("W2"),
		solid=tap("W3"),
		ok=tap("W4"),
		fault=tap("W5"),
		miss=tap("Miss"),
		totalSteps=counts.totalSteps,
		holdsHeld=counts.Holds,
		totalHolds=counts.totalHolds,
		minesHit=counts.Mines,
		totalMines=counts.totalMines,
		rollsHeld=counts.Rolls,
		totalRolls=counts.totalRolls,
	}
end

-- The simulated ITG judgments (ITG windows applied to each tap's offset), from
-- which ECFA Cloud computes the secondary ITG and EX scores.
local GetSimulatedITGCounts = function(player)
	local pnum = tonumber(ToEnumShortString(player):sub(-1))
	local c = SL[ToEnumShortString(player)].Stages.Stats[SL.Global.Stages.PlayedThisGame + 1].ex_counts
	if not c then return nil end
	return {
		fantasticPlus=c.W0,
		fantastic=c.W1,
		excellent=c.W2,
		great=c.W3,
		decent=c.W4,
		wayOff=c.W5,
		miss=c.Miss,
		held=c.Held,
		minesHit=c.HitMine,
		failed=WF.ITGFailed[pnum],
	}
end

-- The timing windows the engine judged with (ECFA Cloud only accepts Waterfall's).
local GetTiming = function()
	local pref = function(name) return PREFSMAN:GetPreference(name) end
	return {
		w1=pref("TimingWindowSecondsW1"),
		w2=pref("TimingWindowSecondsW2"),
		w3=pref("TimingWindowSecondsW3"),
		w4=pref("TimingWindowSecondsW4"),
		w5=pref("TimingWindowSecondsW5"),
		hold=pref("TimingWindowSecondsHold"),
		mine=pref("TimingWindowSecondsMine"),
		roll=pref("TimingWindowSecondsRoll"),
		scale=pref("TimingWindowScale"),
		add=pref("TimingWindowAdd"),
	}
end

-- Final values of the Easy, Normal and Hard lifebars.
local GetLifeBars = function(player)
	local life = WF.GetLifeBarValues(tonumber(ToEnumShortString(player):sub(-1)))
	return { easy=life[1], normal=life[2], hard=life[3] }
end

-- Plays a random sound from Sounds/<folder>/ (e.g. "Evaluation PB"), if any exist.
local PlayRandomSound = function(folder)
	local files = findFiles(THEME:GetCurrentThemeDirectory() .. "Sounds/" .. folder .. "/")
	if #files > 0 then
		SOUND:PlayOnce(files[math.random(#files)])
	end
end

-- Builds one player's submission, or nil if their score shouldn't be submitted.
-- Returns chartHash, submission.
local BuildSubmission = function(player, packInfo, songInfo)
	local pn = ToEnumShortString(player)
	if not (GAMESTATE:IsHumanPlayer(player) and GAMESTATE:IsSideJoined(player)) then return nil end
	if SL[pn].ApiKey == "" or not SL[pn].IsPadPlayer then return nil end

	local _, valid, _ = ValidForECFACloud(player)
	local stats = STATSMAN:GetCurStageStats():GetPlayerStageStats(player)
	if not valid or stats:GetFailed() then return nil end
	-- Only complete passes count: a play the player gave up on is a Fail.
	if WF.GetClearType(player) == #WF.ClearTypes then return nil end

	-- The hash is normally computed in Select Music; make sure we have it.
	if SL[pn].Streams.Hash == "" then
		ComputeChartHash(GAMESTATE:GetCurrentSteps(player), pn)
	end
	if SL[pn].Streams.Hash == "" then return nil end

	return SL[pn].Streams.Hash, {
		rate=tonumber(string.format("%.0f", SL.Global.ActiveModifiers.MusicRate * 100)),
		score=tonumber(("%.0f"):format(stats:GetPercentDancePoints() * 10000)),
		judgmentCounts=GetJudgmentCounts(player),
		lifebars=GetLifeBars(player),
		timing=GetTiming(),
		faPlus={ ms10=WF.FAPlusCount[tonumber(pn:sub(-1))][1], ms12=WF.FAPlusCount[tonumber(pn:sub(-1))][2] },
		itg=GetSimulatedITGCounts(player),
		usedCmod=(GAMESTATE:GetPlayerState(pn):GetPlayerOptions("ModsLevel_Preferred"):CMod() ~= nil),
		comment=CreateCommentString(player),
		playerOptions=GetPlayerOptionsJsonForECFACloud(player),
		chart=GetChartInfoForECFACloud(player),
		song=songInfo,
		pack=packInfo,
	}
end

-- Banners already being uploaded from this screen (each once, even with two players).
local uploadedBanners = {}

-- The one-line event summary under a side, e.g. "ECFA 2026 · Timing #2 · RP #3 ▲2"
-- (the results window has the details).
local ShowEventSummary = function(master, side, events)
	local summary = master:GetChild("P"..side.."EventText")
	if not summary or not events or #events == 0 or not GAMESTATE:IsSideJoined("PlayerNumber_P"..side) then return end
	local Rank = function(rank, previous)
		if not rank then return "unranked" end
		return "#"..rank..((previous and previous > rank) and (" ▲"..(previous - rank)) or "")
	end
	local parts = {}
	for e in ivalues(events) do
		local line = e.name
		-- Older servers send only the Ranking Points board.
		if e.timingRank ~= nil or e.timingPoints ~= nil then
			line = line.." · Timing "..Rank(e.timingRank, e.previousTimingRank)
		end
		parts[#parts+1] = line.." · RP "..Rank(e.rank, e.previousRank)
	end
	summary:settext(table.concat(parts, "   "))
	summary:visible(true)
	DiffuseEmojis(summary)
end

-- Queues the given submissions for later and tells each player.
local QueueForLater = function(master, submissions)
	for i, s in pairs(submissions) do
		local result = ECFACloudSavePending(s.player, s.chartHash, s.submission)
		local text = master:GetChild("P"..i.."SubmitText")
		if text then
			text:playcommand(result == "full" and "QueueFull" or (result and "Queued" or "SubmitFailed"),
				{ count=ECFACloudPendingCount(s.player) })
		end
	end
end

-- After a successful submission, send any plays queued while offline.
local RetryQueued = function(master, players)
	for i, player in pairs(players) do
		if ECFACloudPendingCount(player) > 0 then
			ECFACloudRetryPending(player, SL[ToEnumShortString(player)].ApiKey, function(remaining)
				local pending = master:GetChild("P"..i.."PendingText")
				if pending then pending:playcommand("Update", { count=remaining }) end
			end)
		end
	end
end

local AutoSubmitRequestProcessor = function(res, ctx)
	local overlay = ctx.overlay
	local master = overlay:GetChild("AutoSubmitMaster")
	local popup = overlay:GetChild("ECFACloudResults")

	if res.error or res.statusCode ~= 200 then
		local code = res.statusCode or 0
		if res.error or code == 0 or code == 429 or code >= 500 then
			-- ECFA Cloud unreachable or temporarily failing: keep the scores for later.
			QueueForLater(master, ctx.submissions)
			if popup then popup:playcommand("Failed", { text=THEME:GetString("ECFACloud", "Unreachable") }) end
		else
			-- Rejected outright; retrying wouldn't help.
			for side in pairs(ctx.submissions) do
				local text = master:GetChild("P"..side.."SubmitText")
				if text then text:queuecommand("SubmitFailed") end
			end
			if popup then popup:playcommand("Failed", { text=THEME:GetString("ECFACloud", "SubmitFailed") }) end
		end
		return
	end

	-- Leaderboards cached in song select (scorebox, pane) are out of date now.
	SL.ECFACloud.RequestCache = {}

	local panes = overlay:GetChild("Panes")
	local data = JsonDecode(res.body)
	local succeeded = {}

	for side, submitted in pairs(ctx.submissions) do
		local playerData = data and data["player"..side]
		local submitText = master:GetChild("P"..side.."SubmitText")

		if not playerData or playerData["error"] then
			-- The server rejected this player's submission (e.g. revoked API key).
			if submitText then submitText:queuecommand("SubmitFailed") end
			if popup then popup:playcommand("Failed", { side=side, text=THEME:GetString("ECFACloud", "SubmitFailed") }) end
		else
			succeeded[side] = submitted.player
			if submitText then submitText:queuecommand("Submit") end

			-- The QR pane stops offering to submit (both of its sides in single player).
			for i = 1, 2 do
				local qr = panes and panes:GetChild("Pane7_SideP"..i)
				qr = qr and qr:GetChild("")
				if qr and (i == side or GAMESTATE:GetNumSidesJoined() == 1) then
					qr:GetChild("HelpText"):settext(THEME:GetString("ECFACloud", "ScoreAlreadySubmitted"))
				end
			end

			-- ECFA Events results for this play (empty when the chart isn't in an open event).
			ShowEventSummary(master, side, playerData["events"])

			-- Upload any pack/song banners ECFA Cloud doesn't have yet.
			for hash in ivalues(playerData["missingBanners"] or {}) do
				if not uploadedBanners[hash] and ctx.bannerPaths[hash] then
					uploadedBanners[hash] = true
					UploadBannerToECFACloud(hash, ctx.bannerPaths[hash], ctx.apiKeys[side])
				end
			end

			-- Only show a leaderboard for the chart that was actually played.
			local sameChart = SL["P"..side].Streams.Hash == playerData["chartHash"]
			local personalRank = nil
			for entry in ivalues(sameChart and playerData["wfLeaderboard"] or {}) do
				if entry["isSelf"] then personalRank = entry["rank"] end
			end

			-- Personal best / world record text above the side's stats.
			if sameChart and (playerData["result"] == "score-added" or playerData["result"] == "improved")
					and overlay:GetChild("P"..side.."_AF_Upper") then
				local recordText = master:GetChild("P"..side.."RecordText")
				local logo = master:GetChild("P"..side.."ECFACloud_Logo")
				recordText:visible(true)
				logo:visible(true)
				recordText:diffuseshift():effectcolor1(Color.White):effectcolor2(Color.Yellow):effectperiod(3)
				if personalRank == 1 then
					recordText:settext(THEME:GetString("ECFACloud", "WorldRecord"))
					PlayRandomSound("Evaluation WR")
				else
					recordText:settext(THEME:GetString("ECFACloud", "PersonalBest"))
					PlayRandomSound("Evaluation PB")
				end
				local recordTextXStart = recordText:GetX() - recordText:GetWidth()*recordText:GetZoom()/2
				local logoWidth = logo:GetWidth()*logo:GetZoom()
				-- This will automatically adjust based on the length of the recordText length.
				logo:xy(recordTextXStart - logoWidth/2, recordText:GetY())
			end

			if popup then
				popup:playcommand("Results", { side=side, data=playerData, personalRank=personalRank, showBoard=sameChart })
			end
		end
	end

	RetryQueued(master, succeeded)
end

local af = Def.ActorFrame {
	Name="AutoSubmitMaster",
	RequestResponseActor(17, 50)..{
		OnCommand=function(self)
			local headers = {}
			local query = {
				maxLeaderboardResults=NumEntries,
			}
			local body = {}
			-- side -> { player, chartHash, submission }, kept for queueing on failure
			local submissions = {}
			-- banner hash -> local file, and side -> API key, for uploading missing banners
			local bannerPaths, apiKeys = {}, {}

			local song = GAMESTATE:GetCurrentSong()
			local packInfo, packBannerPath = GetPackInfoForECFACloud(song)
			local songInfo, songBannerPath = GetSongInfoForECFACloud(song)
			if packInfo and packInfo.bannerHash then bannerPaths[packInfo.bannerHash] = packBannerPath end
			if songInfo and songInfo.bannerHash then bannerPaths[songInfo.bannerHash] = songBannerPath end

			for i=1,2 do
				local player = "PlayerNumber_P"..i
				local pn = ToEnumShortString(player)
				local chartHash, submission = BuildSubmission(player, packInfo, songInfo)

				if chartHash then
					query["chartHashP"..i] = chartHash
					headers["x-api-key-player-"..i] = SL[pn].ApiKey
					apiKeys[i] = SL[pn].ApiKey
					body["player"..i] = submission
					submissions[i] = { player=player, chartHash=chartHash, submission=submission }
				elseif GAMESTATE:IsSideJoined(player) then
					-- Hide the submit text if we're not submitting a score for a player.
					-- For example in versus, if one player fails and the other passes, we
					-- want to show that the first player score won't be submitted.
					self:GetParent():GetChild("P"..i.."SubmitText"):visible(false)
				end
			end

			if next(submissions) == nil then return end

			if not online then
				-- ECFA Cloud is enabled but wasn't reachable at the title screen.
				QueueForLater(self:GetParent(), submissions)
				return
			end

			-- Unjoined players won't have the text displayed.
			self:GetParent():GetChild("P1SubmitText"):settext(THEME:GetString("ECFACloud", "Submitting"))
			self:GetParent():GetChild("P2SubmitText"):settext(THEME:GetString("ECFACloud", "Submitting"))

			-- The results window opens now and fills in when ECFA Cloud answers.
			local overlay = SCREENMAN:GetTopScreen():GetChild("Overlay"):GetChild("ScreenEval Common")
			local popup = overlay and overlay:GetChild("ECFACloudResults")
			if popup then
				local sides = {}
				for i = 1, 2 do
					if submissions[i] then sides[#sides+1] = i end
				end
				popup:playcommand("Open", { sides=sides })
			end

			self:playcommand("MakeECFACloudRequest", {
				endpoint="score-submit?"..NETWORK:EncodeQueryParameters(query),
				method="POST",
				headers=headers,
				body=JsonEncode(body),
				timeout=30,
				callback=AutoSubmitRequestProcessor,
				args={
					overlay=SCREENMAN:GetTopScreen():GetChild("Overlay"):GetChild("ScreenEval Common"),
					submissions=submissions,
					bannerPaths=bannerPaths,
					apiKeys=apiKeys,
				},
			})
		end
	}
}

local textColor = Color.White
local shadowLength = 0
if ThemePrefs.Get("RainbowMode") then
	textColor = Color.Black
end

for i=1,2 do
	local player = (i == 1) and PLAYER_1 or PLAYER_2

	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal").. {
		Name="P"..i.."SubmitText",
		Text="",
		InitCommand=function(self)
			self:xy(_screen.w * (i == 1 and 0.25 or 0.75), _screen.h - 15)
			self:diffuse(textColor)
			self:shadowlength(shadowLength)
			self:zoom(0.8)
			self:visible(GAMESTATE:IsSideJoined(player))
		end,
		SubmitCommand=function(self)
			self:settext(THEME:GetString("ECFACloud", "Submitted"))
		end,
		SubmitFailedCommand=function(self)
			self:settext(THEME:GetString("ECFACloud", "SubmitFailed"))
			DiffuseEmojis(self)
		end,
		TimedOutCommand=function(self)
			self:settext(THEME:GetString("ECFACloud", "TimedOut"))
		end,
		QueuedCommand=function(self, params)
			self:settext(THEME:GetString("ECFACloud", "SavedForLater"):format(params.count))
		end,
		QueueFullCommand=function(self)
			self:settext(THEME:GetString("ECFACloud", "QueueFull"))
		end,
	}

	-- Plays still waiting in the offline queue, shown after a retry.
	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal").. {
		Name="P"..i.."PendingText",
		Text="",
		InitCommand=function(self)
			self:xy(_screen.w * (i == 1 and 0.25 or 0.75), _screen.h - 48)
			self:diffuse(color("#ffcc33")):shadowlength(1):zoom(0.6):visible(false)
		end,
		UpdateCommand=function(self, params)
			if params.count > 0 then
				self:settext(THEME:GetString("ECFACloud", "PendingCount"):format(params.count)):visible(true)
			else
				self:visible(false)
			end
		end,
	}

	-- e.g. "ECFA 2026 · Timing #2 · RP #3 ▲2" (details are in the results window)
	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal").. {
		Name="P"..i.."EventText",
		Text="",
		InitCommand=function(self)
			self:xy(_screen.w * (i == 1 and 0.25 or 0.75), _screen.h - 32)
			self:diffuse(Color.Yellow)
			self:shadowlength(1)
			self:zoom(0.7)
			self:maxwidth(_screen.w * 0.45 / 0.7)
			self:visible(false)
		end,
	}

	af[#af+1] = Def.Sprite{
		Texture=THEME:GetPathG("","ECFA logo small.png"),
		Name="P"..i.."ECFACloud_Logo",
		InitCommand=function(self)
			self:zoom(40 / self:GetWidth())
			self:visible(false)
		end,
	}

	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Bold")..{
		Name="P"..i.."RecordText",
		InitCommand=function(self)
			local x = _screen.cx + 225 * (i == 1 and -1 or 1)
			self:zoom(0.225)
			self:xy(x,40)
			self:visible(false)
		end,
	}
end

return af
