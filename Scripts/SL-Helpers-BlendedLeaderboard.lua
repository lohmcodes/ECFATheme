-- -----------------------------------------------------------------------
-- Blended leaderboard: a chart's ECFA Cloud EX scores in one list with its EX
-- scores on GrooveStats and ArrowCloud, each row marked with where it came from.
-- EX is the one score all three services keep.
--
-- GrooveStats and ArrowCloud are only ever read from: one GET request per chart
-- for its leaderboard. This theme never submits anything to either of them.
--
-- ArrowCloud's leaderboards are public, so every player gets them. With the
-- player's own key the theme asks ArrowCloud's API instead, which also marks
-- their own scores. GrooveStats only answers with a player's key. Keys are read
-- (never written) from the profile folder:
--
--   <profile dir>/GrooveStats.ini    [GrooveStats] ApiKey=<64 characters>
--   <profile dir>/ArrowCloud.ini     [ArrowCloud]  ApiKey=<key>   (optional)
--
-- Both hosts must also be listed in HttpAllowHosts in Save/Preferences.ini.

local GrooveStatsLeaderboardURL = "https://api.groovestats.com/player-leaderboards.php"
-- With a key: the API for themes. Without: the public one ArrowCloud's website uses (same reply).
local ArrowCloudChartURL = "https://api.arrowcloud.dance/v1/chart/"
local ArrowCloudPublicChartURL = "https://api.arrowcloud.dance/chart/"
local RequestTimeout = 10

-- The sources in display order (ties sort ECFA Cloud first), with the short tag
-- and color used to mark their rows.
BlendedSources = {
	{ key="ECFA", label="EC", name="ECFA Cloud", color=color("#e2579e") },
	{ key="GS",   label="GS", name="GrooveStats", color=color("#f2a33a") },
	{ key="AC",   label="AC", name="ArrowCloud", color=color("#56b4ef") },
}
BlendedSource = {}
for i, source in ipairs(BlendedSources) do
	source.order = i
	BlendedSource[source.key] = source
end

-- -----------------------------------------------------------------------
-- API keys

local ReadProfileApiKey = function(player, file, section)
	local slot = (player == PLAYER_1) and "ProfileSlot_Player1" or "ProfileSlot_Player2"
	local dir = PROFILEMAN:GetProfileDir(slot)
	if not dir or #dir == 0 or not FILEMAN:DoesFileExist(dir..file) then return "" end

	local contents = IniFile.ReadFile(dir..file)
	local key = contents and contents[section] and contents[section]["ApiKey"]
	return key and tostring(key) or ""
end

