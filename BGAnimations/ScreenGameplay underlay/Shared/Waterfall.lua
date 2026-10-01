-- Drives the Waterfall lifebars and scoring helpers (Scripts/WF-LifeBars.lua,
-- Scripts/WF-Scoring.lua) during gameplay.

-- Start every ScreenGameplay with full lifebars and empty counts.
WF.InitializeLifeBars()
WF.InitScoring()

local af = Def.ActorFrame{
	Name="WaterfallController",
	JudgmentMessageCommand=function(self, params)
		if not params.Player then return end
		WF.LifeBarProcessJudgment(params)
		if not IsAutoplay(params.Player) then
			WF.TrackFAPlus(tonumber(ToEnumShortString(params.Player):sub(-1)), params)
		end
	end,
	WFLifeChangedMessageCommand=function(self, params)
		WF.TrackLifeChange(params.pn, params.ind, params.newlife, GAMESTATE:GetCurMusicSeconds())
	end,
}

-- One hidden actor per auto-regenerating lifebar keeps its regen ticking.
for player in ivalues(GAMESTATE:GetHumanPlayers()) do
	local pn = tonumber(ToEnumShortString(player):sub(-1))
	for ind = 1, #WF.LifeBarNames do
		if WF.LifeBarMetrics[ind].UseAutoRegen and not GAMESTATE:IsCourseMode() then
			af[#af+1] = Def.Actor{
				InitCommand=function(self) WF.ResetLifeRegenState(pn, ind) end,
				WFLifeChangedMessageCommand=function(self, params)
					if params.pn ~= pn or params.ind ~= ind or params.regenflag then return end
					local life = WF.GetCurrentLife(pn, ind)
					if life > 0 and life < WF.LifeBarMetrics[ind].RegenThreshold then
						if WF.LifeBarValues[pn][ind].RegenState == 0 then
							WF.LifeBarValues[pn][ind].RegenState = 1
							WF.LifeRegenTick(pn, ind, self)
						else
							WF.LifeChangedAddRegenTime(pn, ind)
						end
					end
				end,
				RegenTickCommand=function(self) WF.LifeRegenTick(pn, ind, self) end,
			}
		end
	end
end

return af
