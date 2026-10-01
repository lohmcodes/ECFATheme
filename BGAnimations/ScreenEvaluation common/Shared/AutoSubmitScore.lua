-- Submits each player's score to ECFA Cloud after a song, shows the results
-- (leaderboard, PB/WR, event results), uploads missing pack/song banners, and
-- queues scores that couldn't be submitted for later (Scripts/SL-ECFACloud-Pending.lua).

if GAMESTATE:IsCourseMode() or not ThemePrefs.Get("EnableECFACloud") then return end

-- When ECFA Cloud is unreachable we still queue eligible scores for later.
local online = IsServiceAllowed(SL.ECFACloud.AutoSubmit)

local NumEntries = math.min(10, PREFSMAN:GetPreference("MaxHighScoresPerListForMachine"))

local SetEntryText = function(rank, name, score, date, actor)
	if actor == nil then return end

	actor:GetChild("Rank"):settext(rank)
	actor:GetChild("Name"):settext(name)
	actor:GetChild("Score"):settext(score)
	actor:GetChild("Date"):settext(date)
end

-- Show the full ECFA Cloud username, falling back to the machine tag.
local GetMachineTag = function(entry)
	if not entry then return end
	if entry["name"] then
		return entry["name"]
	end
	if entry["machineTag"] then
		return entry["machineTag"]:sub(1, 4):upper()
	end
	return ""
end

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

-- Banners ECFA Cloud has already asked for this session (upload each only once).
local uploadedBanners = {}

