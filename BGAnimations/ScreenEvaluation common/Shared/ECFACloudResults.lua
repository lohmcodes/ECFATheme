-- ECFA Cloud results in a window over the evaluation screen. It opens as soon as
-- a score is being submitted, then shows where the play landed on the chart's
-- Waterfall leaderboard and, for a chart in an open event, the event results on
-- both boards. START or BACK closes it; until then it has the players' input, so
-- those presses don't leave the screen. Filled in by Shared/AutoSubmitScore.lua.

if GAMESTATE:IsCourseMode() or not ThemePrefs.Get("EnableECFACloud") then return end

local font = ThemePrefs.Get("ThemeFont")
local NumRows = 8
local RowHeight = 15
local ColumnWidth = 300
local Height = 320

local Pink = color("#e2579e")
local Gold = color("#e8c55a")
local Cyan = color("#5ad1e8")
local Muted = color("#9aa3b5")
local SelfColor = color("#A1FF94")
local RivalColor = color("#BD94FF")

local s = function(key) return THEME:GetString("ECFACloud", key) end

local Commas = function(n)
	local text = tostring(math.floor(math.abs(n or 0)))
	return (text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local Signed = function(n)
	return ((n or 0) < 0 and "-" or "+")..Commas(n)
end

-- "#3 of 42  ▲2", "#7 of 42  NEW" or "unranked"
local RankText = function(rank, previous, count)
	if not rank then return s("Unranked") end
	local text = "#"..rank..((count or 0) > 0 and (" / "..count) or "")
	if previous and previous > rank then
		text = text.."  ▲"..(previous - rank)
	elseif previous and previous < rank then
		text = text.."  ▼"..(rank - previous)
	elseif not previous then
		text = text.."  NEW"
	end
	return text
end

-- The rows to show: the top of the board, with the player's own row kept in.
local VisibleRows = function(board)
	local rows = {}
	for e in ivalues(board or {}) do rows[#rows+1] = e end
	if #rows <= NumRows then return rows end
	local own
	for i = NumRows + 1, #rows do
		if rows[i]["isSelf"] then own = rows[i] end
	end
	local shown = {}
	for i = 1, NumRows do shown[i] = rows[i] end
	if own then shown[NumRows] = own end
	return shown
end

local root = nil
local open = false

local Release = function()
	if not open then return end
	open = false
	SL.ECFACloud.ResultsOpen = false
	for player in ivalues(GAMESTATE:GetHumanPlayers()) do
		SCREENMAN:set_input_redirected(player, false)
	end
end

local Input = function(event)
	if not open or not event or event.type ~= "InputEventType_FirstPress" then return false end
	if event.GameButton == "Start" or event.GameButton == "Back" then
		Release()
		root:playcommand("Close")
		return true
	end
	return false
end

-- One player's results.
local Column = function(side)
	local col = Def.ActorFrame{
		Name="Side"..side,
		InitCommand=function(self) self:visible(false) end,
		ShowCommand=function(self, params)
			self:visible(true):x(params.x)
		end,
	}

	col[#col+1] = LoadFont(font.." Normal")..{
		Name="Player",
		InitCommand=function(self)
			self:y(-120):zoom(0.9):maxwidth((ColumnWidth - 20) / 0.9)
			local pn = "P"..side
			local name = SL[pn] and SL[pn].ECFACloudUsername ~= "" and SL[pn].ECFACloudUsername
				or PROFILEMAN:GetPlayerName("PlayerNumber_"..pn)
			self:settext(name or "")
		end,
	}

	col[#col+1] = LoadFont(font.." Normal")..{
		Name="Status",
		InitCommand=function(self)
			self:y(-101):zoom(0.75):maxwidth((ColumnWidth - 20) / 0.75):settext(s("Submitting"))
		end,
	}

	col[#col+1] = LoadFont(font.." Normal")..{
		Name="ChartRank",
		InitCommand=function(self) self:y(-84):zoom(0.7):diffuse(Muted):maxwidth((ColumnWidth - 20) / 0.7) end,
	}

	-- The chart's Waterfall leaderboard.
	for i = 1, NumRows do
		local y = -62 + (i - 1) * RowHeight
		col[#col+1] = Def.ActorFrame{
			Name="Row"..i,
			InitCommand=function(self) self:y(y) end,
			LoadFont(font.." Normal")..{
				Name="Rank",
				InitCommand=function(self) self:x(-ColumnWidth/2 + 40):horizalign(right):zoom(0.7):maxwidth(40 / 0.7) end,
			},
			LoadFont(font.." Normal")..{
				Name="Name",
				InitCommand=function(self) self:x(-ColumnWidth/2 + 48):horizalign(left):zoom(0.7):maxwidth(150 / 0.7) end,
			},
			LoadFont(font.." Normal")..{
				Name="Score",
				InitCommand=function(self) self:x(ColumnWidth/2 - 14):horizalign(right):zoom(0.7) end,
			},
		}
	end

	-- Event results (when the chart is in an open event).
	col[#col+1] = LoadFont(font.." Normal")..{
		Name="EventName",
		InitCommand=function(self) self:y(68):zoom(0.8):diffuse(Gold):maxwidth((ColumnWidth - 20) / 0.8) end,
	}
	col[#col+1] = LoadFont(font.." Normal")..{
		Name="EventPoints",
		InitCommand=function(self) self:y(85):zoom(0.68):maxwidth((ColumnWidth - 20) / 0.68) end,
	}
	-- Timing Rank first, then Ranking Points, as on the site.
	col[#col+1] = LoadFont(font.." Normal")..{
		Name="EventTP",
		InitCommand=function(self) self:y(100):zoom(0.68):diffuse(Cyan):maxwidth((ColumnWidth - 20) / 0.68) end,
	}
	col[#col+1] = LoadFont(font.." Normal")..{
		Name="EventRP",
		InitCommand=function(self) self:y(115):zoom(0.68):diffuse(Gold):maxwidth((ColumnWidth - 20) / 0.68) end,
	}

	col.FailedCommand=function(self, params)
		if params.side and params.side ~= side then return end
		self:GetChild("Status"):settext(params.text):diffuse(color("#ff7b7b"))
	end

	col.ResultsCommand=function(self, params)
		if params.side ~= side then return end
		local data = params.data or {}

		-- How the play went on ECFA Cloud.
		local status = self:GetChild("Status")
		if data["result"] == "score-added" or data["result"] == "improved" then
			if params.personalRank == 1 then
				status:settext(s("WorldRecord")):diffuse(Color.Yellow)
			else
				status:settext(s("PersonalBest")):diffuse(Color.Yellow)
			end
		else
			status:settext(s("NotPersonalBest")):diffuse(Color.White)
		end
		self:GetChild("ChartRank"):settext(params.personalRank and s("ChartRank"):format(params.personalRank) or "")

		local rows = params.showBoard and VisibleRows(data["wfLeaderboard"]) or {}
		for i = 1, NumRows do
			local row = self:GetChild("Row"..i)
			local e = rows[i]
			local rank, name, score = row:GetChild("Rank"), row:GetChild("Name"), row:GetChild("Score")
			if e then
				local c = e["isSelf"] and SelfColor or (e["isRival"] and RivalColor or Color.White)
				rank:settext(tostring(e["rank"] or "")..".")
				name:settext(e["name"] or e["machineTag"] or "")
				score:settext(("%.2f%%"):format((tonumber(e["score"]) or 0) / 100))
				rank:diffuse(c); name:diffuse(c); score:diffuse(e["isFail"] and Color.Red or c)
			else
				rank:settext(""); name:settext(""); score:settext("")
			end
		end

		local ev = data["events"] and data["events"][1]
		if ev then
			self:GetChild("EventName"):settext(ev["name"] or "")
			local points = ("%s %s / %s"):format(s("SongPoints"), Commas(ev["songPoints"]), Commas(ev["maxPoints"]))
			if (tonumber(ev["bonusPoints"]) or 0) > 0 then
				points = points.."  (+"..Commas(ev["bonusPoints"]).." bonus)"
			end
			self:GetChild("EventPoints"):settext(points)
			self:GetChild("EventRP"):settext(("%s %s (%s)   %s"):format(s("RankingPoints"), Commas(ev["rankingPoints"]),
				Signed(ev["rankingPointsDelta"]), RankText(ev["rank"], ev["previousRank"], ev["entrantCount"])))
			if ev["timingPoints"] ~= nil then
				self:GetChild("EventTP"):settext(("%s %s (%s)   %s"):format(s("TimingPower"), Commas(ev["timingPoints"]),
					Signed(ev["timingPointsDelta"]), RankText(ev["timingRank"], ev["previousTimingRank"], ev["timingEntrantCount"])))
			end
			DiffuseEmojis(self:GetChild("EventRP"))
			DiffuseEmojis(self:GetChild("EventTP"))
		end
	end

	return col
end

local af = Def.ActorFrame{
	Name="ECFACloudResults",
	InitCommand=function(self)
		root = self
		SL.ECFACloud.ResultsOpen = false
		self:visible(false)
	end,

	-- A submission went out: params.sides lists the sides being submitted.
	OpenCommand=function(self, params)
		local sides = params.sides or {}
		if #sides == 0 then return end
		local window = self:GetChild("Window")
		local width = ColumnWidth * #sides + 10
		window:GetChild("Border"):zoomto(width + 4, Height + 4)
		window:GetChild("Body"):zoomto(width, Height)
		window:GetChild("Header"):zoomto(width, 26)
		for i, side in ipairs(sides) do
			window:GetChild("Side"..side):playcommand("Show", { x = (#sides == 1) and 0 or (i == 1 and -ColumnWidth/2 or ColumnWidth/2) })
		end

		open = true
		SL.ECFACloud.ResultsOpen = true
		local screen = SCREENMAN:GetTopScreen()
		screen:AddInputCallback(Input)
		for player in ivalues(GAMESTATE:GetHumanPlayers()) do
			SCREENMAN:set_input_redirected(player, true)
		end
		self:visible(true):diffusealpha(0):linear(0.15):diffusealpha(1)
	end,
	CloseCommand=function(self)
		self:stoptweening():linear(0.12):diffusealpha(0):queuecommand("Hide")
	end,
	HideCommand=function(self)
		self:visible(false)
		local screen = SCREENMAN:GetTopScreen()
		if screen then screen:RemoveInputCallback(Input) end
	end,
	-- Leaving the screen (e.g. the menu timer ran out) gives the input back too.
	OffCommand=function(self) Release() end,

	-- Dim the screen behind the window.
	Def.Quad{
		InitCommand=function(self) self:FullScreen():diffuse(0, 0, 0, 0.6) end,
	},
}

local window = Def.ActorFrame{
	Name="Window",
	InitCommand=function(self) self:xy(_screen.cx, _screen.cy) end,
	Def.Quad{ Name="Border", InitCommand=function(self) self:diffuse(Pink):diffusealpha(0.8) end },
	Def.Quad{ Name="Body", InitCommand=function(self) self:diffuse(color("#0b0d14")) end },
	Def.Quad{ Name="Header", InitCommand=function(self) self:y(-Height/2 + 13):diffuse(Pink):diffusealpha(0.85) end },
	Def.Sprite{
		Texture=THEME:GetPathG("", "ECFA logo small.png"),
		InitCommand=function(self) self:zoom(22 / self:GetHeight()):y(-Height/2 + 13):x(-66) end,
	},
	LoadFont("Wendy/_wendy small")..{
		Text=s("ECFACloud"),
		InitCommand=function(self) self:y(-Height/2 + 13):zoom(0.4):x(10) end,
	},
	LoadFont(font.." Normal")..{
		Text=THEME:GetString("Common", "PopupDismissText"),
		InitCommand=function(self) self:y(Height/2 - 14):zoom(0.7):diffuse(Muted) end,
	},
}
window[#window+1] = Column(1)
window[#window+1] = Column(2)
af[#af+1] = window

return af
