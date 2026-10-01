-- One Waterfall lifebar, filling the space behind the notefield ("Surround").
local args = ...
local player = args.player
local ind = args.index
local pnum = tonumber(ToEnumShortString(player):sub(-1))
local c = WF.LifeBarColors[ind]
local max = WF.LifeBarMetrics[ind].MaxValue
local alpha = 0.3

local MakeQuad = function(side)
	return Def.Quad{
		InitCommand=function(self)
			self:vertalign(top):zoomto(_screen.w/2, _screen.h-80):y(80):diffuse(c[1], c[2], c[3], 1)
			if side == "left" then
				self:horizalign(left):faderight(0.8):x(0)
			else
				self:horizalign(right):fadeleft(0.8):x(_screen.w)
			end
			self:diffusealpha(WF.VisibleLifeBar[pnum] == ind and alpha or 0)
		end,
		WFLifeChangedMessageCommand=function(self, params)
			if params.pn == pnum and params.ind == ind then
				self:finishtweening():smooth(0.2):croptop(1 - params.newlife / max)
			end
		end,
		WFLifeBarFailedMessageCommand=function(self, params)
			if params.pn ~= pnum then return end
			self:linear(0.2):diffusealpha(WF.VisibleLifeBar[pnum] == ind and alpha or 0)
		end,
	}
end

local af = Def.ActorFrame{}
if GAMESTATE:GetCurrentStyle():GetStyleType() == "StyleType_OnePlayerTwoSides" then
	-- double: flank both sides of the screen
	af[#af+1] = MakeQuad("left")
	af[#af+1] = MakeQuad("right")
else
	af[#af+1] = MakeQuad(player == PLAYER_1 and "left" or "right")
end
return af
