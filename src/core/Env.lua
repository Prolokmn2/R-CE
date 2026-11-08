-- Capability detection: resolves every executor function we may use, once.
return function(RCE)
	local E = {}
	local env = getfenv()
	local gen = (getgenv and getgenv()) or {}

	local function resolve(name)
		local first, rest = name:match("^([^%.]+)%.?(.*)$")
		local cur = env[first]
		if cur == nil then
			cur = gen[first]
		end
		if rest ~= "" then
			for part in rest:gmatch("[^%.]+") do
				if type(cur) ~= "table" then
					return nil
				end
				cur = cur[part]
			end
		end
		return cur
	end

	local function pick(...)
		for _, n in ipairs({ ... }) do
			local v = resolve(n)
			if v ~= nil then
				return v
			end
		end
		return nil
	end

	E.getgc = pick("getgc")
	E.hookfunction = pick("hookfunction", "replaceclosure")
	E.restorefunction = pick("restorefunction")
	E.hookmetamethod = pick("hookmetamethod")
	E.getnamecallmethod = pick("getnamecallmethod")
	E.setnamecallmethod = pick("setnamecallmethod")
	E.checkcaller = pick("checkcaller")
	E.newcclosure = pick("newcclosure") or function(f)
		return f
	end
	E.iscclosure = pick("iscclosure")
	E.isexecutorclosure = pick("isexecutorclosure", "checkclosure", "is_synapse_function")
	E.getcallingscript = pick("getcallingscript")

	E.getscriptbytecode = pick("getscriptbytecode")
	E.decompile = pick("decompile")
	E.getscripts = pick("getscripts")
	E.getloadedmodules = pick("getloadedmodules")

	E.getreg = pick("debug.getregistry", "getreg", "getregistry")
	E.getconstants = pick("debug.getconstants", "getconstants")
	E.getupvalues = pick("debug.getupvalues", "getupvalues")
	E.getupvalue = pick("debug.getupvalue", "getupvalue")
	E.setupvalue = pick("debug.setupvalue", "setupvalue")
	E.getinfo = pick("debug.getinfo", "getinfo") or debug.info and function(f)
		local s, l, n = debug.info(f, "sln")
		return { source = s, short_src = s, linedefined = l, name = n }
	end

	E.allocm = pick("allocm")
	E.readmem = pick("readmem")
	E.writemem = pick("writemem")
	E.freem = pick("freem")

	E.setreadonly = pick("setreadonly")
	E.gethui = pick("gethui")
	E.setclipboard = pick("setclipboard", "toclipboard")

	local TRACKED = {
		"getgc", "hookfunction", "hookmetamethod", "getnamecallmethod", "checkcaller",
		"getscriptbytecode", "decompile", "getscripts", "getloadedmodules", "getreg",
		"getconstants", "getupvalues", "setupvalue", "getinfo", "allocm", "readmem",
		"writemem", "setclipboard", "gethui",
	}

	function E.report()
		local have, miss = {}, {}
		for _, n in ipairs(TRACKED) do
			if E[n] then
				have[#have + 1] = n
			else
				miss[#miss + 1] = n
			end
		end
		return have, miss
	end

	return E
end
