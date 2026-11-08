-- LiveView: real-time feed of everything happening (remotes, events, http, scripts, property changes)
-- Think of it as a unified event stream console
return function(RCE)
	local E = RCE.require("src/core/Env.lua")
	local U = RCE.require("src/core/Util.lua")

	local LV = {
		log = {},
		MAX = 3000,
		listeners = {},
		flags = {
			enabled = false,
			paused = false,
			showRemotes = true,
			showHttp = true,
			showEvents = true,
			showHooks = true,
			showErrors = true,
			showCustom = true,
		},
		filter = "",
		stats = { total = 0, remotes = 0, http = 0, events = 0, hooks = 0 },
	}

	local nextId = 0
	local t0 = os.clock()

	local function push(kind, text, data)
		if LV.flags.paused then return end
		if LV.filter ~= "" and not text:lower():find(LV.filter:lower(), 1, true) then return end
		nextId += 1
		LV.stats.total += 1
		if kind == "remote" then LV.stats.remotes += 1
		elseif kind == "http" then LV.stats.http += 1
		elseif kind == "event" then LV.stats.events += 1
		elseif kind == "hook" then LV.stats.hooks += 1
		end
		local e = {
			id = nextId,
			t = os.clock() - t0,
			kind = kind,
			text = text,
			data = data,
		}
		LV.log[#LV.log + 1] = e
		if #LV.log > LV.MAX then table.remove(LV.log, 1) end
		for _, f in ipairs(LV.listeners) do pcall(f, e) end
	end

	function LV.onLog(f) table.insert(LV.listeners, f) end
	function LV.clear()
		table.clear(LV.log)
		LV.stats = { total = 0, remotes = 0, http = 0, events = 0, hooks = 0 }
	end

	-- Wire up to other modules once they're loaded
	function LV.wire()
		-- Wire RemoteSpy
		local ok1, RS = pcall(RCE.require, "src/modules/RemoteSpy.lua")
		if ok1 and RS then
			RS.onLog(function(e)
				if LV.flags.enabled and LV.flags.showRemotes then
					local argPreview = ""
					for i = 1, math.min(3, e.args.n) do
						argPreview = argPreview .. U.trunc(U.ser(e.args[i]), 40)
						if i < math.min(3, e.args.n) then argPreview = argPreview .. ", " end
					end
					push("remote",
						("[REMOTE] %s:%s(%s)"):format(e.path, e.method, argPreview),
						e)
				end
			end)
		end

		-- Wire HttpSpy
		local ok2, HS = pcall(RCE.require, "src/modules/HttpSpy.lua")
		if ok2 and HS then
			HS.onLog(function(e)
				if LV.flags.enabled and LV.flags.showHttp then
					push("http",
						("[HTTP] %s %s"):format(e.method, U.trunc(e.url, 80)),
						e)
				end
			end)
		end

		-- Wire EventSpy
		local ok3, ES = pcall(RCE.require, "src/modules/EventSpy.lua")
		if ok3 and ES then
			ES.onLog(function(e)
				if LV.flags.enabled and LV.flags.showEvents then
					push("event",
						("[EVENT] %s @ %s"):format(e.kind, e.source),
						e)
				end
			end)
		end

		-- Wire Hooks module
		local ok4, Hooks = pcall(RCE.require, "src/modules/Hooks.lua")
		if ok4 and Hooks then
			Hooks.onLog(function(e)
				if LV.flags.enabled and LV.flags.showHooks then
					push("hook",
						("[HOOK] %s %s"):format(e.kind, e.title),
						e)
				end
			end)
		end

		-- Wire script error capture via loadstring wrapper
		if E.hookfunction and type(loadstring) == "function" and not LV._loadstringHooked then
			local oldLS = loadstring
			pcall(E.hookfunction, loadstring, function(src, chunkname)
				local ok, fn, err = pcall(oldLS, src, chunkname)
				if ok then
					if fn == nil and LV.flags.enabled and LV.flags.showErrors then
						push("error", ("[LOAD ERR] %s: %s"):format(chunkname or "?", tostring(err)), nil)
					end
					return fn, err
				end
				return oldLS(src, chunkname)
			end)
			LV._loadstringHooked = true
		end
	end

	-- Inject a custom message
	function LV.inject(text)
		push("custom", "[CUSTOM] " .. tostring(text), nil)
	end

	RCE.OnUnload(function()
		LV.flags.enabled = false
	end)

	return LV
end
