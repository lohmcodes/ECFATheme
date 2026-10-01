-- This script needs to be loaded before other scripts that use it.

local PlayerDefaults = {
	__index = {
		initialize = function(self)
			self.ActiveModifiers = {
				SpeedModType = "M",
				SpeedMod = 250,
				JudgmentGraphic = "Optimus Dark 1x7 (doubleres).png",
				HeldGraphic = "None",
				ComboFont = "Wendy",
				HoldJudgment = "Love 1x2 (doubleres).png",
				NoteSkin = nil,
				NoteSkinVariant = nil,
				Mini = "0%",
				Spacing = "0%",
				BackgroundFilter = 0,
				VisualDelay = "0ms",

				HideTargets = false,
				HideSongBG = false,
				HideCombo = false,
				HideLifebar = false,
				HideScore = false,
				HideDanger = false,
				HideComboExplosions = false,

				FlashMiss = false,
				FlashWayOff = false,
				FlashDecent = false,
				FlashGreat = false,
				FlashExcellent = false,
				FlashFantastic = false,
				SubtractiveScoring = false,
				MeasureCounter = "None",
				MeasureCounterLeft = false,
				MeasureCounterUp = true,
				HideLookahead = false,
				MeasureLines = "Off",
				DataVisualizations = "Step Statistics",
				StepStatsExtra = "None",
				TargetScore = "Personal best",
				TargetScoreNumber = 100,
				ActionOnMissedTarget = "Nothing",
				Pacemaker = false,
				LifeMeterType = "Standard",
				PreferredLifeBar = "Hard",
				NPSGraphAtTop = false,
				JudgmentTilt = false,
				TiltMultiplier = 1,
				ColumnCues = true,
				ColumnCountdown = false,
				ShowHeldMiss = false,
				DisplayScorebox = true,

				ErrorBar = "None",
				ErrorBarUp = false,
				ErrorBarMultiTick = false,
				ErrorBarTrim = "Off",

				HideEarlyDecentWayOffJudgments = false,
				HideEarlyDecentWayOffFlash = false,
				ShowEarlyDecentWayOffColumn = false,

				-- While SL no longer supports disabling individual timing windows
				-- in ITG mode, Casual mode still does so we still track it here.
				TimingWindows = {true, true, true, true, true},
				ShowFaPlusWindow = false,
				ShowExScore = false,
				ShowHardEXScore = false,
				ShowFaPlusPane = true,
				
				RainbowMax = false,
				ResponsiveColors = false,
				ShowLifePercent = false,
				
				PackBanner = false,
				StepInfo = false,
				SBITGScore = true,
				SBExScore = true,
				SBEvents = true,
				
				FlashMiss = true,
				FlashWayOff = false,
				FlashDecent = false,
				FlashGreat = false,
				FlashExcellent = false,
				FlashFantastic = false,
				
				TiltMultiplier = 1,
				ComboColors = "Glow",
				ComboMode = "FullCombo",
				TimerMode = "Time",
				JudgmentAnimation = "Default",
				RailBalance = "No",

				NoteFieldOffsetX = 0,
				NoteFieldOffsetY = 0,
			}
			-- TODO(teejusb): Rename "Streams" as the data contains more information than that.
			self.Streams = {
				-- Chart identifiers used to cache the chart hash so we only
				-- parse a given chart once.
				Filename = "",
				StepsType = "",
				Difficulty = "",
				Description = "",

				-- Information parsed out from the chart.
				NotesPerMeasure = {},
				EquallySpacedPerMeasure = {},
				PeakNPS = 0,
				NPSperMeasure = {},
				ColumnCues = {},
				Hash = '',

				Crossovers = 0,
				Footswitches = 0,
				Sideswitches = 0,
				Jacks = 0,
				Brackets = 0,

				-- Data for measure counter. Populated in ./ScreenGameplay in/MeasureCounterAndMods.lua.
				-- Uses the notesThreshold option.
				Measures = {},
			}
			self.HighScores = {
				EnteringName = false,
				Name = ""
			}
			self.Stages = {
				Stats = {}
			}
			self.PlayerOptionsString = nil
			self.ITLData = {
				["pathMap"] = {},
				["hashMap"] = {},
				["unlockFolders"] = {},
			}

			-- default panes to intialize ScreenEvaluation to
			-- when only a single player is joined (single, double)
			-- in versus (2 players joined) only EvalPanePrimary will be used
			self.EvalPanePrimary   = 1 -- large score and judgment counts
			self.EvalPaneSecondary = 5 -- offset histogram

			-- The ECFA Cloud API key loaded for this player (ECFACloud.ini)
			self.ApiKey = ""
			self.ECFACloudUsername = ""
			-- Whether or not the player is playing on pad.
			self.IsPadPlayer = false
			self.Favorites = {}
		end
	}
}

