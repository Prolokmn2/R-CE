return function(RCE)
	local U = {}

	function U.trunc(s, n)
		s = tostring(s)
		if #s > n then
			return s:sub(1, n - 3) .. "..."
		end
		return s
	end

	function U.pathOf(inst)
		local ok, p = pcall(function()
			return inst:GetFullName()
		end)
		return ok and p or tostring(inst)
	end

	local function quote(s)
		if #s > 200 then
			s = s:sub(1, 200) .. "..."
		end
		return '"' .. (s:gsub('[%c"\\]', function(c)
			return "\\" .. string.byte(c)
		end)) .. '"'
	end

	-- compact, cycle-safe, depth-limited serializer for logs
	function U.ser(v, depth, seen)
		depth = depth or 0
		local t = typeof(v)
		if t == "string" then
			return quote(v)
		elseif t == "number" or t == "boolean" or t == "nil" then
			return tostring(v)
		elseif t == "Instance" then
			return ("%s<%s>"):format(v.ClassName, U.pathOf(v))
		elseif t == "function" then
			local ok, name = pcall(debug.info, v, "n")
			return "function:" .. ((ok and name and name ~= "") and name or "anonymous")
		elseif t == "table" then
			seen = seen or {}
			if seen[v] then
				return "<cycle>"
			end
			if depth >= 3 then
				return "{...}"
			end
			seen[v] = true
			local parts, n = {}, 0
			for k, val in next, v do
				n += 1
				if n > 25 then
					parts[#parts + 1] = "..."
					break
				end
				local ks
				if type(k) == "string" and k:match("^[%a_][%w_]*$") then
					ks = k
				else
					ks = "[" .. U.ser(k, depth + 1, seen) .. "]"
				end
				parts[#parts + 1] = ks .. " = " .. U.ser(val, depth + 1, seen)
			end
			seen[v] = nil
			return "{" .. table.concat(parts, ", ") .. "}"
		end
		return t .. ":" .. tostring(v)
	end

	function U.hexdump(s, base)
		local lines = {}
		for i = 1, #s, 16 do
			local chunk = s:sub(i, i + 15)
			local hex = chunk:gsub(".", function(c)
				return string.format("%02X ", string.byte(c))
			end)
			local asc = chunk:gsub("[^\32-\126]", ".")
			lines[#lines + 1] = string.format("%08X  %-48s |%s|", (base or 0) + i - 1, hex, asc)
		end
		return lines
	end

	function U.fromhex(h)
		h = h:gsub("[^%x]", "")
		if #h % 2 == 1 then
			h = h .. "0"
		end
		return (h:gsub("%x%x", function(x)
			return string.char(tonumber(x, 16))
		end))
	end

	function U.clip(text)
		local E = RCE.require("src/core/Env.lua")
		if E.setclipboard then
			return pcall(E.setclipboard, text)
		end
		return false
	end

	function U.log(msg)
		print("[R-CE] " .. tostring(msg))
	end

	return U
end
