-- -----------------------------------------------------------------------
-- EX leaderboards from other services, and the blended board.
--
-- ECFA Cloud fetches each chart's GrooveStats and ArrowCloud EX leaderboards for
-- the theme (player-leaderboards with external=1), so players need no keys or
-- accounts there and cabs only talk to ECFA Cloud. Nothing is ever submitted to
-- GrooveStats or ArrowCloud.
--
-- The blended board puts ECFA Cloud's EX scores and those two in one list, best
-- first, each row tagged with where it came from. Every leaderboard the theme
-- shows is either EX or Waterfall (WF), and says which.

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

-- A leaderboard from ECFA Cloud's response (all of them share one shape), as
--   { score=<hundredths of a percent>, name, date, isSelf, isRival, isFail }.
-- nil when the service wasn't available.
LeaderboardEntries = function(board)
	if type(board) ~= "table" then return nil end
	local entries = {}
	for e in ivalues(board) do
		if tonumber(e["score"]) then
			entries[#entries+1] = {
				score=tonumber(e["score"]), name=tostring(e["name"] or ""), date=e["date"], rank=tonumber(e["rank"]),
				isSelf=e["isSelf"] and true or false, isRival=e["isRival"] and true or false, isFail=e["isFail"] and true or false,
			}
		end
	end
	return entries
end

-- The three EX sources from one player's ECFA Cloud response:
-- { ECFA=entries, GS=entries or nil, AC=entries or nil }
ExSourcesFromResponse = function(playerData)
	return {
		ECFA = LeaderboardEntries(playerData and playerData["exLeaderboard"]) or {},
		GS = LeaderboardEntries(playerData and playerData["gsExLeaderboard"]),
		AC = LeaderboardEntries(playerData and playerData["acExLeaderboard"]),
	}
end

-- A name's words, lowercased: "Chance R." is { "chance", "r" }.
local NameWords = function(name)
	local words = {}
	for word in tostring(name or ""):lower():gmatch("%w+") do words[#words+1] = word end
	return words
end

-- Whether two services' names are probably the same player: the same once case,
-- spaces and punctuation are ignored ("Eternal Polaris" and "EternalPolaris"), or
-- one is the other plus a last initial ("Chance R." and "Chance").
SamePlayerName = function(a, b)
	a, b = tostring(a or ""), tostring(b or "")
	if a ~= "" and a:lower() == b:lower() then return true end
	local wa, wb = NameWords(a), NameWords(b)
	local ja, jb = table.concat(wa), table.concat(wb)
	if ja == "" or jb == "" then return false end
	if ja == jb then return true end
	if #wa > #wb then wa, wb, ja, jb = wb, wa, jb, ja end
	return #wb == #wa + 1 and #wb[#wb] == 1 and #ja >= 3 and table.concat(wb, "", 1, #wa) == ja
end

-- Merges the sources into one list, best EX first, each entry tagged with its
-- source. A player appears at most once per service, and a score that another
-- service already listed for the same player (see SamePlayerName; the dates may
-- differ, since services record them differently) is listed once, under the
-- first source in BlendedSources. When none of the player's own scores make the
-- cut, their best takes the last row (without a rank, since their place in the
-- combined list isn't known).
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

	-- listed[score] = the entries kept with that score, to spot the same score from another service
	local rows, seen, listed, ownBest = {}, {}, {}, nil
	local AlreadyListed = function(e)
		for kept in ivalues(listed[e.score] or {}) do
			if kept.source ~= e.source and SamePlayerName(kept.name, e.name) then return true end
		end
		return false
	end
	for e in ivalues(all) do
		local id = e.source.."\n"..e.name
		if not seen[id] and not AlreadyListed(e) then
			seen[id] = true
			listed[e.score] = listed[e.score] or {}
			table.insert(listed[e.score], e)
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
