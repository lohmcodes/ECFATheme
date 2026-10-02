-- Updates the theme from GitHub (see Scripts/SL-Helpers-ThemeUpdate.lua): reads
-- the latest manifest, hashes the local files, downloads the ones that differ into
-- Save/ECFAThemeUpdate/, and once every download has checked out, copies them into
-- the theme and reloads it. Back cancels until the copying starts.

local Concurrent = 3      -- downloads at a time
local HashesPerFrame = 25 -- local files hashed per frame, so the screen keeps moving
local Retries = 2         -- extra tries per file

local s = function(key) return THEME:GetString("ScreenECFAThemeUpdate", key) end

-- phase: fetch, scan, download, apply, reload, restart, uptodate, failed, cancelled
local state = {
	phase="fetch", manifest=nil, previous=nil,
	paths={}, scanned=0, todo={}, removed={},
	nextDownload=1, retry={}, active=0, finished=0, attempts={}, requests={},
	detail="",
}
local master = nil

local CancelDownloads = function()
	for _, request in pairs(state.requests) do request:Cancel() end
	state.requests = {}
end

local Fail = function(text)
	CancelDownloads()
	state.phase = "failed"
	state.detail = text
	if master then master:playcommand("Refresh") end
end

local InputHandler = function(event)
	if not event.PlayerNumber or not event.button then return false end
	if event.type ~= "InputEventType_FirstPress" then return false end

	local finished = state.phase == "failed" or state.phase == "uptodate" or state.phase == "restart"
	local busy = state.phase == "apply" or state.phase == "reload"
	if not busy and (event.GameButton == "Back" or (finished and event.GameButton == "Start")) then
		CancelDownloads()
		state.phase = "cancelled"
		SCREENMAN:GetTopScreen():Cancel()
	end
	return false
end