-- Loads the player's GrooveStats and ArrowCloud keys. Read only: the files are
-- never created or changed here.
ParseBlendedLeaderboardKeys = function(player)
	if not player then return end
	local pn = ToEnumShortString(player)

	local gs = ReadProfileApiKey(player, "GrooveStats.ini", "GrooveStats")
	SL[pn].GrooveStatsApiKey = (#gs == 64) and gs or ""
	SL[pn].ArrowCloudApiKey = ReadProfileApiKey(player, "ArrowCloud.ini", "ArrowCloud")
end

-- Whether there's anything to blend in besides ECFA Cloud. Always, since
-- ArrowCloud's leaderboards are public; kept as one place to switch sources off.
HasBlendedLeaderboardSources = function(player)
	return true
end

-- -----------------------------------------------------------------------
-- Leaderboard entries from each service, all as
--   { score=<EX in hundredths of a percent>, name, date, isSelf, isRival, isFail }

-- ECFA Cloud's exLeaderboard (same shape as its other boards).
BlendedEntriesFromECFACloud = function(board)
	local entries = {}
	for e in ivalues(board or {}) do
		if tonumber(e["score"]) then
			entries[#entries+1] = {
				score=tonumber(e["score"]), name=tostring(e["name"] or ""), date=e["date"],
				isSelf=e["isSelf"] and true or false, isRival=e["isRival"] and true or false, isFail=e["isFail"] and true or false,
			}
		end
	end
	return entries
end

local ResponseError = function(res)
	if res.error then
		return ToEnumShortString(res.error) == "Timeout" and "Timed Out" or "Failed to Load"
	end
	if res.statusCode == 401 or res.statusCode == 403 then return "Invalid API key" end
	if res.statusCode ~= 200 then return "Failed to Load" end
	return nil
end

-- GrooveStats answers for the key it was sent as player 1.
local ParseGrooveStats = function(res)
	local err = ResponseError(res)
	if err then return nil, err end
	local ok, data = pcall(JsonDecode, res.body)
	if not ok or type(data) ~= "table" or type(data["player1"]) ~= "table" then return nil, "Failed to Load" end
	-- A chart GrooveStats doesn't know has no leaderboards, which just means no scores.
	return BlendedEntriesFromECFACloud(data["player1"]["exLeaderboard"])
end

-- ArrowCloud returns several boards (ITG, EX, HardEX) with scores formatted as text,
-- from either of its URLs.
local ParseArrowCloud = function(res)
	local err = ResponseError(res)
	if err then return nil, err end
	local ok, data = pcall(JsonDecode, res.body)
	if not ok or type(data) ~= "table" or type(data["leaderboards"]) ~= "table" then return nil, "Failed to Load" end

	local entries = {}
	for board in ivalues(data["leaderboards"]) do
		if board["type"] == "EX" then
			for e in ivalues(board["scores"] or {}) do
				local pct = tonumber((tostring(e["score"] or ""):gsub("%%", "")))
				if pct then
					entries[#entries+1] = {
						score=math.floor(pct * 100 + 0.5),
						name=tostring(e["alias"] or e["userAlias"] or "--"),
						date=e["date"],
						isSelf=e["isSelf"] and true or false, isRival=e["isRival"] and true or false, isFail=false,
					}
				end
			end
		end
	end
	return entries
end

-- -----------------------------------------------------------------------
-- Fetches the chart's GrooveStats and ArrowCloud EX leaderboards for one player,
-- then calls done(results) once both are back. results.GS and results.AC are
-- { entries={...} } or { error="..." }; GrooveStats is left out for a player
-- without a key. Results are kept for a minute (RemoveStaleCachedRequests), so
-- moving back to a chart, or from the song wheel into gameplay, doesn't ask again.
--
-- Returns a handle whose Cancel() stops the requests and the callback.
FetchBlendedSources = function(player, hash, maxResults, done)
	local pn = ToEnumShortString(player)
	local gsKey = SL[pn].GrooveStatsApiKey or ""
	local acKey = SL[pn].ArrowCloudApiKey or ""
	local handle = { cancelled=false, requests={} }
	handle.Cancel = function(self)
		self.cancelled = true
		for request in ivalues(self.requests) do request:Cancel() end
		self.requests = {}
	end

	local results = {}
	if not hash or hash == "" then
		done(results)
		return handle
	end

	local cacheKey = CRYPTMAN:SHA256String(hash..gsKey..acKey..maxResults.."-blended-leaderboards")
	local cached = SL.ECFACloud.RequestCache[cacheKey]
	if cached and cached.Results then
		done(cached.Results)
		return handle
	end

	local waiting = 0
	local finish = function()
		waiting = waiting - 1
		if waiting > 0 or handle.cancelled then return end
		handle.requests = {}
		-- Only remember complete answers, so a failed service is asked again next time.
		if not (results.GS and results.GS.error) and not (results.AC and results.AC.error) then
			SL.ECFACloud.RequestCache[cacheKey] = { Results=results, Timestamp=GetTimeSinceStart() }
		end
		done(results)
	end
	local store = function(key, entries, err)
		results[key] = entries and { entries=entries } or { error=err or "Failed to Load" }
	end

	if gsKey ~= "" then waiting = waiting + 1 end
	waiting = waiting + 1  -- ArrowCloud, with or without a key

	if gsKey ~= "" then
		handle.requests[#handle.requests+1] = NETWORK:HttpRequest{
			url=GrooveStatsLeaderboardURL.."?"..NETWORK:EncodeQueryParameters({ chartHashP1=hash, maxLeaderboardResults=maxResults }),
			method="GET",
			headers={ ["x-api-key-player-1"]=gsKey },
			connectTimeout=RequestTimeout,
			transferTimeout=RequestTimeout,
			onResponse=function(res)
				store("GS", ParseGrooveStats(res))
				finish()
			end,
		}
	end
	handle.requests[#handle.requests+1] = NETWORK:HttpRequest{
		url=(acKey ~= "") and (ArrowCloudChartURL..hash.."/leaderboards?limit="..maxResults) or (ArrowCloudPublicChartURL..hash.."/leaderboards"),
		method="GET",
		headers=(acKey ~= "") and { ["Authorization"]="Bearer "..acKey } or {},
		connectTimeout=RequestTimeout,
		transferTimeout=RequestTimeout,
		onResponse=function(res)
			store("AC", ParseArrowCloud(res))
			finish()
		end,
	}
	return handle
end

-- -----------------------------------------------------------------------
-- Merges the sources into one list, best EX first, each entry tagged with its
-- source. A player can appear once per service. When none of the player's own
-- scores make the cut, their best takes the last row (without a rank, since
-- their place in the combined list isn't known).
--
-- lists: { ECFA={entries}, GS={entries}, AC={entries} } (any may be missing)
BlendLeaderboards = function(lists, maxRows)
	local all = {}
	for source in ivalues(BlendedSources) do
		for e in ivalues(lists[source.key] or {}) do
			all[#all+1] = {
				source=source.key, score=e.score, name=e.name, date=e.date,
				isSelf=e.isSelf, isRival=e.isRival, isFail=e.isFail,
			}
		end
	end
	table.sort(all, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		return BlendedSource[a.source].order < BlendedSource[b.source].order
	end)

	local rows, seen, ownBest = {}, {}, nil
	for e in ivalues(all) do
		local id = e.source.."\n"..e.name
		if not seen[id] then
			seen[id] = true
			if #rows < maxRows then
				e.rank = #rows + 1
				rows[#rows+1] = e
			elseif e.isSelf and not ownBest then
				ownBest = e
			end
		end
	end
	if ownBest then
		for e in ivalues(rows) do
			if e.isSelf then return rows end
		end
		ownBest.rank = nil
		rows[#rows] = ownBest
	end
	return rows
end

-- "Mon D, YYYY" from any date starting with YYYY-MM-DD, or "".
FormatBlendedDate = function(date)
	local year, month, day = tostring(date or ""):match("^(%d%d%d%d)-(%d%d)-(%d%d)")
	if not year then return "" end
	local months = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
	return (months[tonumber(month)] or "").." "..tonumber(day)..", "..year
end
