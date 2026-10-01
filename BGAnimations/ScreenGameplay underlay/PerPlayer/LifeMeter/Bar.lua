-- One Waterfall lifebar, as a horizontal bar at the top of the screen
-- ("Standard") or a vertical bar beside the notefield ("Vertical").
local args = ...
local player = args.player
local ind = args.index
local pn = ToEnumShortString(player)
local pnum = tonumber(pn:sub(-1))
local c = WF.LifeBarColors[ind]
local max = WF.LifeBarMetrics[ind].MaxValue

local vertical = args.type == "Vertical"
local w, h = 136, 18
local x = _screen.cx + (player==PLAYER_1 and -1 or 1) * SL_WideScale(238, 288)
local y = 20
local rot = 0
if vertical then
	w, h = 250, 16
	x = GetNotefieldX(player) + (GetNotefieldWidth()/2 + 16) * (player==PLAYER_1 and -1 or 1)
	y = _screen.cy + 35
	rot = -90
elseif GAMESTATE:GetPlayerState(player):GetPlayerOptions("ModsLevel_Preferred"):UsingReverse() then
	y = _screen.h - 14
end

-- get SongPosition specific to this player so that split BPMs are handled
local songposition = GAMESTATE:GetPlayerState(player):GetSongPosition()
local swoosh

local Update = function(self)
	if not swoosh then return end
	local velocity = -(songposition:GetCurBPS() * 0.5)
	if songposition:GetFreeze() or songposition:GetDelay() then velocity = 0 end
	swoosh:texcoordvelocity(velocity, 0)
end

-- zoomtowidth (not zoomx): the fill is a 1px quad but the swoosh is a 128px texture
local Resize = function(self, life)
	self:finishtweening():decelerate(0.1):zoomtowidth(w * life / max)
end

return Def.ActorFrame{
	InitCommand=function(self)
		self:xy(x, y):rotationz(rot):SetUpdateFunction(Update)
		self:diffusealpha(WF.VisibleLifeBar[pnum] == ind and 1 or 0)
	end,
	-- show the bar that's currently visible for this player
	WFLifeBarFailedMessageCommand=function(self, params)
		if params.pn ~= pnum then return end
		self:finishtweening():linear(0.2):diffusealpha(WF.VisibleLifeBar[pnum] == ind and 1 or 0)
	end,

	-- frame
	Def.Quad{ InitCommand=function(self) self:zoomto(w+4, h+4) end },
	Def.Quad{ InitCommand=function(self) self:zoomto(w, h):diffuse(0,0,0,1) end },

	-- fill
	Def.Quad{
		InitCommand=function(self) self:x(-w/2):horizalign(left):zoomto(w, h):diffuse(c[1], c[2], c[3], 1) end,
		WFLifeChangedMessageCommand=function(self, params)
			if params.pn == pnum and params.ind == ind then Resize(self, params.newlife) end
		end,
	},
	-- a scrolling gradient on top of the fill
	LoadActor("swoosh.png")..{
		InitCommand=function(self)
			swoosh = self
			self:x(-w/2):horizalign(left):zoomto(w, h):diffusealpha(0.2):customtexturerect(0, 0, 1, 1)
		end,
		WFLifeChangedMessageCommand=function(self, params)
			if params.pn == pnum and params.ind == ind then Resize(self, params.newlife) end
		end,
	},
	-- percent
	LoadFont("Common Normal")..{
		InitCommand=function(self)
			self:visible(SL[pn].ActiveModifiers.ShowLifePercent and not vertical or false)
			self:zoom(0.8):x((w/2 + 26) * (player==PLAYER_1 and -1 or 1)):settext("100%")
		end,
		WFLifeChangedMessageCommand=function(self, params)
			if params.pn == pnum and params.ind == ind then
				self:settext(("%d%%"):format(math.floor(params.newlife / max * 100)))
			end
		end,
	},
}
