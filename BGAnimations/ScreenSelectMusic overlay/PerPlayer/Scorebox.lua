-- ECFA Cloud leaderboards in a small box on the song wheel. Not for courses.
if GAMESTATE:IsCourseMode() then return end

-- Respect existing preference for where to show a scorebox
if ThemePrefs.Get("MusicWheelGS") ~= "Scorebox" then return end

local player = ...
local pn = ToEnumShortString(player)

if not IsServiceAllowed(SL.ECFACloud.GetScores) or SL[pn].ApiKey == "" then return end

local n = player==PLAYER_1 and "1" or "2"
local IsNotWide = (GetScreenAspectRatio() < 16/9)
local NoteFieldIsCentered = (GetNotefieldX(player) == _screen.cx)
local NumEntries = 5

local border = 5
local width = 162
local height = 80
local yShift = 0

-- 0/1: ECFA Cloud ITG / EX (EX first when the player uses EX scoring)
-- 2: the event leaderboard, when the chart is in an open ECFA Cloud event
-- 3: the blended board: ECFA Cloud, GrooveStats and ArrowCloud EX scores in one
--    list (GrooveStats/ArrowCloud are only read from, see SL-Helpers-BlendedLeaderboard.lua)
local cur_style = 0
local num_styles = 4

-- Styles in the order they got data; the box rotates through these.
local styleOrder = {}
local styleOrderSet = {}

local ECFACloudPink = color("#b8327a")
local ECFACloudCyan = color("#2b8fb3")
local EventGold = color("#c9a227")
local BlendedSilver = color("#c0c0c0")

local currentHash = "nothing"

local style_color = {
	[0] = ECFACloudPink,
	[1] = ECFACloudCyan,
	[2] = EventGold,
	[3] = BlendedSilver,
}
if SL[pn].ActiveModifiers.ShowExScore then
	style_color[0], style_color[1] = ECFACloudCyan, ECFACloudPink
end
local event_name = ""

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

-- The blended board waits for ECFA Cloud and the other services to all answer.
local blend = { lists={}, ecfaDone=false, extDone=false, wanted=false, handle=nil }

local ResetAllData = function()
	all_data = {}
	styleOrder = {}
	styleOrderSet = {}
	blend.lists = {}
	blend.ecfaDone = false
	blend.extDone = false
	SL[pn].Rival = {}
	SL[pn].Rival.Score = 0
	SL[pn].Rival.ExScore = 0
	SL[pn].Rival.WRScore = 0
	SL[pn].Rival.WRExScore = 0

	for i=1,num_styles do
		local data = { has_data=false, scores={} }
		for j=1,NumEntries do
			data.scores[j] = {
				rank="",
				name="",
				score="",
				isSelf=false,
				isRival=false,
				isFail=false,
				isEx=false,
				source=nil,
			}
		end
		all_data[i] = data
	end
end

-- Initialize the all_data object.
ResetAllData()

