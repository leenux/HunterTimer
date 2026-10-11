HunterTimer = HunterTimer or {}
HunterTimer.Json = {}
local Json = HunterTimer.Json

local function esc(s)
	s = tostring(s)
	s = string.gsub(s, "\\", "\\\\")
	s = string.gsub(s, '"', '\\"')
	s = string.gsub(s, "\n", "\\n")
	s = string.gsub(s, "\r", "\\r")
	return s
end

local function enc_value(v)
	local t = type(v)
	if v == nil then
		return "null"
	elseif t == "number" then
		return string.format("%.6g", v)
	elseif t == "boolean" then
		if v then return "true" else return "false" end
	elseif t == "string" then
		return '"' .. esc(v) .. '"'
	elseif t == "table" then
		return Json.EncodeObject(v)
	else
		return '"' .. esc(tostring(v)) .. '"'
	end
end

function Json.EncodeObject(tbl)
	local parts = {}
	for k, v in pairs(tbl) do
		if type(k) == "string" and v ~= nil then
			table.insert(parts, '"' .. esc(k) .. '":' .. enc_value(v))
		end
	end
	return "{" .. table.concat(parts, ",") .. "}"
end