local GlobalDefaults = {
	__index = {

		-- since the initialize() function is called every game cycle, the idea
		-- is to define variables we want to reset every game cycle inside
		initialize = function(self)
			self.ActiveModifiers = {
				MusicRate = 1.0,
			}
			self.Stages = {
				PlayedThisGame = 0,
				Restarts = 0,
				Remaining = PREFSMAN:GetPreference("SongsPerPlay"),
				Stats = {}
			}
			self.ScreenAfter = {
				PlayAgain = "ScreenEvaluationSummary",
				PlayerOptions  = Branch.GameplayScreen(),
				PlayerOptions2 = Branch.GameplayScreen(),
				PlayerOptions3 = Branch.GameplayScreen(),
				PlayerOptions4 = Branch.GameplayScreen(),
			}
			self.ContinuesRemaining = ThemePrefs.Get("NumberOfContinuesAllowed") or 0
			self.GameMode = ValidGameMode(ThemePrefs.Get("DefaultGameMode"))
			self.ScreenshotTexture = nil
			self.MenuTimer = {
				ScreenECFACloudLogin  = ThemePrefs.Get("ScreenECFACloudLoginMenuTimer"),
				ScreenSelectMusic       = ThemePrefs.Get("ScreenSelectMusicMenuTimer"),
				ScreenSelectMusicCasual = ThemePrefs.Get("ScreenSelectMusicCasualMenuTimer"),
				ScreenPlayerOptions     = ThemePrefs.Get("ScreenPlayerOptionsMenuTimer"),
				ScreenEvaluation        = ThemePrefs.Get("ScreenEvaluationMenuTimer"),
				ScreenEvaluationNonstop = ThemePrefs.Get("ScreenEvaluationNonstopMenuTimer"),
				ScreenEvaluationSummary = ThemePrefs.Get("ScreenEvaluationSummaryMenuTimer"),
				ScreenNameEntry         = ThemePrefs.Get("ScreenNameEntryMenuTimer"),
			}
			self.TimeAtSessionStart = nil
			self.SampleMusicLoops = ThemePrefs.Get("SampleMusicLoops")
			self.SampleMusicStartsImmediately = ThemePrefs.Get("SampleMusicStartsImmediately")

			-- Is the music wheel locked? Useful when loading overlay screens
			self.MusicWheelLocked = false
			
			self.GameplayReloadCheck = false
			-- How long to wait before displaying a "cue"
			self.ColumnCueMinTime = 1.5

			-- TODO(teejusb): We should only initialize this once to save on compute.
			self.ECFACloudPlayerOptionKeys = CreateECFACloudPlayerOptionKeys()

			-- used to track active OptionRow index when navigating the Operator Menu's many screens and sub-screens
			-- shaped like: { ScreenOptionsService=3, ScreenVisualOptions=1 }
			self.PrevScreenOptionsServiceRow = {}
		end,

		-- These values outside initialize() won't be reset each game cycle,
		-- but are rather manipulated as needed by the theme.
		ActiveColorIndex = ThemePrefs.Get("SimplyLoveColor") or 1,
	}
}

