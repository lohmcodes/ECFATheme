-- -----------------------------------------------------------------------
-- ECFA Cloud offline queue.
--
-- When a score can't be submitted (the machine is offline, ECFA Cloud is
-- unreachable, or the request fails), it is saved to the player's profile in
-- ECFACloudPending.jsonl (one JSON object per line, at most
-- ECFA_PENDING_MAX entries) and submitted later, after the next successful
-- submission. Queued plays carry how long ago they were played, so ECFA Cloud
-- records them with their real play time.

ECFA_PENDING_MAX = 50

local PendingPath = function(player)
	local slot = (player == PLAYER_1) and "ProfileSlot_Player1" or "ProfileSlot_Player2"
	local dir = PROFILEMAN:GetProfileDir(slot)
	if not dir or dir == "" then return nil end
	return dir .. "ECFACloudPending.jsonl"
end

local ReadLines = function(player)
	local path = PendingPath(player)
	if not path or not FILEMAN:DoesFileExist(path) then return {} end
	local f = RageFileUtil.CreateRageFile()
	local content = nil
	if f:Open(path, 1) then content = f:Read() end
	f:destroy()
	local lines = {}
	for line in (content or ""):gmatch("[^\n]+") do
		if line:match("%S") then lines[#lines+1] = line end
	end
	return lines
end

local WriteLines = function(player, lines)
	local path = PendingPath(player)
	if not path then return false end
	local f = RageFileUtil.CreateRageFile()
	local ok = f:Open(path, 2)
	if ok then f:Write(table.concat(lines, "\n") .. (#lines > 0 and "\n" or "")) end
	f:destroy()
	return ok
end

-- Seconds since 1970 by the machine's local clock (ITGmania's Lua has no
-- os.time). Only differences between two of these are ever used, so the
-- missing timezone doesn't matter.
local LocalEpochSeconds = function()
	-- Days from civil date (Howard Hinnant's algorithm).
	local y, m, d = Year(), MonthOfYear() + 1, DayOfMonth()
	if m <= 2 then y = y - 1 end
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = math.floor((153 * mp + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	local days = era * 146097 + doe - 719468
	return days * 86400 + Hour() * 3600 + Minute() * 60 + Second()
end

ECFACloudPendingCount = function(player)
	return #ReadLines(player)
end

-- Queues one player's submission (the table normally sent as "player1"/"player2").
-- Returns true, "full", or false.
ECFACloudSavePending = function(player, chartHash, submission)
	if not (player and chartHash and chartHash ~= "" and submission) then return false end
	local lines = ReadLines(player)
	if #lines >= ECFA_PENDING_MAX then return "full" end
	lines[#lines+1] = JsonEncode({ chartHash=chartHash, savedAt=LocalEpochSeconds(), submission=submission })
	return WriteLines(player, lines) and true or false
end

-- Submits queued plays for one player, oldest first, one request at a time.
-- Stops at the first network failure (they'll be retried next time). Plays the
-- server rejects as invalid are dropped so they can't block the queue.
-- onDone(remainingCount) is called when finished.
ECFACloudRetryPending = function(player, apiKey, onDone)
	local done = function() if onDone then onDone(ECFACloudPendingCount(player)) end end
	if not apiKey or apiKey == "" then return done() end

	local function step()
		local lines = ReadLines(player)
		if #lines == 0 then return done() end

		local entry = JsonDecode(lines[1])
		local dropFirst = function()
			local current = ReadLines(player)
			if current[1] == lines[1] then table.remove(current, 1); WriteLines(player, current) end
		end
		if type(entry) ~= "table" or not entry.chartHash or type(entry.submission) ~= "table" then
			dropFirst()
			return step()
		end

		local submission = entry.submission
		submission.playedSecondsAgo = math.max(0, LocalEpochSeconds() - (tonumber(entry.savedAt) or LocalEpochSeconds()))

		NETWORK:HttpRequest{
			url=GetECFACloudURL().."/api/v1/score-submit?chartHashP1="..entry.chartHash,
			method="POST",
			body=JsonEncode({ player1=submission }),
			headers={ ["x-api-key-player-1"]=apiKey, ["Content-Type"]="application/json" },
			connectTimeout=10,
			transferTimeout=20,
			onResponse=function(response)
				local code = response.statusCode or 0
				if response.error or code == 0 or code == 429 or code >= 500 then
					-- Still offline or ECFA Cloud is having trouble: try again next time.
					return done()
				end
				if code ~= 200 then
					-- Rejected outright; drop it so it can't block the queue.
					dropFirst()
					return step()
				end
				local data = JsonDecode(response.body)
				local result = data and data.player1
				if result and result.error == "invalid-api-key" then return done() end
				-- Recorded, or permanently invalid: either way it leaves the queue.
				dropFirst()
				step()
			end,
		}
	end
	step()
end
