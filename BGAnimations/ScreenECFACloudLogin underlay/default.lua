-- QR code login for ECFA Cloud.
--
-- Each joined player without an API key (or everyone, if QRLogin is "Always")
-- is shown a QR code for <ECFA Cloud>/link?uuid=<link id>&side=<1|2>. After the
-- player approves the link on their phone, the server hands this machine a
-- fresh API key the next time we poll /api/v1/device/poll.
--
-- The QR code only carries a hash of a secret that never leaves this machine,
-- so someone who can see the screen (e.g. on a stream) can't collect the key.

local qrcodeSize = 168
local qrModulePath = THEME:GetPathB("", "_modules/QR Code/SL-QRCode.lua")
local secret = CRYPTMAN:GenerateRandomUUID():gsub("-", ""):upper()
-- First 32 hex characters of SHA-256(secret); must match deviceLinkId() on the server.
local linkId = BinaryToHex(CRYPTMAN:SHA256String(secret)):sub(1, 32):upper()
local pollInterval = 2

local ResetECFACloudSettings = function(pn)
  SL[pn].ApiKey = ""
  SL[pn].ECFACloudUsername = ""
  SL[pn].IsPadPlayer = false
end

local HandleLinks = function(data)
  if not data or data.status ~= "linked" or not data.links then return end

  for link in ivalues(data.links) do
    local side = link.side
    local pn = (side == 1) and "P1" or "P2"
    local player = (side == 1) and PLAYER_1 or PLAYER_2

    if link.apiKey and #link.apiKey == 64 and GAMESTATE:IsHumanPlayer(player) then
      if link.playerOptions then
        SetPlayerOptionsJsonFromECFACloud(player, link.playerOptions)
      end

      SL[pn].ApiKey = link.apiKey
      SL[pn].ECFACloudUsername = link.username or ""
      -- If they're QR code logging in, let's assume they're a pad player.
      SL[pn].IsPadPlayer = true
      MESSAGEMAN:Broadcast("SetCreditsText", {pn=pn, username=SL[pn].ECFACloudUsername})
      MESSAGEMAN:Broadcast("HideQr", {pn=pn, username=SL[pn].ECFACloudUsername})
    end
  end
end

local InputHandler = function(event)
	if not event.PlayerNumber or not event.button then return false end

	if event.type == "InputEventType_FirstPress" then
		if event.GameButton == "Back" then
			SCREENMAN:GetTopScreen():Cancel()

		elseif event.GameButton == "Start" then
			SCREENMAN:GetTopScreen():StartTransitioningScreen("SM_GoToNextScreen")
		end
	end
end

local af = Def.ActorFrame{
  InitCommand=function(self)
    self:Center()
    self.request = nil
    self.leaving = false
  end,
  OnCommand=function(self)
    SCREENMAN:GetTopScreen():AddInputCallback(InputHandler)
    self:queuecommand("Poll")
  end,
  -- Poll the server until every player shown a QR code has linked, or we leave the screen.
  PollCommand=function(self)
    if self.leaving then return end

    -- Only ask for keys for sides that are still showing a QR code.
    self.waitingSides = {}
    for player in ivalues(GAMESTATE:GetHumanPlayers()) do
      if self:GetChild("Player"..ToEnumShortString(player)).showingQr then
        self.waitingSides[#self.waitingSides+1] = (player == PLAYER_1) and 1 or 2
      end
    end
    if #self.waitingSides == 0 then return end

    if self.request == nil then
      self.request = NETWORK:HttpRequest{
        url=GetECFACloudURL().."/api/v1/device/poll?secret="..secret.."&sides="..table.concat(self.waitingSides, ","),
        method="GET",
        connectTimeout=10,
        transferTimeout=10,
        onResponse=function(response)
          self.request = nil
          if self.leaving then return end
          if response.statusCode == 200 then
            HandleLinks(JsonDecode(response.body))
          end
        end,
      }
    end
    self:sleep(pollInterval):queuecommand("Poll")
  end,
  CancelCommand=function(self)
    self.leaving = true
    if self.request then self.request:Cancel() end
    ResetECFACloudSettings("P1")
    ResetECFACloudSettings("P2")
  end,
  OffCommand=function(self)
    self.leaving = true
    if self.request then self.request:Cancel() end
  end,

  LoadFont("Common Normal")..{
    Text=THEME:GetString("ScreenSelectProfile", "LoginInstructions"),
    InitCommand=function(self)
      self:y(-150)
      if ThemePrefs.Get("RainbowMode") then
        self:diffuse(Color.Black)
      end
    end,
  },
  LoadFont("Common Normal")..{
    Text=THEME:GetString("ScreenSelectProfile", "VisitWebsite"):format(GetECFACloudHost()),
    InitCommand=function(self)
      self:y(-120)
      if ThemePrefs.Get("RainbowMode") then
        self:diffuse(Color.Black)
      end
    end,
  },

  LoadFont("Common Bold")..{
    Text=THEME:GetString("ScreenEvaluation", "PressStartToContinue"),
    InitCommand=function(self)
      self:zoom(0.55):y(150):shadowlength(1)
    end,
  },
}

local boxWidth = 200
local boxHeight = 200
local border = 2

for player in ivalues(GAMESTATE:GetHumanPlayers()) do
  local pn = ToEnumShortString(player)
  -- Display a QR code to fetch the API key if we always want to display the
  -- screen, or if the player doesn't already have an API key saved.
  local showQr = ThemePrefs.Get("QRLogin") == "Always" or SL[pn].ApiKey == ""

  local childAf = Def.ActorFrame{
    Name="Player"..pn,
    InitCommand=function(self)
      self:x(200 * (player == PLAYER_1 and -1 or 1) ):y(15)
      self.showingQr = showQr
    end,
    HideQrMessageCommand=function(self, params)
      if params.pn == pn then
        self.showingQr = false
      end
    end,

    -- White box for the border
    Def.Quad {
      InitCommand=function(self) self:zoomto(boxWidth, boxHeight):diffuse(Color.White) end,
    },

    -- Smaller black box for the main body
    Def.Quad {
      InitCommand=function(self) self:zoomto(boxWidth - border, boxHeight - border):diffuse(Color.Black) end,
    },

    LoadFont("Common Normal")..{
      Text=SL[pn].ApiKey ~= "" and THEME:GetString("ScreenSelectProfile", "ProfileConnected") or "",
      InitCommand=function(self)
        if ThemePrefs.RainbowMode then
          self:diffuse(Color.Black)
        end
      end,
      HideQrMessageCommand=function(self, params)
        if params.pn == pn then
          WriteECFACloudIni(player)
          self:settext(params.username .. '\nLogged in!')
        end
      end,
    },
  }

  if showQr then
    local side = (player == PLAYER_1) and 1 or 2
    local url = ("%s/link?uuid=%s&side=%d"):format(GetECFACloudURL(), linkId, side)

    childAf[#childAf+1] = LoadActor( qrModulePath , {url, qrcodeSize} )..{
      Name="QRCode",
      InitCommand=function(self) self:xy(-84, -84) end,
      HideQrMessageCommand=function(self, params)
        if params.pn == pn then
          self:visible(false)
        end
      end
    }
  end

  af[#af+1] = childAf
end

return af
