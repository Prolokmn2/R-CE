-- EventSpy: hooks BindableEvent / BindableFunction + RBXScriptSignal:Connect calls
-- Inspired by DEX++ event monitoring approach
return function(RCE)
	local E = RCE.require("src/core/Env.lua")
	local U = RCE.require("src/core/Util.lua")
	local Registry = RCE.require("src/core/Registry.lua")

	local ES = {
		log = {},
		MAX = 2000,
		listeners = {},
		flags = { enabled = false, paused = false, trackConnect = false },
		watchedEvents = {},  -- path -> true
		connectionCount = 0,
	}

	local shared = Registry.get("eventspy_shared")
	if type(shared) ~= "table" then
		shared = {}
		Registry.set("eventspy_shared", shared)
	end

	local nextId = 0
	local function push(kind, source, args)
		if ES.flags.paused then return end
		nextId += 1
		local e = { id = nextId, t = os.clock(), kind = kind, source = source, args = args }
		ES.log[#ES.log + 1] = e
		if #ES.log > ES.MAX then table.remove(ES.log, 1) end
		for _, f in ipairs(ES.listeners) do pcall(f, e) end
	end

	function ES.onLog(f) table.insert(ES.listeners, f) end
	function ES.clear() table.clear(ES.log) end

	function ES.format(e)
		local lines = {
			("Kind    : %s"):format(e.kind),
			("Source  : %s"):format(e.source),
			("Time    : %.4f"):format(e.t),
			("Args    : %d"):format(e.args.n),
		}
		for i = 1, e.args.n do
			lines[#lines + 1] = ("  [%d] %s = %s"):format(i, typeof(e.args[i]), U.trunc(U.ser(e.args[i]), 200))
		end
		return lines
	end

	-- Hook a specific signal/event by watching its :Fire calls
	function ES.watchInstance(inst)
		if not inst or typeof(inst) ~= "Instance" then return false, "not an instance" end
		local path = U.pathOf(inst)
		if ES.watchedEvents[path] then return false, "already watched" end
		local cn = inst.ClassName
		if cn == "BindableEvent" then
			local ok, err = pcall(function()
				local origFire = inst.Fire
				if E.hookfunction then
					E.hookfunction(origFire, E.newcclosure(function(self, ...)
						if ES.flags.enabled then
							task.defer(push, "BindableEvent:Fire", path, table.pack(...))
						end
						return origFire(self, ...)
					end))
				end
			end)
			if ok then
				ES.watchedEvents[path] = inst
				return true
			else
				return false, tostring(err)
			end
		elseif cn == "BindableFunction" then
			-- wrap the OnInvoke callback
			ES.watchedEvents[path] = inst
			local orig = inst.OnInvoke
			inst.OnInvoke = function(...)
				if ES.flags.enabled then
					task.defer(push, "BindableFunction:Invoke", path, table.pack(...))
				end
				if orig then return orig(...) end
			end
			return true
		end
		return false, "not a BindableEvent or BindableFunction"
	end

	-- Scan workspace/game for all Bindable instances and watch them
	function ES.scanAndWatchAll()
		local count = 0
		local function recurse(inst)
			local cn = inst.ClassName
			if cn == "BindableEvent" or cn == "BindableFunction" then
				local ok = ES.watchInstance(inst)
				if ok then count += 1 end
			end
			for _, c in ipairs(inst:GetChildren()) do
				pcall(recurse, c)
			end
		end
		for _, svc in ipairs({ "Workspace", "ReplicatedStorage", "ServerScriptService",
			"Players", "StarterGui", "StarterPlayer", "Teams" }) do
			pcall(function()
				recurse(game:GetService(svc))
			end)
		end
		return count
	end

	-- Install __namecall hook for :Fire / :InvokeServer on remotes too (bindable)
	function ES.install()
		if not (E.hookmetamethod and E.getnamecallmethod) then
			return false, "hookmetamethod / getnamecallmethod missing"
		end
		shared.eventSink = function(kind, path, args)
			if ES.flags.enabled then
				task.defer(push, kind, path, args)
			end
		end
		if shared.eventInstalled then return true end
		local old
		local ok, err = pcall(function()
			old = E.hookmetamethod(game, "__namecall", E.newcclosure(function(self, ...)
				local method = E.getnamecallmethod()
				local sink = shared.eventSink
				if sink and (method == "Fire" or method == "Invoke") and typeof(self) == "Instance" then
					local cn = self.ClassName
					if cn == "BindableEvent" or cn == "BindableFunction" then
						if not (E.checkcaller and E.checkcaller()) then
							local path = U.pathOf(self)
							if ES.watchedEvents[path] or ES.flags.enabled then
								sink(cn .. ":" .. method, path, table.pack(...))
							end
						end
					end
				end
				if E.setnamecallmethod then E.setnamecallmethod(method) end
				return old(self, ...)
			end))
		end)
		if not ok then return false, tostring(err) end
		shared.eventInstalled = true
		return true
	end

	RCE.OnUnload(function()
		ES.flags.enabled = false
		shared.eventSink = nil
		table.clear(ES.watchedEvents)
	end)

	return ES
end
