-- Pane9 shows ECFA Cloud event results (e.g. ECFA 2026) for the song that was
-- just played: points earned, clear type, ranking points, rank, and the
-- event leaderboard for the song. It's filled in by Shared/AutoSubmitScore.lua
-- once the score submission comes back.

if not IsServiceAllowed(SL.ECFACloud.AutoSubmit) or not SL.ECFACloud.Events or GAMESTATE:IsCourseMode() then return end

local player = unpack(...)
local NumEntries = 7
local RowHeight = 22

local Commas = function(n)
	local s = tostring(math.floor(n or 0))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

local pane = Def.ActorFrame{
	InitCommand=function(self) self:y(_screen.cy - 62):zoom(0.8) end,
}

-- Event name
pane[#pane+1] = LoadFont("Common Bold")..{
	Name="EventName",
	Text=THEME:GetString("ECFACloud", "EventResults"),
	InitCommand=function(self) self:zoom(0.45):y(-6):maxwidth(560) end,
	ShowEventCommand=function(self, params) self:settext(params.event.name) end,
}

-- Summary lines
pane[#pane+1] = LoadFont("Common Normal")..{
	Name="Summary",
	Text=THEME:GetString("ECFACloud", "Waiting"),
	InitCommand=function(self) self:y(36):vertspacing(-2):maxwidth(300) end,
	NoEventCommand=function(self) self:settext(THEME:GetString("ECFACloud", "NotAnEventSong")) end,
	ShowEventCommand=function(self, params)
		local e = params.event
		local rank = e.rank and ("#"..e.rank.." / "..e.entrantCount) or "—"
		if e.rank and e.previousRank and e.previousRank > e.rank then
			rank = rank.."  ▲"..(e.previousRank - e.rank)
		elseif e.rank and not e.previousRank then
			rank = rank.."  NEW"
		end
		local delta = e.rankingPointsDelta or 0
		self:settext(table.concat({
			("EX %.2f%%  ·  %s"):format(e.exScore / 100, e.clearType),
			("%s + %s bonus  /  %s pts"):format(Commas(e.songPoints), Commas(e.bonusPoints), Commas(e.maxPoints)),
			("Ranking points %s (%s%s)"):format(Commas(e.rankingPoints), delta >= 0 and "+" or "-", Commas(math.abs(delta))),
			("Rank %s"):format(rank),
		}, "\n"))
		if e.improved then
			self:diffuseshift():effectcolor1(Color.White):effectcolor2(Color.Yellow):effectperiod(3)
		end
		DiffuseEmojis(self)
	end,
}

-- Event leaderboard for this song
local list = Def.ActorFrame{
	Name="EventLeaderboard",
	InitCommand=function(self) self:y(94) end,
}
for i=1, NumEntries do
	local row = Def.ActorFrame{
		Name="Row"..i,
		InitCommand=function(self) self:y(RowHeight * (i - 1)) end,
		LoadFont("Common Normal")..{ Name="Rank", InitCommand=function(self) self:x(-120):horizalign(right):maxwidth(40) end },
		LoadFont("Common Normal")..{ Name="Name", InitCommand=function(self) self:x(-110):horizalign(left):maxwidth(150) end },
		LoadFont("Common Normal")..{ Name="Score", InitCommand=function(self) self:x(130):horizalign(right) end },
	}
	row.ShowEventCommand=function(self, params)
		local entry = params.event.leaderboard and params.event.leaderboard[i]
		local rank, name, score = self:GetChild("Rank"), self:GetChild("Name"), self:GetChild("Score")
		if not entry then
			rank:settext(""); name:settext(i == 1 and "" or ""); score:settext("")
			return
		end
		rank:settext(entry.rank..".")
		name:settext(entry.name)
		score:settext(("%.2f%%"):format(entry.score / 100))
		local c = Color.White
		if entry.isSelf then c = color("#A1FF94") elseif entry.isRival then c = color("#BD94FF") end
		rank:diffuse(c); name:diffuse(c)
		score:diffuse(SL.JudgmentColors["ITG"][1])
	end
	list[#list+1] = row
end
pane[#pane+1] = list

pane[#pane+1] = Def.Sprite{
	Texture=THEME:GetPathG("","ECFACloud.png"),
	InitCommand=function(self) self:zoom(0.3):xy(165, 25) end,
}

return pane
