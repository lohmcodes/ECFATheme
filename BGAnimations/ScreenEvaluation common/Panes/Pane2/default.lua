-- Pane2 displays the secondary ITG/EX score: a simulated ITG play, where every
-- tap's offset was re-judged with ITG's windows (see WF.SimulateITGJudgment),
-- with its judgment counts (Fantastic+ within 15ms, Fantastic, Excellent, ...)
-- and judgment counts on holds, mines, rolls
local player = unpack(...)
local pn = ToEnumShortString(player)

return Def.ActorFrame{
	-- score displayed as a percentage
	LoadActor("./Percentage.lua", ...),

	-- labels like "FANTASTIC", "MISS", "holds", "rolls", etc.
	LoadActor("./JudgmentLabels.lua", ...),

	-- numbers (How many Fantastics? How many Misses? etc.)
	LoadActor("./JudgmentNumbers.lua", ...),
}