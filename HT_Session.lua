HunterTimer = HunterTimer or {}
local HT = HunterTimer
HT.Session = HT.Session or {}
local S = HT.Session

local active = false
local protocol = nil
local t0 = 0
local lines = {}
local lastAutoMono = nil
local runId = nil

local function now()
	return GetTime()
end

local function stamp_name(proto)
	local d = date("%Y%m%d_%H%M%S")
	return "HunterTimer_" .. proto .. "_" .. d
end

function S.IsActive()
	return active
end

function S.GetProtocol()
	return protocol
end

function S.Begin(protocolName)
	if active then
		return false, "already_active"
	end
	active = true
	protocol = protocolName
	t0 = now()
	lines = { "# huntertimer v1" }
	lastAutoMono = nil
	runId = protocolName .. "_" .. tostring(t0)
	local speed = 0
	if UnitRangedDamage then
		speed = UnitRangedDamage("player") or 0
	end
	local lag = 0
	if GetNetStats then
		local _, _, lagHome, lagWorld = GetNetStats()
		lag = lagWorld or lagHome or 0
	end
	S.Emit("session_meta", {
		extras = {
			protocol = protocolName,
			runId = runId,
			player = UnitName("player"),
			rangedSpeed = speed,
			latencyMs = lag,
			aimSeconds = HT.AIM_SECONDS,
			version = 1,
		}
	})
	return true
end

function S.Emit(typeName, fields)
	if not active then
		return
	end
	fields = fields or {}
	local t = now()
	local mono = t - t0
	local row = {
		t = t,
		mono = mono,
		type = typeName,
		spellId = fields.spellId,
		spell = fields.spell,
		castDur = fields.castDur,
		step = fields.step,
		expect = fields.expect,
		phaseHint = fields.phaseHint,
		extras = fields.extras,
	}
	if typeName == "auto_cast" then
		lastAutoMono = mono
		row.phaseHint = 0
	elseif lastAutoMono ~= nil and row.phaseHint == nil then
		row.phaseHint = mono - lastAutoMono
	end
	table.insert(lines, HT.Json.EncodeObject(row))
end

function S.Abort()
	active = false
	protocol = nil
	lines = {}
	lastAutoMono = nil
end

function S.StopAndExport()
	if not active then
		return false, "not_active"
	end
	local name = stamp_name(protocol or "unknown")
	local text = table.concat(lines, "\n") .. "\n"
	local ok, err = pcall(function()
		ExportFile(name, text)
	end)
	if not ok then
		HT.Print("ExportFile 失败: " .. tostring(err))
		return false, err
	end
	HT.Print("已导出 Imports/" .. name .. ".txt")
	active = false
	protocol = nil
	lines = {}
	lastAutoMono = nil
	return true, name
end

function S.GetLastAutoMono()
	return lastAutoMono
end
