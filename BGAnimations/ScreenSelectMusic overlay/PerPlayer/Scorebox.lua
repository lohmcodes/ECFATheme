-- Leaderboards in a small box on the song wheel. Not for courses.
--
-- The box rotates through these boards, each switched on or off in the Show Score
-- Boxes player option, and always says which one it's showing (EX or WF, and where
-- the scores come from):
--   0  Blended EX: ECFA Cloud, GrooveStats and ArrowCloud EX scores in one list
--   1  GrooveStats EX
--   2  ArrowCloud EX
--   3  ECFA Cloud WF (Waterfall)
--   4  the event leaderboard (WF), when the chart is in an open ECFA Cloud event
-- ECFA Cloud fetches the GrooveStats and ArrowCloud boards (SL-Helpers-BlendedLeaderboard.lua).
if GAMESTATE:IsCourseMode() then return end

-- Respect existing preference for where to show a scorebox
if ThemePrefs.Get("MusicWheelGS") ~= "Scorebox" then return end

local player = ...
local pn = ToEnumShortString(player)

if not IsServiceAllowed(SL.ECFACloud.GetScores) or SL[pn].ApiKey == "" then return end

local n = player==PLAYER_1 and "1" or "2"
local IsNotWide = (GetScreenAspectRatio() < 16/9)
local NumEntries = 10

local border = 5
local width = 162
-- Ten rows in a box taller than the old five-row one, raised by half the growth
-- so its bottom edge stays where it was (clear of the footer).
local height = 110
local yShift = -(height - 80) / 2
local row_spacing = height / NumEntries
local text_zoom = 0.6
-- How wide a name may get on screen (maxwidth is measured before the zoom): up
-- to the score, or up to the source tag on the blended board.
local NameRoom = function(blended)
	local narrow = IsNotWide and #GAMESTATE:GetHumanPlayers() > 1
	if narrow then return (blended and 44 or 60) / text_zoom end
	return (blended and 80 or 95) / text_zoom
end

local BOARDS = {
	[0] = { option="SBBlended",     kind="EX", label="Blended",     color=color("#c0c0c0"), external=true },
	[1] = { option="SBGrooveStats", kind="EX", label="GrooveStats", color=color("#f2a33a"), external=true },
	[2] = { option="SBArrowCloud",  kind="EX", label="ArrowCloud",  color=color("#56b4ef"), external=true },
	[3] = { option="SBITGScore",    kind="WF", label="ECFA Cloud",  color=color("#b8327a") },
	[4] = { option="SBEvents",      kind="WF", label="",            color=color("#c9a227") }, -- labeled with the event's name
}
local num_styles = 5
local cur_style = 0

-- Boards with data, in rotation order.
local styleOrder = {}
local styleOrderSet = {}

local currentHash = "nothing"

local self_color = color("#a1ff94")
local rival_color = color("#c29cff")

local loop_seconds = 5
local transition_seconds = 0.5
local anim_seconds = transition_seconds
-- True while a request is in flight for the current chart (keeps the spinner up).
local pending = false
-- Bumped every time MakeRequestCommand starts a new request (new chart
-- selected). A response whose generation no longer matches is for a chart the
-- player has since scrolled past, and is discarded.
local requestGeneration = 0

local all_data = {}

local ResetAllData = function()
	all_data = {}
	styleOrder = {}
	styleOrderSet = {}
	SL[pn].Rival = {}
	SL[pn].Rival.Score = 0
	SL[pn].Rival.ExScore = 0
	SL[pn].Rival.WRScore = 0
	SL[pn].Rival.WRExScore = 0

	for i=1,num_styles do
		local data = { has_data=false, scores={} }
		for j=1,NumEntries do
			data.scores[j] = { rank="", name="", score="", isSelf=false, isRival=false, isFail=false, source=nil }
		end
		all_data[i] = data
	end
end

-- Initialize the all_data object.
ResetAllData()

-- Whether the player wants a board in the rotation.
local Wanted = function(style)
	return SL[pn].ActiveModifiers[BOARDS[style].option] and true or false
end

-- Whether to ask ECFA Cloud for the GrooveStats and ArrowCloud boards too.
local WantsExternal = function()
	for style=0,num_styles-1 do
		if BOARDS[style].external and Wanted(style) then return true end
	end
	return false
end

