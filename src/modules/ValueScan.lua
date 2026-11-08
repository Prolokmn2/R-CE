-- ValueScan v2: Cheat-Engine style scanner -- now supports string, bool, Vector3, CFrame, Instance
return function(RCE)
	local E = RCE.require("src/core/Env.lua")
	local U = RCE.require("src/core/Util.lua")
	local RunService = game:GetService("RunService")

	local V = {
		results = {},
		frozen = {},
		MAX = 3000,
		includeUpvalues = true,
		truncated = false,
		-- NEW: scan mode
		scanType = "number",  -- "number" | "string" | "bool" | "any"
	}

	local function read(e)
		if e.kind == "t" then
			local ok, v = pcall(rawget, e.t, e.k)
			return ok and v or nil
		end
		local ok, v = pcall(E.getupvalue, e.fn, e.i)
		return ok and v or nil
	end

	local function typeMatch(v, scanType, value)
		if scanType == "any" then
			return true, v
		elseif scanType == "number" then
			return type(v) == "number" and (value == nil or v == value), v
		elseif scanType == "string" then
			if type(v) ~= "string" then return false end
			if value == nil or value == "" then return true, v end
			return v:lower():find(tostring(value):lower(), 1, true) ~= nil, v
		elseif scanType == "bool" then
			return type(v) == "boolean" and (value == nil or v == value), v
		elseif scanType == "integer" then
			return type(v) == "number" and math.floor(v) == v and (value == nil or v == value), v
		elseif scanType == "vector3" then
			if typeof(v) ~= "Vector3" then return false end
			if value == nil then return true, v end
			return v == value, v
		elseif scanType == "instance" then
			return typeof(v) == "Instance", v
		end
		return false
	end

	function V.first(value, scanType)
		table.clear(V.results)
		V.truncated = false
		V.scanType = scanType or V.scanType
		if not E.getgc then
			return false, "getgc missing"
		end
		local gc = E.getgc(true)
		local function add(e)
			if #V.results >= V.MAX then
				V.truncated = true
				return false
			end
			e.last = value
			e.scanType = V.scanType
			V.results[#V.results + 1] = e
			return true
		end
		for i, obj in ipairs(gc) do
			local t = type(obj)
			if t == "table" and obj ~= V.results and obj ~= V.frozen and obj ~= gc then
				for k, v in next, obj do
					local match = typeMatch(v, V.scanType, value)
					if match then
						if not add({ kind = "t", t = obj, k = k }) then break end
					end
				end
			elseif t == "function" and V.includeUpvalues and E.getupvalues then
				local skip = (E.iscclosure and E.iscclosure(obj)) or (E.isexecutorclosure and E.isexecutorclosure(obj))
				if not skip then
					local ok, ups = pcall(E.getupvalues, obj)
					if ok and type(ups) == "table" then
						for idx, val in pairs(ups) do
							local match = typeMatch(val, V.scanType, value)
							if match then
								if not add({ kind = "u", fn = obj, i = idx }) then break end
							end
						end
					end
				end
			end
			if V.truncated then break end
			if i % 4000 == 0 then task.wait() end
		end
		return true
	end

	-- mode: exact | changed | same | inc | dec | contains (string) | truthy
	function V.next(mode, value)
		local keep = {}
		for _, e in ipairs(V.results) do
			local cur = read(e)
			local ok = false
			if cur == nil then
				-- value gone, drop it
			elseif mode == "exact" then
				if type(cur) == "number" and type(value) == "number" then
					ok = cur == value
				elseif type(cur) == "string" then
					ok = cur == tostring(value)
				else
					ok = cur == value
				end
			elseif mode == "changed" then
				ok = cur ~= e.last
			elseif mode == "same" then
				ok = cur == e.last
			elseif mode == "inc" then
				ok = type(cur) == "number" and type(e.last) == "number" and cur > e.last
			elseif mode == "dec" then
				ok = type(cur) == "number" and type(e.last) == "number" and cur < e.last
			elseif mode == "contains" then
				ok = type(cur) == "string" and cur:lower():find(tostring(value or ""):lower(), 1, true) ~= nil
			elseif mode == "truthy" then
				ok = cur and cur ~= 0 and cur ~= "" and cur ~= false
			end
			if ok then
				e.last = cur
				keep[#keep + 1] = e
			end
		end
		V.results = keep
	end

	function V.describe(e)
		local cur = read(e)
		if e.kind == "t" then
			local sib, n = {}, 0
			for k in next, e.t do
				if k ~= e.k then
					n += 1
					sib[#sib + 1] = tostring(k)
					if n >= 4 then break end
				end
			end
			return ("tbl[%s]=%s  {%s}"):format(tostring(e.k), U.trunc(U.ser(cur), 60), table.concat(sib, ","))
		end
		local ok, info = pcall(E.getinfo, e.fn)
		local name = (ok and type(info) == "table" and info.name and info.name ~= "") and info.name or "anon"
		local src = (ok and type(info) == "table") and tostring(info.short_src) or "?"
		return ("upv#%s of %s(%s)=%s"):format(tostring(e.i), name, src, U.trunc(U.ser(cur), 60))
	end

	function V.set(e, value)
		if e.kind == "t" then
			local ok = pcall(rawset, e.t, e.k, value)
			if not ok and E.setreadonly then
				pcall(E.setreadonly, e.t, false)
				ok = pcall(rawset, e.t, e.k, value)
			end
			return ok
		end
		return (pcall(E.setupvalue, e.fn, e.i, value))
	end

	function V.freeze(e, value)
		V.frozen[e] = value
	end

	function V.thaw(e)
		V.frozen[e] = nil
	end

	local conn = RunService.Heartbeat:Connect(function()
		for e, val in next, V.frozen do
			V.set(e, val)
		end
	end)
	RCE.OnUnload(function()
		conn:Disconnect()
		table.clear(V.frozen)
	end)

	return V
end
