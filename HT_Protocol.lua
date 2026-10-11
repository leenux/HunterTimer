HunterTimer = HunterTimer or {}
local HT = HunterTimer
HT.AUTO_SHOT_ID = HT.AUTO_SHOT_ID or 75
HT.DEFAULT_TIMEOUT = HT.DEFAULT_TIMEOUT or 8
HT.DEFAULT_REPEATS = HT.DEFAULT_REPEATS or 5
HT.AIM_SECONDS = HT.AIM_SECONDS or 0.5
HT.Protocol = HT.Protocol or {}
local P = HT.Protocol

local registry = {}
local running = false
local currentName = nil
local currentDef = nil
local stepIndex = 1
local repeatIndex = 1
local stepEnteredAt = 0
local matchCount = 0
local timedOut = false
local updateFrame = nil

local function mark(action, step, extra)
	extra = extra or {}
	extra.action = action
	extra["repeat"] = repeatIndex
	HT.Session.Emit("protocol_mark", {
		step = step and step.id or nil,
		expect = step and step.expect or nil,
		extras = extra,
	})
end

local function name_in_list(spell, names)
	if not spell or not names then
		return false
	end
	local i
	for i = 1, table.getn(names) do
		if spell == names[i] then
			return true
		end
	end
	return false
end

local function id_in_list(sid, ids)
	if not sid or not ids then
		return false
	end
	local i
	for i = 1, table.getn(ids) do
		if sid == ids[i] then
			return true
		end
	end
	return false
end

local function matches(step, ev)
	if not step or not ev then
		return false
	end
	if ev.type ~= step.expect then
		return false
	end
	if step.spellId and ev.spellId ~= step.spellId then
		return false
	end
	if step.spellIds and not id_in_list(ev.spellId, step.spellIds) then
		return false
	end
	if step.spellNames and not name_in_list(ev.spell, step.spellNames) then
		return false
	end
	return true
end

local function current_step()
	if not currentDef then
		return nil
	end
	return currentDef.steps[stepIndex]
end

local function finish_success()
	HT.Print("协议完成，正在导出…")
	HT.EventCore.OnNormalized = nil
	HT.EventCore.Disable()
	running = false
	currentName = nil
	currentDef = nil
	HT.Session.StopAndExport()
end

local function enter_step()
	local step = current_step()
	if not step then
		finish_success()
		return
	end
	timedOut = false
	matchCount = 0
	stepEnteredAt = GetTime()
	mark("enter", step, {})
	if step.prompt then
		HT.Print(step.prompt)
	end
	if step.count then
		HT.Print(string.format("进度 0/%d", step.count))
	end
end

local function advance()
	local step = current_step()
	mark("complete", step, { matches = matchCount })
	stepIndex = stepIndex + 1
	if stepIndex > table.getn(currentDef.steps) then
		local repeats = currentDef.repeats or 1
		if repeatIndex < repeats then
			repeatIndex = repeatIndex + 1
			stepIndex = 1
			HT.Print(string.format("第 %d/%d 轮", repeatIndex, repeats))
			enter_step()
		else
			finish_success()
		end
	else
		enter_step()
	end
end

local function on_event(ev)
	if not running or timedOut then
		return
	end
	local step = current_step()
	if not matches(step, ev) then
		return
	end
	if step.count then
		matchCount = matchCount + 1
		HT.Print(string.format("进度 %d/%d", matchCount, step.count))
		if matchCount >= step.count then
			advance()
		end
	else
		matchCount = 1
		advance()
	end
end

local function ensure_update()
	if updateFrame then
		return
	end
	updateFrame = CreateFrame("Frame")
	updateFrame:SetScript("OnUpdate", function()
		if not running or timedOut then
			return
		end
		local step = current_step()
		if not step then
			return
		end
		local timeout = step.timeout or HT.DEFAULT_TIMEOUT
		if GetTime() - stepEnteredAt > timeout then
			timedOut = true
			mark("timeout", step, {})
			HT.Print("步骤超时。/ht retry 重试，/ht skip 跳过")
		end
	end)
end

function P.Register(name, def)
	def = def or {}
	def.name = name
	registry[name] = def
end

function P.List()
	local names = {}
	local k, _
	for k, _ in pairs(registry) do
		table.insert(names, k)
	end
	table.sort(names)
	return names
