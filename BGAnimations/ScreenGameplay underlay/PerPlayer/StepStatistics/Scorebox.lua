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

local cur_style = 0
local num_styles = 3

local ECFACloudPink = color("#b8327a")
local ECFACloudCyan = color("#2b8fb3")
local EventGold = color("#c9a227")

-- Styles 0 and 1 are the ECFA Cloud ITG and EX leaderboards (EX first when the
-- player uses EX scoring); style 2 is the event leaderboard, when the chart is
-- in an open ECFA Cloud event.
local style_color = {
	[0] = ECFACloudPink,
	[1] = ECFACloudCyan,
	[2] = EventGold,
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

local all_data = {}

local ResetAllData = function()
	SL[pn].Rival = {}
	SL[pn].Rival.Score = 0
	SL[pn].Rival.ExScore = 0
	SL[pn].Rival.WRScore = 0
	SL[pn].Rival.WRExScore = 0

	all_data = {}
	for i=1,num_styles do
		local data = {
			["has_data"]=false,
			["scores"]={}
		}
		local scores = data["scores"]
		for i=1,NumEntries do
			scores[#scores+1] = {
				["rank"]="",
				["name"]="",
				["score"]="",
				["isSelf"]=false,
				["isRival"]=false,
				["isFail"]=false,
				["isEx"]=false,
			}
		end
		all_data[#all_data + 1] = data
	end
end
-- Initialize the all_data object.
ResetAllData()

-- Checks to see if any data is available.
local HasData = function(idx)
	return all_data[idx+1] and all_data[idx+1].has_data
end

local SetScoreData = function(data_idx, score_idx, rank, name, score, isSelf, isRival, isFail, isEx)
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

	-- Remember the best rival/self score and the top score of the ITG and EX
	-- boards for the rival pace in SubtractiveScoring.
	if data_idx == 3 or tonumber(score) == nil then return end
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
		SetScoreData(1, 1, "", text, "", false, false, false, false)
		master:queuecommand("CheckScorebox")
		return
	end

	local playerStr = "player"..n
	local data = JsonDecode(res.body)

	-- ECFA Cloud refused this player, e.g. their API key was revoked or their account deleted.
	if data and data[playerStr] and data[playerStr]["error"] then
		local text = data[playerStr]["error"] == "invalid-api-key" and "Invalid API key" or "Failed to Load 😞"
		SetScoreData(1, 1, "", text, "", false, false, false, false)
		master:queuecommand("CheckScorebox")
		return
	end

	if data and data[playerStr] then
		local showITG = SL[pn].ActiveModifiers.SBITGScore
		local showEX = SL[pn].ActiveModifiers.SBExScore
		local showEvents = SL[pn].ActiveModifiers.SBEvents
		local exFirst = SL[pn].ActiveModifiers.ShowExScore
		local itgIdx = exFirst and 2 or 1
		local exIdx = exFirst and 1 or 2

		if showITG and data[playerStr]["wfLeaderboard"] then
			FillBoard(itgIdx, data[playerStr]["wfLeaderboard"], false)
		end
		if showEX and data[playerStr]["exLeaderboard"] then
			FillBoard(exIdx, data[playerStr]["exLeaderboard"], true)
		end

		-- The first open event that includes this chart.
		local ev = data[playerStr]["events"] and data[playerStr]["events"][1]
		if showEvents and ev and ev["leaderboard"] then
			event_name = ev["name"] or ""
			FillBoard(3, ev["leaderboard"], false)
			master:playcommand("SetEventName")
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
		if #all_data == 0 then return end

		-- On first display, use zero animation time so content appears instantly.
		anim_seconds = self.isFirst and 0 or transition_seconds

		local start = cur_style

		cur_style = (cur_style + 1) % num_styles
		if cur_style ~= start or self.isFirst then
			-- Make sure we have the next set of data.
			while cur_style ~= start do
				if HasData(cur_style) then
					-- If this is the first time we're looping, update the start variable
					-- since it may be different than the default
					if self.isFirst then
						start = cur_style
						self.isFirst = false
						-- Continue looping to figure out the next style.
					else
						break
					end
				end
				cur_style = (cur_style + 1) % num_styles
			end
		end

		-- Loop only if there's something new to loop to.
		if start ~= cur_style then
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
				self:queuecommand("MakeRequest")
			end
		end,
		MakeRequestCommand=function(self)
			if SL[pn].ApiKey == "" or SL[pn].Streams.Hash == "" then return end

			local query = {
				maxLeaderboardResults=NumEntries,
			}
			query["chartHashP"..n] = SL[pn].Streams.Hash
			local headers = {}
			headers["x-api-key-player-"..n] = SL[pn].ApiKey

			-- Clear all rows; mark first as Loading
			for i=1,NumEntries do
				local nameActor = self:GetParent():GetChild("Name"..i)
				local scoreActor = self:GetParent():GetChild("Score"..i)
				local rankActor = self:GetParent():GetChild("Rank"..i)
				if nameActor then nameActor:settext(i==1 and "Loading..." or "") end
				if scoreActor then scoreActor:settext("") end
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

	-- Outline
	Def.Quad{
		Name="Outline",
		InitCommand=function(self)
			self:diffuse(style_color[0]):setsize(width + border, height + border)
		end,
		LoopScoreboxCommand=function(self)
			self:linear(anim_seconds):diffuse(style_color[cur_style])
		end
	},
	-- Main body
	Def.Quad{
		Name="Background",
		InitCommand=function(self)
			self:diffuse(color("#000000")):setsize(width, height)
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
			if cur_style == 0 or cur_style == 1 then
				self:sleep(anim_seconds/2):linear(anim_seconds/2):diffusealpha(0.5)
			else
				self:linear(anim_seconds/2):diffusealpha(0.15)
			end
		end
	},
	-- EX Text
	Def.BitmapText{
		Font=ThemePrefs.Get("ThemeFont") .. " Normal",
		Text="EX",
		InitCommand=function(self)
			self:diffusealpha(0):x(2):y(-5)
			if SL[pn].ActiveModifiers.ShowExScore then self:diffusealpha(0.3) end
		end,
		LoopScoreboxCommand=function(self)
			if (cur_style == 1 and not SL[pn].ActiveModifiers.ShowExScore) or (cur_style == 0 and SL[pn].ActiveModifiers.ShowExScore) then
				self:sleep(anim_seconds/2):linear(anim_seconds/2):diffusealpha(0.3)
			else
				self:linear(anim_seconds/2):diffusealpha(0)
			end
		end
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
		end
	},
}

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
				if score.rank ~= "" then
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
				local clr = Color.White
				if score.isSelf then
					clr = self_color
				elseif score.isRival then
					clr = rival_color
				end
				self:settext(score.rank)
				self:linear(anim_seconds/2):diffusealpha(1):diffuse(clr)
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
			local clr = Color.White
			if score.isSelf then
				clr = self_color
			elseif score.isRival then
				clr = rival_color
			end
			self:settext(score.name)
			self:linear(anim_seconds/2):diffusealpha(1):diffuse(clr)
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
		end
	}
end
return af