SL = {
	P1 = setmetatable( {}, PlayerDefaults),
	P2 = setmetatable( {}, PlayerDefaults),
	Global = setmetatable( {}, GlobalDefaults),

	-- Colors that Simply Love's background can be
	-- These colors are used for text on dark backgrounds and backgrounds containing dark text:
	Colors = {
		"#FF5D47",
		"#FF577E",
		"#FF47B3",
		"#DD57FF",
		"#8885ff",
		"#3D94FF",
		"#00B8CC",
		"#5CE087",
		"#AEFA44",
		"#FFFF00",
		"#FFBE00",
		"#FF7D00",
	},
	-- Colors used by ITG for difficulties
	ITGDiffColors = {
		"#a355b8", --beginner
		"#1ec51d", --easy
		"#d6db41", --medium
		"#ba3049",
		"#2691c5",
		"#F7F7F7", --edit
	},
	DDRDiffColors = {
		"#2dccef", --beginner
		"#eaa910", --basic
		"#ff344d", --difficult
		"#30d81e", --expert
		"#e900ff", --challenge
		"#F7F7F7", --edit
	},
	-- These are the original SL colors. They're used for decorative (non-text) elements, like the background hearts:
	DecorativeColors = {
		"#FF3C23",
		"#FF003C",
		"#C1006F",
		"#8200A1",
		"#413AD0",
		"#0073FF",
		"#00ADC0",
		"#5CE087",
		"#AEFA44",
		"#FFFF00",
		"#FFBE00",
		"#FF7D00"
	},
	-- These judgment colors are used for text & numbers on dark backgrounds:
	JudgmentColors = {
		-- Waterfall judgments: Masterful, Awesome, Solid, OK, Fault, Miss
		Waterfall = {
			color("#FF00BE"),	-- fuchsia
			color("#FFFF00"),	-- yellow
			color("#00c800"),	-- green
			color("#0080FF"),	-- blue
			color("#808080"),	-- gray
			color("#ff3030")	-- red (slightly lightened)
		},
		-- ITG and FA+ colors are still used for the simulated ITG/EX judgments
		-- (see SimulateITGJudgment in WF-Scoring.lua).
		Casual = {
			color("#21CCE8"),	-- blue
			color("#e29c18"),	-- gold
			color("#66c955"),	-- green
			color("#b45cff"),	-- purple (greatly lightened)
			color("#c9855e"),	-- peach?
			color("#ff3030")	-- red (slightly lightened)
		},
		ITG = {
			color("#21CCE8"),	-- blue
			color("#e29c18"),	-- gold
			color("#66c955"),	-- green
			color("#b45cff"),	-- purple (greatly lightened)
			color("#c9855e"),	-- peach?
			color("#ff3030")	-- red (slightly lightened)
		},
		["FA+"] = {
			color("#21CCE8"),	-- blue
			color("#ffffff"),	-- white
			color("#e29c18"),	-- gold
			color("#66c955"),	-- green
			color("#b45cff"),	-- purple (greatly lightened)
			color("#ff3030"),	-- red (slightly lightened)
      color("#ff00cc")	-- pink (hard ex)
		},
	},
	-- Engine Preferences applied for each game mode (see SetGameModePreferences()).
	-- Plays are judged with Waterfall timing (as used by ECFA 2021). The ITG and
	-- FA+ tables are never applied: they're kept as reference data for the
	-- simulated ITG/EX scores and timing displays.
	Preferences = {
		Waterfall = {
			TimingWindowAdd=0,
			TimingWindowScale=1,
			RegenComboAfterMiss=5,
			MaxRegenComboAfterMiss=5,
			MinTNSToHideNotes="TapNoteScore_W4",
			MinTNSToScoreNotes="TapNoteScore_None",
			HarshHotLifePenalty=false,

			PercentageScoring=true,
			AllowW1="AllowW1_Everywhere",
			SubSortByNumSteps=true,

			TimingWindowSecondsW1=0.015000,
			TimingWindowSecondsW2=0.030000,
			TimingWindowSecondsW3=0.050000,
			TimingWindowSecondsW4=0.100000,
			TimingWindowSecondsW5=0.160000,
			TimingWindowSecondsHold=0.300000,
			TimingWindowSecondsMine=0.071500,
			TimingWindowSecondsRoll=0.350000,
		},
		ITG = {
			TimingWindowAdd=0.0015,
			RegenComboAfterMiss=5,
			MaxRegenComboAfterMiss=10,
			MinTNSToHideNotes="TapNoteScore_W3",
			MinTNSToScoreNotes=ThemePrefs.Get("RescoreEarlyHits") and "TapNoteScore_W3" or "TapNoteScore_None",
			HarshHotLifePenalty=true,

			PercentageScoring=true,
			AllowW1="AllowW1_Everywhere",
			SubSortByNumSteps=true,

			TimingWindowSecondsW1=0.021500,
			TimingWindowSecondsW2=0.043000,
			TimingWindowSecondsW3=0.102000,
			TimingWindowSecondsW4=0.135000,
			TimingWindowSecondsW5=0.180000,
			TimingWindowSecondsHold=0.320000,
			TimingWindowSecondsMine=0.070000,
			TimingWindowSecondsRoll=0.350000,
		},
		["FA+"] = {
			TimingWindowAdd=0.0015,
			RegenComboAfterMiss=5,
			MaxRegenComboAfterMiss=10,
			MinTNSToHideNotes="TapNoteScore_W4",
			MinTNSToScoreNotes=ThemePrefs.Get("RescoreEarlyHits") and "TapNoteScore_W4" or "TapNoteScore_None",
			HarshHotLifePenalty=true,

			PercentageScoring=true,
			AllowW1="AllowW1_Everywhere",
			SubSortByNumSteps=true,

			TimingWindowSecondsW1=0.013500,
			TimingWindowSecondsW2=0.021500,
			TimingWindowSecondsW3=0.043000,
			TimingWindowSecondsW4=0.102000,
			TimingWindowSecondsW5=0.135000,
			TimingWindowSecondsHold=0.320000,
			-- NOTE(teejusb): FA+ mode previously had mines set to
			-- 65ms instead of the actual window size of 70ms. This
			-- was to account for "SM5 Mines" but now with the patch here:
			-- https://gist.github.com/DinsFire64/4a3f763cd3033afd55a176980b32a3b5
			-- and the development in the thread here:
			-- https://github.com/stepmania/stepmania/issues/1896
			-- it's as good as "fixed" for the very very large majority of
			-- cases so we can set this back to 70ms now.
			TimingWindowSecondsMine=0.070000,
			TimingWindowSecondsRoll=0.350000,
		},
	},
	Metrics = {
		-- The PercentScoreWeightCheckpointHit and
		-- GradeWeightCheckpointHit metrics are only used in pump game
		-- mode. We have to set them to 0 for two reasons:
		-- 1. Due to an inconsistency in the game engine the score for
		--    perfect play adds up to less than 100% when
		--    PercentScoreWeightCheckpointHit is > 0.
		-- 2. It brings the scoring in pump mode closer to PIU scoring,
		--    which does not award points for held checkpoints, but
		--    only penalizes missed checkpoints.

		Waterfall = {
			PercentScoreWeightW1=10,
			PercentScoreWeightW2=9,
			PercentScoreWeightW3=6,
			PercentScoreWeightW4=3,
			PercentScoreWeightW5=0,
			PercentScoreWeightMiss=0,
			PercentScoreWeightLetGo=0,
			PercentScoreWeightHeld=6,
			PercentScoreWeightHitMine=-3,
			PercentScoreWeightCheckpointHit=0,

			GradeWeightW1=10,
			GradeWeightW2=9,
			GradeWeightW3=6,
			GradeWeightW4=3,
			GradeWeightW5=0,
			GradeWeightMiss=0,
			GradeWeightLetGo=0,
			GradeWeightHeld=6,
			GradeWeightHitMine=-3,
			GradeWeightCheckpointHit=0,

			-- The engine's own lifebar never moves: the three Waterfall lifebars
			-- (Scripts/WF-LifeBars.lua) decide whether a player fails.
			LifePercentChangeW1=0,
			LifePercentChangeW2=0,
			LifePercentChangeW3=0,
			LifePercentChangeW4=0,
			LifePercentChangeW5=0,
			LifePercentChangeMiss=0,
			LifePercentChangeLetGo=0,
			LifePercentChangeHeld=0,
			LifePercentChangeHitMine=0,

			InitialValue=0.5,
		},
		Casual = {
			PercentScoreWeightW1=3,
			PercentScoreWeightW2=2,
			PercentScoreWeightW3=1,
			PercentScoreWeightW4=0,
			PercentScoreWeightW5=0,
			PercentScoreWeightMiss=0,
			PercentScoreWeightLetGo=0,
			PercentScoreWeightHeld=3,
			PercentScoreWeightHitMine=-1,
			PercentScoreWeightCheckpointHit=0,

			GradeWeightW1=3,
			GradeWeightW2=2,
			GradeWeightW3=1,
			GradeWeightW4=0,
			GradeWeightW5=0,
			GradeWeightMiss=0,
			GradeWeightLetGo=0,
			GradeWeightHeld=3,
			GradeWeightHitMine=-1,
			GradeWeightCheckpointHit=0,

			LifePercentChangeW1=0,
			LifePercentChangeW2=0,
			LifePercentChangeW3=0,
			LifePercentChangeW4=0,
			LifePercentChangeW5=0,
			LifePercentChangeMiss=0,
			LifePercentChangeLetGo=0,
			LifePercentChangeHeld=0,
			LifePercentChangeHitMine=0,

			InitialValue=0.5,
		},
		ITG = {
			PercentScoreWeightW1=5,
			PercentScoreWeightW2=4,
			PercentScoreWeightW3=2,
			PercentScoreWeightW4=0,
			PercentScoreWeightW5=-6,
			PercentScoreWeightMiss=-12,
			PercentScoreWeightLetGo=0,
			PercentScoreWeightHeld=5,
			PercentScoreWeightHitMine=-6,
			PercentScoreWeightCheckpointHit=0,

			GradeWeightW1=5,
			GradeWeightW2=4,
			GradeWeightW3=2,
			GradeWeightW4=0,
			GradeWeightW5=-6,
			GradeWeightMiss=-12,
			GradeWeightLetGo=0,
			GradeWeightHeld=5,
			GradeWeightHitMine=-6,
			GradeWeightCheckpointHit=0,

			LifePercentChangeW1=0.008,
			LifePercentChangeW2=0.008,
			LifePercentChangeW3=0.004,
			LifePercentChangeW4=0.000,
			LifePercentChangeW5=-0.050,
			LifePercentChangeMiss=-0.100,
			LifePercentChangeLetGo=-0.080,
			LifePercentChangeHeld=0.008,
			LifePercentChangeHitMine=-0.050,

			InitialValue=0.5,
		},
		["FA+"] = {
			PercentScoreWeightW1=5,
			PercentScoreWeightW2=5,
			PercentScoreWeightW3=4,
			PercentScoreWeightW4=2,
			PercentScoreWeightW5=0,
			PercentScoreWeightMiss=-12,
			PercentScoreWeightLetGo=0,
			PercentScoreWeightHeld=5,
			PercentScoreWeightHitMine=-6,
			PercentScoreWeightCheckpointHit=0,

			GradeWeightW1=5,
			GradeWeightW2=5,
			GradeWeightW3=4,
			GradeWeightW4=2,
			GradeWeightW5=0,
			GradeWeightMiss=-12,
			GradeWeightLetGo=0,
			GradeWeightHeld=5,
			GradeWeightHitMine=-6,
			GradeWeightCheckpointHit=0,

			LifePercentChangeW1=0.008,
			LifePercentChangeW2=0.008,
			LifePercentChangeW3=0.008,
			LifePercentChangeW4=0.004,
			LifePercentChangeW5=0,
			LifePercentChangeMiss=-0.1,
			LifePercentChangeLetGo=-0.080,
			LifePercentChangeHeld=0.008,
			LifePercentChangeHitMine=-0.05,

			InitialValue=0.5,
		},
	},
	ExWeights = {
		-- W0 is not necessarily a "real" window.
		-- In ITG mode it is emulated based off the value of TimingWindowW1 defined
		-- for FA+ mode.
		W0=3.5,
		W1=3,
		W2=2,
		W3=1,
		W4=0,
		W5=0,
		Miss=0,
		LetGo=0,
		Held=1,
		HitMine=-1
	},
	HardExWeights = {
		W010=3.5,
		W110=3,
		W2=1,
		W3=0,
		W4=0,
		W5=0,
		Miss=0,
		LetGo=0,
		Held=1,
		HitMine=-1
	},
	-- Fields used to determine whether or not we can connect to the
	-- ECFA Cloud services.
	ECFACloud = {
		-- Whether we're connected to ECFA Cloud or not.
		-- Determined on ScreenTitleMenu in ScreenSystemLayer.
		IsConnected = false,

		-- Available ECFA Cloud services. Subject to change while
		-- StepMania is running.
		GetScores = false,
		Leaderboard = false,
		AutoSubmit = false,

		-- Whether ECFA Cloud events are running (server feature flag). Controls
		-- the event results pane on ScreenEvaluation.
		Events = false,

		-- Version of the chart hash algorithm (see SL-ChartParser.lua).
		-- The server rejects hashes from a different version.
		ChartHashVersion = 3,

		-- We want to cache the some of the requests/responses to prevent making the
		-- same request multiple times in a small timeframe.
		-- Each entry is keyed with some string hash which maps to a table with the
		-- following keys:
		--   Response: string, the JSON-ified response to cache
		--   Timestamp: number, when the request was made
		RequestCache = {},
	},

	-- Latest version available for ITGmania.
	ITGmaniaLatestVersion = nil,
}