end

function P.IsRunning()
	return running
end

function P.Start(name)
	if running or HT.Session.IsActive() then
		return false, "already_active"
	end
	local def = registry[name]
	if not def then
		return false, "unknown_protocol"
	end
	local ok, err = HT.Session.Begin(name)
	if not ok then
		return false, err
	end
	HT.EventCore.Enable()
	HT.EventCore.OnNormalized = on_event
	ensure_update()
	running = true
	currentName = name
	currentDef = def
	stepIndex = 1
	repeatIndex = 1
	HT.Print("协议开始: " .. name)
	enter_step()
	return true
end

function P.Stop()
	if not running and not HT.Session.IsActive() then
		return false, "not_active"
	end
	HT.EventCore.OnNormalized = nil
	HT.EventCore.Disable()
	running = false
	currentName = nil
	currentDef = nil
	return HT.Session.StopAndExport()
end

function P.Abort()
	HT.EventCore.OnNormalized = nil
	HT.EventCore.Disable()
	running = false
	currentName = nil
	currentDef = nil
	HT.Session.Abort()
end

function P.Retry()
	if not running then
		return false, "not_running"
	end
	if not timedOut then
		HT.Print("当前步骤未超时，无需 retry")
		return false, "not_timed_out"
	end
	enter_step()
	return true
end

function P.Skip()
	if not running then
		return false, "not_running"
	end
	local step = current_step()
	mark("skip", step, {})
	timedOut = false
	advance()
	return true
end

-- Smoke protocol
P.Register("debug_wait_auto", {
	name = "debug_wait_auto",
	repeats = 1,
	steps = {
		{
			id = "collect",
			expect = "auto_cast",
			count = 3,
			prompt = "开自动射击，等 3 发",
			timeout = 30,
		},
	},
})

local NAMES_AIMED = { "瞄准射击", "Aimed Shot" }
local NAMES_MULTI = { "多重射击", "Multi-Shot" }
local NAMES_STEADY = { "稳固射击", "Steady Shot", "Trueshot" }
local NAMES_ARCANE = { "奥术射击", "Arcane Shot" }
local NAMES_SERPENT = { "毒蛇钉刺", "Serpent Sting" }

-- categoryRecoveryTime from tw_world.spell_template (ms), plus cast/GCD buffer.
-- Aimed 20904: 26000; Multi 25294: 10000; Arcane 14287: 6000; Steady cast ranks: 0; Serpent: 0.
local CD = {
	AIMED = 26,
	MULTI = 10,
	ARCANE = 6,
	STEADY = 0,
	SERPENT = 0,
}

local function wait_timeout(cdSec)
	-- wait for next auto + CD remaining + margin
	return math.max(20, (cdSec or 0) + 15)
end

local function cast_start_timeout(cdSec)
	-- player may need full CD after previous repeat
	return math.max(12, (cdSec or 0) + 10)
end

local function register_cast_protocol(name, names, label, cdSec)
	local startTo = cast_start_timeout(cdSec)
	local landTo = 12
	P.Register(name, {
		name = name,
		repeats = HT.DEFAULT_REPEATS,
		steps = {
			{
				id = "wait_auto1",
				expect = "auto_cast",
				prompt = "等待自动射击落地…",
				timeout = wait_timeout(cdSec),
			},
			{
				id = "cast_start",
				expect = "spell_start",
				spellNames = names,
				prompt = string.format(
					"等 %s CD 好了再读条施放（库表类别CD约%ds，本步超时%ds）",
					label, cdSec or 0, startTo
				),
				timeout = startTo,
			},
			{
				id = "cast_land",
				expect = "spell_cast",
				spellNames = names,
				prompt = "等待" .. label .. "完成",
				timeout = landTo,
			},
			{
				id = "wait_auto2",
				expect = "auto_cast",
				prompt = "等待下一发自动射击",
				timeout = 20,
			},
		},
	})
end

