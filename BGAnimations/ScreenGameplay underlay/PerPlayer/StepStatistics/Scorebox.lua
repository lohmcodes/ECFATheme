-- Leaderboards in a small box next to the notefield during gameplay.
--
-- The same boards as the song wheel's box (switched on or off in the Show Score
-- Boxes player option), each saying which it is (EX or WF, and the source):
--   0  Blended EX: ECFA Cloud, GrooveStats and ArrowCloud EX scores in one list
--   1  GrooveStats EX
--   2  ArrowCloud EX
--   3  ECFA Cloud WF (Waterfall)
--   4  the event leaderboard (WF), when the chart is in an open ECFA Cloud event
-- ECFA Cloud fetches the GrooveStats and ArrowCloud boards (SL-Helpers-BlendedLeaderboard.lua).
local player = ...
local pn = ToEnumShortString(player)

if (not SL[pn].ActiveModifiers.DisplayScorebox or
		not IsServiceAllowed(SL.ECFACloud.GetScores) or
		SL[pn].ApiKey == "") then
	return
end

local n = player==PLAYER_1 and "1" or "2"
local IsUltraWide = (GetScreenAspectRatio() > 21/9)
local NoteFieldIsCentered = (GetNotefieldX(player) == _screen.cx)
local NumEntries = 5

local style = GAMESTATE:GetCurrentStyle():GetName()

local border = 5
local width = 162
local height = 80
local row_spacing = height / NumEntries

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

local self_color = color("#a1ff94")
local rival_color = color("#c29cff")

local loop_seconds = 5
local transition_seconds = 0.5
local anim_seconds = transition_seconds

local all_data = {}

local ResetAllData = function()
	SL[pn].Rival = {}
	SL[pn].Rival.Score = 0
	SL[pn].Rival.ExScore = 0
	SL[pn].Rival.WRScore = 0
	SL[pn].Rival.WRExScore = 0

	all_data = {}
	styleOrder = {}
	styleOrderSet = {}
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
local Wanted = function(s)
	return SL[pn].ActiveModifiers[BOARDS[s].option] and true or false
end

