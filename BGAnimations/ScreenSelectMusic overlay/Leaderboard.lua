local NumEntries = 13
local RowHeight = 24
local paneWidth2Player = 230

-- Name column; blended rows narrow it to fit the source tag after the rank.
local NameX, NameMaxWidth = -paneWidth2Player/2 + 100, 130
local BlendedNameX, BlendedNameMaxWidth = -paneWidth2Player/2 + 113, 104

-- source: a BlendedSource key ("ECFA", "GS" or "AC") for blended rows, else nil.
local SetEntryText = function(rank, name, score, date, actor, source)
	if actor == nil then return end

	actor:GetChild("Rank"):settext(rank):diffuse(Color.White)
	actor:GetChild("Name"):settext(name):diffuse(Color.White)
	actor:GetChild("Score"):settext(score):diffuse(Color.White)
	actor:GetChild("Date"):settext(date):diffuse(Color.White)

	local tag = BlendedSource[source or ""]
	actor:GetChild("Source"):settext(tag and tag.label or ""):diffuse(tag and tag.color or Color.White)
	if tag then
		actor:GetChild("Name"):x(BlendedNameX):maxwidth(BlendedNameMaxWidth)
	else
		actor:GetChild("Name"):x(NameX):maxwidth(NameMaxWidth)
	end
end

local SelfColor = color("#A1FF94")
local RivalColor = color("#BD94FF")

local SetLeaderboardForPlayer = function(player_num, leaderboard, leaderboardData, isRanked)
	if leaderboard == nil or leaderboardData == nil then return end
	local playerStr = "player"..player_num
	local entryNum = 1
	local rivalNum = 1

	-- The blended board's legend: a source is dimmed while loading and faint
	-- when it failed or the player has no key for it.
	local blended = leaderboardData["Blended"]
	for source in ivalues(BlendedSources) do
		local legend = leaderboard:GetChild("Legend"..source.key)
		legend:visible(blended and true or false)
		if blended then
			local status = leaderboardData["Status"][source.key]
			legend:diffuse(source.color):diffusealpha(status == "ok" and 1 or (status == "pending" and 0.5 or 0.2))
		end
	end

	if leaderboardData["Disabled"] then
		if leaderboardData["Name"] then
			local name = leaderboardData["Name"]
			leaderboard:GetChild("Header"):settext(name)
		end
		for j=1, NumEntries do
			local entry = leaderboard:GetChild("LeaderboardEntry"..j)
			if j == 1 then
				SetEntryText("", "Disabled", "", "", entry)
			else
				-- Empty out the remaining rows.
				SetEntryText("", "", "", "", entry)
			end
		end
		return
	end

	-- Hide the rival and self highlights.
	-- They will be unhidden and repositioned as needed below.
	for i=1,3 do
		leaderboard:GetChild("Rival"..i):visible(false)
	end
	leaderboard:GetChild("Self"):visible(false)

	-- Hide/Unhide EX score display
	leaderboard:GetChild("EX"):visible(leaderboardData["IsEX"])

	if leaderboardData then
		if leaderboardData["Name"] then
			local name = leaderboardData["Name"]
			leaderboard:GetChild("Header"):settext(name)
		end

		if leaderboardData["Data"] then
			local added = {}
			for gsEntry in ivalues(leaderboardData["Data"]) do
				-- The blended board can list the same name once per source.
				local key = blended and (gsEntry["source"].."\n"..gsEntry["name"]) or gsEntry["name"]
				if not added[key] then
					added[key] = true
					local entry = leaderboard:GetChild("LeaderboardEntry"..entryNum)
					SetEntryText(
						gsEntry["rank"] and (gsEntry["rank"]..".") or "",
						gsEntry["name"],
						string.format("%.2f%%", gsEntry["score"]/100),
						blended and FormatBlendedDate(gsEntry["date"]) or ParseECFACloudDate(gsEntry["date"]),
						entry,
						blended and gsEntry["source"] or nil
					)
					if blended then
						-- Your own scores can show up once per service, so color the
						-- text instead of using the single highlight bar.
						entry:diffuse(Color.White)
						local clr = gsEntry["isSelf"] and SelfColor or (gsEntry["isRival"] and RivalColor or nil)
						if clr then
							for child in ivalues({"Rank", "Name", "Score", "Date"}) do
								entry:GetChild(child):diffuse(clr)
							end
						end
					elseif gsEntry["isRival"] then
						if gsEntry["isFail"] then
							entry:GetChild("Rank"):diffuse(Color.Black)
							entry:GetChild("Name"):diffuse(Color.Black)
							entry:GetChild("Score"):diffuse(Color.Red)
							entry:GetChild("Date"):diffuse(Color.Black)
						else
							entry:diffuse(Color.Black)
						end
						leaderboard:GetChild("Rival"..rivalNum):y(entry:GetY()):visible(true)
						rivalNum = rivalNum + 1
					elseif gsEntry["isSelf"] then
						if gsEntry["isFail"] then
							entry:GetChild("Rank"):diffuse(Color.Black)
							entry:GetChild("Name"):diffuse(Color.Black)
							entry:GetChild("Score"):diffuse(Color.Red)
							entry:GetChild("Date"):diffuse(Color.Black)
						else
							entry:diffuse(Color.Black)
						end
						leaderboard:GetChild("Self"):y(entry:GetY()):visible(true)
					else
						entry:diffuse(Color.White)
					end

					-- Why does this work for normal entries but not for Rivals/Self where
					-- I have to explicitly set the colors for each child??
					if gsEntry["isFail"] then
						entry:GetChild("Score"):diffuse(Color.Red)
					end
					entryNum = entryNum + 1
				end
			end
		end
	end

	-- Empty out any remaining entries.
	-- This also handles the error case. If success is false, then the above if block will not run.
	-- and we will set the first entry to "Failed to Load 😞".
	local stillLoading = false
	for source in ivalues(blended and BlendedSources or {}) do
		stillLoading = stillLoading or leaderboardData["Status"][source.key] == "pending"
	end
	for i=entryNum, NumEntries do
		local entry = leaderboard:GetChild("LeaderboardEntry"..i)
		-- We didn't get any scores if i is still == 1.
		if i == 1 then
			SetEntryText("", stillLoading and THEME:GetString("ECFACloud", "Loading") or "No Scores", "", "", entry)
		else
			-- Empty out the remaining rows.
			SetEntryText("", "", "", "", entry)
		end
	end
