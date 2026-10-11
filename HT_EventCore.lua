HunterTimer = HunterTimer or {}
local HT = HunterTimer
HT.EventCore = HT.EventCore or {}
local EC = HT.EventCore

local frame = nil
local playerGuid = nil

local function spell_name(id)
	if type(SpellInfo) ~= "function" or not id then
		return nil
	end
	local name = SpellInfo(id)
	return name
end

local function emit_norm(typeName, spellId, castDur)
	local spell = spell_name(spellId)
	local fields = { spellId = spellId, spell = spell, castDur = castDur }
	HT.Session.Emit(typeName, fields)
	local ev = {
		type = typeName,
		spellId = spellId,
		spell = spell,
		castDur = castDur,
		t = GetTime(),
	}
	if EC.OnNormalized then
		EC.OnNormalized(ev)
	end
end

function EC.Enable()
	if frame then
		return
	end
	frame = CreateFrame("Frame")
	playerGuid = nil
	if UnitExists then
		local exists, guid = UnitExists("player")
		if exists and guid then
			playerGuid = guid
		end
	end
	frame:RegisterEvent("START_AUTOREPEAT_SPELL")
	frame:RegisterEvent("STOP_AUTOREPEAT_SPELL")
	frame:RegisterEvent("UNIT_CASTEVENT")
	frame:SetScript("OnEvent", function()
		local e = event
		if e == "START_AUTOREPEAT_SPELL" then
			emit_norm("autorepeat_on")
		elseif e == "STOP_AUTOREPEAT_SPELL" then
			emit_norm("autorepeat_off")
		elseif e == "UNIT_CASTEVENT" then
			if playerGuid and arg1 ~= playerGuid then
				return
			end
			local kind, sid, dur = arg3, arg4, arg5
			if kind == "START" then
				emit_norm("spell_start", sid, dur)
			elseif kind == "FAIL" then
				emit_norm("spell_fail", sid, dur)
			elseif kind == "CAST" then
				if sid == HT.AUTO_SHOT_ID then
					local speed = nil
					if UnitRangedDamage then
						speed = UnitRangedDamage("player")
					end
					HT.Session.Emit("auto_cast", {
						spellId = sid,
						spell = spell_name(sid),
						castDur = dur,
						extras = { rangedSpeed = speed },
					})
					if EC.OnNormalized then
						EC.OnNormalized({
							type = "auto_cast",
							spellId = sid,
							spell = spell_name(sid),
							castDur = dur,
							t = GetTime(),
						})
					end
				else
					emit_norm("spell_cast", sid, dur)
				end
			end
		end
	end)
end

function EC.Disable()
	if not frame then
		return
	end
	frame:UnregisterAllEvents()
	frame:SetScript("OnEvent", nil)
	frame = nil
end
