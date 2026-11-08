-- Heap bridge. Uses allocm/readmem/writemem when the executor provides them and they
-- pass a self-test; otherwise falls back to Luau `buffer` blocks. Handles are kept in the
-- registry bridge so they persist across re-execution.
return function(RCE)
	local E = RCE.require("src/core/Env.lua")
	local Registry = RCE.require("src/core/Registry.lua")
	local HttpService = game:GetService("HttpService")
	local M = {}

	local function probeNative()
		if not (E.allocm and E.readmem and E.writemem) then
			return false
		end
		return (pcall(function()
			local a = E.allocm(16)
			E.writemem(a, "RCE!")
			assert(E.readmem(a, 4) == "RCE!")
			if E.freem then
				E.freem(a)
			end
		end))
	end

	M.native = probeNative()
	M.backend = M.native and "native allocm/readmem/writemem" or "luau buffer (fallback)"

	local fakeBase = 0x10000000
	local function newHandle(name, size)
		if M.native then
			return { name = name, size = size, native = true, addr = E.allocm(size) }
		end
		local n = (Registry.get("heap_counter") or 0) + 1
		Registry.set("heap_counter", n)
		return { name = name, size = size, buf = buffer.create(size), addr = fakeBase + n * 0x1000 }
	end

	function M.get(name)
		return Registry.get("heap:" .. name)
	end

	function M.names()
		local out = {}
		for _, k in ipairs(Registry.keys("heap:")) do
			out[#out + 1] = k:sub(6)
		end
		return out
	end

	function M.alloc(name, size)
		local h = M.get(name)
		if h and h.size >= size then
			return h
		end
		if h then
			M.free(name)
		end
		h = newHandle(name, size)
		Registry.set("heap:" .. name, h)
		return h
	end

	function M.read(h, offset, len)
		if h.native then
			return E.readmem(h.addr + offset, len)
		end
		return buffer.readstring(h.buf, offset, len)
	end

	function M.write(h, offset, data)
		assert(offset >= 0 and offset + #data <= h.size, "write out of bounds")
		if h.native then
			return E.writemem(h.addr + offset, data)
		end
		buffer.writestring(h.buf, offset, data)
	end

	function M.free(name)
		local h = M.get(name)
		if not h then
			return
		end
		if h.native and E.freem then
			pcall(E.freem, h.addr)
		end
		Registry.set("heap:" .. name, nil)
	end

	-- JSON blob persistence:  [u32 length][json]
	function M.save(name, data)
		local json = HttpService:JSONEncode(data)
		local h = M.get(name)
		if not h or h.size < #json + 4 then
			h = M.alloc(name, math.max((#json + 4) * 2, 1024))
		end
		M.write(h, 0, string.pack("<I4", #json) .. json)
	end

	function M.load(name)
		local h = M.get(name)
		if not h then
			return nil
		end
		local ok, res = pcall(function()
			local n = string.unpack("<I4", M.read(h, 0, 4))
			if n <= 0 or n > h.size - 4 then
				return nil
			end
			return HttpService:JSONDecode(M.read(h, 4, n))
		end)
		return ok and res or nil
	end

	return M
end