-- Casual mode plays with Waterfall timing and scoring too, but with only three
-- judgments (OK and Fault are turned off), so Solid stretches to cover OK's window.
-- It also has a simplified song select and no lifebar.
SL.Preferences.Casual = {}
for key, value in pairs(SL.Preferences.Waterfall) do SL.Preferences.Casual[key] = value end
SL.Preferences.Casual.TimingWindowSecondsW3 = SL.Preferences.Waterfall.TimingWindowSecondsW4
SL.Preferences.Casual.TimingWindowSecondsW5 = SL.Preferences.Waterfall.TimingWindowSecondsW4
SL.JudgmentColors.Casual = SL.JudgmentColors.Waterfall
for key, value in pairs(SL.Metrics.Waterfall) do
	if not key:match("^LifePercentChange") then SL.Metrics.Casual[key] = value end
end

-- The game modes a player can pick. Old ThemePrefs/profiles may still say "ITG"
-- or "FA+", which map to Waterfall.
function ValidGameMode(mode)
	if mode == "Casual" then return "Casual" end
	return "Waterfall"
end



-- Initialize preferences by calling this method.  We typically do
-- this from ./BGAnimations/ScreenTitleMenu underlay/default.lua
-- so that preferences reset between each game cycle.

function InitializeSimplyLove()
	SL.P1:initialize()
	SL.P2:initialize()
	SL.Global:initialize()

end

InitializeSimplyLove()
