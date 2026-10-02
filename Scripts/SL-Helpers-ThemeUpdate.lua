-- -----------------------------------------------------------------------
-- Theme updates from GitHub.
--
-- Every push to master publishes version.json and manifest.json (every file's
-- SHA-256) on the repository's update-manifest branch
-- (.github/workflows/update-manifest.yml). At startup the theme reads
-- version.json, and the title menu offers "Update Theme" when that commit isn't
-- the one installed. ScreenECFAThemeUpdate then hashes the local files, downloads
-- only the ones that differ (each checked against the manifest) into
-- Save/ECFAThemeUpdate/, copies them into the theme once every download has
-- succeeded, and reloads the theme.
--
-- ITGmania can't delete files from Lua, so files removed from the theme stay
-- behind. Removed Scripts/ and Modules/ files, which would otherwise still run,
-- are emptied instead.
--
-- Needs raw.githubusercontent.com in HttpAllowHosts (e.g. *.githubusercontent.com).

local Repo = "lohmcodes/ECFATheme"
local RawURL = "https://raw.githubusercontent.com/"..Repo.."/"
local ManifestBranch = "update-manifest"

ThemeUpdateVersionURL = RawURL..ManifestBranch.."/version.json"
ThemeUpdateManifestURL = RawURL..ManifestBranch.."/manifest.json"
-- Downloads wait here until all of them have arrived.
ThemeUpdateStagingDir = "/Save/ECFAThemeUpdate/"

-- What the updater remembers about the installed theme (both left out of git).
local InstalledVersionFile = "Other/installed-version.txt"
local InstalledManifestFile = "Other/installed-manifest.json"

ThemeUpdate = {
	-- The newest version on GitHub ({commit, date, message}), once checked.
	Latest = nil,
	-- Whether Latest isn't the installed version.
	Available = false,
	Checking = false,
	Checked = false,
}

-- -----------------------------------------------------------------------
-- Files

local ReadTextFile = function(path)
	if not FILEMAN:DoesFileExist(path) then return nil end
	local f = RageFileUtil.CreateRageFile()
	local text = nil
	if f:Open(path, 1) then
		text = f:Read()
		f:Close()
	end
	f:destroy()
	return text
end

-- Returns true if the file was written.
local WriteTextFile = function(path, text)
	local f = RageFileUtil.CreateRageFile()
	local ok = f:Open(path, 2)
	if ok then
		f:Write(text)
		f:Close()
	end
	f:destroy()
	return ok and true or false
end

-- A manifest path we're willing to write: relative, inside the theme, no dot folders.
IsSafeThemePath = function(path)
	if type(path) ~= "string" or path == "" or #path > 400 then return false end
	if path:find("[%c\\:]") or path:sub(1, 1) == "/" or path:sub(-1) == "/" or path:find("//", 1, true) then return false end
	for part in path:gmatch("[^/]+") do
		if part:sub(1, 1) == "." then return false end
	end
	return true
end

-- Percent-encodes a path for a URL, keeping its slashes.
EncodeThemePath = function(path)
	return (path:gsub("[^%w%-%._~/]", function(c) return string.format("%%%02X", c:byte()) end))
end

ThemeFileURL = function(commit, path)
	return RawURL..commit.."/"..EncodeThemePath(path)
end

-- Reads manifest.json. Returns the manifest, or nil and why it was refused.
ParseThemeManifest = function(body)
	local ok, manifest = pcall(JsonDecode, body or "")
	if not ok or type(manifest) ~= "table" or type(manifest.commit) ~= "string"
			or not manifest.commit:match("^%x+$") or type(manifest.files) ~= "table" then
		return nil, "Couldn't read the list of theme files."
	end
	local count = 0
	for path, entry in pairs(manifest.files) do
		if not IsSafeThemePath(path) or type(entry) ~= "table" or type(entry.sha256) ~= "string"
				or #entry.sha256 ~= 64 or not entry.sha256:match("^%x+$") then
			return nil, "The list of theme files has a bad entry: "..tostring(path)
		end
		count = count + 1
	end
	if count == 0 then return nil, "The list of theme files is empty." end
	manifest.count = count
	return manifest
end

-- The installed file's SHA-256 (lowercase hex), or nil if it doesn't exist.
LocalThemeFileHash = function(path)
	local full = THEME:GetCurrentThemeDirectory()..path
	if not FILEMAN:DoesFileExist(full) then return nil end
	return BinaryToHex(CRYPTMAN:SHA256File(full)):lower()
end

