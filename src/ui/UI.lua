-- Dark, classic-debugger style UI: Memory | GC Closures | Bytecode | Hooks
return function(RCE)
	local E = RCE.require("src/core/Env.lua")
	local U = RCE.require("src/core/Util.lua")
	local Memory = RCE.require("src/core/Memory.lua")
	local GC = RCE.require("src/modules/GC.lua")
	local VS = RCE.require("src/modules/ValueScan.lua")
	local Hooks = RCE.require("src/modules/Hooks.lua")
	local BC = RCE.require("src/modules/Bytecode.lua")

	local UIS = game:GetService("UserInputService")
	local UI = {}

	local C = {
		bg = Color3.fromRGB(30, 30, 30), panel = Color3.fromRGB(37, 37, 38), row = Color3.fromRGB(51, 51, 55),
		sel = Color3.fromRGB(9, 71, 113), line = Color3.fromRGB(67, 67, 70), text = Color3.fromRGB(212, 212, 212),
		dim = Color3.fromRGB(128, 128, 128), accent = Color3.fromRGB(86, 156, 214), good = Color3.fromRGB(78, 201, 176),
		warn = Color3.fromRGB(220, 220, 170), bad = Color3.fromRGB(244, 71, 71),
	}
	local FONT = Enum.Font.Code
	local U2 = UDim2.new

	local statusLabel
	local function setStatus(msg, color)
		if statusLabel then
			statusLabel.Text = " " .. tostring(msg)
			statusLabel.TextColor3 = color or C.dim
		end
	end

	---------------------------------------------------------------- widgets
	local function mk(class, props, parent)
		local o = Instance.new(class)
		for k, v in pairs(props) do
			o[k] = v
		end
		o.Parent = parent
		return o
	end

	local function label(parent, text, pos, size, color, align)
		return mk("TextLabel", {
			Position = pos, Size = size, BackgroundTransparency = 1, Text = text, TextColor3 = color or C.text,
			Font = FONT, TextSize = 12, TextXAlignment = align or Enum.TextXAlignment.Left,
		}, parent)
	end

	local function button(parent, text, pos, size, cb)
		local b = mk("TextButton", {
			Position = pos, Size = size, BackgroundColor3 = C.row, BorderSizePixel = 0, Text = text,
			TextColor3 = C.text, Font = FONT, TextSize = 12, AutoButtonColor = true,
		}, parent)
		b.Activated:Connect(function()
			local ok, err = pcall(cb, b)
			if not ok then
				setStatus("error: " .. tostring(err), C.bad)
			end
		end)
		return b
	end

	local function input(parent, placeholder, pos, size)
		local t = mk("TextBox", {
			Position = pos, Size = size, BackgroundColor3 = C.row, BorderSizePixel = 0, Text = "",
			PlaceholderText = placeholder, PlaceholderColor3 = C.dim, TextColor3 = C.text, Font = FONT, TextSize = 12,
			ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left,
		}, parent)
		mk("UIPadding", { PaddingLeft = UDim.new(0, 5) }, t)
		return t
	end

	local function newList(parent, pos, size)
		local sf = mk("ScrollingFrame", {
			Position = pos, Size = size, BackgroundColor3 = C.panel, BorderSizePixel = 0, ScrollBarThickness = 6,
			ScrollBarImageColor3 = C.line, CanvasSize = U2(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
		}, parent)
		mk("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, sf)
		local L = { frame = sf, rows = {}, selected = nil, cap = 600, order = 0 }
		function L.add(text, color, onClick)
			L.order += 1
			local row = mk("TextButton", {
				Size = U2(1, -8, 0, 16), BackgroundColor3 = C.panel, BorderSizePixel = 0, Text = " " .. text,
				TextColor3 = color or C.text, Font = FONT, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd, AutoButtonColor = false, LayoutOrder = L.order,
			}, sf)
			row.Activated:Connect(function()
				if L.selected and L.selected.Parent then
					L.selected.BackgroundColor3 = C.panel
				end
				L.selected = row
				row.BackgroundColor3 = C.sel
				if onClick then
					local ok, err = pcall(onClick)
					if not ok then
						setStatus("error: " .. tostring(err), C.bad)
					end
				end
			end)
			L.rows[#L.rows + 1] = row
			if #L.rows > L.cap then
				local r = table.remove(L.rows, 1)
				if r == L.selected then
					L.selected = nil
				end
				r:Destroy()
			end
			return row
		end
		function L.clear()
			for _, r in ipairs(L.rows) do
				r:Destroy()
			end
			table.clear(L.rows)
			L.selected = nil
		end
		function L.toBottom()
			task.defer(function()
				sf.CanvasPosition = Vector2.new(0, 1e6)
			end)
		end
		return L
	end

	-- paged text viewer (keeps each TextLabel under Roblox's text length limit)
	local function newViewer(parent, pos, size)
		local holder = mk("Frame", { Position = pos, Size = size, BackgroundColor3 = C.panel, BorderSizePixel = 0 }, parent)
		local sf = mk("ScrollingFrame", {
			Size = U2(1, 0, 1, -18), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6,
			ScrollBarImageColor3 = C.line, CanvasSize = U2(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.XY,
			ScrollingDirection = Enum.ScrollingDirection.XY,
		}, holder)
		local txt = mk("TextLabel", {
			Size = U2(0, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.XY, BackgroundTransparency = 1, Text = "",
			TextColor3 = C.text, Font = FONT, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top, RichText = false,
		}, sf)
		mk("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingTop = UDim.new(0, 4) }, txt)
		local bar = mk("Frame", { Position = U2(0, 0, 1, -18), Size = U2(1, 0, 0, 18), BackgroundColor3 = C.row, BorderSizePixel = 0 }, holder)
		local V = { lines = {}, page = 1, PER = 100 }
		local pageLbl = label(bar, "", U2(0, 40, 0, 0), U2(1, -80, 1, 0), C.dim, Enum.TextXAlignment.Center)
		local function pages()
			return math.max(1, math.ceil(#V.lines / V.PER))
		end
		function V.render()
			local first = (V.page - 1) * V.PER + 1
			local last = math.min(first + V.PER - 1, #V.lines)
			local buf = {}
			for i = first, last do
				buf[#buf + 1] = U.trunc(V.lines[i], 140)
			end
			txt.Text = table.concat(buf, "\n")
			sf.CanvasPosition = Vector2.zero
			pageLbl.Text = ("page %d/%d  (%d lines)"):format(V.page, pages(), #V.lines)
		end
		function V.set(lines)
			V.lines = lines
			V.page = 1
			V.render()
		end
		function V.get()
			return table.concat(V.lines, "\n")
		end
		button(bar, "<", U2(0, 0, 0, 0), U2(0, 38, 1, 0), function()
			V.page = math.max(1, V.page - 1)
			V.render()
		end)
		button(bar, ">", U2(1, -38, 0, 0), U2(0, 38, 1, 0), function()
			V.page = math.min(pages(), V.page + 1)
			V.render()
		end)
		return V
	end

	---------------------------------------------------------------- Memory tab
	local function buildMemory(page, restore)
		local left = mk("Frame", { Size = U2(0.55, -2, 1, 0), BackgroundTransparency = 1 }, page)
		local right = mk("Frame", { Position = U2(0.55, 2, 0, 0), Size = U2(0.45, -2, 1, 0), BackgroundTransparency = 1 }, page)

		label(left, "VALUE SCANNER   (Lua heap: table fields + upvalues)", U2(0, 6, 0, 2), U2(1, -12, 0, 16), C.accent)
		local valueBox = input(left, "number to find", U2(0, 6, 0, 20), U2(1, -112, 0, 22))
		if restore and restore.value then
			valueBox.Text = tostring(restore.value)
		end
		local resultsList = newList(left, U2(0, 6, 0, 70), U2(1, -12, 1, -132))
		local countLbl = label(left, "0 results", U2(0, 6, 1, -28), U2(1, -12, 0, 16), C.dim)
		local sel

		local function refresh()
			resultsList.clear()
			sel = nil
			for i, e in ipairs(VS.results) do
				if i > 300 then
					resultsList.add(("... %d more, narrow with Next Scan"):format(#VS.results - 300), C.dim)
					break
				end
				resultsList.add(VS.describe(e), nil, function()
					sel = e
				end)
			end
			countLbl.Text = ("%d results%s"):format(#VS.results, VS.truncated and " (capped)" or "")
		end

		button(left, "First Scan", U2(1, -104, 0, 20), U2(0, 98, 0, 22), function()
			local v = tonumber(valueBox.Text)
			if not v then
				setStatus("enter a number first", C.warn)
				return
			end
			setStatus("scanning heap...", C.warn)
			local ok, err = VS.first(v)
			if not ok then
				setStatus(err, C.bad)
				return
			end
			refresh()
			setStatus(("first scan: %d hits"):format(#VS.results), C.good)
		end)

		local row = mk("Frame", { Position = U2(0, 6, 0, 46), Size = U2(1, -12, 0, 20), BackgroundTransparency = 1 }, left)
		mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 3) }, row)
		for _, m in ipairs({ { "Exact", "exact" }, { "Changed", "changed" }, { "Same", "same" }, { "Up", "inc" }, { "Down", "dec" } }) do
			button(row, m[1], U2(0, 0, 0, 0), U2(0.2, -3, 1, 0), function()
				VS.next(m[2], tonumber(valueBox.Text))
				refresh()
				setStatus(("next scan (%s): %d left"):format(m[2], #VS.results), C.good)
			end)
		end

		local setBox = input(left, "new value", U2(0, 6, 1, -54), U2(0.4, 0, 0, 22))
		button(left, "Set", U2(0.4, 10, 1, -54), U2(0.17, 0, 0, 22), function()
			local nv = tonumber(setBox.Text)
			if not sel or not nv then
				setStatus("select a result and enter a number", C.warn)
				return
			end
			local ok = VS.set(sel, nv)
			if ok then
				sel.last = nv
			end
			setStatus(ok and "value written" or "write failed", ok and C.good or C.bad)
		end)
		button(left, "Freeze", U2(0.57, 14, 1, -54), U2(0.17, 0, 0, 22), function()
			local nv = tonumber(setBox.Text)
			if not sel or not nv then
				setStatus("select a result and enter a number", C.warn)
				return
			end
			VS.freeze(sel, nv)
			setStatus("frozen (rewritten every frame)", C.good)
		end)
		button(left, "Thaw", U2(0.74, 18, 1, -54), U2(0.17, 0, 0, 22), function()
			if sel then
				VS.thaw(sel)
				setStatus("thawed", C.good)
			end
		end)

		-- heap bridge
		label(right, "HEAP   " .. Memory.backend, U2(0, 6, 0, 2), U2(1, -12, 0, 16), C.accent)
		local blockList = newList(right, U2(0, 6, 0, 20), U2(1, -12, 0, 70))
		local viewer = newViewer(right, U2(0, 6, 0, 120), U2(1, -12, 1, -184))
		local cur
		local function showBlock(name)
			cur = name
			local h = Memory.get(name)
			if not h then
				return
			end
			viewer.set(U.hexdump(Memory.read(h, 0, math.min(h.size, 512)), 0))
		end
		local function refreshBlocks()
			blockList.clear()
			for _, n in ipairs(Memory.names()) do
				local h = Memory.get(n)
				blockList.add(("%s  (%dB @ 0x%X)"):format(n, h.size, h.addr or 0), nil, function()
					showBlock(n)
				end)
			end
		end
		local scratchN = 0
		button(right, "New 256B", U2(0, 6, 0, 94), U2(0, 90, 0, 20), function()
			repeat
				scratchN += 1
			until not Memory.get("scratch" .. scratchN)
			Memory.alloc("scratch" .. scratchN, 256)
			refreshBlocks()
		end)
		button(right, "Refresh", U2(0, 100, 0, 94), U2(0, 80, 0, 20), function()
			refreshBlocks()
			if cur then
				showBlock(cur)
			end
		end)
		button(right, "Free", U2(0, 184, 0, 94), U2(0, 60, 0, 20), function()
			if cur and cur ~= "state" then
				Memory.free(cur)
				cur = nil
				viewer.set({})
				refreshBlocks()
			end
		end)
		local writeBox = input(right, "offset:HEXBYTES   e.g. 0:DEADBEEF", U2(0, 6, 1, -58), U2(1, -84, 0, 22))
		button(right, "Write", U2(1, -74, 1, -58), U2(0, 68, 0, 22), function()
			local h = cur and Memory.get(cur)
			local off, hex = writeBox.Text:match("^%s*(%d+)%s*:%s*(.+)$")
			if not h or not off then
				setStatus("select a block, then use offset:HEX", C.warn)
				return
			end
			Memory.write(h, tonumber(off), U.fromhex(hex))
			showBlock(cur)
			setStatus("bytes written", C.good)
		end)
		label(right, "persistence: " .. RCE.require("src/core/Registry.lua").backend, U2(0, 6, 1, -30), U2(1, -12, 0, 16), C.dim)
		refreshBlocks()

		return { value = function() return valueBox.Text end }
	end

	---------------------------------------------------------------- GC tab
	local openScript -- assigned after Bytecode tab is built

	local function buildGC(page, restore)
		local filter = input(page, "filter: name / path / k:constant", U2(0, 6, 0, 4), U2(0.36, 0, 0, 22))
		if restore and restore.filter then
			filter.Text = tostring(restore.filter)
		end
		local countLbl = label(page, "", U2(0.36, 170, 0, 4), U2(0.64, -176, 0, 22), C.dim)
		local list = newList(page, U2(0, 6, 0, 32), U2(0.5, -8, 1, -36))
		local viewer = newViewer(page, U2(0.5, 2, 0, 32), U2(0.5, -8, 1, -62))
		local sel

		local function render()
			list.clear()
			sel = nil
			for i, d in ipairs(GC.results) do
				if i > 600 then
					list.add(("... %d more, refine the filter"):format(#GC.results - 600), C.dim)
					break
				end
				local short = tostring(d.path):match("[^%.]+%.[^%.]+$") or tostring(d.path)
				list.add(("%s  %s:%d"):format(d.name, short, d.line), nil, function()
					sel = d
					viewer.set(GC.details(d))
				end)
			end
			countLbl.Text = ("%d closures  (blacklist: %d entries)"):format(#GC.results, #GC.blacklist)
		end

		button(page, "Scan", U2(0.36, 6, 0, 4), U2(0, 70, 0, 22), function()
			setStatus("crawling getgc()...", C.warn)
			local res, err = GC.scan(filter.Text, false)
			if not res then
				setStatus(err, C.bad)
				return
			end
			render()
			setStatus(("scan finished: %d closures"):format(#res), C.good)
		end)

		local auto = false
		local autoBtn
		autoBtn = button(page, "Auto: OFF", U2(0.36, 82, 0, 4), U2(0, 82, 0, 22), function()
			auto = not auto
			autoBtn.Text = auto and "Auto: ON" or "Auto: OFF"
			autoBtn.TextColor3 = auto and C.good or C.text
			if auto then
				task.spawn(function()
					while auto and statusLabel and statusLabel.Parent do
						GC.scan(filter.Text, true)
						render()
						task.wait(3)
					end
				end)
			end
		end)
		RCE.OnUnload(function()
			auto = false
		end)

		local bar = mk("Frame", { Position = U2(0.5, 2, 1, -28), Size = U2(0.5, -8, 0, 24), BackgroundTransparency = 1 }, page)
		mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 3) }, bar)
		button(bar, "Hook", U2(0, 0, 0, 0), U2(0.25, -3, 1, 0), function()
			if not sel then
				return
			end
			local ok, err = Hooks.hookClosure(sel.fn, sel.name .. " @ " .. tostring(sel.path))
			setStatus(ok and "hooked - calls appear in the Hooks tab" or tostring(err), ok and C.good or C.bad)
		end)
		button(bar, "Unhook", U2(0, 0, 0, 0), U2(0.25, -3, 1, 0), function()
			if sel then
				local ok, err = Hooks.unhook(sel.fn)
				setStatus(ok and "unhooked" or tostring(err), ok and C.good or C.warn)
			end
		end)
		button(bar, "Copy", U2(0, 0, 0, 0), U2(0.25, -3, 1, 0), function()
			setStatus(U.clip(viewer.get()) and "copied" or "setclipboard missing", C.good)
		end)
		button(bar, "Script>BC", U2(0, 0, 0, 0), U2(0.25, -3, 1, 0), function()
			if sel and sel.script then
				openScript(sel.script)
			else
				setStatus("no owning script for this closure", C.warn)
			end
		end)
		return { filter = function() return filter.Text end }
	end

	---------------------------------------------------------------- Bytecode tab
	local function buildBytecode(page)
		local filter = input(page, "filter scripts", U2(0, 6, 0, 4), U2(0.3, 0, 0, 22))
		local list = newList(page, U2(0, 6, 0, 32), U2(0.36, -8, 1, -36))
		local viewer = newViewer(page, U2(0.36, 2, 0, 32), U2(0.64, -8, 1, -36))
		local scripts, sel = {}, nil

		local function refresh()
			list.clear()
			table.clear(scripts)
			local f = filter.Text:lower()
			for _, s in ipairs(BC.listScripts()) do
				local p = U.pathOf(s)
				if not GC.isBlacklisted(p) and (f == "" or p:lower():find(f, 1, true)) then
					scripts[#scripts + 1] = { s = s, p = p }
				end
			end
			table.sort(scripts, function(a, b)
				return a.p < b.p
			end)
			for i, r in ipairs(scripts) do
				if i > 600 then
					list.add("... refine the filter", C.dim)
					break
				end
				list.add(("[%s] %s"):format(r.s.ClassName:sub(1, 1), r.p), nil, function()
					sel = r.s
				end)
			end
		end

		local function disasm(inst)
			sel = inst
			setStatus("disassembling " .. U.pathOf(inst) .. " ...", C.warn)
			local lines, err = BC.disassembleScript(inst)
			if not lines then
				viewer.set({ "error: " .. tostring(err) })
				setStatus(tostring(err), C.bad)
				return
			end
			viewer.set(lines)
			setStatus(("%d lines of disassembly"):format(#lines), C.good)
		end

		button(page, "Refresh", U2(0.3, 6, 0, 4), U2(0, 70, 0, 22), refresh)
		button(page, "Disassemble", U2(0.3, 80, 0, 4), U2(0, 100, 0, 22), function()
			if sel then
				disasm(sel)
			end
		end)
		button(page, "Decompile", U2(0.3, 184, 0, 4), U2(0, 90, 0, 22), function()
			if not sel then
				return
			end
			setStatus("decompiling...", C.warn)
			local lines, err = BC.decompileScript(sel)
			viewer.set(lines or { "error: " .. tostring(err) })
			setStatus(lines and "decompiled" or tostring(err), lines and C.good or C.bad)
		end)
		button(page, "Copy", U2(0.3, 278, 0, 4), U2(0, 60, 0, 22), function()
			setStatus(U.clip(viewer.get()) and "copied" or "setclipboard missing", C.good)
		end)
		refresh()

		return function(inst)
			disasm(inst)
		end
	end

	---------------------------------------------------------------- Hooks tab
	local function buildHooks(page)
		local t0 = os.clock()
		local list = newList(page, U2(0, 6, 0, 32), U2(0.45, -8, 1, -36))
		local viewer = newViewer(page, U2(0.45, 2, 0, 32), U2(0.55, -8, 1, -36))
		local KCOL = { remote = C.accent, require = C.good, hook = C.warn }

		local function addEntry(e)
			list.add(("%7.2f %-7s %s"):format(e.t - t0, e.kind, e.title), KCOL[e.kind], function()
				viewer.set(e.body)
			end)
			list.toBottom()
		end
		for _, e in ipairs(Hooks.log) do
			addEntry(e)
		end
		Hooks.onLog(function(e)
			if page.Parent then
				addEntry(e)
			end
		end)

		local function toggle(text, x, flag, installer)
			local b
			b = button(page, text .. ": OFF", U2(0, x, 0, 4), U2(0, 118, 0, 22), function()
				if not Hooks.flags[flag] then
					local ok, err = installer()
					if not ok then
						setStatus(tostring(err), C.bad)
						return
					end
				end
				Hooks.flags[flag] = not Hooks.flags[flag]
				b.Text = text .. (Hooks.flags[flag] and ": ON" or ": OFF")
				b.TextColor3 = Hooks.flags[flag] and C.good or C.text
			end)
		end
		toggle("Remotes", 6, "remote", Hooks.installRemote)
		toggle("require", 128, "require", Hooks.installRequire)
		local pauseBtn
		pauseBtn = button(page, "Pause", U2(0, 250, 0, 4), U2(0, 70, 0, 22), function()
			Hooks.flags.paused = not Hooks.flags.paused
			pauseBtn.Text = Hooks.flags.paused and "Paused" or "Pause"
			pauseBtn.TextColor3 = Hooks.flags.paused and C.warn or C.text
		end)
		button(page, "Clear", U2(0, 324, 0, 4), U2(0, 60, 0, 22), function()
			Hooks.clear()
			list.clear()
			viewer.set({})
		end)
		button(page, "Copy", U2(0, 388, 0, 4), U2(0, 60, 0, 22), function()
			setStatus(U.clip(viewer.get()) and "copied" or "setclipboard missing", C.good)
		end)
	end

	---------------------------------------------------------------- window
	function UI.Init()
		local parentGui = (E.gethui and E.gethui()) or game:GetService("CoreGui")
		local gui = mk("ScreenGui", {
			Name = "RCE_" .. math.random(100000, 999999), ResetOnSpawn = false, IgnoreGuiInset = true,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999999,
		}, parentGui)

		local W, H = 780, 500
		local win = mk("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = U2(0.5, 0, 0.5, 0), Size = U2(0, W, 0, H),
			BackgroundColor3 = C.bg, BorderSizePixel = 0, ClipsDescendants = true,
		}, gui)
		mk("UIStroke", { Color = C.line, Thickness = 1 }, win)

		local title = mk("Frame", { Size = U2(1, 0, 0, 24), BackgroundColor3 = Color3.fromRGB(45, 45, 48), BorderSizePixel = 0 }, win)
		label(title, "  R-CE  |  Roblox Cheat Engine  v" .. RCE.Version .. "   [RightShift: hide]", U2(0, 0, 0, 0), U2(1, -60, 1, 0), C.accent)

		local body = mk("Frame", { Position = U2(0, 0, 0, 24), Size = U2(1, 0, 1, -24), BackgroundTransparency = 1 }, win)
		local collapsed = false
		button(title, "-", U2(1, -52, 0, 2), U2(0, 24, 0, 20), function()
			collapsed = not collapsed
			body.Visible = not collapsed
			win.Size = collapsed and U2(0, W, 0, 24) or U2(0, W, 0, H)
		end)
		button(title, "x", U2(1, -26, 0, 2), U2(0, 24, 0, 20), function()
			RCE.Unload()
		end)

		-- drag
		local dragging, dragStart, startPos
		title.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				dragging, dragStart, startPos = true, i.Position, win.Position
			end
		end)
		title.InputEnded:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end)
		local c1 = UIS.InputChanged:Connect(function(i)
			if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
				local d = i.Position - dragStart
				win.Position = U2(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
			end
		end)
		local c2 = UIS.InputBegan:Connect(function(i, gp)
			if not gp and i.KeyCode == Enum.KeyCode.RightShift then
				gui.Enabled = not gui.Enabled
			end
		end)

		-- tabs + status
		local tabBar = mk("Frame", { Size = U2(1, 0, 0, 24), BackgroundColor3 = C.panel, BorderSizePixel = 0 }, body)
		mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 2) }, tabBar)
		local content = mk("Frame", { Position = U2(0, 0, 0, 26), Size = U2(1, 0, 1, -46), BackgroundTransparency = 1 }, body)
		statusLabel = mk("TextLabel", {
			Position = U2(0, 0, 1, -18), Size = U2(1, 0, 0, 18), BackgroundColor3 = Color3.fromRGB(0, 122, 204), BorderSizePixel = 0,
			Text = "", TextColor3 = C.text, Font = FONT, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, body)
		statusLabel.BackgroundColor3 = Color3.fromRGB(24, 24, 26)

		local pages, tabButtons = {}, {}
		local current
		local function select(name)
			current = name
			for n, p in pairs(pages) do
				p.Visible = n == name
				tabButtons[n].BackgroundColor3 = n == name and C.sel or C.row
			end
		end
		local function addTab(name)
			local p = mk("Frame", { Size = U2(1, 0, 1, 0), BackgroundTransparency = 1, Visible = false }, content)
			pages[name] = p
			tabButtons[name] = button(tabBar, name, U2(0, 0, 0, 0), U2(0, 130, 1, 0), function()
				select(name)
			end)
			return p
		end

		local restore = Memory.load("state") or {}
		buildMemory(addTab("Memory"), restore)
		buildGC(addTab("GC Closures"), restore)
		local disasm = buildBytecode(addTab("Bytecode"))
		openScript = function(inst)
			select("Bytecode")
			disasm(inst)
		end
		buildHooks(addTab("Hooks"))
		select(restore.tab and pages[restore.tab] and restore.tab or "Memory")

		local have, miss = E.report()
		setStatus(("%d/%d capabilities%s"):format(#have, #have + #miss, #miss > 0 and ("  |  missing: " .. table.concat(miss, ", ")) or ""),
			#miss == 0 and C.good or C.warn)

		local memView = pages["Memory"]
		RCE.OnUnload(function()
			pcall(function()
				local st = { tab = current }
				for _, d in ipairs(memView:GetDescendants()) do
					if d:IsA("TextBox") and d.PlaceholderText == "number to find" then
						st.value = d.Text
					end
				end
				for _, d in ipairs(pages["GC Closures"]:GetDescendants()) do
					if d:IsA("TextBox") then
						st.filter = d.Text
						break
					end
				end
				Memory.save("state", st)
			end)
			c1:Disconnect()
			c2:Disconnect()
			gui:Destroy()
		end)

		U.log("R-CE v" .. RCE.Version .. " ready. RightShift toggles the window.")
	end

	return UI
end
