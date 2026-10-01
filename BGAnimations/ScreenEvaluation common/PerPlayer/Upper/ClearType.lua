-- The play's Waterfall clear type (Mastery ... Easy Clear, or Fail), just above the
-- letter grade (LetterGrade.lua puts the grade at x=70 on the outer side) and below
-- the machine/personal record texts (RecordTexts.lua, y up to about 66).
-- See WF.GetClearType in Scripts/WF-Scoring.lua.
local player = ...
if SL.Global.GameMode ~= "Waterfall" or GAMESTATE:IsCourseMode() then return end

local ct = WF.GetClearType(player)
-- remembered for the score submission and anything else on this screen
SL[ToEnumShortString(player)].Stages.Stats[SL.Global.Stages.PlayedThisGame + 1].clear_type = ct

return LoadFont(ThemePrefs.Get("ThemeFont") .. " Bold")..{
	Name="ClearType",
	Text=WF.ClearTypes[ct]:upper(),
	InitCommand=function(self)
		-- kept narrow enough to stay clear of the song banner
		self:zoom(0.32):maxwidth(130 / 0.32)
		self:xy(70 * (player==PLAYER_1 and -1 or 1), _screen.cy-163)
		self:diffuse(WF.ClearTypeColor(ct)):shadowlength(1)
	end,
}
