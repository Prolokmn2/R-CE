--[[
	R-CE  |  Roblox Cheat Engine  |  loader
	loadstring(game:HttpGet("https://raw.githubusercontent.com/Prolokmn2/R-CE/main/loader.lua"))()

	Optional globals (set BEFORE running the loader):
		getgenv().RCE_BASE  = "https://raw.githubusercontent.com/<user>/<repo>/<branch>/"
		getgenv().RCE_LOCAL = true   -- read modules from workspace/R-CE/<path> instead of HTTP
]]
local genv = (getgenv and getgenv()) or _G
if genv.RCE and type(genv.RCE.Unload) == "function" then
	pcall(genv.RCE.Unload)
end

local BASE = genv.RCE_BASE or "https://raw.githubusercontent.com/Prolokmn2/R-CE/main/"
local LOCAL = genv.RCE_LOCAL

local RCE = { Version = "0.1.0", Modules = {}, Cleanups = {}, Base = BASE }

local function fetch(path)
	if LOCAL and readfile then
		return readfile("R-CE/" .. path)
	end
	return game:HttpGet(BASE .. path)
end

-- every module file is:  return function(RCE) ... return Module end
function RCE.require(path)
	local cached = RCE.Modules[path]
	if cached ~= nil then
		return cached
	end
	local ok, src = pcall(fetch, path)
	if not ok or type(src) ~= "string" or src == "" then
		error(("[R-CE] failed to fetch %s: %s"):format(path, tostring(src)), 0)
	end
	local fn, err = loadstring(src, "=RCE/" .. path)
	if not fn then
		error(("[R-CE] syntax error in %s: %s"):format(path, tostring(err)), 0)
	end
	local mod = fn()(RCE)
	RCE.Modules[path] = mod
	return mod
end

function RCE.OnUnload(fn)
	table.insert(RCE.Cleanups, fn)
end

function RCE.Unload()
	for i = #RCE.Cleanups, 1, -1 do
		pcall(RCE.Cleanups[i])
	end
	table.clear(RCE.Cleanups)
	if genv.RCE == RCE then
		genv.RCE = nil
	end
end

genv.RCE = RCE

local ok, err = pcall(function()
	RCE.require("src/ui/UI.lua").Init()
end)
if not ok then
	warn("[R-CE] startup failed: " .. tostring(err))
	RCE.Unload()
end

return RCE
