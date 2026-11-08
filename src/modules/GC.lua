-- Surgical garbage-collector closure scanner.
return function(RCE)
	local E = RCE.require("src/core/Env.lua")
	local U = RCE.require("src/core/Util.lua")
	local G = { results = {}, seen = setmetatable({}, { __mode = "k" }), MAX = 4000 }

	-- Closures / scripts whose path or source contains any of these are skipped. Editable at runtime.
	G.blacklist = { "Components", "UI", "Panels", "Menu", "Packages", "_Index", "RbxCharacterSounds" }

	function G.isBlacklisted(s)
		if not s then
			return false
		end
		for _, w in ipairs(G.blacklist) do
			if s:find(w, 1, true) then
				return true
			end
		end
		return false
	end

	local function describe(fn)
		local d = { fn = fn }
		local ok, info = pcall(E.getinfo, fn)
		if ok and type(info) == "table" then
			d.name = info.name
			d.src = info.short_src or info.source
			d.line = info.linedefined
			d.nups = info.nups
			d.params = info.numparams
		end
		local okE, fenv = pcall(getfenv, fn)
		if okE and type(fenv) == "table" then
			local okS, s = pcall(function()
				return fenv.script
			end)
			if okS and typeof(s) == "Instance" then
				d.script = s
				d.path = U.pathOf(s)
			end
		end
		if not d.name or d.name == "" then
			d.name = "anonymous"
		end
		d.path = d.path or d.src or "?"
		d.line = d.line or 0
		return d
	end
	G.describe = describe

	local function constantsMatch(fn, needle)
		local ok, ks = pcall(E.getconstants, fn)
		if not ok or type(ks) ~= "table" then
			return false
		end
		for _, v in next, ks do
			if tostring(v):lower():find(needle, 1, true) then
				return true
			end
		end
		return false
	end

	local function matches(d, f)
		if f == "" then
			return true
		end
		if f:sub(1, 2) == "k:" then
			return constantsMatch(d.fn, f:sub(3))
		end
		return d.name:lower():find(f, 1, true) ~= nil or d.path:lower():find(f, 1, true) ~= nil
	end

	-- merge = true keeps old results and only appends newly seen closures (used by auto mode)
	function G.scan(filter, merge)
		if not E.getgc then
			return nil, "getgc missing"
		end
		filter = (filter or ""):lower()
		if not merge then
			table.clear(G.results)
			G.seen = setmetatable({}, { __mode = "k" })
		end
		local gc = E.getgc(true)
		for i, obj in ipairs(gc) do
			if type(obj) == "function" and not G.seen[obj] then
				local skip = (E.iscclosure and E.iscclosure(obj)) or (E.isexecutorclosure and E.isexecutorclosure(obj))
				if not skip then
					local d = describe(obj)
					if not G.isBlacklisted(d.path) and not G.isBlacklisted(d.src) and matches(d, filter) then
						G.seen[obj] = true
						G.results[#G.results + 1] = d
						if #G.results >= G.MAX then
							break
						end
					end
				end
			end
			if i % 2500 == 0 then
				task.wait()
			end
		end
		table.sort(G.results, function(a, b)
			if a.path ~= b.path then
				return a.path < b.path
			end
			return a.line < b.line
		end)
		return G.results
	end

	local function sortedPairs(t, limit, fmt, out)
		local idx = {}
		for k in pairs(t) do
			idx[#idx + 1] = k
		end
		pcall(table.sort, idx)
		for n, k in ipairs(idx) do
			if n > limit then
				out[#out + 1] = ("  ... %d more"):format(#idx - limit)
				break
			end
			out[#out + 1] = fmt:format(tostring(k), U.trunc(U.ser(t[k]), 110))
		end
	end

	function G.details(d)
		local fn = d.fn
		local L = {
			"Name     : " .. d.name,
			"Script   : " .. d.path,
			("Source   : %s:%s"):format(tostring(d.src), tostring(d.line)),
			("Params   : %s   Upvalues: %s"):format(tostring(d.params or "?"), tostring(d.nups or "?")),
			"",
			"-- constants --",
		}
		local ok, ks = pcall(E.getconstants, fn)
		if ok and type(ks) == "table" then
			sortedPairs(ks, 80, "  K[%s] %s", L)
		else
			L[#L + 1] = "  (debug.getconstants unavailable)"
		end
		L[#L + 1] = ""
		L[#L + 1] = "-- upvalues --"
		local ok2, ups = pcall(E.getupvalues, fn)
		if ok2 and type(ups) == "table" then
			sortedPairs(ups, 60, "  U[%s] %s", L)
		else
			L[#L + 1] = "  (debug.getupvalues unavailable)"
		end
		return L
	end

	return G
end
