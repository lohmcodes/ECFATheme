-- Pane8 lists the chart's blended EX leaderboard: ECFA Cloud, GrooveStats and
-- ArrowCloud EX scores in one list, each row tagged with where it came from
-- (Scripts/SL-Helpers-BlendedLeaderboard.lua), with the player's place on it.
-- It loads once the play has been submitted (so the new score is on it), or
-- straight away when there's nothing to submit: Shared/AutoSubmitScore.lua sends
-- ECFACloudBlendedReady either way.
--
-- With one player joined, this pane is loaded for both sides of the screen; the
-- one on the player's own side asks ECFA Cloud, and both show the answer
-- (ECFACloudBlendedBoard).

if GAMESTATE:IsCourseMode() or not ThemePrefs.Get("EnableECFACloud") then return end
if not IsServiceAllowed(SL.ECFACloud.GetScores) then return end

local player, controller = unpack(...)
local pn = ToEnumShortString(player)
if SL[pn].ApiKey == "" then return end
local side = pn:sub(-1)

local font = ThemePrefs.Get("ThemeFont") .. " Normal"
-- Same rows as the machine high score pane (Pane4): a header, then nine scores.
local RowHeight = 22
local NumRows = 9
local SelfColor = color("#A1FF94")
local RivalColor = color("#BD94FF")
local s = function(key) return THEME:GetString("ECFACloud", key) end
local Asks = (controller == nil or controller == player)

local pane = Def.ActorFrame{
	InitCommand=function(self) self:y(_screen.cy - 62):zoom(0.8) end,
	ECFACloudBlendedReadyMessageCommand=function(self, params)
		if params.player ~= player or self.loaded or not Asks then return end
		self.loaded = true
		self:playcommand("Load")
	end,
	ECFACloudBlendedBoardMessageCommand=function(self, params)
		if params.player ~= player then return end
		self:playcommand("Fill", params)
	end,
}

-- Header: what this is, and which services are in it (a service ECFA Cloud
-- couldn't reach is dimmed).
pane[#pane+1] = LoadFont(font)..{
	Text=s("BlendedLeaderboard").." EX",
	InitCommand=function(self) self:horizalign(left):x(-150):diffuse(Color.White) end,
}
for i, source in ipairs(BlendedSources) do
	pane[#pane+1] = LoadFont(font)..{
		Name="Legend"..source.key,
		Text=source.label,
		InitCommand=function(self) self:horizalign(right):x(150 - (#BlendedSources - i) * 30):diffuse(source.color):diffusealpha(0.35) end,
		FillCommand=function(self, params)
			self:diffusealpha(params.available[source.key] and 1 or 0.2)
		end,
	}
end

-- Loading, empty and error messages, in the first row.
pane[#pane+1] = LoadFont(font)..{
	Name="Status",
	Text=s("Loading"),
	InitCommand=function(self) self:horizalign(left):xy(-120, RowHeight):diffuse(color("#9aa3b5")) end,
	FillCommand=function(self, params)
		self:settext(params.status or ""):visible(params.status ~= nil)
		DiffuseEmojis(self)
	end,
}

for i = 1, NumRows do
	local y = RowHeight * i
	local row = Def.ActorFrame{
		Name="Row"..i,
		FillCommand=function(self, params)
			local e = params.rows and params.rows[i]
			self:visible(e ~= nil)
			if not e then return end
			local c = e.isSelf and SelfColor or (e.isRival and RivalColor or Color.White)
			local tag = BlendedSource[e.source or ""]
			self:GetChild("Rank"):settext(BlendedRankText(e)):diffuse(c)
			self:GetChild("Source"):settext(tag and tag.label or ""):diffuse(tag and tag.color or Color.White)
			self:GetChild("Name"):settext(e.name or ""):diffuse(c)
			self:GetChild("Score"):settext(("%.2f%%"):format((e.score or 0) / 100)):diffuse(e.isSelf and SelfColor or SL.JudgmentColors["FA+"][1])
			self:GetChild("Date"):settext(FormatBlendedDate(e.date)):diffuse(c)
		end,
	}
	row.InitCommand = function(self) self:visible(false) end
	row[#row+1] = LoadFont(font)..{ Name="Rank", InitCommand=function(self) self:horizalign(right):xy(-122, y):maxwidth(55) end }
	row[#row+1] = LoadFont(font)..{ Name="Source", InitCommand=function(self) self:horizalign(left):xy(-116, y):zoom(0.75) end }
	row[#row+1] = LoadFont(font)..{ Name="Name", InitCommand=function(self) self:horizalign(left):xy(-90, y):maxwidth(100) end }
	row[#row+1] = LoadFont(font)..{ Name="Score", InitCommand=function(self) self:horizalign(left):xy(16, y) end }
	row[#row+1] = LoadFont(font)..{ Name="Date", InitCommand=function(self) self:horizalign(left):xy(84, y):zoom(0.85):maxwidth(76 / 0.85) end }
	pane[#pane+1] = row
end

-- The player's place, under the list.
pane[#pane+1] = LoadFont(font)..{
	Name="Place",
	Text="",
	InitCommand=function(self) self:horizalign(left):xy(-150, RowHeight * (NumRows + 1)):zoom(0.85):diffuse(SelfColor) end,
	FillCommand=function(self, params)
		local own
		for e in ivalues(params.rows or {}) do
			if e.isSelf then own = e break end
		end
		if params.status then
			self:settext("")
		elseif own then
			self:settext(s("BlendedPlace"):format((BlendedRankText(own):gsub("%.$", ""))))
		else
			self:settext(s("BlendedNoOwnScore"))
		end
	end,
}

local Show = function(board)
	board.player = player
	MESSAGEMAN:Broadcast("ECFACloudBlendedBoard", board)
end

pane[#pane+1] = RequestResponseActor(0, RowHeight)..{
	LoadCommand=function(self)
		local hash = SL[pn].Streams.Hash
		if hash == "" then
			Show({ status=s("FailedToLoad"), available={} })
			return
		end
		local query = { maxLeaderboardResults=NumRows, external=1 }
		query["chartHashP"..side] = hash
		local headers = {}
		headers["x-api-key-player-"..side] = SL[pn].ApiKey
		self:playcommand("MakeECFACloudRequest", {
			endpoint="player-leaderboards?"..NETWORK:EncodeQueryParameters(query),
			method="GET",
			headers=headers,
			timeout=10,
			callback=function(res)
				local data = (not res.error and res.statusCode == 200) and JsonDecode(res.body) or nil
				local d = data and data["player"..side]
				if not d or d["error"] then
					Show({ status=s("FailedToLoad"), available={} })
					return
				end
				local sources = ExSourcesFromResponse(d)
				local rows = BlendLeaderboards(sources, NumRows)
				Show({
					rows=rows,
					status=(#rows == 0) and "No Scores" or nil,
					available={ ECFA=true, GS=sources.GS ~= nil, AC=sources.AC ~= nil },
				})
			end,
		})
	end,
}

return pane
