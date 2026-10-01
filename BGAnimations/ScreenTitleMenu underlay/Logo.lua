-- The ECFA logo on the title menu (and, via ScreenLogo underlay.lua, in attract mode).
local logo_height = 170
local y = -15

local af = Def.ActorFrame{}

-- On light backgrounds (RainbowMode, holiday cheer) the white lettering needs a dark backdrop.
if DarkUI() then
	af[#af+1] = Def.Quad{
		InitCommand=function(self)
			self:zoomto(400, logo_height + 24):y(y):diffuse(Color.Black):diffusealpha(0.85)
			self:fadeleft(0.2):faderight(0.2)
		end,
	}
end

af[#af+1] = Def.Sprite{
	Name="Logo",
	Texture=THEME:GetPathG("", "ECFA logo.png"),
	InitCommand=function(self)
		self:zoom(logo_height / self:GetHeight()):y(y)
	end,
}

return af