local StartDownload = function(i)
	local path = state.todo[i]
	local name = "ecfa-theme-update-"..i..".part"
	state.active = state.active + 1
	state.detail = path
	state.requests[i] = NETWORK:HttpRequest{
		url=ThemeFileURL(state.manifest.commit, path),
		method="GET",
		downloadFile=name,
		connectTimeout=15,
		transferTimeout=300,
		onResponse=function(res)
			state.requests[i] = nil
			state.active = state.active - 1
			if state.phase ~= "download" then return end

			-- The download only lives in /Downloads/ until this callback returns.
			local file = "/Downloads/"..name
			local ok = not res.error and res.statusCode == 200
				and FILEMAN:DoesFileExist(file)
				and BinaryToHex(CRYPTMAN:SHA256File(file)):lower() == state.manifest.files[path].sha256:lower()
				and FILEMAN:Copy(file, ThemeUpdateStagingDir..path)
			if ok then
				state.finished = state.finished + 1
			else
				state.attempts[path] = (state.attempts[path] or 0) + 1
				if state.attempts[path] > Retries then
					local why = res.error and (res.errorMessage or ToEnumShortString(res.error))
						or (res.statusCode ~= 200 and ("HTTP "..tostring(res.statusCode)))
						or "the file didn't match"
					Fail(s("DownloadFailed"):format(path, why))
					return
				end
				state.retry[#state.retry+1] = i
			end
			master:queuecommand("Download")
		end,
	}
end

local af = Def.ActorFrame{
	InitCommand=function(self)
		master = self
		self:xy(_screen.cx, _screen.cy - 20)
	end,
	OnCommand=function(self)
		SCREENMAN:GetTopScreen():AddInputCallback(InputHandler)
		if not NETWORK:IsUrlAllowed(ThemeUpdateManifestURL) then
			Fail(s("Blocked"))
			return
		end
		self:playcommand("Refresh")
		self:queuecommand("Fetch")
	end,
	OffCommand=function(self)
		if state.phase ~= "reload" then CancelDownloads() end
	end,

	FetchCommand=function(self)
		state.requests.manifest = NETWORK:HttpRequest{
			url=ThemeUpdateManifestURL,
			method="GET",
			connectTimeout=15,
			transferTimeout=60,
			onResponse=function(res)
				state.requests.manifest = nil
				if state.phase ~= "fetch" then return end
				if res.error or res.statusCode ~= 200 then
					Fail(s("ManifestFailed"):format(res.errorMessage or ("HTTP "..tostring(res.statusCode))))
					return
				end
				local manifest, err = ParseThemeManifest(res.body)
				if not manifest then
					Fail(err)
					return
				end
				state.manifest = manifest
				state.previous = ReadInstalledThemeManifest()
				for path in pairs(manifest.files) do state.paths[#state.paths+1] = path end
				table.sort(state.paths)
				state.phase = "scan"
				self:queuecommand("Scan")
			end,
		}
	end,

	-- Compares the installed files with the manifest, a few per frame.
	ScanCommand=function(self)
		if state.phase ~= "scan" then return end
		local last = math.min(state.scanned + HashesPerFrame, #state.paths)
		for i = state.scanned + 1, last do
			local path = state.paths[i]
			if LocalThemeFileHash(path) ~= state.manifest.files[path].sha256:lower() then
				state.todo[#state.todo+1] = path
			end
		end
		state.scanned = last
		self:playcommand("Refresh")
		if state.scanned < #state.paths then
			self:queuecommand("Scan")
			return
		end

		for path in ivalues(RemovedThemeFiles(state.manifest, state.previous)) do
			if RemovedThemeFileStub(path, state.manifest.commit) then state.removed[#state.removed+1] = path end
		end
		if #state.todo == 0 and #state.removed == 0 then
			RecordInstalledTheme(state.manifest)
			ThemeUpdate.Available = false
			state.phase = "uptodate"
			self:playcommand("Refresh")
			return
		end
		if not CanWriteThemeFolder() then
			Fail(s("ReadOnly"))
			return
		end
		state.phase = "download"
		self:queuecommand("Download")
	end,

	-- Keeps up to Concurrent downloads going; each finished one queues this again.
	DownloadCommand=function(self)
		if state.phase ~= "download" then return end
		while state.active < Concurrent do
			local i = table.remove(state.retry, 1)
			if not i and state.nextDownload <= #state.todo then
				i = state.nextDownload
				state.nextDownload = state.nextDownload + 1
			end
			if not i then break end
			StartDownload(i)
		end
		self:playcommand("Refresh")
		if state.finished == #state.todo and state.active == 0 then
			state.phase = "apply"
			self:queuecommand("Apply")
		end
	end,

	-- Every file is in Save/ECFAThemeUpdate/: copy them into the theme.
	ApplyCommand=function(self)
		self:playcommand("Refresh")
		local dir = THEME:GetCurrentThemeDirectory()
		for path in ivalues(state.todo) do
			if not FILEMAN:Copy(ThemeUpdateStagingDir..path, dir..path) then
				-- Files copied so far stay; updating again picks up the rest.
				Fail(s("CopyFailed"):format(path))
				return
			end
		end
		for path in ivalues(state.removed) do
			local f = RageFileUtil.CreateRageFile()
			if f:Open(dir..path, 2) then
				f:Write(RemovedThemeFileStub(path, state.manifest.commit))
				f:Close()
			end
			f:destroy()
		end
		RecordInstalledTheme(state.manifest)
		ThemeUpdate.Available = false
		state.phase = "reload"
		self:playcommand("Refresh")
		self:sleep(1.5):queuecommand("Reload")
	end,

	-- Switching to the current theme reloads all of it, scripts included. If this
	-- screen is somehow still here a few seconds later, ask for a restart.
	ReloadCommand=function(self)
		THEME:SetTheme(THEME:GetCurThemeName())
		self:sleep(4):queuecommand("ReloadFallback")
	end,
	ReloadFallbackCommand=function(self)
		state.detail = s("RestartNeeded")
		state.phase = "restart"
		self:playcommand("Refresh")
	end,
}

-- Title
af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Bold")..{
	Text=s("Title"),
	InitCommand=function(self) self:y(-90):zoom(1.1) end,
}

-- Installed and latest versions, with the latest commit's message.
af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
	InitCommand=function(self) self:y(-55):zoom(0.8):diffuse(color("#bbbbbb")):maxwidth(_screen.w * 0.8 / 0.8) end,
	RefreshCommand=function(self)
		local latest = (state.manifest and state.manifest.commit) or (ThemeUpdate.Latest and ThemeUpdate.Latest.commit)
		self:settext(s("Versions"):format(ShortInstalledThemeCommit() or s("Unknown"), latest and latest:sub(1, 7) or "..."))
	end,
}
af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
	InitCommand=function(self) self:y(-33):zoom(0.75):diffuse(color("#888888")):maxwidth(_screen.w * 0.8 / 0.75) end,
	RefreshCommand=function(self)
		local message = (state.manifest and state.manifest.message) or (ThemeUpdate.Latest and ThemeUpdate.Latest.message) or ""
		self:settext(message ~= "" and ('"'..message..'"') or "")
	end,
}

-- What's happening now.
af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
	InitCommand=function(self) self:y(5) end,
	RefreshCommand=function(self)
		local text = ({
			fetch=s("Fetching"),
			scan=s("Comparing"):format(state.scanned, #state.paths),
			download=s("Downloading"):format(state.finished, #state.todo),
			apply=s("Installing"),
			reload=s("Reloading"):format(#state.todo),
			restart=s("Updated"):format(#state.todo),
			uptodate=s("UpToDate"),
			failed=s("Failed"),
		})[state.phase] or ""
		self:settext(text):diffuse(state.phase == "failed" and color("#ff6b6b") or Color.White)
	end,
}

-- Progress bar
local barWidth = 420
af[#af+1] = Def.Quad{
	InitCommand=function(self) self:y(35):zoomto(barWidth, 10):diffuse(color("#333333")) end,
}
af[#af+1] = Def.Quad{
	InitCommand=function(self) self:xy(-barWidth/2, 35):horizalign(left):zoomto(0, 10) end,
	RefreshCommand=function(self)
		local fraction = 0
		if state.phase == "scan" then
			fraction = #state.paths > 0 and (state.scanned / #state.paths) or 0
		elseif state.phase == "download" then
			fraction = #state.todo > 0 and (state.finished / #state.todo) or 0
		elseif state.phase == "apply" or state.phase == "reload" or state.phase == "restart" or state.phase == "uptodate" then
			fraction = 1
		end
		self:diffuse(GetHexColor(SL.Global.ActiveColorIndex, true)):zoomto(barWidth * fraction, 10)
	end,
}

-- The file being downloaded, or why it stopped.
af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
	InitCommand=function(self) self:y(62):zoom(0.7):diffuse(color("#999999")):maxwidth(_screen.w * 0.85 / 0.7) end,
	RefreshCommand=function(self)
		if state.phase == "download" or state.phase == "failed" or state.phase == "restart" then
			self:settext(state.detail)
		elseif state.phase == "reload" and #state.removed > 0 then
			self:settext(s("RemovedNote"):format(#state.removed))
		else
			self:settext("")
		end
	end,
}

-- Which buttons do what.
af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
	InitCommand=function(self) self:y(110):zoom(0.75):diffuse(color("#777777")) end,
	RefreshCommand=function(self)
		if state.phase == "failed" or state.phase == "uptodate" or state.phase == "restart" then
			self:settext(s("PressStart"))
		elseif state.phase == "apply" or state.phase == "reload" then
			self:settext("")
		else
			self:settext(s("PressBack"))
		end
	end,
}

return af
