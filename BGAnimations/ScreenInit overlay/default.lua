local af = Def.ActorFrame{ InitCommand=function(self) self:Center() end }

-- check SM5 version, current game (dance, pump, etc.), and RTT support
af[#af+1] = LoadActor("./CompatibilityChecks.lua")

-- -----------------------------------------------------------------------
-- The ECFA logo on a black band. ScreenInit lasts 2.5 seconds (TimerSeconds in metrics.ini).

local logo_height = 180

-- black band behind the logo
af[#af+1] = Def.Quad{
	InitCommand=function(self) self:zoomto(_screen.w,0):diffuse(Color.Black) end,
	OnCommand=function(self) self:accelerate(0.3):zoomtoheight(logo_height + 30):diffusealpha(0.9):sleep(2.1) end,
	OffCommand=function(self) self:accelerate(0.3):zoomtoheight(0) end
}

af[#af+1] = Def.Sprite{
	Texture=THEME:GetPathG("", "ECFA logo.png"),
	InitCommand=function(self)
		self.full_zoom = logo_height / self:GetHeight()
		self:zoom(self.full_zoom * 0.92):diffusealpha(0)
	end,
	OnCommand=function(self)
		self:sleep(0.35):decelerate(0.5):zoom(self.full_zoom):diffusealpha(1)
		self:sleep(1.1):linear(0.4):diffusealpha(0)
	end,
}

return af
