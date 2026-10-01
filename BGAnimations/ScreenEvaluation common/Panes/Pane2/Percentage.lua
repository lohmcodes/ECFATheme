local player, controller = unpack(...)

local percent = nil
local diffuse = nil
local styletype = ToEnumShortString(GAMESTATE:GetCurrentStyle():GetStyleType())
if (styletype == "TwoPlayersSharedSides") then
	stats = STATSMAN:GetCurStageStats():GetRoutineStageStats()
	-- Format the Percentage string, removing the % symbol
	percent = CalculateExScore(player)
	diffuse = SL.JudgmentColors[SL.Global.GameMode][1]
elseif SL[ToEnumShortString(player)].ActiveModifiers.ShowExScore then
	percent = CalculateExScore(player)
	diffuse = SL.JudgmentColors["ITG"][1]
else
	percent = CalculateSimulatedITGScore(player)
	diffuse = Color.White
end
local label = SL[ToEnumShortString(player)].ActiveModifiers.ShowExScore and "EX" or "ITG"

return Def.ActorFrame{
	Name="PercentageContainer"..ToEnumShortString(player),
	OnCommand=function(self)
		self:y( _screen.cy-26 )
	end,

	-- dark background quad behind player percent score
	Def.Quad{
		InitCommand=function(self)
			self:diffuse(color("#101519")):zoomto(158.5, 88)
			self:horizalign(controller==PLAYER_1 and left or right)
			self:x(150 * (controller == PLAYER_1 and -1 or 1))
			self:y(14)
			if ThemePrefs.Get("VisualStyle") == "Technique" then
				self:diffusealpha(0.5)
			elseif ThemePrefs.Get("VisualStyle") == "Transistor"  then
				self:diffusealpha(0.7)
			end
		end
	},

	-- which secondary score this is (simulated from note timing)
	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Text=label,
		InitCommand=function(self)
			self:zoom(0.6):diffuse(Color.White):diffusealpha(0.7)
			self:horizalign(controller==PLAYER_1 and left or right)
			self:xy(146 * (controller == PLAYER_1 and -1 or 1), 48)
		end
	},

	LoadFont(ThemePrefs.Get("ThemeFont") .. " Bold")..{
		Name="Percent",
		Text=("%.2f"):format(percent),
		InitCommand=function(self)
			self:horizalign(right):zoom(0.95)
			self:x( (controller == PLAYER_1 and 1.5 or 141))
			self:diffuse(diffuse)
		end
	}
}
