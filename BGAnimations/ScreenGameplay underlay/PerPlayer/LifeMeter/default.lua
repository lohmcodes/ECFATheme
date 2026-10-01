local player = ...
local pn = ToEnumShortString(player)
if SL[pn].ActiveModifiers.HideLifebar then return end

-- One meter per Waterfall lifebar (Easy, Normal, Hard), drawn on top of each
-- other. Only the player's preferred lifebar is shown; when it fails, the next
-- easier one takes its place (see WF.VisibleLifeBar in Scripts/WF-LifeBars.lua).
local lifemeter_type = SL[pn].ActiveModifiers.LifeMeterType or CustomOptionRow("LifeMeterType").Choices[1]

local af = Def.ActorFrame{ Name="LifeMeter_"..pn }
for ind = 1, #WF.LifeBarNames do
	af[#af+1] = LoadActor(lifemeter_type == "Surround" and "./Surround.lua" or "./Bar.lua", {player=player, index=ind, type=lifemeter_type})
end
return af
