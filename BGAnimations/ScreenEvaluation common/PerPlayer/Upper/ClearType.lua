-- The play's Waterfall clear type (Mastery ... Easy Clear, or Fail), opposite
-- the letter grade. See WF.GetClearType in Scripts/WF-Scoring.lua.
local player = ...
if SL.Global.GameMode ~= "Waterfall" or GAMESTATE:IsCourseMode() then return end

local ct = WF.GetClearType(player)
-- remembered for the score submission and anything else on this screen
SL[ToEnumShortString(player)].Stages.Stats[SL.Global.Stages.PlayedThisGame + 1].clear_type = ct

return LoadFont(ThemePrefs.Get("ThemeFont") .. " Bold")..{
	Name="ClearType",
	Text=WF.ClearTypes[ct]:upper(),
	InitCommand=function(self)
		self:zoom(0.55):maxwidth(150 / 0.55)
		self:xy(75 * (player==PLAYER_1 and 1 or -1), _screen.cy-150)
		self:diffuse(WF.ClearTypeColor(ct)):shadowlength(1)
	end,
}
