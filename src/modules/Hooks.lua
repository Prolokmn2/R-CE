-- Hook interceptors: remote traffic, require(), and arbitrary closures (logs args/returns/constants/upvalues).
return function(RCE)
	local E = RCE.require("src/core/Env.lua")
	local U = RCE.require("src/core/Util.lua")
	local Registry = RCE.require("src/core/Registry.lua")

	local H = {
		log = {},
		MAX = 500,
		flags = { remote = false, require = false, paused = false },
		hooked = {},
		listeners = {},
	}
	local nextId = 0

	-- Hook shims are installed once per session and reused after a re-execute; they just call shared sinks.
	local shared = Registry.get("hook_shared")
	if type(shared) ~= "table" then
		shared = {}
		Registry.set("hook_shared", shared)
	end

	local function push(kind, title, body)
		if H.flags.paused then
			return
		end
		nextId += 1
		local e = { id = nextId, t = os.clock(), kind = kind, title = title, body = body }
		H.log[#H.log + 1] = e
		if #H.log > H.MAX then
			table.remove(H.log, 1)
		end
		for _, f in ipairs(H.listeners) do
			pcall(f, e)
		end
	end

	function H.onLog(f)
		table.insert(H.listeners, f)
	end

	function H.clear()
		table.clear(H.log)
	end

	---------------------------------------------------------------- remotes
	local REMOTE_METHODS = { FireServer = true, InvokeServer = true }

	local function logRemote(remote, method, args, caller)
		pcall(function()
			local cn = remote.ClassName
			if not cn:find("Remote") then
				return
			end
			local lines = {
				"Remote : " .. U.pathOf(remote),
				"Class  : " .. cn,
				"Method : " .. method,
				"Caller : " .. (caller and U.pathOf(caller) or "?"),
				"Args   : " .. args.n,
			}
			for i = 1, args.n do
				lines[#lines + 1] = ("  [%d] %s = %s"):format(i, typeof(args[i]), U.ser(args[i]))
			end
			push("remote", remote.Name .. ":" .. method, lines)
		end)
	end

	function H.installRemote()
		if not (E.hookmetamethod and E.getnamecallmethod) then
			return false, "hookmetamethod / getnamecallmethod missing"
		end
		shared.remoteSink = function(remote, method, args, caller)
			if H.flags.remote then
				task.defer(logRemote, remote, method, args, caller)
			end
		end
		if shared.remoteInstalled then
			return true
		end
		local old
		local ok, err = pcall(function()
			old = E.hookmetamethod(game, "__namecall", E.newcclosure(function(self, ...)
				local method = E.getnamecallmethod()
				local sink = shared.remoteSink
				if sink and REMOTE_METHODS[method] and typeof(self) == "Instance" then
					if not (E.checkcaller and E.checkcaller()) then
						local caller = E.getcallingscript and E.getcallingscript() or nil
						sink(self, method, table.pack(...), caller)
					end
				end
				if E.setnamecallmethod then
					E.setnamecallmethod(method)
				end
				return old(self, ...)
			end))
		end)
		if not ok then
			return false, tostring(err)
		end
		shared.remoteInstalled = true
		return true
	end

	---------------------------------------------------------------- require
	function H.installRequire()
		if not E.hookfunction then
			return false, "hookfunction missing"
		end
		shared.requireSink = function(mod, caller, ...)
			if H.flags.require then
				local extra = table.pack(...)
				task.defer(function()
					pcall(function()
						push("require", typeof(mod) == "Instance" and U.pathOf(mod) or tostring(mod), {
							"Module : " .. (typeof(mod) == "Instance" and U.pathOf(mod) or tostring(mod)),
							"Caller : " .. (caller and U.pathOf(caller) or "?"),
							"Extra  : " .. extra.n .. " arg(s)",
						})
					end)
				end)
			end
		end
		if shared.requireInstalled then
			return true
		end
		local oldReq
		local ok, err = pcall(function()
			oldReq = E.hookfunction(require, E.newcclosure(function(mod, ...)
				local sink = shared.requireSink
				if sink and not (E.checkcaller and E.checkcaller()) then
					sink(mod, E.getcallingscript and E.getcallingscript() or nil, ...)
				end
				return oldReq(mod, ...)
			end))
		end)
		if not ok then
			return false, tostring(err)
		end
		shared.requireInstalled = true
		return true
	end

	---------------------------------------------------------------- closures
	function H.hookClosure(fn, label)
		if not E.hookfunction then
			return false, "hookfunction missing"
		end
		if H.hooked[fn] then
			return false, "already hooked"
		end
		-- capture static info BEFORE hooking (a hooked fn reports the shim's constants)
		local static = {}
		local okK, ks = pcall(E.getconstants, fn)
		if okK and type(ks) == "table" then
			static[#static + 1] = "constants:"
			local n = 0
			for k, v in pairs(ks) do
				n += 1
				if n > 25 then
					break
				end
				static[#static + 1] = ("  K[%s] %s"):format(tostring(k), U.trunc(U.ser(v), 100))
			end
		end
		local okU, ups = pcall(E.getupvalues, fn)
		if okU and type(ups) == "table" then
			static[#static + 1] = "upvalues:"
			local n = 0
			for k, v in pairs(ups) do
				n += 1
				if n > 25 then
					break
				end
				static[#static + 1] = ("  U[%s] %s"):format(tostring(k), U.trunc(U.ser(v), 100))
			end
		end

		local entry = { fn = fn, label = label, active = true, calls = 0 }
		local old
		local function shim(...)
			if not entry.active or H.flags.paused then
				return old(...)
			end
			entry.calls += 1
			local args = table.pack(...)
			local rets = table.pack(old(...))
			local calls = entry.calls
			task.defer(function()
				pcall(function()
					local lines = { "Hooked : " .. label, "Call # : " .. calls, "Args   : " .. args.n }
					for i = 1, args.n do
						lines[#lines + 1] = ("  [%d] %s = %s"):format(i, typeof(args[i]), U.ser(args[i]))
					end
					lines[#lines + 1] = "Returns: " .. rets.n
					for i = 1, rets.n do
						lines[#lines + 1] = ("  [%d] %s = %s"):format(i, typeof(rets[i]), U.ser(rets[i]))
					end
					lines[#lines + 1] = ""
					for _, s in ipairs(static) do
						lines[#lines + 1] = s
					end
					push("hook", label, lines)
				end)
			end)
			return table.unpack(rets, 1, rets.n)
		end
		local ok, err = pcall(function()
			old = E.hookfunction(fn, shim)
		end)
		if not ok then
			return false, tostring(err)
		end
		entry.old = old
		H.hooked[fn] = entry
		return true
	end

	function H.unhook(fn)
		local entry = H.hooked[fn]
		if not entry then
			return false, "not hooked"
		end
		entry.active = false
		if E.restorefunction then
			pcall(E.restorefunction, fn)
		end
		H.hooked[fn] = nil
		return true
	end

	RCE.OnUnload(function()
		H.flags.remote, H.flags.require = false, false
		shared.remoteSink, shared.requireSink = nil, nil
		for fn in pairs(H.hooked) do
			H.unhook(fn)
		end
	end)

	return H
end
