HunterTimer = HunterTimer or {}
local HT = HunterTimer

HT.AUTO_SHOT_ID = 75
HT.DEFAULT_TIMEOUT = 8
HT.DEFAULT_REPEATS = 5
HT.AIM_SECONDS = 0.5

function HT.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99HunterTimer|r: " .. tostring(msg))
end

function HT.DetectCapabilities()
	HT.hasSuperWow = (SUPERWOW_VERSION ~= nil) or (type(SpellInfo) == "function")
	HT.hasExportFile = (type(ExportFile) == "function")
	HT.hasUnitCastEvent = true
end

function HT.CanStart()
	return HT.hasExportFile and (type(SpellInfo) == "function")
end

local function trim_lower(msg)
	msg = msg or ""
	msg = string.gsub(msg, "^%s+", "")
	msg = string.gsub(msg, "%s+$", "")
	return string.lower(msg)
end

SLASH_HUNTERTIMER1 = "/ht"
SlashCmdList["HUNTERTIMER"] = function(msg)
	local raw = msg or ""
	raw = string.gsub(raw, "^%s+", "")
	raw = string.gsub(raw, "%s+$", "")
	local _, _, cmd, rest = string.find(string.lower(raw), "^(%S+)%s*(.*)$")
	cmd = cmd or "help"
	-- keep original rest casing for protocol names where needed; protocols are lowercase
	local _, _, _, restOrig = string.find(raw, "^(%S+)%s*(.*)$")
	rest = rest or ""
	restOrig = restOrig or rest

	if cmd == "help" or cmd == "" then
		HT.Print("/ht list|start <name>|stop|abort|retry|skip")
	elseif cmd == "list" then
		local names = HT.Protocol.List()
		if table.getn(names) == 0 then
			HT.Print("(no protocols)")
		else
			local i
			for i = 1, table.getn(names) do
				HT.Print(names[i])
			end
		end
	elseif cmd == "start" then
		if not HT.CanStart() then
			HT.Print("需要 SuperWoW ExportFile + SpellInfo，拒绝 start")
			return
		end
		local name = rest
		if name == nil or name == "" then
			HT.Print("用法: /ht start <protocol>")
			return
		end
		-- freeform session without protocol: /ht start test
		if name == "test" then
			if HT.Session.IsActive() then
				HT.Print("已有会话进行中，先 /ht stop 或 /ht abort")
				return
			end
			local ok, err = HT.Session.Begin("test")
			if not ok then
				HT.Print("无法开始: " .. tostring(err))
				return
			end
			HT.EventCore.Enable()
			HT.Session.Emit("snapshot", {
				extras = { note = "session_started", rangedSpeed = UnitRangedDamage and UnitRangedDamage("player") or 0 },
			})
			HT.Print("会话开始: test（导出请 /ht stop）")
			return
		end
		local ok, err = HT.Protocol.Start(name)
		if not ok then
			HT.Print("无法开始协议: " .. tostring(err))
		end
	elseif cmd == "stop" then
		if HT.Protocol.IsRunning() then
			HT.Protocol.Stop()
		elseif HT.Session.IsActive() then
			HT.EventCore.Disable()
			HT.Session.StopAndExport()
		else
			HT.Print("无进行中的会话")
		end
	elseif cmd == "abort" then
		if HT.Protocol.IsRunning() or HT.Session.IsActive() then
			HT.Protocol.Abort()
			HT.Print("已丢弃会话")
		else
			HT.Print("无进行中的会话")
		end
	elseif cmd == "retry" then
		local ok, err = HT.Protocol.Retry()
		if not ok then
			HT.Print("retry 失败: " .. tostring(err))
		end
	elseif cmd == "skip" then
		local ok, err = HT.Protocol.Skip()
		if not ok then
			HT.Print("skip 失败: " .. tostring(err))
		end
	else
		HT.Print("unknown: " .. cmd)
	end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
	HT.DetectCapabilities()
	if not HT.CanStart() then
		HT.Print("|cffff0000缺少 SuperWoW 文件/施法 API，测量不可用|r")
	else
		HT.Print("就绪。/ht help")
	end
	local _, class = UnitClass("player")
	if class ~= "HUNTER" then
		HT.Print("|cffffff00非猎人：可继续测事件，协议不强制|r")
	end
end)