-- Paths the previously installed version had that the new one doesn't.
RemovedThemeFiles = function(manifest, previous)
	local removed = {}
	if not previous or type(previous.files) ~= "table" then return removed end
	for path in pairs(previous.files) do
		if manifest.files[path] == nil and IsSafeThemePath(path) then
			removed[#removed+1] = path
		end
	end
	table.sort(removed)
	return removed
end

-- What a removed file is replaced with, for the ones that would otherwise keep
-- running (every Scripts/ and Modules/ file is loaded). nil leaves the file as is.
RemovedThemeFileStub = function(path, commit)
	if (path:match("^Scripts/") or path:match("^Modules/")) and path:lower():match("%.lua$") then
		return "-- Removed from the theme in "..commit:sub(1, 7)..". ITGmania can't delete files, so it's emptied instead.\n"
	end
	return nil
end

-- -----------------------------------------------------------------------
-- Installed version

-- The commits the installed theme could be: the one the updater last installed,
-- and the git checkout's (for a theme folder cloned with git).
InstalledThemeCommits = function()
	local dir = THEME:GetCurrentThemeDirectory()
	local commits = {}
	local recorded = ReadTextFile(dir..InstalledVersionFile)
	commits[#commits+1] = recorded and recorded:match("^%s*(%x+)")

	local head = ReadTextFile(dir..".git/HEAD")
	if head then
		local ref = head:match("^ref:%s*(%S+)")
		if not ref then
			commits[#commits+1] = head:match("^%s*(%x+)")
		else
			local sha = ReadTextFile(dir..".git/"..ref)
			sha = sha and sha:match("^%s*(%x+)")
			if not sha then
				for line in (ReadTextFile(dir..".git/packed-refs") or ""):gmatch("[^\r\n]+") do
					local s, r = line:match("^(%x+)%s+(%S+)$")
					if r == ref then sha = s end
				end
			end
			commits[#commits+1] = sha
		end
	end
	return commits
end

IsThemeCommitInstalled = function(commit)
	for installed in ivalues(InstalledThemeCommits()) do
		if installed:lower() == commit:lower() then return true end
	end
	return false
end

ShortInstalledThemeCommit = function()
	local commits = InstalledThemeCommits()
	return commits[1] and commits[1]:sub(1, 7) or nil
end

ReadInstalledThemeManifest = function()
	local text = ReadTextFile(THEME:GetCurrentThemeDirectory()..InstalledManifestFile)
	if not text then return nil end
	local ok, manifest = pcall(JsonDecode, text)
	return (ok and type(manifest) == "table" and type(manifest.files) == "table") and manifest or nil
end

-- Remembers what's now installed. Returns false if the theme folder can't be written.
RecordInstalledTheme = function(manifest)
	local dir = THEME:GetCurrentThemeDirectory()
	local files = {}
	for path, entry in pairs(manifest.files) do
		files[path] = { sha256=entry.sha256 }
	end
	return WriteTextFile(dir..InstalledVersionFile, manifest.commit.."\n")
		and WriteTextFile(dir..InstalledManifestFile, JsonEncode({ commit=manifest.commit, files=files }))
end

-- Whether the theme folder can be written, checked before downloading anything.
CanWriteThemeFolder = function()
	local path = THEME:GetCurrentThemeDirectory()..InstalledVersionFile
	return WriteTextFile(path, ReadTextFile(path) or "")
end

-- -----------------------------------------------------------------------
-- Startup check

-- Looks up the newest version once per session. done(available) is called when
-- the answer comes back.
CheckForThemeUpdate = function(done)
	if ThemeUpdate.Checking or ThemeUpdate.Checked then return end
	if not NETWORK:IsUrlAllowed(ThemeUpdateVersionURL) then
		ThemeUpdate.Checked = true
		return
	end
	ThemeUpdate.Checking = true
	NETWORK:HttpRequest{
		url=ThemeUpdateVersionURL,
		method="GET",
		connectTimeout=10,
		transferTimeout=10,
		onResponse=function(res)
			ThemeUpdate.Checking = false
			ThemeUpdate.Checked = true
			if res.error or res.statusCode ~= 200 then return end
			local ok, latest = pcall(JsonDecode, res.body)
			if not ok or type(latest) ~= "table" or type(latest.commit) ~= "string" or not latest.commit:match("^%x+$") then return end
			ThemeUpdate.Latest = latest
			ThemeUpdate.Available = not IsThemeCommitInstalled(latest.commit)
			if done then done(ThemeUpdate.Available) end
		end,
	}
end

-- ScreenTitleMenu's ChoiceNames: "Update Theme" sits above Exit when there's an update.
ThemeUpdateChoiceNames = function()
	return ThemeUpdate.Available and "1,2,3,Update,4" or "1,2,3,4"
end
