-- Cross-scope state bridge. Lives in debug.getregistry() when writable,
-- otherwise falls back to getgenv(). Survives re-execution of the loader.
return function(RCE)
	local E = RCE.require("src/core/Env.lua")
	local R = {}
	local KEY = "__RCE_STATE"
	local genv = (getgenv and getgenv()) or _G

	local function viaRegistry()
		if not E.getreg then
			return nil
		end
		local ok, reg = pcall(E.getreg)
		if not ok or type(reg) ~= "table" then
			return nil
		end
		local ok2, cur = pcall(function()
			return reg[KEY]
		end)
		if ok2 and type(cur) == "table" then
			return cur
		end
		local fresh = {}
		local ok3 = pcall(function()
			reg[KEY] = fresh
		end)
		if ok3 and reg[KEY] == fresh then
			return fresh
		end
		return nil
	end

	local reg = viaRegistry()
	local store = reg or genv[KEY] or {}
	if not reg then
		genv[KEY] = store
	end
	R.backend = reg and "debug.getregistry" or "getgenv"

	function R.get(k)
		return store[k]
	end

	function R.set(k, v)
		store[k] = v
	end

	function R.keys(prefix)
		local out = {}
		for k in next, store do
			if type(k) == "string" and (not prefix or k:sub(1, #prefix) == prefix) then
				out[#out + 1] = k
			end
		end
		table.sort(out)
		return out
	end

	return R
end