-- Whether to ask ECFA Cloud for the GrooveStats and ArrowCloud boards too.
local WantsExternal = function()
	for s=0,num_styles-1 do
		if BOARDS[s].external and Wanted(s) then return true end
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
local FillBoard = function(s, rows, emptyText)
	local data = all_data[s+1]
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
			row.rank = e.rank and (tostring(e.rank)..".") or ""
			row.name = e.name
			row.score = string.format("%.2f", e.score/100)
			row.isSelf = e.isSelf
			row.isRival = e.isRival
			row.isFail = e.isFail
			row.source = e.source
		end
	end
	if styleOrderSet[s] then return end
	styleOrderSet[s] = true
	styleOrder[#styleOrder+1] = s
	table.sort(styleOrder)
end

-- The first board the player has switched on, for showing an error.
local FirstWantedStyle = function()
	for s=0,num_styles-1 do
		if Wanted(s) then return s end
	end
	return 3
end

local LeaderboardRequestProcessor = function(res, master)
	if master == nil then return end

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
		if style ~= "double" then
			self:xy(70 * (player==PLAYER_1 and 1 or -1), -115)
			-- offset a bit more when NoteFieldIsCentered
			if NoteFieldIsCentered and IsUsingWideScreen() then
				self:addx( 2 * (player==PLAYER_1 and 1 or -1) )
			end

			-- ultrawide and both players joined
			if IsUltraWide and #GAMESTATE:GetHumanPlayers() > 1 then
				self:x(self:GetX() * -1)
			end
		else
			self:xy(GetNotefieldWidth() - 140, -115)
		end

		self.isFirst = true
	end,
	CheckScoreboxCommand=function(self)
		self:queuecommand("LoopScorebox")
	end,
	LoopScoreboxCommand=function(self)
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

		if #styleOrder > 1 then
			self:sleep(loop_seconds):queuecommand("LoopScorebox")
		end
	end,

	RequestResponseActor(0, 0)..{
		OnCommand=function(self)
			self:queuecommand("MakeRequest")
		end,
		CurrentSongChangedMessageCommand=function(self)
			if not self.isFirst then
				ResetAllData()
				self:GetParent().isFirst = true
				self:queuecommand("MakeRequest")
			end
		end,
		MakeRequestCommand=function(self)
			if SL[pn].ApiKey == "" or SL[pn].Streams.Hash == "" then return end

			local query = {
				maxLeaderboardResults=NumEntries,
			}
			query["chartHashP"..n] = SL[pn].Streams.Hash
			if WantsExternal() then query["external"] = 1 end
			local headers = {}
			headers["x-api-key-player-"..n] = SL[pn].ApiKey

			-- Clear all rows; mark first as Loading
			for i=1,NumEntries do
				local nameActor = self:GetParent():GetChild("Name"..i)
				local scoreActor = self:GetParent():GetChild("Score"..i)
				local rankActor = self:GetParent():GetChild("Rank"..i)
				if nameActor then nameActor:settext(i==1 and "Loading..." or "") end
				if scoreActor then scoreActor:settext("") end
				local sourceActor = self:GetParent():GetChild("Source"..i)
				if sourceActor then sourceActor:settext("") end
				if rankActor then
					if i==1 and rankActor.GetTexture then
						-- crown sprite: fade out
						rankActor:diffusealpha(0)
					else
						rankActor:settext("")
					end
				end
			end

			-- We technically will send two requests in ultrawide versus mode since
			-- both players will have their own individual scoreboxes.
			-- Should be fine though.
			self:playcommand("MakeECFACloudRequest", {
				endpoint="player-leaderboards?"..NETWORK:EncodeQueryParameters(query),
				method="GET",
				headers=headers,
				timeout=10,
				callback=LeaderboardRequestProcessor,
				args=self:GetParent(),
			})
		end
	},

	-- Outline, in the board's color
	Def.Quad{
		Name="Outline",
		InitCommand=function(self)
			self:diffuse(BOARDS[0].color):setsize(width + border, height + border)
		end,
		LoopScoreboxCommand=function(self)
			self:linear(anim_seconds):diffuse(BOARDS[cur_style].color)
		end
	},
	-- Main body
	Def.Quad{
		Name="Background",
		InitCommand=function(self)
			self:diffuse(color("#000000")):setsize(width, height)
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
		end
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
		end
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
	local zoom = 0.87

	-- Rank 1 gets a crown.
	if i == 1 then
		af[#af+1] = Def.Sprite{
			Name="Rank"..i,
			Texture=THEME:GetPathG("", "crown.png"),
			InitCommand=function(self)
				self:zoom(0.09):xy(-width/2 + 14, y):diffusealpha(0)
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
			end
		}
	else
		af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
			Name="Rank"..i,
			Text="",
			InitCommand=function(self)
				self:diffuse(Color.White):xy(-width/2 + 27, y):maxwidth(30):horizalign(right):zoom(zoom)
			end,
			LoopScoreboxCommand=function(self)
				self:linear(anim_seconds/2):diffusealpha(0):queuecommand("SetScorebox")
			end,
			SetScoreboxCommand=function(self)
				local score = all_data[cur_style+1]["scores"][i]
				self:settext(score.rank)
				self:linear(anim_seconds/2):diffusealpha(1):diffuse(RowColor(score))
			end
		}
	end

	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="Name"..i,
		Text="",
		InitCommand=function(self)
			self:diffuse(Color.White):xy(-width/2 + 30, y):maxwidth(100):horizalign(left):zoom(zoom)
		end,
		LoopScoreboxCommand=function(self)
			self:linear(anim_seconds/2):diffusealpha(0):queuecommand("SetScorebox")
		end,
		SetScoreboxCommand=function(self)
			local score = all_data[cur_style+1]["scores"][i]
			-- Narrower on the blended board, to make room for the source tag.
			self:maxwidth(cur_style == 0 and 72 or 100)
			self:settext(score.name)
			self:linear(anim_seconds/2):diffusealpha(1):diffuse(RowColor(score))
		end
	}

	-- Source tag (EC/GS/AC) on the blended board, just left of the score.
	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="Source"..i,
		Text="",
		InitCommand=function(self)
			self:xy(-width/2 + 118, y):horizalign(right):zoom(0.6)
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
		end
	}

	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="Score"..i,
		Text="",
		InitCommand=function(self)
			self:diffuse(Color.White):xy(-width/2 + 160, y):horizalign(right):zoom(zoom)
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
		end
	}
end
return af
