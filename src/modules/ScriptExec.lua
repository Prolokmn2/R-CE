-- ScriptExec: Execute / Run arbitrary Lua, with output capture and history
-- Also provides "Invoke" helper to call RemoteFunctions with custom args
return function(RCE)
	local E = RCE.require("src/core/Env.lua")
	local U = RCE.require("src/core/Util.lua")

	local SE = {
		history = {},
		MAX_HISTORY = 50,
		output = {},
		listeners = {},
	}

	local function pushOutput(kind, text)
		local e = { t = os.clock(), kind = kind, text = text }
		SE.output[#SE.output + 1] = e
		if #SE.output > 2000 then table.remove(SE.output, 1) end
		for _, f in ipairs(SE.listeners) do pcall(f, e) end
	end

	function SE.onOutput(f) table.insert(SE.listeners, f) end
	function SE.clearOutput() table.clear(SE.output) end

	-- Override print to capture in exec context
	local function makeEnv()
		local env = setmetatable({}, { __index = getfenv and getfenv(0) or _G })
		env.print = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				parts[#parts + 1] = tostring(select(i, ...))
			end
			pushOutput("print", table.concat(parts, "\t"))
		end
		env.warn = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				parts[#parts + 1] = tostring(select(i, ...))
			end
			pushOutput("warn", table.concat(parts, "\t"))
		end
		env.error = function(msg, level)
			pushOutput("error", tostring(msg))
			error(msg, (level or 1) + 1)
		end
		-- convenience globals
		env.game = game
		env.workspace = workspace
		env.script = nil
		env.RCE = RCE
		return env
	end

	function SE.exec(src, label)
		label = label or "exec"
		-- save to history
		if src and src:match("%S") then
			-- deduplicate: remove old copy if same script
			for i = #SE.history, 1, -1 do
				if SE.history[i] == src then
					table.remove(SE.history, i)
					break
				end
			end
			table.insert(SE.history, 1, src)
			if #SE.history > SE.MAX_HISTORY then
				SE.history[SE.MAX_HISTORY + 1] = nil
			end
		end

		pushOutput("exec", (">>> Running: %s"):format(label))
		local fn, loadErr = loadstring(src, "=" .. label)
		if not fn then
			pushOutput("error", "Syntax: " .. tostring(loadErr))
			return false, loadErr
		end

		if setfenv then
			setfenv(fn, makeEnv())
		end

		local results = table.pack(pcall(fn))
		local ok = table.remove(results, 1)
		if not ok then
			local msg = tostring(results[1])
			pushOutput("error", msg)
			return false, msg
		end

		if results.n > 0 then
			local parts = {}
			for i = 1, results.n do
				parts[#parts + 1] = U.ser(results[i])
			end
			pushOutput("result", "=> " .. table.concat(parts, ", "))
		else
			pushOutput("ok", "Done.")
		end
		return true
	end

	-- Quick invoke a RemoteFunction with parsed args
	function SE.invokeRemote(path, argsSource)
		local parts = {}
		for seg in path:gmatch("[^%.]+") do parts[#parts + 1] = seg end
		local obj = game
		for _, seg in ipairs(parts) do
			local ok, next = pcall(function()
				local svc = pcall(function() return game:GetService(seg) end)
				return obj:FindFirstChild(seg) or (svc and game:GetService(seg)) or obj[seg]
			end)
			if not ok or not next then
				return false, "path not found: " .. seg
			end
			obj = next
		end
		if typeof(obj) ~= "Instance" then
			return false, "not an Instance"
		end
		-- parse args via loadstring
		local argFn, err = loadstring("return " .. (argsSource or ""))
		if not argFn then
			return false, "bad args: " .. tostring(err)
		end
		local argOk, args = pcall(argFn)
		if not argOk then
			return false, "args error: " .. tostring(args)
		end
		if type(args) ~= "table" then args = { args } end
		local callOk, result = pcall(function()
			if obj.ClassName == "RemoteFunction" then
				return obj:InvokeServer(table.unpack(args))
			elseif obj.ClassName == "RemoteEvent" then
				obj:FireServer(table.unpack(args))
				return "(FireServer sent)"
			elseif obj.ClassName == "BindableFunction" then
				return obj:Invoke(table.unpack(args))
			elseif obj.ClassName == "BindableEvent" then
				obj:Fire(table.unpack(args))
				return "(Fire sent)"
			else
				return false, "not a Remote/Bindable"
			end
		end)
		if not callOk then
			return false, tostring(result)
		end
		return true, result
	end

	return SE
end
