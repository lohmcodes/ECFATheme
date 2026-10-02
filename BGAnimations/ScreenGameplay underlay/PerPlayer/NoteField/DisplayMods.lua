local player = ...

local optionslist = GetPlayerOptionsString(player)

local af = Def.ActorFrame{
  InitCommand = function(self)
    if GAMESTATE:GetCurrentStyle():GetStyleType() == "StyleType_TwoPlayersSharedSides" then
      -- if p1 3/4 of the notefielx, if p2 5/4
        self:diffusealpha(1):xy(GetNotefieldX(player) / (player == PLAYER_1 and 0.825 or 1.25), SCREEN_HEIGHT/4*1.3)
		else
      self:diffusealpha(1):xy(GetNotefieldX(player), SCREEN_HEIGHT/4*1.3)
    end
  end,
  OnCommand=function(self)
    self:sleep(5):decelerate(0.5):diffusealpha(0)
  end,
  PlayerOptionsChangedMessageCommand=function(self, params)
    if params.Player ~= player then return false end
    self:stoptweening():playcommand("Init"):queuecommand("On")
  end,
}

af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
  Text=optionslist,
  InitCommand=function(self)
    self:y(15)
    self:zoom(0.8)
    self:wrapwidthpixels(125)
    self:shadowcolor(Color.Black)
    self:shadowlength(1)
  end,
  PlayerOptionsChangedMessageCommand=function(self, params)
    if params.Player ~= player then return false end
    optionslist = GetPlayerOptionsString(player, "ModsLevel_Song")
    self:settext(optionslist)
  end
}

-- "(No CMOD)" charts: a CMod play won't be submitted to ECFA Cloud, so say so loudly.
if not GAMESTATE:IsCourseMode() then
	local song = GAMESTATE:GetCurrentSong()
	if IsNoCmodSong(song)
		and GAMESTATE:GetPlayerState(ToEnumShortString(player)):GetPlayerOptions("ModsLevel_Preferred"):CMod() then
			af[#af+1] = Def.ActorFrame{
				InitCommand=function(self)
					self:y(15+15*#values)
				end,
				Name="CModWarning",
				Def.Quad{
					Name="BGCmodWarning",
					InitCommand=function(self)
						self:diffuse(0,0,0,0.8)
							:x(0)
							:setsize(90, 30)
					end,
				},
				Def.BitmapText {
					Name="CModWarningText",
					Font=ThemePrefs.Get("ThemeFont") .. " Normal",
					Text="CMod On",
					InitCommand=function(self)
						self:zoom(1.5)
							:diffuse(1,0,0,1)
							:horizalign(center)						
					end,
				}
			}
			
	end
end

return af