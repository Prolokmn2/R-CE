-- HttpSpy: intercepts game:HttpGet / HttpPost / HttpRequestAsync (syn.request / http.request)
-- Based on techniques from Ketamine source: hook the HttpService metatable + executor http function
return function(RCE)
	local E = RCE.require("src/core/Env.lua")
	local U = RCE.require("src/core/Util.lua")
	local Registry = RCE.require("src/core/Registry.lua")

	local HS = {
		log = {},
		MAX = 1000,
		listeners = {},
		flags = { enabled = false, paused = false },
	}

	local shared = Registry.get("httpspy_shared")
	if type(shared) ~= "table" then
		shared = {}
		Registry.set("httpspy_shared", shared)
	end

	local nextId = 0
	local function push(method, url, body, headers, statusCode, responseBody)
		if HS.flags.paused then return end
		nextId += 1
		local e = {
			id = nextId,
			t = os.clock(),
			method = method,
			url = url,
			body = body,
			headers = headers or {},
			statusCode = statusCode,
			responseBody = responseBody,
		}
		HS.log[#HS.log + 1] = e
		if #HS.log > HS.MAX then table.remove(HS.log, 1) end
		for _, f in ipairs(HS.listeners) do pcall(f, e) end
	end

	function HS.onLog(f) table.insert(HS.listeners, f) end
	function HS.clear() table.clear(HS.log) end

	function HS.format(e)
		local lines = {
			("Method  : %s"):format(e.method),
			("URL     : %s"):format(e.url),
			("Time    : %.4f"):format(e.t),
		}
		if e.statusCode then
			lines[#lines + 1] = ("Status  : %s"):format(tostring(e.statusCode))
		end
		if e.body and e.body ~= "" then
			lines[#lines + 1] = "Request Body:"
			for chunk in (e.body .. "\n"):gmatch("([^\n]*)\n") do
				lines[#lines + 1] = "  " .. U.trunc(chunk, 200)
			end
		end
		if e.headers and next(e.headers) then
			lines[#lines + 1] = "Headers:"
			for k, v in pairs(e.headers) do
				lines[#lines + 1] = ("  %s: %s"):format(tostring(k), U.trunc(tostring(v), 100))
			end
		end
		if e.responseBody and e.responseBody ~= "" then
			lines[#lines + 1] = "Response (first 500 chars):"
			local rb = tostring(e.responseBody)
			local chunk = rb:sub(1, 500)
			for line in (chunk .. "\n"):gmatch("([^\n]*)\n") do
				lines[#lines + 1] = "  " .. line
			end
			if #rb > 500 then lines[#lines + 1] = "  ... (truncated)" end
		end
		return lines
	end

	function HS.install()
		local installed = false

		-- Hook HttpService __namecall (HttpGet, HttpPost, GetAsync, PostAsync, RequestAsync)
		if E.hookmetamethod and E.getnamecallmethod then
			shared.httpSink = function(method, url, body, headers, statusCode, resp)
				if HS.flags.enabled then
					task.defer(push, method, url, body, headers, statusCode, resp)
				end
			end
			if not shared.httpInstalled then
				local hs = game:GetService("HttpService")
				local old
				local ok = pcall(function()
					old = E.hookmetamethod(game, "__namecall", function(self, ...)
						local method = E.getnamecallmethod()
						local HTTP_METHODS = {
							HttpGet = true, HttpPost = true, GetAsync = true,
							PostAsync = true, RequestAsync = true,
						}
						local sink = shared.httpSink
						if sink and HTTP_METHODS[method] and self == hs then
							if not (E.checkcaller and E.checkcaller()) then
								local args = table.pack(...)
								local ok2, result = pcall(old, self, ...)
								local url = typeof(args[1]) == "string" and args[1]
									or (typeof(args[1]) == "table" and args[1].Url) or "?"
								local body = typeof(args[1]) == "table" and args[1].Body or
									(args[2] and typeof(args[2]) == "string" and args[2]) or ""
								local hdrs = typeof(args[1]) == "table" and args[1].Headers or {}
								local status, resp = nil, nil
								if ok2 then
									if type(result) == "table" then
										status = result.StatusCode
										resp = result.Body
									elseif type(result) == "string" then
										resp = result
									end
								end
								sink(method, url, body, hdrs, status, resp)
								if ok2 then return result else error(result, 0) end
							end
						end
						if E.setnamecallmethod then E.setnamecallmethod(method) end
						return old(self, ...)
					end)
				end)
				if ok then
					shared.httpInstalled = true
					installed = true
				end
			else
				installed = true
			end
		end

		-- Hook executor http functions (syn.request, http.request, request)
		local httpFuncs = {}
		if getgenv then
			local g = getgenv()
			if type(g.syn) == "table" and type(g.syn.request) == "function" then
				httpFuncs[#httpFuncs + 1] = { name = "syn.request", fn = g.syn.request,
					set = function(f) g.syn.request = f end }
			end
			if type(g.http) == "table" and type(g.http.request) == "function" then
				httpFuncs[#httpFuncs + 1] = { name = "http.request", fn = g.http.request,
					set = function(f) g.http.request = f end }
			end
			if type(g.request) == "function" then
				httpFuncs[#httpFuncs + 1] = { name = "request", fn = g.request,
					set = function(f) g.request = f end }
			end
		end
		for _, h in ipairs(httpFuncs) do
			if not shared["http_hooked_" .. h.name] then
				local old = h.fn
				local name = h.name
				h.set(function(opts)
					local result = table.pack(pcall(old, opts))
					local ok2 = table.remove(result, 1)
					local sink = shared.httpSink
					if sink and HS.flags.enabled and type(opts) == "table" then
						local resp = result[1]
						sink(name, opts.Url or opts.url or "?",
							opts.Body or opts.body or "",
							opts.Headers or opts.headers or {},
							type(resp) == "table" and resp.StatusCode or nil,
							type(resp) == "table" and resp.Body or nil)
					end
					if ok2 then
						return table.unpack(result, 1, result.n)
					else
						error(result[1], 0)
					end
				end)
				shared["http_hooked_" .. name] = true
				installed = true
			else
				installed = true
			end
		end

		if not installed then
			return false, "no hookable http methods found (needs hookmetamethod or executor http functions)"
		end
		return true
	end

	RCE.OnUnload(function()
		HS.flags.enabled = false
		shared.httpSink = nil
	end)

	return HS
end