local function AppendStyle(style_index)
	if not styleOrderSet[style_index] then
		styleOrderSet[style_index] = true
		styleOrder[#styleOrder+1] = style_index
	end
end

-- source: the BlendedSource key of a row on the blended board, else nil.
local SetScoreData = function(data_idx, score_idx, rank, name, score, isSelf, isRival, isFail, isEx, source)
	if score_idx > NumEntries then return end
	all_data[data_idx].has_data = true

	local score_data = all_data[data_idx]["scores"][score_idx]
	score_data.rank = rank..((#rank > 0) and "." or "")
	score_data.name = name
	score_data.score = score
	score_data.isSelf = isSelf
	score_data.isRival = isRival
	score_data.isFail = isFail
	score_data.isEx = isEx
	score_data.source = source

	-- Remember the best rival/self score and the top score of the ITG and EX
	-- boards for the rival pace in SubtractiveScoring (ECFA Cloud boards only).
	if data_idx >= 3 or tonumber(score) == nil then return end
	local value = tonumber(score)
	if not isFail and (isRival or isSelf) then
		if isEx then
			SL[pn].Rival.ExScore = math.max(SL[pn].Rival.ExScore, value)
		else
			SL[pn].Rival.Score = math.max(SL[pn].Rival.Score, value)
		end
	end
	if rank == "1" then
		if isEx then
			SL[pn].Rival.WRExScore = math.max(SL[pn].Rival.WRExScore, value)
		else
			SL[pn].Rival.WRScore = math.max(SL[pn].Rival.WRScore, value)
		end
	end
end

-- Fills one board from an ECFA Cloud leaderboard (a list of entries).
local FillBoard = function(data_idx, entries, isEx)
	SetScoreData(data_idx, 1, "", "No Scores", "", false, false, false, isEx)
	local count = 0
	local added = {}
	for entry in ivalues(entries) do
		if count >= NumEntries then break end
		if not added[entry["name"]] then
			added[entry["name"]] = true
			count = count + 1
			SetScoreData(data_idx, count,
							tostring(entry["rank"]),
							entry["name"],
							string.format("%.2f", entry["score"]/100),
							entry["isSelf"],
							entry["isRival"],
							entry["isFail"],
							isEx
						)
		end
	end
	AppendStyle(data_idx - 1)
end

-- Fills the blended board (style 3) once ECFA Cloud and the other services have
-- all answered. kick: start the rotation if this is the box's first or second board
-- (the ECFA Cloud response handler does that itself).
local UpdateBlended = function(master, kick)
	if not blend.wanted or not blend.ecfaDone or not blend.extDone then return end
	SetScoreData(4, 1, "", "No Scores", "", false, false, false, true)
	for i, e in ipairs(BlendLeaderboards(blend.lists, NumEntries)) do
		SetScoreData(4, i, e.rank and tostring(e.rank) or "", e.name, string.format("%.2f", e.score/100),
			e.isSelf, e.isRival, e.isFail, true, e.source)
	end
	local before = #styleOrder
	AppendStyle(3)
	if kick and before <= 1 and #styleOrder > before then
		master:queuecommand("CheckScorebox")
	end
end

local LeaderboardRequestProcessor = function(res, args)
	local master = args and args.parent
	-- Discard responses for a chart we've since scrolled past.
	if not args or args.generation ~= requestGeneration or master == nil then return end
	pending = false

	if res.error or res.statusCode ~= 200 then
		local error = res.error and ToEnumShortString(res.error) or nil
		local text = ""
		if error == "Timeout" then
			text = "Timed Out"
		elseif error or (res.statusCode ~= nil and res.statusCode ~= 200) then
			text = "Failed to Load 😞"
		end
		SetScoreData(1, 1, "", text, "", false, false, false, false)
		AppendStyle(0)
		blend.ecfaDone = true
		UpdateBlended(master, false)
		master:queuecommand("CheckScorebox")
		return
	end

	local playerStr = "player"..n
	local data = JsonDecode(res.body)

	-- ECFA Cloud refused this player, e.g. their API key was revoked or their account deleted.
	if data and data[playerStr] and data[playerStr]["error"] then
		local text = data[playerStr]["error"] == "invalid-api-key" and "Invalid API key" or "Failed to Load 😞"
		SetScoreData(1, 1, "", text, "", false, false, false, false)
		AppendStyle(0)
		blend.ecfaDone = true
		UpdateBlended(master, false)
		master:queuecommand("CheckScorebox")
		return
	end

	if data and data[playerStr] then
		if SL[pn].Streams.Hash ~= data[playerStr]["chartHash"] then return end
		currentHash = SL[pn].Streams.Hash

		local showITG = SL[pn].ActiveModifiers.SBITGScore
		local showEX = SL[pn].ActiveModifiers.SBExScore
		local showEvents = SL[pn].ActiveModifiers.SBEvents
		local exFirst = SL[pn].ActiveModifiers.ShowExScore
		local itgIdx = exFirst and 2 or 1
		local exIdx = exFirst and 1 or 2

		-- Fill in display order so the first board shown is the first style.
		local boards = {
			{ idx=itgIdx, key="wfLeaderboard", show=showITG, isEx=false },
			{ idx=exIdx, key="exLeaderboard", show=showEX, isEx=true },
		}
		table.sort(boards, function(a, b) return a.idx < b.idx end)
		for board in ivalues(boards) do
			if board.show and data[playerStr][board.key] then
				FillBoard(board.idx, data[playerStr][board.key], board.isEx)
			end
		end

		-- The first open event that includes this chart.
		local ev = data[playerStr]["events"] and data[playerStr]["events"][1]
		if showEvents and ev and ev["leaderboard"] then
			event_name = ev["name"] or ""
			FillBoard(3, ev["leaderboard"], false)
			master:playcommand("SetEventName")
		end

		blend.lists.ECFA = BlendedEntriesFromECFACloud(data[playerStr]["exLeaderboard"])
	end
	blend.ecfaDone = true
	UpdateBlended(master, false)
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
	OffCommand=function(self)
		self:stoptweening()
		if blend.handle then
			blend.handle:Cancel()
			blend.handle = nil
		end
	end,
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

			local query = {
				maxLeaderboardResults=NumEntries,
			}
			query["chartHashP"..n] = SL[pn].Streams.Hash
			local headers = {}
			headers["x-api-key-player-"..n] = SL[pn].ApiKey

			requestGeneration = requestGeneration + 1
			pending = true

			RemoveStaleCachedRequests()
			ResetAllData()

			local parent = self:GetParent()
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
			parent:GetChild("ECFACloudLogo"):visible(false)
			parent:GetChild("EventName"):diffusealpha(0)
			parent:GetChild("Outline"):diffusealpha(0):visible(false)
			parent:GetChild("Background"):diffusealpha(0):visible(false)

			if IsItlSong(player) then
				UpdatePathMap(player, SL[pn].Streams.Hash)
			end

			-- GrooveStats/ArrowCloud for the blended board, alongside the ECFA Cloud request.
			if blend.handle then
				blend.handle:Cancel()
				blend.handle = nil
			end
			blend.wanted = SL[pn].ActiveModifiers.SBBlended and HasBlendedLeaderboardSources(player)
			if blend.wanted then
				local generation = requestGeneration
				blend.handle = FetchBlendedSources(player, SL[pn].Streams.Hash, NumEntries, function(results)
					if generation ~= requestGeneration then return end
					blend.handle = nil
					blend.lists.GS = results.GS and results.GS.entries
					blend.lists.AC = results.AC and results.AC.entries
					blend.extDone = true
					UpdateBlended(parent, true)
				end)
			end

			-- Charts looked at in the last minute are cached (see RemoveStaleCachedRequests).
			local cacheKey = CRYPTMAN:SHA256String(SL[pn].Streams.Hash..SL[pn].ApiKey.."-player-leaderboards")
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

	-- Outline
	Def.Quad{
		Name="Outline",
		InitCommand=function(self)
			self:diffuse(style_color[0]):setsize(width + border, height + border)
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
			self:linear(anim_seconds):diffuse(style_color[cur_style])
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
	-- ECFA Cloud Logo
	Def.Sprite{
		Texture=THEME:GetPathG("", "ECFA logo small.png"),
		Name="ECFACloudLogo",
		InitCommand=function(self)
			self:zoom(110 / self:GetWidth()):diffusealpha(0.5)
		end,
		LoopScoreboxCommand=function(self)
			self:visible(true)
			if cur_style == 0 or cur_style == 1 then
				self:sleep(anim_seconds/2):linear(anim_seconds/2):diffusealpha(0.5)
			else
				self:linear(anim_seconds/2):diffusealpha(0.15)
			end
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening() end
	},
	-- EX Text
	Def.BitmapText{
		Font=ThemePrefs.Get("ThemeFont") .. " Normal",
		Text="EX",
		InitCommand=function(self)
			self:diffusealpha(0):x(2):y(-5)
		end,
		LoopScoreboxCommand=function(self)
			if (cur_style == 1 and not SL[pn].ActiveModifiers.ShowExScore) or (cur_style == 0 and SL[pn].ActiveModifiers.ShowExScore) or cur_style == 3 then
				self:sleep(anim_seconds/2):linear(anim_seconds/2):diffusealpha(0.3)
			else
				self:linear(anim_seconds/2):diffusealpha(0)
			end
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening() end
	},
	-- Event name, shown under the event leaderboard
	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="EventName",
		Text="",
		InitCommand=function(self)
			self:zoom(0.6):y(height/2 - 6):maxwidth((width - 10) / 0.6):diffuse(EventGold):diffusealpha(0)
		end,
		SetEventNameCommand=function(self) self:settext(event_name) end,
		LoopScoreboxCommand=function(self)
			if cur_style == 2 then
				self:sleep(anim_seconds/2):linear(anim_seconds/2):diffusealpha(0.8)
			else
				self:linear(anim_seconds/2):diffusealpha(0)
			end
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

for i=1,NumEntries do
	local y = -height/2 + 16 * i - 8
	local zoom = 0.87

	-- Rank 1 gets a crown.
	if i == 1 then
		af[#af+1] = Def.Sprite{
			Name="Rank"..i,
			Texture=THEME:GetPathG("", "crown.png"),
			InitCommand=function(self)
				self:zoom(0.09):xy(-width/2 + 14, y):diffusealpha(0)
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
				if score.rank ~= "" then
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
				self:diffuse(Color.White):xy(-width/2 + 27, y):maxwidth(30):horizalign(right):zoom(zoom)
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
				local clr = Color.White
				if score.isSelf then
					clr = self_color
				elseif score.isRival then
					clr = rival_color
				end
				self:settext(score.rank)
				self:linear(anim_seconds/2):diffusealpha(1):diffuse(clr)
			end,
			ResetCommand=function(self) self:stoptweening() end,
			OffCommand=function(self) self:stoptweening() end
		}
	end

	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="Name"..i,
		Text="",
		InitCommand=function(self)
			self:diffuse(Color.White):xy(-width/2 + 30, y):maxwidth(100):horizalign(left):zoom(zoom)
			if IsNotWide and #GAMESTATE:GetHumanPlayers() > 1 then
				self:x(-width/2 + 45):maxwidth(70)
			end
		end,
		PlayerJoinedMessageCommand=function(self,params)
			if IsNotWide then
				self:x(-width/2 + 45):maxwidth(70)
			else
				self:x(-width/2 + 30):maxwidth(100)
			end
		end,
		PlayerUnjoinedMessageCommand=function(self,params)
			self:x(-width/2 + 30):maxwidth(100)
		end,
		LoopScoreboxCommand=function(self)
			self:linear(anim_seconds/2):diffusealpha(0):queuecommand("SetScorebox")
		end,
		SetScoreboxCommand=function(self)
			local score = all_data[cur_style+1]["scores"][i]
			local clr = Color.White
			if score.isSelf then
				clr = self_color
			elseif score.isRival then
				clr = rival_color
			end
			local narrow = IsNotWide and #GAMESTATE:GetHumanPlayers() > 1
			self:maxwidth((narrow and 70 or 100) - (cur_style == 3 and 28 or 0))
			self:settext(score.name)
			self:linear(anim_seconds/2):diffusealpha(1):diffuse(clr)
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening() end
	}

	-- Source tag (EC/GS/AC) on the blended board, just left of the score.
	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="Source"..i,
		Text="",
		InitCommand=function(self)
			self:xy(-width/2 + 118, y):horizalign(right):zoom(0.6)
			if IsNotWide and #GAMESTATE:GetHumanPlayers() > 1 then
				self:x(-width/2 + 98)
			end
		end,
		PlayerJoinedMessageCommand=function(self,params)
			self:x(IsNotWide and (-width/2 + 98) or (-width/2 + 118))
		end,
		PlayerUnjoinedMessageCommand=function(self,params)
			self:x(-width/2 + 118)
		end,
		LoopScoreboxCommand=function(self)
			self:linear(anim_seconds/2):diffusealpha(0):queuecommand("SetScorebox")
		end,
		SetScoreboxCommand=function(self)
			local score = all_data[cur_style+1]["scores"][i]
			local tag = cur_style == 3 and BlendedSource[score.source or ""]
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
			self:diffuse(Color.White):xy(-width/2 + 160, y):horizalign(right):zoom(zoom)
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
			local clr = Color.White
			if score.isFail then
				clr = Color.Red
			elseif score.isEx then
				clr = SL.JudgmentColors["FA+"][1]
			elseif score.isSelf then
				clr = self_color
			elseif score.isRival then
				clr = rival_color
			end
			self:settext(score.score)
			self:linear(anim_seconds/2):diffusealpha(1):diffuse(clr)
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening() end
	}
end
return af
