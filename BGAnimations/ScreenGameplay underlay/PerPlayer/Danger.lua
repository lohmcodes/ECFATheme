local player = ...

-- Don't bother loading any code for Danger if FailType for this player is FailType_Off
local failtype = GAMESTATE:GetPlayerState(player):GetPlayerOptions("ModsLevel_Preferred"):FailSetting()
if failtype == "FailType_Off" then return end

-- ------------------------------------------------------------------

local pn = ToEnumShortString(player)
local pnum = tonumber(pn:sub(-1))

local style = GAMESTATE:GetCurrentStyle()
local styleType = style:GetStyleType()
local IsPlayingDouble = (styleType == 'StyleType_OnePlayerTwoSides' or styleType == 'StyleType_TwoPlayersSharedSides')

local danger = Def.Quad{
	Name="Danger" .. pn,
	InitCommand=function(self)
		self:visible(not SL[pn].ActiveModifiers.HideLifebar)
		self:diffusealpha(0)

		if IsPlayingDouble or PREFSMAN:GetPreference("Center1Player") and GAMESTATE:GetNumSidesJoined() == 1 then
			self:stretchto(0,0,_screen.w,_screen.h)
		elseif not IsPlayingDouble and player == PLAYER_1 then
			self:faderight(0.1):stretchto(0,0,_screen.cx,_screen.h)
		elseif not IsPlayingDouble and player == PLAYER_2 then
			self:fadeleft(0.1):stretchto(_screen.cx,0,_screen.w,_screen.h)
		end
	end,
	DangerCommand=function(self) self:linear(0.3):diffusealpha(0.7):diffuseshift():effectcolor1(1, 0, 0.24, 0.1):effectcolor2(1, 0, 0, 0.35) end,
	DeadCommand=function(self) self:diffusealpha(0):stopeffect():stoptweening():diffuse(1,0,0,1):linear(0.3):diffusealpha(0.8):linear(0.3):diffusealpha(0) end,
	OutOfDangerCommand=function(self) self:diffusealpha(0):stopeffect():stoptweening():diffuse(0,1,0,0.5):linear(0.3):diffusealpha(0.4):linear(0.3):diffusealpha(0) end,
	HideCommand=function(self) self:stopeffect():stoptweening():linear(0.3):diffusealpha(0) end
}

-- Driven by the Waterfall lifebars (Scripts/WF-LifeBars.lua): danger follows the
-- lifebar shown on screen, which drops to the next easier one when it fails.
if SL[pn].ActiveModifiers.HideDanger then
	-- only flash when the player fails
	danger.WFDangerMessageCommand=function(self, param)
		if param.pn == pnum and param.ind == WF.LowestLifeBarToFail and param.event == "Dead" then
			self:playcommand("Dead")
		end
	end
else
	danger.WFDangerMessageCommand=function(self, param)
		if param.pn ~= pnum then return end
		local visible = WF.VisibleLifeBar[pnum]
		if param.ind == visible then
			if param.event == "In" then
				self:playcommand("Danger")
			elseif param.event == "Dead" then
				self:playcommand("Dead")
			elseif param.event == "Out" then
				self:playcommand("OutOfDanger")
			end
		elseif param.event == "Dead" and param.ind == visible + 1
		and WF.GetCurrentLife(pnum, visible) > WF.DangerThreshold[visible] then
			-- the harder lifebar died, and the one now shown isn't in danger
			self:playcommand("Hide")
		end
	end
end

return danger
