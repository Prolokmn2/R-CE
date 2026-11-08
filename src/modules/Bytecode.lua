-- Luau bytecode parser + disassembler (opcode names, operands, constants, jump targets, line info).
-- Handles Roblox's client-encoded opcodes (x227) as well as plain Luau bytecode (auto-detected).
return function(RCE)
	local E = RCE.require("src/core/Env.lua")
	local U = RCE.require("src/core/Util.lua")
	local B = {}

	-- NAME:KIND  (+ = has AUX word). Index in this list == opcode number (current Luau layout).
	local OPLIST = "NOP:-,BREAK:-,LOADNIL:A,LOADB:ABC,LOADN:AD,LOADK:AD,MOVE:AB,GETGLOBAL:AC+,SETGLOBAL:AC+,GETUPVAL:AB,SETUPVAL:AB,CLOSEUPVALS:A,GETIMPORT:AD+,GETTABLE:ABC,SETTABLE:ABC,GETTABLEKS:ABC+,SETTABLEKS:ABC+,GETTABLEN:ABC,SETTABLEN:ABC,NEWCLOSURE:AD,NAMECALL:ABC+,CALL:ABC,RETURN:AB,JUMP:D,JUMPBACK:D,JUMPIF:AD,JUMPIFNOT:AD,JUMPIFEQ:AD+,JUMPIFLE:AD+,JUMPIFLT:AD+,JUMPIFNOTEQ:AD+,JUMPIFNOTLE:AD+,JUMPIFNOTLT:AD+,ADD:ABC,SUB:ABC,MUL:ABC,DIV:ABC,MOD:ABC,POW:ABC,ADDK:ABC,SUBK:ABC,MULK:ABC,DIVK:ABC,MODK:ABC,POWK:ABC,AND:ABC,OR:ABC,ANDK:ABC,ORK:ABC,CONCAT:ABC,NOT:AB,MINUS:AB,LENGTH:AB,NEWTABLE:AB+,DUPTABLE:AD,SETLIST:ABC+,FORNPREP:AD,FORNLOOP:AD,FORGLOOP:AD+,FORGPREP_INEXT:AD,FASTCALL3:ABC+,FORGPREP_NEXT:AD,NATIVECALL:-,GETVARARGS:AB,DUPCLOSURE:AD,PREPVARARGS:A,LOADKX:A+,JUMPX:E,FASTCALL:AC,COVERAGE:E,CAPTURE:AB,SUBRK:ABC,DIVRK:ABC,FASTCALL1:ABC,FASTCALL2:ABC+,FASTCALL2K:ABC+,FORGPREP:AD,JUMPXEQKNIL:AD+,JUMPXEQKB:AD+,JUMPXEQKN:AD+,JUMPXEQKS:AD+,IDIV:ABC,IDIVK:ABC"

	local OPS = {}
	do
		local i = 0
		for name, kind in OPLIST:gmatch("([%w_]+):([%w%-%+]+)") do
			OPS[i] = { name = "OP_" .. name, kind = (kind:gsub("%+", "")), aux = kind:find("+", 1, true) ~= nil }
			i += 1
		end
	end
	B.OPS = OPS

	local JUMPD = {}
	for _, n in ipairs({
		"JUMP", "JUMPBACK", "JUMPIF", "JUMPIFNOT", "JUMPIFEQ", "JUMPIFLE", "JUMPIFLT", "JUMPIFNOTEQ", "JUMPIFNOTLE",
		"JUMPIFNOTLT", "FORNPREP", "FORNLOOP", "FORGLOOP", "FORGPREP_INEXT", "FORGPREP_NEXT", "FORGPREP",
		"JUMPXEQKNIL", "JUMPXEQKB", "JUMPXEQKN", "JUMPXEQKS",
	}) do
		JUMPD["OP_" .. n] = true
	end

	---------------------------------------------------------------- parser
	function B.parse(bytes)
		local pos = 1
		local function byte()
			local b = string.byte(bytes, pos)
			if not b then
				error("unexpected end of bytecode", 0)
			end
			pos += 1
			return b
		end
		local function varint()
			local v, shift = 0, 0
			while true do
				local b = byte()
				v += (b % 128) * 2 ^ shift
				if b < 128 then
					break
				end
				shift += 7
			end
			return v
		end
		local function u32()
			local v = string.unpack("<I4", bytes, pos)
			pos += 4
			return v
		end
		local function i32()
			local v = string.unpack("<i4", bytes, pos)
			pos += 4
			return v
		end
		local function f64()
			local v = string.unpack("<d", bytes, pos)
			pos += 8
			return v
		end
		local function f32()
			local v = string.unpack("<f", bytes, pos)
			pos += 4
			return v
		end

		local version = byte()
		if version == 0 then
			error("compile error blob: " .. bytes:sub(2, 200), 0)
		end
		local types = 0
		if version >= 4 then
			types = byte()
		end

		local strs = {}
		for i = 1, varint() do
			local n = varint()
			strs[i] = bytes:sub(pos, pos + n - 1)
			pos += n
		end
		if types >= 3 then
			while byte() ~= 0 do
				varint()
			end
		end

		local protos = {}
		for pi = 1, varint() do
			local p = { id = pi - 1 }
			local protoSize, protoStart = 0, 0
			if version >= 12 then
				protoSize = varint()
			end
			protoStart = pos
			p.maxstack, p.numparams, p.nups = byte(), byte(), byte()
			p.vararg = byte() ~= 0
			if version >= 4 then
				p.flags = byte()
				pos += varint() -- skip type info
			end
			local sizecode = varint()
			p.code = table.create(sizecode)
			for j = 1, sizecode do
				p.code[j] = u32()
			end
			p.k = {}
			for j = 1, varint() do
				local t = byte()
				local k
				if t == 0 then
					k = { t = "nil" }
				elseif t == 1 then
					k = { t = "boolean", v = byte() ~= 0 }
				elseif t == 2 then
					k = { t = "number", v = f64() }
				elseif t == 3 then
					k = { t = "string", v = strs[varint()] }
				elseif t == 4 then
					k = { t = "import", v = u32() }
				elseif t == 5 then
					local keys = {}
					for q = 1, varint() do
						keys[q] = varint()
					end
					k = { t = "table", keys = keys }
				elseif t == 6 then
					k = { t = "closure", v = varint() }
				elseif t == 8 then -- table with constant values (v7+)
					local keys = {}
					for q = 1, varint() do
						keys[q] = varint()
						i32()
					end
					k = { t = "table", keys = keys }
				elseif t == 9 then -- 64-bit integer (v8+)
					local neg = byte() ~= 0
					local v, shift = 0, 0
					while true do
						local b = byte()
						v += (b % 128) * 2 ^ shift
						if b < 128 then
							break
						end
						shift += 7
					end
					k = { t = "integer", v = neg and -v or v }
				elseif t == 11 then -- double vector
					k = { t = "vector", v = { f64(), f64(), f64(), f64() } }
				elseif t == 7 then
					k = { t = "vector", v = { f32(), f32(), f32(), f32() } }
				else
					error("unknown constant type " .. t, 0)
				end
				p.k[j] = k
			end
			p.children = {}
			for j = 1, varint() do
				p.children[j] = varint()
			end
			p.linedefined = varint()
			local dn = varint()
			p.name = dn ~= 0 and strs[dn] or nil

			if byte() ~= 0 then -- line info
				p.gap = byte()
				local intervals = math.floor((sizecode - 1) / 2 ^ p.gap) + 1
				p.lineinfo = {}
				local last = 0
				for j = 1, sizecode do
					last = (last + byte()) % 256
					p.lineinfo[j] = last
				end
				p.abs = {}
				local lastline = 0
				for j = 1, intervals do
					lastline += i32()
					p.abs[j] = lastline
				end
			end
			p.upnames = {}
			if byte() ~= 0 then -- debug info
				for _ = 1, varint() do
					varint() varint() varint() byte()
				end
				for j = 1, varint() do
					p.upnames[j] = strs[varint()]
				end
			end
			if version == 11 then
				for _ = 1, varint() do
					byte()
					varint()
				end
			elseif version >= 12 then
				pos = protoStart + protoSize -- skips feedback vector / cost / unknown trailing data
			end
			protos[pi] = p
		end
		local main = varint()
		return { version = version, types = types, strings = strs, protos = protos, main = main }
	end

	---------------------------------------------------------------- disassembler
	local function chooseMul(bc)
		local best, bestBad = 1, math.huge
		for _, mul in ipairs({ 203, 1 }) do
			local bad = 0
			for _, p in ipairs(bc.protos) do
				local pc = 1
				while pc <= #p.code do
					local def = OPS[(p.code[pc] % 256) * mul % 256]
					if not def then
						bad += 1
						pc += 1
					else
						pc += def.aux and 2 or 1
					end
				end
			end
			if bad < bestBad then
				best, bestBad = mul, bad
			end
		end
		return best
	end

	local function kstr(p, idx)
		local k = p.k[idx + 1]
		if not k then
			return ("K[%d]=?"):format(idx)
		end
		local t = k.t
		if t == "string" then
			return ("K[%d] %s"):format(idx, U.ser(k.v))
		elseif t == "number" then
			return ("K[%d] %.14g"):format(idx, k.v)
		elseif t == "boolean" then
			return ("K[%d] %s"):format(idx, tostring(k.v))
		elseif t == "nil" then
			return ("K[%d] nil"):format(idx)
		elseif t == "vector" then
			return ("K[%d] vector(%g,%g,%g,%g)"):format(idx, k.v[1], k.v[2], k.v[3], k.v[4])
		elseif t == "closure" then
			return ("K[%d] closure proto #%d"):format(idx, k.v)
		elseif t == "integer" then
			return ("K[%d] %d (int64)"):format(idx, k.v)
		end
		return ("K[%d] <%s>"):format(idx, t)
	end

	local function importName(p, aux)
		local n = math.floor(aux / 2 ^ 30)
		local parts = {}
		for s = 1, n do
			local idx = math.floor(aux / 2 ^ (30 - 10 * s)) % 1024
			local k = p.k[idx + 1]
			parts[#parts + 1] = (k and k.t == "string") and k.v or "?"
		end
		return table.concat(parts, ".")
	end

	local function lineAt(p, pc0)
		if not p.abs then
			return nil
		end
		return p.abs[math.floor(pc0 / 2 ^ p.gap) + 1] + p.lineinfo[pc0 + 1]
	end

	local KOP_C = { OP_ADDK = true, OP_SUBK = true, OP_MULK = true, OP_DIVK = true, OP_MODK = true, OP_POWK = true, OP_ANDK = true, OP_ORK = true, OP_IDIVK = true }

	function B.disassemble(bytes)
		local okp, bc = pcall(B.parse, bytes)
		if not okp then
			return nil, tostring(bc)
		end
		local mul = chooseMul(bc)
		local out = {
			("; R-CE Luau disassembly | bytecode v%d, types v%d | %d protos | opcode key x%d"):format(bc.version, bc.types, #bc.protos, mul),
		}
		for pi, p in ipairs(bc.protos) do
			out[#out + 1] = ""
			out[#out + 1] = ("; ---- proto #%d%s%s | params=%d upvals=%d stack=%d vararg=%s | defined line %d ----"):format(
				p.id, p.name and (" '" .. p.name .. "'") or "", (p.id == bc.main) and " (main)" or "",
				p.numparams, p.nups, p.maxstack, tostring(p.vararg), p.linedefined
			)
			if #p.k > 0 then
				out[#out + 1] = "; constants:"
				for j = 1, #p.k do
					out[#out + 1] = ";   " .. kstr(p, j - 1)
				end
			end
			local pc = 1
			while pc <= #p.code do
				local raw = p.code[pc]
				local idx0 = pc - 1
				local ln = lineAt(p, idx0)
				local lns = ln and ("L" .. ln) or ""
				local def = OPS[(raw % 256) * mul % 256]
				if not def then
					out[#out + 1] = ("[%04d] %-6s ???  raw=%08X"):format(idx0, lns, raw)
					pc += 1
				else
					local A = math.floor(raw / 256) % 256
					local Bv = math.floor(raw / 65536) % 256
					local Cv = math.floor(raw / 16777216)
					local D = math.floor(raw / 65536)
					if D >= 32768 then
						D -= 65536
					end
					local Ev = math.floor(raw / 256)
					if Ev >= 8388608 then
						Ev -= 16777216
					end
					local aux = def.aux and p.code[pc + 1] or nil
					local kind, ops = def.kind, ""
					if kind == "A" then ops = "A=" .. A
					elseif kind == "AB" then ops = ("A=%d B=%d"):format(A, Bv)
					elseif kind == "AC" then ops = ("A=%d C=%d"):format(A, Cv)
					elseif kind == "ABC" then ops = ("A=%d B=%d C=%d"):format(A, Bv, Cv)
					elseif kind == "AD" then ops = ("A=%d D=%d"):format(A, D)
					elseif kind == "D" then ops = "D=" .. D
					elseif kind == "E" then ops = "E=" .. Ev end
					if aux then
						ops ..= (" AUX=0x%X"):format(aux)
					end

					local n, cm = def.name, nil
					if n == "OP_LOADK" or n == "OP_DUPTABLE" or n == "OP_DUPCLOSURE" then
						cm = kstr(p, D)
					elseif n == "OP_GETGLOBAL" or n == "OP_SETGLOBAL" or n == "OP_GETTABLEKS" or n == "OP_SETTABLEKS" or n == "OP_NAMECALL" then
						cm = kstr(p, aux)
					elseif n == "OP_GETIMPORT" then
						cm = importName(p, aux)
					elseif KOP_C[n] then
						cm = kstr(p, Cv)
					elseif n == "OP_SUBRK" or n == "OP_DIVRK" then
						cm = kstr(p, Bv)
					elseif n == "OP_NEWCLOSURE" then
						cm = "proto #" .. tostring(p.children[D + 1])
					elseif n == "OP_CALL" then
						cm = ("args=%s returns=%s"):format(Bv == 0 and "multi" or Bv - 1, Cv == 0 and "multi" or Cv - 1)
					elseif n == "OP_GETUPVAL" or n == "OP_SETUPVAL" then
						cm = "upvalue " .. (p.upnames[Bv + 1] or tostring(Bv))
					elseif n == "OP_LOADB" then
						cm = tostring(Bv ~= 0)
					elseif n == "OP_JUMPX" then
						cm = ("-> [%04d]"):format(idx0 + Ev + 1)
					elseif JUMPD[n] then
						cm = ("-> [%04d]"):format(idx0 + D + 1)
						if n == "OP_JUMPXEQKN" or n == "OP_JUMPXEQKS" then
							cm ..= "  " .. kstr(p, aux % 16777216)
						end
					end
					out[#out + 1] = ("[%04d] %-6s %-18s %-26s%s"):format(idx0, lns, def.name, ops, cm and ("; " .. cm) or "")
					pc += def.aux and 2 or 1
				end
			end
		end
		return out, bc
	end

	---------------------------------------------------------------- script helpers
	function B.listScripts()
		local out, seen = {}, {}
		for _, fname in ipairs({ "getscripts", "getloadedmodules" }) do
			local f = E[fname]
			if f then
				local ok, res = pcall(f)
				if ok and type(res) == "table" then
					for _, s in ipairs(res) do
						if not seen[s] then
							seen[s] = true
							out[#out + 1] = s
						end
					end
				end
			end
		end
		return out
	end

	function B.disassembleScript(inst)
		if not E.getscriptbytecode then
			return nil, "getscriptbytecode missing"
		end
		local ok, bytes = pcall(E.getscriptbytecode, inst)
		if not ok or type(bytes) ~= "string" or #bytes == 0 then
			return nil, "no bytecode: " .. tostring(bytes)
		end
		return B.disassemble(bytes)
	end

	function B.decompileScript(inst)
		if not E.decompile then
			return nil, "decompile missing"
		end
		local ok, src = pcall(E.decompile, inst)
		if not ok then
			return nil, tostring(src)
		end
		local lines = {}
		for l in (tostring(src) .. "\n"):gmatch("(.-)\n") do
			lines[#lines + 1] = l
		end
		return lines
	end

	return B
end