end
local getLocalLeaderboard = function(pn)
	if not GAMESTATE:IsPlayerEnabled(pn) then return {} end
    local HighScores = PROFILEMAN:GetMachineProfile():GetHighScoreList(GAMESTATE:GetCurrentSong(),GAMESTATE:GetCurrentSteps(pn)):GetHighScores()
    local profileName = PROFILEMAN:GetProfile(pn):GetLastUsedHighScoreName()
    local localData = {}
    if HighScores then
        for i, highscore in ipairs(HighScores) do
            local name = highscore:GetName()
            local percentDP = highscore:GetPercentDP()
            local score = tonumber(("%.0f"):format(percentDP * 10000))
            local date = highscore:GetDate()
            local grade = highscore:GetGrade()
            local isRival = false
            local isSelf = name == profileName
            local isFail = false
            if grade == "Grade_Failed" then
                isFail = true
            end
            local entry = {
                name=name,
                score=score,
                date=date,
                isRival=isRival,
                isSelf=isSelf,
                isFail=isFail,
                rank=i
            }
            table.insert(localData, entry)
        end
    end
    return localData
end
-- Shows the More Leaderboards arrows when a player has more than one board.
local UpdatePaneIcons = function(master, pn)
	master:GetChild(pn.."Leaderboard"):GetChild("PaneIcons"):visible(#master[pn]["Leaderboards"] > 1)
end

-- Rebuilds a player's blended board from what has arrived so far, and redraws
-- it if it's the board on screen.
local RefreshBlended = function(master, pn)
	local blend = master[pn] and master[pn].Blend
	if not blend or not blend.page then return end
	blend.page.Data = BlendLeaderboards(blend.lists, NumEntries)
	UpdatePaneIcons(master, pn)
	if master[pn]["Leaderboards"][master[pn]["LeaderboardIndex"]] == blend.page then
		SetLeaderboardForPlayer(pn == "P1" and 1 or 2, master:GetChild(pn.."Leaderboard"), blend.page, master[pn].isRanked)
	end
end

-- Puts the blended board first and asks GrooveStats (with the player's key) and
-- ArrowCloud for the chart's EX leaderboard (read only).
local StartBlended = function(master, player)
	local pn = ToEnumShortString(player)
	if not GAMESTATE:IsSideJoined(player) or SL[pn].Streams.Hash == "" or not HasBlendedLeaderboardSources(player) then return end

	local blend = master[pn].Blend
	blend.status = {
		ECFA = (SL[pn].ApiKey ~= "" and IsServiceAllowed(SL.ECFACloud.Leaderboard)) and "pending" or "off",
		GS = SL[pn].GrooveStatsApiKey ~= "" and "pending" or "off",
		AC = "pending",
	}
	blend.page = {
		Name=THEME:GetString("ECFACloud", "BlendedLeaderboard"),
		Data={},
		IsEX=true,
		Blended=true,
		Status=blend.status,
	}
	table.insert(master[pn]["Leaderboards"], 1, blend.page)
	master[pn]["LeaderboardIndex"] = 1

	blend.handle = FetchBlendedSources(player, SL[pn].Streams.Hash, NumEntries, function(results)
		blend.handle = nil
		for key in ivalues({"GS", "AC"}) do
			if results[key] then
				blend.lists[key] = results[key].entries
				blend.status[key] = results[key].error and "error" or "ok"
			end
		end
		RefreshBlended(master, pn)
	end)
	RefreshBlended(master, pn)
end

local CancelBlended = function(master)
	for pn in ivalues({"P1", "P2"}) do
		local blend = master[pn] and master[pn].Blend
		if blend and blend.handle then
			blend.handle:Cancel()
			blend.handle = nil
		end
	end
end

local LeaderboardRequestProcessor = function(res, master)
	if master == nil then return end

	if res.error or res.statusCode ~= 200 then
		local error = res.error and ToEnumShortString(res.error) or nil
		local text = ""
		if error == "Timeout" then
			text = "Timed Out"
		elseif error or (res.statusCode ~= nil and res.statusCode ~= 200) then
			text = "Failed to Load 😞"
		end
		for i=1, 2 do
			local pn = "P"..i
			local leaderboard = master:GetChild(pn.."Leaderboard")
			local leaderboardList = master[pn]["Leaderboards"]
			local localData = getLocalLeaderboard(pn)
			leaderboardList[#leaderboardList + 1] = {
				Name="Machine's  Best",
				Data=DeepCopy(localData),
				IsEX=false
			}
			master[pn]["LeaderboardIndex"] = 1
			local blend = master[pn].Blend
			if blend.page then
				-- The blended board still has the other services' scores.
				if blend.status.ECFA == "pending" then blend.status.ECFA = "error" end
				RefreshBlended(master, pn)
			else
				for j=1, NumEntries do
					local entry = leaderboard:GetChild("LeaderboardEntry"..j)
					if j == 1 then
						SetEntryText("", text, "", "", entry)
					else
						-- Empty out the remaining rows.
						SetEntryText("", "", "", "", entry)
					end
				end
			end
		end
		return
	end

	local data = JsonDecode(res.body)

	for i=1, 2 do
		local playerStr = "player"..i
		local pn = "P"..i
		local leaderboard = master:GetChild(pn.."Leaderboard")
		local leaderboardList = master[pn]["Leaderboards"]

		local blend = master[pn].Blend
		if blend.page and blend.status.ECFA == "pending" then
			if data[playerStr] and not data[playerStr]["error"] then
				blend.lists.ECFA = BlendedEntriesFromECFACloud(data[playerStr]["exLeaderboard"])
				blend.status.ECFA = "ok"
			else
				blend.status.ECFA = "error"
			end
			blend.page.Data = BlendLeaderboards(blend.lists, NumEntries)
		end

		if data[playerStr] then
			master[pn].isRanked = data[playerStr]["isRanked"]

			-- The Waterfall leaderboard first, then the simulated ITG and EX ones
			-- (EX first of those if the player prefers EX).
			local boards = {
				{ key="wfLeaderboard", name="ECFA Cloud", isEx=false },
				{ key="itgLeaderboard", name="ITG", isEx=false },
				{ key="exLeaderboard", name="EX", isEx=true },
			}
			if SL["P"..i].ActiveModifiers.ShowExScore then
				boards[2], boards[3] = boards[3], boards[2]
			end
			for board in ivalues(boards) do
				if data[playerStr][board.key] then
					leaderboardList[#leaderboardList + 1] = {
						Name=board.name,
						Data=DeepCopy(data[playerStr][board.key]),
						IsEX=board.isEx
					}
					master[pn]["LeaderboardIndex"] = 1
				end
			end

			-- Then any event leaderboards.
			-- ECFA Cloud event leaderboards are Waterfall scored.
			for ev in ivalues(data[playerStr]["events"] or {}) do
				if ev["leaderboard"] then
					leaderboardList[#leaderboardList + 1] = {
						Name=ev["name"],
						Data=DeepCopy(ev["leaderboard"]),
						IsEX=false
					}
					master[pn]["LeaderboardIndex"] = 1
				end
			end

			-- Display the local leaderboard last
			local localData = getLocalLeaderboard(pn)
			leaderboardList[#leaderboardList + 1] = {
				Name="Machine's  Best",
				Data=DeepCopy(localData),
				IsEX=false
			}
			master[pn]["LeaderboardIndex"] = 1

		end
		UpdatePaneIcons(master, pn)

		-- We assume that at least one leaderboard has been added.
		-- If leaderboardData is nil as a result, the SetLeaderboardForPlayer
		-- function will handle it.
		local leaderboardData = leaderboardList[1]
		SetLeaderboardForPlayer(i, leaderboard, leaderboardData, master[pn].isRanked)
	end
end

local af = Def.ActorFrame{
	Name="LeaderboardMaster",
	InitCommand=function(self) self:visible(false) end,
	ShowLeaderboardCommand=function(self)
		self:visible(true)
		CancelBlended(self)
		for i=1, 2 do
			local pn = "P"..i
			self[pn] = {}
			self[pn].isRanked = false
			self[pn].Leaderboards = {}
			self[pn].LeaderboardIndex = 0
			self[pn].Blend = { lists={}, status={} }
		end
		MESSAGEMAN:Broadcast("ResetEntry")
		-- Only make the request when this actor gets actually displayed through the sort menu.
		self:queuecommand("SendLeaderboardRequest")
	end,
	HideLeaderboardCommand=function(self)
		CancelBlended(self)
		self:visible(false)
	end,
	OffCommand=function(self) CancelBlended(self) end,
	LeaderboardInputEventMessageCommand=function(self, event)
		local pn = ToEnumShortString(event.PlayerNumber)
		if #self[pn].Leaderboards == 0 then return end

		if event.type == "InputEventType_FirstPress" then
			-- We don't use modulus because #Leaderboards might be zero.
			if event.GameButton == "MenuLeft" then
				self[pn].LeaderboardIndex = self[pn].LeaderboardIndex - 1

				if self[pn].LeaderboardIndex == 0 then
					-- Wrap around if we decremented from 1 to 0.
					self[pn].LeaderboardIndex = #self[pn].Leaderboards
				end
			elseif event.GameButton == "MenuRight" then
				self[pn].LeaderboardIndex = self[pn].LeaderboardIndex + 1

				if self[pn].LeaderboardIndex > #self[pn].Leaderboards then
					-- Wrap around if we incremented past #Leaderboards
					self[pn].LeaderboardIndex = 1
				end
			end

			if event.GameButton == "MenuLeft" or event.GameButton == "MenuRight" then
				local leaderboard = self:GetChild(pn.."Leaderboard")
				local leaderboardList = self[pn]["Leaderboards"]
				local leaderboardData = leaderboardList[self[pn].LeaderboardIndex]
				SetLeaderboardForPlayer("P1" == pn and 1 or 2, leaderboard, leaderboardData, self[pn].isRanked)
			end
		end
	end,

	Def.Quad{ InitCommand=function(self) self:FullScreen():diffuse(0,0,0,0.875) end },
	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Text=THEME:GetString("Common", "PopupDismissText"),
		InitCommand=function(self) self:xy(_screen.cx, _screen.h-50):zoom(1.1) end
	},
	RequestResponseActor(17, 50)..{
		SendLeaderboardRequestCommand=function(self)
			-- The blended board (GrooveStats/ArrowCloud, read only) goes first.
			for player in ivalues(PlayerNumber) do
				StartBlended(self:GetParent(), player)
			end
			-- If a player does not have an API key or chart hash just show the local leaderboard.
			for i=1,2 do
				local pn = "P"..i
				if SL[pn].ApiKey == "" or SL[pn].Streams.Hash == "" or not IsServiceAllowed(SL.ECFACloud.Leaderboard) then
					local pn = "P"..i
					local leaderboard = self:GetParent():GetChild(pn.."Leaderboard")
					local leaderboardList = self:GetParent()[pn]["Leaderboards"]
					local localData = getLocalLeaderboard(pn)
					leaderboardList[#leaderboardList + 1] = {
						Name="Machine's  Best",
						Data=DeepCopy(localData),
						IsEX=false
					}
					self:GetParent()[pn]["LeaderboardIndex"] = 1
					UpdatePaneIcons(self:GetParent(), pn)
				end
			end
			if not IsServiceAllowed(SL.ECFACloud.Leaderboard) then
				if SL.ECFACloud.IsConnected then
					-- If we disable the service from a previous request, surface it to the user here.
					for i=1, 2 do
						local pn = "P"..i
						local leaderboard = self:GetParent():GetChild(pn.."Leaderboard")
						local leaderboardList = self:GetParent()[pn]["Leaderboards"]
						leaderboardList[#leaderboardList + 1] = {
							Name="ECFA Cloud",
							Disabled=true,
							IsEX=false
						}
						SetLeaderboardForPlayer(i, leaderboard, leaderboardList[1], false)
					end
				end
				return
			end

			local sendRequest = false
			local headers = {}
			local query = {
				maxLeaderboardResults=NumEntries,
			}

			for i=1,2 do
				local pn = "P"..i
				if SL[pn].ApiKey ~= "" and SL[pn].Streams.Hash ~= "" then
					query["chartHashP"..i] = SL[pn].Streams.Hash
					headers["x-api-key-player-"..i] = SL[pn].ApiKey
					sendRequest = true
				end
			end
			-- Only send the request if it's applicable.
			-- Technically this should always be true since otherwise we wouldn't even get to this screen.
			if sendRequest then
				self:playcommand("MakeECFACloudRequest", {
					endpoint="player-leaderboards?"..NETWORK:EncodeQueryParameters(query),
					method="GET",
					headers=headers,
					timeout=10,
					callback=LeaderboardRequestProcessor,
					args=SCREENMAN:GetTopScreen():GetChild("Overlay"):GetChild("LeaderboardMaster"),
				})
			end
		end
	}
}

local paneWidth1Player = 330
local paneWidth = (GAMESTATE:GetNumSidesJoined() == 1) and paneWidth1Player or paneWidth2Player
local paneHeight = 360
local borderWidth = 2

for player in ivalues( PlayerNumber ) do
	af[#af+1] = Def.ActorFrame{
		Name=ToEnumShortString(player).."Leaderboard",
		InitCommand=function(self)
			self:y(_screen.cy - 15)
			self:queuecommand("Refresh")
		end,
		PlayerJoinedMessageCommand=function(self)
			self:queuecommand("Refresh")
		end,

		RefreshCommand=function(self)
			self:visible(GAMESTATE:IsSideJoined(player))

			if GAMESTATE:GetNumSidesJoined() == 1 then
				self:xy(_screen.cx, _screen.cy - 15)
			else
				self:xy(_screen.cx + 160 * (player==PLAYER_1 and -1 or 1), _screen.cy - 15)
			end
			self:SetWidth(paneWidth)
		end,

		-- White border
		Def.Quad {
			InitCommand=function(self)
				self:diffuse(Color.White)
			end,
			RefreshCommand=function(self)
				local width = self:GetParent():GetWidth()
				self:zoomto(width + borderWidth, paneHeight + borderWidth)
			end
		},

		-- Main black body
		Def.Quad {
			InitCommand=function(self)
				self:diffuse(Color.Black)
			end,
			RefreshCommand=function(self)
				local width = self:GetParent():GetWidth()
				self:zoomto(width, paneHeight)
			end
		},

		-- Header border
		Def.Quad {
			InitCommand=function(self)
				self:diffuse(Color.White):y(-paneHeight/2 + RowHeight/2)
			end,
			RefreshCommand=function(self)
				local width = self:GetParent():GetWidth()
				self:zoomto(width + borderWidth, RowHeight + borderWidth)
			end
		},

		-- Blue Header
		Def.Quad {
			InitCommand=function(self)
				self:diffuse(Color.Blue):y(-paneHeight/2 + RowHeight/2)
			end,
			RefreshCommand=function(self)
				local width = self:GetParent():GetWidth()
				self:zoomto(width, RowHeight)
			end
		},

		-- Header Text
		LoadFont("Wendy/_wendy small").. {
			Name="Header",
			Text="ECFA Cloud",
			InitCommand=function(self)
				self:zoom(0.5)
				self:y(-paneHeight/2 + 12)
			end
		},

		-- EX Text
		LoadFont("Wendy/_wendy small").. {
			Name="EX",
			Text="EX",
			InitCommand=function(self)
				self:zoom(0.5)
				self:y(-paneHeight/2 + 12)
				self:x(paneWidth/2 - 16)
				self:visible(false)
			end
		},

		-- Blended board legend: which services are in the list.
		LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal").. {
			Name="LegendECFA",
			Text=BlendedSource["ECFA"].label,
			InitCommand=function(self)
				self:zoom(0.75):horizalign(left):y(-paneHeight/2 + 12):visible(false)
			end,
			RefreshCommand=function(self)
				self:x(-self:GetParent():GetWidth()/2 + 6 + 0 * 22)
			end
		},
		LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal").. {
			Name="LegendGS",
			Text=BlendedSource["GS"].label,
			InitCommand=function(self)
				self:zoom(0.75):horizalign(left):y(-paneHeight/2 + 12):visible(false)
			end,
			RefreshCommand=function(self)
				self:x(-self:GetParent():GetWidth()/2 + 6 + 1 * 22)
			end
		},
		LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal").. {
			Name="LegendAC",
			Text=BlendedSource["AC"].label,
			InitCommand=function(self)
				self:zoom(0.75):horizalign(left):y(-paneHeight/2 + 12):visible(false)
			end,
			RefreshCommand=function(self)
				self:x(-self:GetParent():GetWidth()/2 + 6 + 2 * 22)
			end
		},

		-- Highlight backgrounds for the leaderboard. Initially hidden.
		Def.Quad {
			Name="Rival1",
			InitCommand=function(self)
				self:diffuse(color("#BD94FF")):visible(false)
			end,
			ResetEntryMessageCommand=function(self)
				self:visible(false)
			end,
			RefreshCommand=function(self)
				local width = self:GetParent():GetWidth()
				self:zoomto(width, RowHeight)
			end
		},

		Def.Quad {
			Name="Rival2",
			InitCommand=function(self)
				self:diffuse(color("#BD94FF")):visible(false)
			end,
			ResetEntryMessageCommand=function(self)
				self:visible(false)
			end,
			RefreshCommand=function(self)
				local width = self:GetParent():GetWidth()
				self:zoomto(width, RowHeight)
			end
		},

		Def.Quad {
			Name="Rival3",
			InitCommand=function(self)
				self:diffuse(color("#BD94FF")):visible(false)
			end,
			ResetEntryMessageCommand=function(self)
				self:visible(false)
			end,
			RefreshCommand=function(self)
				local width = self:GetParent():GetWidth()
				self:zoomto(width, RowHeight)
			end
		},

		Def.Quad {
			Name="Self",
			InitCommand=function(self)
				self:diffuse(color("#A1FF94")):visible(false)
			end,
			ResetEntryMessageCommand=function(self)
				self:visible(false)
			end,
			RefreshCommand=function(self)
				local width = self:GetParent():GetWidth()
				self:zoomto(width, RowHeight)
			end
		},

		-- Marker for the additional panes. Hidden by default.
		Def.ActorFrame{
			Name="PaneIcons",
			InitCommand=function(self)
				self:y(paneHeight/2 - RowHeight/2)
				self:visible(false)
			end,
			ResetEntryMessageCommand=function(self)
				self:visible(false)
			end,

			LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal").. {
				Name="LeftIcon",
				Text="&MENULEFT;",
				InitCommand=function(self)
					self:x(-paneWidth/2 + 10)
				end,
				OnCommand=function(self) self:queuecommand("Bounce") end,
				BounceCommand=function(self)
					self:decelerate(0.5):addx(10):accelerate(0.5):addx(-10)
					self:queuecommand("Bounce")
				end,
			},

			LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal").. {
				Name="Text",
				Text=THEME:GetString("ECFACloud", "MoreLeaderboards"),
				InitCommand=function(self)
					self:diffuse(Color.White)
				end,
			},

			LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal").. {
				Name="RightIcon",
				Text="&MENURiGHT;",
				InitCommand=function(self)
					self:x(paneWidth/2 - 10)
				end,
				OnCommand=function(self) self:queuecommand("Bounce") end,
				BounceCommand=function(self)
					self:decelerate(0.5):addx(-10):accelerate(0.5):addx(10)
					self:queuecommand("Bounce")
				end,
			},
		}
	}

	local af2 = af[#af]
	for i=1, NumEntries do
		--- Each entry has a Rank, Name, and Score subactor.
		af2[#af2+1] = Def.ActorFrame{
			Name="LeaderboardEntry"..i,
			InitCommand=function(self)
				if NumEntries % 2 == 1 then
					self:y(RowHeight*(i - (NumEntries+1)/2) )
				else
					self:y(RowHeight*(i - NumEntries/2))
				end
			end,
			RefreshCommand=function(self)
				local width = self:GetParent():GetWidth()
				self:x(-(width-paneWidth2Player)/2)
				self:GetChild("Date"):visible(GAMESTATE:GetNumSidesJoined() == 1)
			end,

			LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal").. {
				Name="Rank",
				Text="",
				InitCommand=function(self)
					self:horizalign(right)
					self:maxwidth(30)
					self:x(-paneWidth2Player/2 + 30 + borderWidth)
					self:diffuse(Color.White)
				end,
				ResetEntryMessageCommand=function(self)
					self:settext("")
					self:diffuse(Color.White)
				end
			},

			-- Source tag (EC/GS/AC) on blended rows, between the rank and the name.
			LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal").. {
				Name="Source",
				Text="",
				InitCommand=function(self)
					self:horizalign(left)
					self:zoom(0.75)
					self:x(-paneWidth2Player/2 + 36 + borderWidth)
				end,
				ResetEntryMessageCommand=function(self)
					self:settext("")
				end
			},

			LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal").. {
				Name="Name",
				Text=(i==1 and THEME:GetString("ECFACloud", "Loading") or ""),
				InitCommand=function(self)
					self:horizalign(center)
					self:maxwidth(130)
					self:x(-paneWidth2Player/2 + 100)
					self:diffuse(Color.White)
				end,
				ResetEntryMessageCommand=function(self)
					self:settext(i==1 and THEME:GetString("ECFACloud", "Loading") or "")
					self:diffuse(Color.White)
					self:x(NameX):maxwidth(NameMaxWidth)
				end
			},

			LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal").. {
				Name="Score",
				Text="",
				InitCommand=function(self)
					self:horizalign(right)
					self:x(paneWidth2Player/2-borderWidth)
					self:diffuse(Color.White)
				end,
				ResetEntryMessageCommand=function(self)
					self:settext("")
					self:diffuse(Color.White)
				end
			},
			LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal").. {
				Name="Date",
				Text="",
				InitCommand=function(self)
					self:horizalign(right)
					self:x(paneWidth2Player/2 + 100 - borderWidth)
					self:diffuse(Color.White)
				end,
				ResetEntryMessageCommand=function(self)
					self:settext("")
					self:diffuse(Color.White)
				end
			},
		}
	end
end

return af