-- The best rival/own score and the #1 score on ECFA Cloud's WF and EX boards, for
-- the rival pace in SubtractiveScoring (whether or not those boards are shown).
local TrackRivals = function(board, isEx)
	for e in ivalues(board or {}) do
		local value = tonumber(e["score"]) and tonumber(e["score"]) / 100
		if value then
			if not e["isFail"] and (e["isRival"] or e["isSelf"]) then
				if isEx then
					SL[pn].Rival.ExScore = math.max(SL[pn].Rival.ExScore, value)
				else
					SL[pn].Rival.Score = math.max(SL[pn].Rival.Score, value)
				end
			end
			if tonumber(e["rank"]) == 1 then
				if isEx then
					SL[pn].Rival.WRExScore = math.max(SL[pn].Rival.WRExScore, value)
				else
					SL[pn].Rival.WRScore = math.max(SL[pn].Rival.WRScore, value)
				end
			end
		end
	end
end

-- Fills a board and adds it to the rotation. rows: entries as from
-- LeaderboardEntries/BlendLeaderboards; emptyText: shown when there are none.
local FillBoard = function(style, rows, emptyText)
	local data = all_data[style+1]
	data.has_data = true
	data.scores[1].name = emptyText or "No Scores"
	local count = 0
	local seen = {}
	for e in ivalues(rows or {}) do
		if count >= NumEntries then break end
		-- One row per player on a single-source board (the blended board does its own merging).
		local id = (e.source or "").."\n"..e.name
		if not seen[id] then
			seen[id] = true
			count = count + 1
			local row = data.scores[count]
			row.rank = BlendedRankText(e)
			row.name = e.name
			row.score = string.format("%.2f", e.score/100)
			row.isSelf = e.isSelf
			row.isRival = e.isRival
			row.isFail = e.isFail
			row.source = e.source
		end
	end
	if styleOrderSet[style] then return end
	styleOrderSet[style] = true
	styleOrder[#styleOrder+1] = style
	table.sort(styleOrder)
end

-- The first board the player has switched on, for showing an error.
local FirstWantedStyle = function()
	for style=0,num_styles-1 do
		if Wanted(style) then return style end
	end
	return 3
end

local LeaderboardRequestProcessor = function(res, args)
	local master = args and args.parent
	-- Discard responses for a chart we've since scrolled past.
	if not args or args.generation ~= requestGeneration or master == nil then return end
	pending = false

	if res.error or res.statusCode ~= 200 then
		local error = res.error and ToEnumShortString(res.error) or nil
		FillBoard(FirstWantedStyle(), {}, error == "Timeout" and "Timed Out" or "Failed to Load 😞")
		master:queuecommand("CheckScorebox")
		return
	end

	local playerStr = "player"..n
	local data = JsonDecode(res.body)
	local d = data and data[playerStr]

	-- ECFA Cloud refused this player, e.g. their API key was revoked or their account deleted.
	if d and d["error"] then
		FillBoard(FirstWantedStyle(), {}, d["error"] == "invalid-api-key" and "Invalid API key" or "Failed to Load 😞")
		master:queuecommand("CheckScorebox")
		return
	end

	if d then
		if SL[pn].Streams.Hash ~= d["chartHash"] then return end
		currentHash = SL[pn].Streams.Hash
		TrackRivals(d["wfLeaderboard"], false)
		TrackRivals(d["exLeaderboard"], true)

		if Wanted(0) then FillBoard(0, BlendLeaderboards(ExSourcesFromResponse(d), NumEntries)) end
		-- A missing GrooveStats/ArrowCloud board means ECFA Cloud couldn't get it.
		if Wanted(1) then
			local gs = LeaderboardEntries(d["gsExLeaderboard"])
			FillBoard(1, gs or {}, gs and "No Scores" or "Unavailable")
		end
		if Wanted(2) then
			local ac = LeaderboardEntries(d["acExLeaderboard"])
			FillBoard(2, ac or {}, ac and "No Scores" or "Unavailable")
		end
		if Wanted(3) then FillBoard(3, LeaderboardEntries(d["wfLeaderboard"])) end

		-- The first open event that includes this chart.
		local ev = d["events"] and d["events"][1]
		if Wanted(4) and ev and ev["leaderboard"] then
			BOARDS[4].label = ev["name"] or ""
			FillBoard(4, LeaderboardEntries(ev["leaderboard"]))
		end
	end
	master:queuecommand("CheckScorebox")
end

local af = Def.ActorFrame{
	Name="ScoreBox"..pn,
	InitCommand=function(self)
		if #GAMESTATE:GetHumanPlayers() == 1 then
			self:x(_screen.cx + 80):y(_screen.cy + 160 + yShift)
			if pn == "P2" then
				self:y(_screen.cy*1.65 - 55 + yShift)
			end
		else
			if pn == "P1" then
				self:zoom(0.65):x(_screen.cx - 65):y(_screen.cy + 178 + yShift)
				if IsNotWide then
					self:x(_screen.cx - 48)
				end
			else
				self:zoom(0.65):x(_screen.cx + 371):y(_screen.cy + 178 + yShift)
				if IsNotWide then
					self:x(_screen.cx + 279)
				end
			end
		end
		self.isFirst = true
	end,
	ResetCommand=function(self) self:stoptweening() end,
	OffCommand=function(self) self:stoptweening() end,
	PlayerJoinedMessageCommand=function(self, params)
		if pn == "P1" then
			self:zoom(0.65):x(_screen.cx - 65):y(_screen.cy + 178 + yShift)
			if IsNotWide then
				self:x(_screen.cx - 48)
			end
		else
			self:zoom(0.65):x(_screen.cx + 371):y(_screen.cy + 178 + yShift)
			if IsNotWide then
				self:x(_screen.cx + 279)
			end
		end
	end,
	PlayerUnjoinedMessageCommand=function(self, params)
		if params.Player == player then
			self:visible(false)
		end
		self:x(_screen.cx + 80):y(_screen.cy + 160 + yShift):zoom(1)
		if pn == "P2" then
			self:y(_screen.cy*1.65 - 55 + yShift)
		end
	end,
	CurrentSongChangedMessageCommand=function(self)
		self:finishtweening():visible(false)
		self.isFirst = true
	end,
	CheckScoreboxCommand=function(self)
		if GAMESTATE:GetCurrentSong() and GAMESTATE:GetCurrentSteps(player) then
			self:queuecommand("LoopScorebox")
		end
	end,
	LoopScoreboxCommand=function(self)
		self:visible(true)

		if #styleOrder == 0 then return end

		self:finishtweening()

		-- On first display, use zero animation time so content appears instantly.
		anim_seconds = self.isFirst and 0 or transition_seconds

		-- Always start on the first board (Blended EX when it's on).
		if self.isFirst then
			self.isFirst = false
			self.orderPos = 1
		else
			self.orderPos = (self.orderPos % #styleOrder) + 1
		end
		cur_style = styleOrder[self.orderPos]

		for i=1,NumEntries do
			self:GetChild("Name"..i):visible(true)
			self:GetChild("Score"..i):visible(true)
			self:GetChild("Rank"..i):visible(true)
		end
		self:GetChild("Outline"):visible(true)
		self:GetChild("Background"):linear(anim_seconds/2):diffusealpha(1):visible(true)

		if #styleOrder > 1 then
			self:sleep(loop_seconds):queuecommand("LoopScorebox")
		end
	end,

	RequestResponseActor(0, 0)..{
		OnCommand=function(self)
			self:queuecommand("MakeRequest")
			-- Create variables for both players, even if they're not currently active.
			self.IsParsing = {false, false}
		end,
		-- Broadcasted from ./PerPlayer/DensityGraph.lua
		P1ChartParsingMessageCommand=function(self)	self.IsParsing[1] = true end,
		P2ChartParsingMessageCommand=function(self)	self.IsParsing[2] = true end,
		P1ChartParsedMessageCommand=function(self)
			self.IsParsing[1] = false
			if pn == "P1" then
				self:queuecommand("ChartParsed")
			end
		end,
		P2ChartParsedMessageCommand=function(self)
			self.IsParsing[2] = false
			if pn == "P2" then
				self:queuecommand("ChartParsed")
			end
		end,
		ChartParsedMessageCommand=function(self)
			if not self.leaving_screen then
				self:queuecommand("MakeRequest")
			end
		end,
		MakeRequestCommand=function(self)
			-- Section/group headers in the wheel have no current song, though
			-- GetCurrentSteps can still report the last song's steps.
			if not GAMESTATE:GetCurrentSong() then
				self:GetParent():finishtweening():visible(false)
				return
			end
			if SL[pn].ApiKey == "" or SL[pn].Streams.Hash == "" then return end
			if self.IsParsing[1] or self.IsParsing[2] then return end

			if currentHash == SL[pn].Streams.Hash then
				self:GetParent():visible(true)
				self:GetParent():queuecommand("CheckScorebox")
				return
			end

			local external = WantsExternal()
			local query = {
				maxLeaderboardResults=NumEntries,
			}
			query["chartHashP"..n] = SL[pn].Streams.Hash
			if external then query["external"] = 1 end
			local headers = {}
			headers["x-api-key-player-"..n] = SL[pn].ApiKey

			requestGeneration = requestGeneration + 1
			pending = true

			RemoveStaleCachedRequests()
			ResetAllData()

			local parent = self:GetParent()
			-- Every chart starts on the first board (Blended EX when it's on), including
			-- another difficulty of the same song, instead of carrying on the rotation.
			parent:stoptweening()
			parent.isFirst = true
			parent:visible(true)
			for i=1,NumEntries do
				parent:GetChild("Name"..i):settext(""):visible(false)
				parent:GetChild("Score"..i):settext(""):visible(false)
				parent:GetChild("Source"..i):settext("")
				local rankChild = parent:GetChild("Rank"..i)
				if i == 1 then
					-- Crown sprite: no settext
					rankChild:diffusealpha(0):visible(false)
				else
					rankChild:settext(""):visible(false)
				end
			end
			parent:GetChild("LoadingSpinner"):visible(true)
			parent:GetChild("Kind"):diffusealpha(0)
			parent:GetChild("SourceLabel"):diffusealpha(0)
			parent:GetChild("Outline"):diffusealpha(0):visible(false)
			parent:GetChild("Background"):diffusealpha(0):visible(false)

			if IsItlSong(player) then
				UpdatePathMap(player, SL[pn].Streams.Hash)
			end

			-- Charts looked at in the last minute are cached (see RemoveStaleCachedRequests).
			local cacheKey = CRYPTMAN:SHA256String(SL[pn].Streams.Hash..SL[pn].ApiKey..(external and "-external" or "").."-player-leaderboards")
			local cached = SL.ECFACloud.RequestCache[cacheKey]
			if cached then
				-- drop any request still running for the previous chart (and its spinner)
				if self.request_handler then
					self.request_handler:Cancel()
					self.request_handler = nil
				end
				self:GetChild("Spinner"):visible(false)
				LeaderboardRequestProcessor(cached.Response, {parent=parent, generation=requestGeneration})
				return
			end

			-- We technically will send two requests in ultrawide versus mode since
			-- both players will have their own individual scoreboxes.
			-- Should be fine though.
			self:playcommand("MakeECFACloudRequest", {
				endpoint="player-leaderboards?"..NETWORK:EncodeQueryParameters(query),
				method="GET",
				headers=headers,
				timeout=10,
				callback=function(res, args)
					-- Remember it briefly, so coming back to this chart is instant.
					if not res.error and res.statusCode == 200 then
						SL.ECFACloud.RequestCache[cacheKey] = { Response=res, Timestamp=GetTimeSinceStart() }
					end
					LeaderboardRequestProcessor(res, args)
				end,
				args={parent=parent, generation=requestGeneration},
			})
		end,
	},

	-- Outline, in the board's color
	Def.Quad{
		Name="Outline",
		InitCommand=function(self)
			self:diffuse(BOARDS[0].color):setsize(width + border, height + border)
			if IsNotWide and #GAMESTATE:GetHumanPlayers() > 1 then
				self:setsize(width + border - 40, height + border)
			end
		end,
		PlayerJoinedMessageCommand=function(self,params)
			if IsNotWide then
				self:setsize(width + border - 40, height + border)
			else
				self:setsize(width + border, height + border)
			end
		end,
		PlayerUnjoinedMessageCommand=function(self,params)
			self:setsize(width + border, height + border)
		end,
		LoopScoreboxCommand=function(self)
			self:linear(anim_seconds):diffuse(BOARDS[cur_style].color)
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening() end
	},
	-- Main body
	Def.Quad{
		Name="Background",
		InitCommand=function(self)
			self:diffuse(color("#000000")):setsize(width, height)
			if IsNotWide and #GAMESTATE:GetHumanPlayers() > 1 then
				self:setsize(width - 40, height)
			end
		end,
		PlayerJoinedMessageCommand=function(self,params)
			if IsNotWide then
				self:setsize(width - 40, height)
			else
				self:setsize(width, height)
			end
		end,
		PlayerUnjoinedMessageCommand=function(self,params)
			self:setsize(width, height)
		end,
	},
	-- Which board this is, behind the rows: "EX" or "WF" ...
	Def.BitmapText{
		Name="Kind",
		Font=ThemePrefs.Get("ThemeFont") .. " Normal",
		Text="",
		InitCommand=function(self)
			self:zoom(1.6):y(-8):diffusealpha(0)
		end,
		LoopScoreboxCommand=function(self)
			self:linear(anim_seconds/2):diffusealpha(0):queuecommand("SetScorebox")
		end,
		SetScoreboxCommand=function(self)
			self:settext(BOARDS[cur_style].kind):diffuse(BOARDS[cur_style].color):linear(anim_seconds/2):diffusealpha(0.22)
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening() end
	},
	-- ... and where the scores come from.
	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="SourceLabel",
		Text="",
		InitCommand=function(self)
			self:zoom(0.6):y(14):maxwidth((width - 16) / 0.6):diffusealpha(0)
		end,
		LoopScoreboxCommand=function(self)
			self:linear(anim_seconds/2):diffusealpha(0):queuecommand("SetScorebox")
		end,
		SetScoreboxCommand=function(self)
			self:settext(BOARDS[cur_style].label:upper()):diffuse(BOARDS[cur_style].color):linear(anim_seconds/2):diffusealpha(0.45)
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening() end
	},

	-- Loading spinner, shown from the moment a request is fired until it responds.
	Def.Sprite{
		Texture=THEME:GetPathG("", "LoadingSpinner 10x3.png"),
		Name="LoadingSpinner",
		Frames=Sprite.LinearFrames(30,1),
		InitCommand=function(self)
			self:zoom(0.15):diffuse(GetHexColor(SL.Global.ActiveColorIndex, true)):visible(false)
		end,
		VisualStyleSelectedMessageCommand=function(self)
			self:diffuse(GetHexColor(SL.Global.ActiveColorIndex, true))
		end,
		LoopScoreboxCommand=function(self)
			if not pending then
				self:visible(false)
			end
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening():visible(false) end
	},
}

-- Row text color: you, a rival, or anyone else.
local RowColor = function(score)
	if score.isSelf then return self_color end
	if score.isRival then return rival_color end
	return Color.White
end

for i=1,NumEntries do
	local y = -height/2 + row_spacing * i - row_spacing/2

	-- Rank 1 gets a crown.
	if i == 1 then
		af[#af+1] = Def.Sprite{
			Name="Rank"..i,
			Texture=THEME:GetPathG("", "crown.png"),
			InitCommand=function(self)
				self:zoom(0.064):xy(-width/2 + 14, y):diffusealpha(0)
				if IsNotWide and #GAMESTATE:GetHumanPlayers() > 1 then
					self:x(-width/2 + 32)
				end
			end,
			PlayerJoinedMessageCommand=function(self,params)
				if IsNotWide then
					self:x(-width/2 + 32)
				else
					self:x(-width/2 + 14)
				end
			end,
			PlayerUnjoinedMessageCommand=function(self,params)
				self:x(-width/2 + 14)
			end,
			LoopScoreboxCommand=function(self)
				self:linear(anim_seconds/2):diffusealpha(0):queuecommand("SetScorebox")
			end,
			SetScoreboxCommand=function(self)
				local score = all_data[cur_style+1]["scores"][i]
				if score.rank == "1." then
					self:linear(anim_seconds/2):diffusealpha(1)
				else
					self:diffusealpha(0)
				end
			end,
			ResetCommand=function(self) self:stoptweening() end,
			OffCommand=function(self) self:stoptweening() end
		}
	else
		af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
			Name="Rank"..i,
			Text="",
			InitCommand=function(self)
				self:diffuse(Color.White):xy(-width/2 + 27, y):maxwidth(22 / text_zoom):horizalign(right):zoom(text_zoom)
				if IsNotWide and #GAMESTATE:GetHumanPlayers() > 1 then
					self:x(-width/2 + 42)
				end
			end,
			PlayerJoinedMessageCommand=function(self,params)
				if IsNotWide then
					self:x(-width/2 + 42)
				else
					self:x(-width/2 + 27)
				end
			end,
			PlayerUnjoinedMessageCommand=function(self,params)
				self:x(-width/2 + 27)
			end,
			LoopScoreboxCommand=function(self)
				self:linear(anim_seconds/2):diffusealpha(0):queuecommand("SetScorebox")
			end,
			SetScoreboxCommand=function(self)
				local score = all_data[cur_style+1]["scores"][i]
				self:settext(score.rank)
				self:linear(anim_seconds/2):diffusealpha(1):diffuse(RowColor(score))
			end,
			ResetCommand=function(self) self:stoptweening() end,
			OffCommand=function(self) self:stoptweening() end
		}
	end

	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="Name"..i,
		Text="",
		InitCommand=function(self)
			self:diffuse(Color.White):xy(-width/2 + 30, y):maxwidth(NameRoom(false)):horizalign(left):zoom(text_zoom)
			if IsNotWide and #GAMESTATE:GetHumanPlayers() > 1 then
				self:x(-width/2 + 45)
			end
		end,
		PlayerJoinedMessageCommand=function(self,params)
			if IsNotWide then
				self:x(-width/2 + 45)
			else
				self:x(-width/2 + 30)
			end
		end,
		PlayerUnjoinedMessageCommand=function(self,params)
			self:x(-width/2 + 30)
		end,
		LoopScoreboxCommand=function(self)
			self:linear(anim_seconds/2):diffusealpha(0):queuecommand("SetScorebox")
		end,
		SetScoreboxCommand=function(self)
			local score = all_data[cur_style+1]["scores"][i]
			-- Narrower on the blended board, to make room for the source tag.
			self:maxwidth(NameRoom(cur_style == 0))
			self:settext(score.name)
			self:linear(anim_seconds/2):diffusealpha(1):diffuse(RowColor(score))
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening() end
	}

	-- Source tag (EC/GS/AC) on the blended board, just left of the score.
	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="Source"..i,
		Text="",
		InitCommand=function(self)
			self:xy(-width/2 + 121, y):horizalign(right):zoom(0.5)
			if IsNotWide and #GAMESTATE:GetHumanPlayers() > 1 then
				self:x(-width/2 + 101)
			end
		end,
		PlayerJoinedMessageCommand=function(self,params)
			self:x(IsNotWide and (-width/2 + 101) or (-width/2 + 121))
		end,
		PlayerUnjoinedMessageCommand=function(self,params)
			self:x(-width/2 + 121)
		end,
		LoopScoreboxCommand=function(self)
			self:linear(anim_seconds/2):diffusealpha(0):queuecommand("SetScorebox")
		end,
		SetScoreboxCommand=function(self)
			local score = all_data[cur_style+1]["scores"][i]
			local tag = cur_style == 0 and BlendedSource[score.source or ""]
			self:settext(tag and tag.label or "")
			if tag then
				self:linear(anim_seconds/2):diffuse(tag.color)
			end
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening() end
	}

	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="Score"..i,
		Text="",
		InitCommand=function(self)
			self:diffuse(Color.White):xy(-width/2 + 160, y):horizalign(right):zoom(text_zoom)
			if IsNotWide and #GAMESTATE:GetHumanPlayers() > 1 then
				self:x(-width/2 + 140)
			end
		end,
		PlayerJoinedMessageCommand=function(self,params)
			if IsNotWide then
				self:x(-width/2 + 140)
			else
				self:x(-width/2 + 160)
			end
		end,
		PlayerUnjoinedMessageCommand=function(self,params)
			self:x(-width/2 + 160)
		end,
		LoopScoreboxCommand=function(self)
			self:linear(anim_seconds/2):diffusealpha(0):queuecommand("SetScorebox")
		end,
		SetScoreboxCommand=function(self)
			local score = all_data[cur_style+1]["scores"][i]
			local clr = RowColor(score)
			if score.isFail then
				clr = Color.Red
			elseif BOARDS[cur_style].kind == "EX" and not (score.isSelf or score.isRival) then
				clr = SL.JudgmentColors["FA+"][1]
			end
			self:settext(score.score)
			self:linear(anim_seconds/2):diffusealpha(1):diffuse(clr)
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening() end
	}
end
return af
