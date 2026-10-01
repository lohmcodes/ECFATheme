local IsUltraWide = (GetScreenAspectRatio() >= 21/9)

local AwardMap = {
	["StageAward_FullComboW1"] = 1,
	["StageAward_FullComboW2"] = 2,
	["StageAward_SingleDigitW2"] = 2,
	["StageAward_OneW2"] = 2,
	["StageAward_FullComboW3"] = 3,
	["StageAward_SingleDigitW3"] = 3,
	["StageAward_OneW3"] = 3,
	["StageAward_100PercentW3"] = 3,
	-- The StageAwards below technically doesn't exist, but we create them on the
	-- fly below.
	["StageAward_FullComboW4"] = 4,
	["StageAward_FullComboW0"] = 0,
}

local ClearLamp = { color("#0000CC"), color("#990000") }

-- Whether a Waterfall score judged every note. A score saved from a play the player
-- gave up on judged fewer notes than the chart has, so its percentage (out of the
-- whole chart) is lower than the percentage of the notes it did judge.
local IsCompleteScore = function(score)
	local m = SL.Metrics.Waterfall
	local points, possible = 0, 0
	for w in ivalues({ "W1", "W2", "W3", "W4", "W5", "Miss" }) do
		local n = score:GetTapNoteScore("TapNoteScore_"..w)
		points = points + n * m["PercentScoreWeight"..w]
		possible = possible + n * m.PercentScoreWeightW1
	end
	for h in ivalues({ "Held", "LetGo", "MissedHold" }) do
		local n = score:GetHoldNoteScore("HoldNoteScore_"..h)
		if h == "Held" then points = points + n * m.PercentScoreWeightHeld end
		possible = possible + n * m.PercentScoreWeightHeld
	end
	points = points + score:GetTapNoteScore("TapNoteScore_HitMine") * m.PercentScoreWeightHitMine
	if possible <= 0 then return false end
	return math.abs(math.max(0, points / possible) - score:GetPercentDP()) <= 0.0001
end

local function GetLamp(high_score_list)
	-- If no scores then just return.
	if high_score_list == nil or #high_score_list:GetHighScores() == 0 then
		return nil
	end

	local best_lamp = nil
	local tap_count = 99

	for score in ivalues(high_score_list:GetHighScores()) do
		local award = score:GetStageAward()
		-- (the "quint" lamp only exists for scores saved by ITG mode, which stored its white count in Score)
		if score:GetGrade() == "Grade_Tier01" and SL.Global.GameMode ~= "Waterfall" then
			if score:GetPercentDP() == 1.0 and score:GetScore() < score:GetTapNoteScore("TapNoteScore_W1") and score:GetScore() == 0 then
				award = "StageAward_FullComboW0"
			end
		end

		-- The engine has no award for a full combo with W4s (a Waterfall "Full Combo"
		-- of OKs), so make one. Waterfall full combos are also broken by mines.
		if SL.Global.GameMode == "Waterfall" and score:GetGrade() ~= "Grade_Failed" then
			local misses = score:GetTapNoteScore("TapNoteScore_Miss") +
					score:GetHoldNoteScore("HoldNoteScore_LetGo") +
					score:GetTapNoteScore("TapNoteScore_CheckpointMiss") +
					score:GetTapNoteScore("TapNoteScore_HitMine")
			if misses + score:GetTapNoteScore("TapNoteScore_W5") > 0 then
				award = nil
			elseif award == nil and IsCompleteScore(score) then
				award = "StageAward_FullComboW4"
			end
		end

		if award and AwardMap[award] ~= nil then
			-- Reset tap count if the best lamp goes up
			if best_lamp ~= nil and AwardMap[award] < best_lamp then
				tap_count = 99
			end
			best_lamp = math.min(best_lamp and best_lamp or 999, AwardMap[award])
		end
		
		-- Single Digit Judge Count
		if AwardMap[award] == best_lamp then
			if best_lamp == 1 and score:GetScore() > 0 then
				tap_count = math.min(tap_count, score:GetScore())
			elseif best_lamp == 2 then
				tap_count = math.min(tap_count, score:GetTapNoteScore("TapNoteScore_W2"))
			elseif best_lamp == 3 then
				tap_count = math.min(tap_count, score:GetTapNoteScore("TapNoteScore_W3"))
			end
		end
			
		
		if AwardMap[award] == best_lamp and best_lamp == 1 and score:GetScore() == 0 then
			best_lamp = 0
		elseif best_lamp == nil then
			if score:GetGrade() == "Grade_Failed" then best_lamp = 52
			else best_lamp = 51 end
		end
	end

	return best_lamp,tap_count
end

return Def.ActorFrame{
	Def.Quad{
		InitCommand=function(self)
			self:visible(false)
		end,
		SetGradeCommand=function(self, param)
			self:scaletoclipped(SL_WideScale(5, 6), 31)

			local lamp, tap_count = GetLamp(param.HighScoreList)
			if lamp == nil then
				self:visible(false)
				self:GetParent():GetChild("Judge"):playcommand("Hide")
			else
				self:visible(true)
				-- Default to the quint color.
				local lamp_color = color("1,0.2,0.406,1")
				if lamp > 50 then
					self:visible(true)
					self:stopeffect()
					self:diffuse(ClearLamp[lamp - 50])
					self:GetParent():GetChild("Judge"):playcommand("Hide")
				elseif lamp ~= 0 then
					lamp_color = SL.JudgmentColors[SL.Global.GameMode][lamp]
					self:diffuseshift():effectperiod(0.8)
					self:effectcolor1(lamp_color)
					self:effectcolor2(lerp_color(0.70, color("#ffffff"), lamp_color))
					
					if tap_count and tap_count < 10 then
						self:GetParent():GetChild("Judge"):playcommand("Count", {count=tap_count,lamp=lamp,PlayerNumber=param.PlayerNumber})
					else
						self:GetParent():GetChild("Judge"):playcommand("Hide")
					end
				else
					self:diffuseshift():effectperiod(0.8)
					self:effectcolor1(lamp_color)
					self:effectcolor2(lerp_color(0.70, color("#ffffff"), lamp_color))
				end				
			end

			-- Ultrawide is quite hard to align, manually scale for it.
			if IsUltraWide then
				self:x((SL_WideScale(13, 20) + 10) * (param.PlayerNumber == PLAYER_1 and -1 or 1))
			else
				self:x(SL_WideScale(13, 20) * (param.PlayerNumber == PLAYER_1 and -1 or 1))
			end
		end
	},
	
	Def.BitmapText{
		Font=ThemePrefs.Get("ThemeFont") .. " ScreenEval",
		Name="Judge",
		Text="5",
		InitCommand=function(self)
			self:visible(false)
			self:zoom(0.15)
			self:addy(10)
			self:diffuse(1,1,1,1)
		end,
		CountCommand=function(self, param)
			if param.PlayerNumber == PLAYER_2 then
				-- Ultrawide is quite hard to align, manually scale for it.
				if IsUltraWide then
					self:x(SL_WideScale(7, 14) +10)
				else
					self:x(SL_WideScale(7, 14))
				end
			else
				self:x(SL_WideScale(-7, -13))
			end
			self:settext(param.count):visible(true):diffuse(SL.JudgmentColors["FA+"][param.lamp+1])
		end,
		HideCommand=function(self)
			self:settext(""):visible(false)
		end,
	}
}