local function register_instant_protocol(name, names, label, cdSec)
	local startTo = cast_start_timeout(cdSec)
	P.Register(name, {
		name = name,
		repeats = HT.DEFAULT_REPEATS,
		steps = {
			{
				id = "wait_auto1",
				expect = "auto_cast",
				prompt = "等待自动射击落地…",
				timeout = wait_timeout(cdSec),
			},
			{
				id = "instant",
				expect = "spell_cast",
				spellNames = names,
				prompt = string.format(
					"等 %s CD 好了再按一次（库表类别CD约%ds，本步超时%ds）",
					label, cdSec or 0, startTo
				),
				timeout = startTo,
			},
			{
				id = "wait_auto2",
				expect = "auto_cast",
				prompt = "等待下一发自动射击",
				timeout = 20,
			},
		},
	})
end

P.Register("baseline_auto", {
	name = "baseline_auto",
	repeats = 1,
	steps = {
		{
			id = "collect_auto",
			expect = "auto_cast",
			count = 10,
			prompt = "站定只开自动射击，采集 10 发；勿施法",
			timeout = 60,
		},
	},
})

register_cast_protocol("cast_aimed", NAMES_AIMED, "瞄准射击", CD.AIMED)
register_cast_protocol("cast_multi", NAMES_MULTI, "多重射击", CD.MULTI)
register_cast_protocol("cast_steady", NAMES_STEADY, "稳固射击", CD.STEADY)
register_instant_protocol("instant_arcane", NAMES_ARCANE, "奥术射击", CD.ARCANE)
register_instant_protocol("instant_serpent", NAMES_SERPENT, "毒蛇钉刺", CD.SERPENT)

local function clip_probe_steps()
	local phases = {
		{ id = "p0", pct = "0%", hint = "Auto 落地后立刻开稳固" },
		{ id = "p25", pct = "25%", hint = "约过 1/4 周期后再开稳固" },
		{ id = "p50", pct = "50%", hint = "约过半周期后再开稳固" },
		{ id = "p75", pct = "75%", hint = "约过 3/4 周期后再开稳固" },
		{ id = "p95", pct = "95%", hint = "接近下一发 Auto 时再开稳固" },
	}
	local steps = {}
	local i
	for i = 1, table.getn(phases) do
		local ph = phases[i]
		table.insert(steps, {
			id = ph.id .. "_wait_auto",
			expect = "auto_cast",
			prompt = "相位 " .. ph.pct .. "：等待 Auto…",
			timeout = 20,
		})
		table.insert(steps, {
			id = ph.id .. "_start",
			expect = "spell_start",
			spellNames = NAMES_STEADY,
			prompt = ph.hint .. "（稳固无类别CD）",
			timeout = 20,
		})
		table.insert(steps, {
			id = ph.id .. "_land",
			expect = "spell_cast",
			spellNames = NAMES_STEADY,
			prompt = "等待稳固完成",
			timeout = 12,
		})
		table.insert(steps, {
			id = ph.id .. "_next_auto",
			expect = "auto_cast",
			prompt = "等待下一发 Auto（记录延迟）",
			timeout = 20,
		})
	end
	return steps
end

P.Register("clip_probe_steady", {
	name = "clip_probe_steady",
	repeats = 1,
	steps = clip_probe_steps(),
})

P.Register("weave_aimed_instant", {
	name = "weave_aimed_instant",
	repeats = HT.DEFAULT_REPEATS,
	steps = {
		{
			id = "wait_auto1",
			expect = "auto_cast",
			prompt = "等待自动射击落地…",
			timeout = wait_timeout(CD.AIMED),
		},
		{
			id = "aimed_start",
			expect = "spell_start",
			spellNames = NAMES_AIMED,
			prompt = string.format(
				"等瞄准CD好了再读条（库表类别CD约%ds）",
				CD.AIMED
			),
			timeout = cast_start_timeout(CD.AIMED),
		},
		{
			id = "aimed_land",
			expect = "spell_cast",
			spellNames = NAMES_AIMED,
			prompt = "等待瞄准完成",
			timeout = 12,
		},
		{
			id = "arcane",
			expect = "spell_cast",
			spellNames = NAMES_ARCANE,
			prompt = string.format(
				"瞄准落地后立刻奥术（奥术类别CD约%ds，若灰了等一下）",
				CD.ARCANE
			),
			timeout = cast_start_timeout(CD.ARCANE),
		},
		{
			id = "wait_auto2",
			expect = "auto_cast",
			prompt = "等待下一发自动射击",
			timeout = 20,
		},
	},
})