-- Fills Pane9 (event results) and the one-line event summary for one side.
local ShowEventResults = function(overlay, i, events)
	local panes = overlay:GetChild("Panes")
	local eventPane = panes and panes:GetChild("Pane9_SideP"..i)
	eventPane = eventPane and eventPane:GetChild("")
	local summary = overlay:GetChild("AutoSubmitMaster"):GetChild("P"..i.."EventText")

	if not events or #events == 0 then
		if eventPane then eventPane:playcommand("NoEvent") end
		return
	end

	-- Show the first event on the pane; list every event in the summary line.
	if eventPane then eventPane:playcommand("ShowEvent", { event=events[1] }) end
	if summary and GAMESTATE:IsSideJoined("PlayerNumber_P"..i) then
		local parts = {}
		for e in ivalues(events) do
			local rank = e.rank and ("#"..e.rank) or "unranked"
			if e.rank and e.previousRank and e.previousRank > e.rank then
				rank = rank.." ▲"..(e.previousRank - e.rank)
			end
			local delta = e.rankingPointsDelta or 0
			parts[#parts+1] = ("%s · %s RP · %s"):format(e.name, (delta >= 0 and "+" or "")..delta, rank)
		end
		summary:settext(table.concat(parts, "   "))
		summary:visible(true)
		DiffuseEmojis(summary)
	end
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
	local P1SubmitText = master:GetChild("P1SubmitText")
	local P2SubmitText = master:GetChild("P2SubmitText")

	if res.error or res.statusCode ~= 200 then
		local code = res.statusCode or 0
		if res.error or code == 0 or code == 429 or code >= 500 then
			-- ECFA Cloud unreachable or temporarily failing: keep the scores for later.
			QueueForLater(master, ctx.submissions)
		else
			-- Rejected outright; retrying wouldn't help.
			if P1SubmitText then P1SubmitText:queuecommand("SubmitFailed") end
			if P2SubmitText then P2SubmitText:queuecommand("SubmitFailed") end
		end
		return
	end

	local panes = overlay:GetChild("Panes")
	local data = JsonDecode(res.body)
	local succeeded = {}

	-- Hijack the leaderboard pane to display the ECFA Cloud leaderboards.
	if panes then
		for i=1,2 do
			local playerStr = "player"..i
			local entryNum = 1
			local rivalNum = 1
			-- Pane 8 is the ECFA Cloud highscores pane.
			local highScorePane = panes:GetChild("Pane8_SideP"..i):GetChild("")
			local QRPane = panes:GetChild("Pane7_SideP"..i):GetChild("")

			-- If only one player is joined, we then need to update both panes with only
			-- one players' data.
			local side = i
			if data and GAMESTATE:GetNumSidesJoined() == 1 then
				if data["player1"] then
					side = 1
				else
					side = 2
				end
				playerStr = "player"..side
			end

			local submitText = (side == 1) and P1SubmitText or P2SubmitText
			local playerData = data and data[playerStr]

			if playerData and playerData["error"] then
				-- The server rejected this player's submission (e.g. revoked API key).
				if ToEnumShortString("PLAYER_P"..i) == "P"..side and submitText then
					submitText:queuecommand("SubmitFailed")
				end
			elseif playerData then
				if ToEnumShortString("PLAYER_P"..i) == "P"..side and ctx.submissions[side] then
					succeeded[side] = ctx.submissions[side].player
				end

				-- ECFA Events results for this play (empty when the chart isn't in an open event).
				ShowEventResults(overlay, i, playerData["events"])

				-- Upload any pack/song banners ECFA Cloud doesn't have yet.
				for hash in ivalues(playerData["missingBanners"] or {}) do
					if not uploadedBanners[hash] and ctx.bannerPaths[hash] then
						uploadedBanners[hash] = true
						UploadBannerToECFACloud(hash, ctx.bannerPaths[hash], ctx.apiKeys[side])
					end
				end

				-- And then also ensure that the chart hash matches the currently parsed one.
				-- It's better to just not display anything than display the wrong scores.
				if SL["P"..side].Streams.Hash == playerData["chartHash"] then
					local personalRank = nil
					local showExScore = SL["P"..side].ActiveModifiers.ShowExScore and playerData["exLeaderboard"]

					local leaderboardData = nil
					if showExScore then
						leaderboardData = playerData["exLeaderboard"]
					elseif playerData["wfLeaderboard"] then
						leaderboardData = playerData["wfLeaderboard"]
					end

					if leaderboardData then
						for entryData in ivalues(leaderboardData) do
							if entryNum > NumEntries then break end
							local entry = highScorePane:GetChild("HighScoreList"):GetChild("HighScoreEntry"..entryNum)
							entry:stoptweening()
							entry:diffuse(Color.White)
							SetEntryText(
								entryData["rank"]..".",
								GetMachineTag(entryData),
								string.format("%.2f%%", entryData["score"]/100),
								ParseECFACloudDate(entryData["date"]),
								entry
							)

							-- Highlight EX scores in blue.
							if showExScore then
								entry:GetChild("Score"):diffuse(SL.JudgmentColors["ITG"][1])
							else
								entry:GetChild("Score"):diffuse(Color.White)
							end

							if entryData["isRival"] then
								entry:diffuse(color("#BD94FF"))
								rivalNum = rivalNum + 1
							elseif entryData["isSelf"] then
								entry:diffuse(color("#A1FF94"))
								personalRank = entryData["rank"]
							end

							if entryData["isFail"] then
								entry:GetChild("Score"):diffuse(Color.Red)
							end
							entryNum = entryNum + 1
						end

						-- Empty out any remaining entries.
						for j=entryNum, NumEntries do
							local entry = highScorePane:GetChild("HighScoreList"):GetChild("HighScoreEntry"..j)
							entry:stoptweening()
							if j == 1 then
								SetEntryText("", "No Scores", "", "", entry)
							else
								SetEntryText("---", "----", "------", "----------", entry)
							end
						end

						QRPane:GetChild("HelpText"):settext(THEME:GetString("ECFACloud", "ScoreAlreadySubmitted"))
						if i == 1 and P1SubmitText then
							P1SubmitText:queuecommand("Submit")
						elseif i == 2 and P2SubmitText then
							P2SubmitText:queuecommand("Submit")
						end
					end

					-- Only update PB/WR messages on the side that is joined
					if ToEnumShortString("PLAYER_P"..i) == "P"..side then
						local upperPane = overlay:GetChild("P"..side.."_AF_Upper")
						if upperPane then
							if playerData["result"] == "score-added" or playerData["result"] == "improved" then
								local recordText = master:GetChild("P"..side.."RecordText")
								local logo = master:GetChild("P"..side.."ECFACloud_Logo")

								recordText:visible(true)
								logo:visible(true)
								recordText:diffuseshift():effectcolor1(Color.White):effectcolor2(Color.Yellow):effectperiod(3)
								if personalRank == 1 then
									local worldRecordText = THEME:GetString("ECFACloud", "WorldRecord")
									if showExScore then
										worldRecordText = worldRecordText .. " (EX)"
									end
									recordText:settext(worldRecordText)
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
						end
					end
				end
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

	-- e.g. "ECFA 2026 · +521 RP · #3 ▲2" (details are on Pane 9)
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
		Texture=THEME:GetPathG("","ECFACloud.png"),
		Name="P"..i.."ECFACloud_Logo",
		InitCommand=function(self)
			self:zoom(0.2)
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
