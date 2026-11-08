-- R-CE v2 UI: Memory | GC Closures | Bytecode | Hooks | Remote Spy | HTTP Spy | Event Spy | Exec | Explorer | Live View
return function(RCE)
	local E = RCE.require("src/core/Env.lua")
	local U = RCE.require("src/core/Util.lua")
	local Memory = RCE.require("src/core/Memory.lua")
	local GC = RCE.require("src/modules/GC.lua")
	local VS = RCE.require("src/modules/ValueScan.lua")
	local Hooks = RCE.require("src/modules/Hooks.lua")
	local BC = RCE.require("src/modules/Bytecode.lua")
	local RS = RCE.require("src/modules/RemoteSpy.lua")
	local HS = RCE.require("src/modules/HttpSpy.lua")
	local ES = RCE.require("src/modules/EventSpy.lua")
	local SE = RCE.require("src/modules/ScriptExec.lua")
	local EX = RCE.require("src/modules/Explorer.lua")
	local LV = RCE.require("src/modules/LiveView.lua")

	-- Wire LiveView to all modules
	LV.wire()

	local UIS = game:GetService("UserInputService")
	local UI = {}

	local C = {
		bg    = Color3.fromRGB(18, 18, 20),
		panel = Color3.fromRGB(28, 28, 32),
		row   = Color3.fromRGB(42, 42, 48),
		sel   = Color3.fromRGB(0, 80, 160),
		line  = Color3.fromRGB(55, 55, 65),
		text  = Color3.fromRGB(220, 220, 225),
		dim   = Color3.fromRGB(120, 120, 130),
		accent= Color3.fromRGB(86, 156, 214),
		good  = Color3.fromRGB(78, 201, 176),
		warn  = Color3.fromRGB(220, 200, 100),
		bad   = Color3.fromRGB(244, 71, 71),
		remote= Color3.fromRGB(100, 180, 255),
		http  = Color3.fromRGB(180, 100, 255),
		event = Color3.fromRGB(255, 180, 60),
		hook  = Color3.fromRGB(255, 120, 80),
		exec  = Color3.fromRGB(120, 255, 120),
		tabBg = Color3.fromRGB(22, 22, 26),
		tabSel= Color3.fromRGB(0, 95, 185),
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

	-- ---------------------------------------------------------------- widgets
	local function mk(class, props, parent)
		local o = Instance.new(class)
		for k, v in pairs(props) do o[k] = v end
		o.Parent = parent
		return o
	end

	local function label(parent, text, pos, size, color, align)
		return mk("TextLabel", {
			Position = pos, Size = size, BackgroundTransparency = 1,
			Text = text, TextColor3 = color or C.text, Font = FONT, TextSize = 12,
			TextXAlignment = align or Enum.TextXAlignment.Left,
		}, parent)
	end

	local function button(parent, text, pos, size, cb)
		local b = mk("TextButton", {
			Position = pos, Size = size, BackgroundColor3 = C.row, BorderSizePixel = 0,
			Text = text, TextColor3 = C.text, Font = FONT, TextSize = 12, AutoButtonColor = true,
		}, parent)
		b.Activated:Connect(function()
			local ok, err = pcall(cb, b)
			if not ok then setStatus("error: " .. tostring(err), C.bad) end
		end)
		return b
	end

	local function input(parent, placeholder, pos, size)
		local t = mk("TextBox", {
			Position = pos, Size = size, BackgroundColor3 = C.row, BorderSizePixel = 0,
			Text = "", PlaceholderText = placeholder, PlaceholderColor3 = C.dim,
			TextColor3 = C.text, Font = FONT, TextSize = 12, ClearTextOnFocus = false,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, parent)
		mk("UIPadding", { PaddingLeft = UDim.new(0, 5) }, t)
		return t
	end

	local function newList(parent, pos, size)
		local sf = mk("ScrollingFrame", {
			Position = pos, Size = size, BackgroundColor3 = C.panel, BorderSizePixel = 0,
			ScrollBarThickness = 5, ScrollBarImageColor3 = C.line,
			CanvasSize = U2(0,0,0,0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
		}, parent)
		mk("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, sf)
		local L = { frame = sf, rows = {}, selected = nil, cap = 1000, order = 0 }
		function L.add(text, color, onClick, bold)
			L.order += 1
			local row = mk("TextButton", {
				Size = U2(1, -6, 0, 15), BackgroundColor3 = C.panel, BorderSizePixel = 0,
				Text = " " .. text, TextColor3 = color or C.text, Font = bold and Enum.Font.GothamBold or FONT,
				TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd, AutoButtonColor = false,
				LayoutOrder = L.order,
			}, sf)
			row.Activated:Connect(function()
				if L.selected and L.selected.Parent then L.selected.BackgroundColor3 = C.panel end
				L.selected = row
				row.BackgroundColor3 = C.sel
				if onClick then
					local ok, err = pcall(onClick)
					if not ok then setStatus("error: " .. tostring(err), C.bad) end
				end
			end)
			L.rows[#L.rows + 1] = row
			if #L.rows > L.cap then
				local r = table.remove(L.rows, 1)
				if r == L.selected then L.selected = nil end
				r:Destroy()
			end
			return row
		end
		function L.clear()
			for _, r in ipairs(L.rows) do r:Destroy() end
			table.clear(L.rows); L.selected = nil
		end
		function L.toBottom()
			task.defer(function() sf.CanvasPosition = Vector2.new(0, 1e6) end)
		end
		return L
	end

	local function newViewer(parent, pos, size)
		local holder = mk("Frame", { Position=pos, Size=size, BackgroundColor3=C.panel, BorderSizePixel=0 }, parent)
		local sf = mk("ScrollingFrame", {
			Size=U2(1,0,1,-18), BackgroundTransparency=1, BorderSizePixel=0, ScrollBarThickness=5,
			ScrollBarImageColor3=C.line, CanvasSize=U2(0,0,0,0), AutomaticCanvasSize=Enum.AutomaticSize.XY,
			ScrollingDirection=Enum.ScrollingDirection.XY,
		}, holder)
		local txt = mk("TextLabel", {
			Size=U2(0,0,0,0), AutomaticSize=Enum.AutomaticSize.XY, BackgroundTransparency=1,
			Text="", TextColor3=C.text, Font=FONT, TextSize=11,
			TextXAlignment=Enum.TextXAlignment.Left, TextYAlignment=Enum.TextYAlignment.Top, RichText=false,
		}, sf)
		mk("UIPadding", { PaddingLeft=UDim.new(0,6), PaddingTop=UDim.new(0,4) }, txt)
		local bar = mk("Frame", { Position=U2(0,0,1,-18), Size=U2(1,0,0,18), BackgroundColor3=C.row, BorderSizePixel=0 }, holder)
		local V = { lines={}, page=1, PER=120 }
		local pageLbl = label(bar,"",U2(0,40,0,0),U2(1,-80,1,0),C.dim,Enum.TextXAlignment.Center)
		local function pages() return math.max(1,math.ceil(#V.lines/V.PER)) end
		function V.render()
			local first=(V.page-1)*V.PER+1
			local last=math.min(first+V.PER-1,#V.lines)
			local buf={}
			for i=first,last do buf[#buf+1]=U.trunc(V.lines[i],160) end
			txt.Text=table.concat(buf,"\n")
			sf.CanvasPosition=Vector2.zero
			pageLbl.Text=("page %d/%d  (%d lines)"):format(V.page,pages(),#V.lines)
		end
		function V.set(lines) V.lines=lines; V.page=1; V.render() end
		function V.get() return table.concat(V.lines,"\n") end
		function V.append(lines)
			for _, l in ipairs(lines) do V.lines[#V.lines+1]=l end
			V.page=pages(); V.render()
		end
		button(bar,"<",U2(0,0,0,0),U2(0,38,1,0),function() V.page=math.max(1,V.page-1); V.render() end)
		button(bar,">",U2(1,-38,0,0),U2(0,38,1,0),function() V.page=math.min(pages(),V.page+1); V.render() end)
		return V
	end

	-- ---------------------------------------------------------------- tab: Memory
	local function buildMemory(page, restore)
		local left  = mk("Frame",{Size=U2(0.52,-2,1,0),BackgroundTransparency=1},page)
		local right = mk("Frame",{Position=U2(0.52,2,0,0),Size=U2(0.48,-2,1,0),BackgroundTransparency=1},page)

		label(left,"VALUE SCANNER",U2(0,6,0,2),U2(1,-12,0,15),C.accent)
		local valueBox = input(left,"value to find (number, string, or Lua expr)",U2(0,6,0,20),U2(1,-152,0,21))
		if restore and restore.value then valueBox.Text=tostring(restore.value) end

		-- Scan type selector
		local typeRow = mk("Frame",{Position=U2(0,6,0,44),Size=U2(1,-12,0,19),BackgroundTransparency=1},left)
		mk("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,Padding=UDim.new(0,2)},typeRow)
		local scanTypeSel = "number"
		local typeButtons = {}
		for _, t in ipairs({"number","string","bool","integer","any"}) do
			local b = button(typeRow, t, U2(0,0,0,0), U2(0.2,-2,1,0), function()
				scanTypeSel = t
				for tn, tb in pairs(typeButtons) do
					tb.BackgroundColor3 = tn==t and C.sel or C.row
				end
			end)
			typeButtons[t] = b
		end
		typeButtons["number"].BackgroundColor3 = C.sel

		local resultsList = newList(left, U2(0,6,0,66), U2(1,-12,1,-130))
		local countLbl = label(left,"0 results",U2(0,6,1,-28),U2(1,-12,0,14),C.dim)
		local sel

		local function refresh()
			resultsList.clear(); sel = nil
			for i, e in ipairs(VS.results) do
				if i > 400 then
					resultsList.add(("... %d more"):format(#VS.results-400),C.dim)
					break
				end
				resultsList.add(VS.describe(e),nil,function() sel=e end)
			end
			countLbl.Text=("%d results%s"):format(#VS.results, VS.truncated and " (capped)" or "")
		end

		button(left,"First Scan",U2(1,-148,0,20),U2(0,70,0,21),function()
			local raw = valueBox.Text
			local value
			if scanTypeSel=="number" or scanTypeSel=="integer" then
				value = tonumber(raw)
				if not value then setStatus("enter a number",C.warn); return end
			elseif scanTypeSel=="bool" then
				value = raw=="true" and true or raw=="false" and false or nil
				if value==nil then setStatus("enter true or false",C.warn); return end
			elseif scanTypeSel=="string" then
				value = raw
			elseif scanTypeSel=="any" then
				value = nil
			end
			setStatus("scanning heap...",C.warn)
			local ok,err = VS.first(value, scanTypeSel)
			if not ok then setStatus(err,C.bad); return end
			refresh()
			setStatus(("first scan: %d hits"):format(#VS.results),C.good)
		end)
		button(left,"Reset",U2(1,-74,0,20),U2(0,66,0,21),function()
			table.clear(VS.results); refresh()
			setStatus("scan reset",C.dim)
		end)

		local row = mk("Frame",{Position=U2(0,6,1,-102),Size=U2(1,-12,0,19),BackgroundTransparency=1},left)
		mk("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,Padding=UDim.new(0,2)},row)
		for _, m in ipairs({{"Exact","exact"},{"Changed","changed"},{"Same","same"},{"Up","inc"},{"Down","dec"},{"Contains","contains"}}) do
			button(row,m[1],U2(0,0,0,0),U2(0,78,1,0),function()
				VS.next(m[2],tonumber(valueBox.Text) or valueBox.Text)
				refresh()
				setStatus(("next scan (%s): %d left"):format(m[2],#VS.results),C.good)
			end)
		end

		local setBox = input(left,"new value",U2(0,6,1,-56),U2(0.38,0,0,21))
		button(left,"Set",U2(0.38,10,1,-56),U2(0,46,0,21),function()
			if not sel then setStatus("select a result first",C.warn); return end
			local nv = tonumber(setBox.Text) or setBox.Text
			if nv=="" then setStatus("enter a value",C.warn); return end
			if setBox.Text=="true" then nv=true elseif setBox.Text=="false" then nv=false end
			local ok = VS.set(sel,nv)
			setStatus(ok and "value written" or "write failed", ok and C.good or C.bad)
		end)
		button(left,"Freeze",U2(0.38,60,1,-56),U2(0,55,0,21),function()
			if not sel then setStatus("select a result first",C.warn); return end
			local nv = tonumber(setBox.Text)
			if not nv then setStatus("freeze requires a number",C.warn); return end
			VS.freeze(sel,nv)
			setStatus("frozen",C.good)
		end)
		button(left,"Thaw",U2(0.38,120,1,-56),U2(0,46,0,21),function()
			if sel then VS.thaw(sel); setStatus("thawed",C.good) end
		end)

		-- right side: heap viewer (unchanged from v1)
		label(right,"HEAP  "..Memory.backend,U2(0,6,0,2),U2(1,-12,0,15),C.accent)
		local blockList = newList(right,U2(0,6,0,20),U2(1,-12,0,66))
		local viewer = newViewer(right,U2(0,6,0,90),U2(1,-12,1,-176))
		local cur
		local function showBlock(name)
			cur=name
			local h=Memory.get(name)
			if not h then return end
			viewer.set(U.hexdump(Memory.read(h,0,math.min(h.size,512)),0))
		end
		local function refreshBlocks()
			blockList.clear()
			for _,n in ipairs(Memory.names()) do
				local h=Memory.get(n)
				blockList.add(("%s (%dB@0x%X)"):format(n,h.size,h.addr or 0),nil,function() showBlock(n) end)
			end
		end
		local scratchN=0
		button(right,"New 256B",U2(0,6,0,90),U2(0,80,0,19),function()
			repeat scratchN+=1 until not Memory.get("scratch"..scratchN)
			Memory.alloc("scratch"..scratchN,256); refreshBlocks()
		end)
		button(right,"Refresh",U2(0,90,0,90),U2(0,70,0,19),function()
			refreshBlocks(); if cur then showBlock(cur) end
		end)
		button(right,"Free",U2(0,164,0,90),U2(0,55,0,19),function()
			if cur and cur~="state" then
				Memory.free(cur); cur=nil; viewer.set({}); refreshBlocks()
			end
		end)
		local writeBox=input(right,"offset:HEXBYTES  e.g. 0:DEADBEEF",U2(0,6,1,-54),U2(1,-82,0,21))
		button(right,"Write",U2(1,-72,1,-54),U2(0,66,0,21),function()
			local h=cur and Memory.get(cur)
			local off,hex=writeBox.Text:match("^%s*(%d+)%s*:%s*(.+)$")
			if not h or not off then setStatus("select a block, use offset:HEX",C.warn); return end
			Memory.write(h,tonumber(off),U.fromhex(hex)); showBlock(cur)
			setStatus("bytes written",C.good)
		end)
		label(right,"persistence: "..RCE.require("src/core/Registry.lua").backend,U2(0,6,1,-28),U2(1,-12,0,14),C.dim)
		refreshBlocks()

		return { value=function() return valueBox.Text end }
	end

	-- ---------------------------------------------------------------- tab: GC Closures
	local openScript
	local function buildGC(page, restore)
		local filter=input(page,"filter: name / path / k:constant",U2(0,6,0,4),U2(0.36,0,0,21))
		if restore and restore.filter then filter.Text=tostring(restore.filter) end
		local countLbl=label(page,"",U2(0.36,170,0,4),U2(0.64,-176,0,21),C.dim)
		local list=newList(page,U2(0,6,0,30),U2(0.5,-8,1,-34))
		local viewer=newViewer(page,U2(0.5,2,0,30),U2(0.5,-8,1,-58))
		local sel

		local function render()
			list.clear(); sel=nil
			for i,d in ipairs(GC.results) do
				if i>600 then list.add(("... %d more"):format(#GC.results-600),C.dim); break end
				local short=tostring(d.path):match("[^%.]+%.[^%.]+$") or tostring(d.path)
				list.add(("%s  %s:%d"):format(d.name,short,d.line),nil,function()
					sel=d; viewer.set(GC.details(d))
				end)
			end
			countLbl.Text=("%d closures  (blacklist: %d)"):format(#GC.results,#GC.blacklist)
		end

		button(page,"Scan",U2(0.36,6,0,4),U2(0,65,0,21),function()
			setStatus("crawling getgc()...",C.warn)
			local res,err=GC.scan(filter.Text,false)
			if not res then setStatus(err,C.bad); return end
			render(); setStatus(("scan: %d closures"):format(#res),C.good)
		end)

		local auto,autoBtn=false
		autoBtn=button(page,"Auto:OFF",U2(0.36,76,0,4),U2(0,78,0,21),function()
			auto=not auto
			autoBtn.Text=auto and "Auto:ON" or "Auto:OFF"
			autoBtn.TextColor3=auto and C.good or C.text
			if auto then
				task.spawn(function()
					while auto and statusLabel and statusLabel.Parent do
						GC.scan(filter.Text,true); render(); task.wait(3)
					end
				end)
			end
		end)
		RCE.OnUnload(function() auto=false end)

		local bar=mk("Frame",{Position=U2(0.5,2,1,-26),Size=U2(0.5,-8,0,22),BackgroundTransparency=1},page)
		mk("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,Padding=UDim.new(0,2)},bar)
		button(bar,"Hook",U2(0,0,0,0),U2(0.25,-2,1,0),function()
			if not sel then return end
			local ok,err=Hooks.hookClosure(sel.fn,sel.name.." @ "..tostring(sel.path))
			setStatus(ok and "hooked - see Hooks tab" or tostring(err), ok and C.good or C.bad)
		end)
		button(bar,"Unhook",U2(0,0,0,0),U2(0.25,-2,1,0),function()
			if sel then
				local ok,err=Hooks.unhook(sel.fn)
				setStatus(ok and "unhooked" or tostring(err), ok and C.good or C.warn)
			end
		end)
		button(bar,"Copy",U2(0,0,0,0),U2(0.25,-2,1,0),function()
			setStatus(U.clip(viewer.get()) and "copied" or "setclipboard missing",C.good)
		end)
		button(bar,"Script>BC",U2(0,0,0,0),U2(0.25,-2,1,0),function()
			if sel and sel.script then openScript(sel.script)
			else setStatus("no owning script",C.warn) end
		end)
		return { filter=function() return filter.Text end }
	end

	-- ---------------------------------------------------------------- tab: Bytecode
	local function buildBytecode(page)
		local filter=input(page,"filter scripts",U2(0,6,0,4),U2(0.3,0,0,21))
		local list=newList(page,U2(0,6,0,30),U2(0.36,-8,1,-34))
		local viewer=newViewer(page,U2(0.36,2,0,30),U2(0.64,-8,1,-34))
		local scripts,sel={},nil

		local function refresh()
			list.clear(); table.clear(scripts)
			local f=filter.Text:lower()
			for _,s in ipairs(BC.listScripts()) do
				local p=U.pathOf(s)
				if not GC.isBlacklisted(p) and (f=="" or p:lower():find(f,1,true)) then
					scripts[#scripts+1]={s=s,p=p}
				end
			end
			table.sort(scripts,function(a,b) return a.p<b.p end)
			for i,r in ipairs(scripts) do
				if i>600 then list.add("... refine filter",C.dim); break end
				list.add(("[%s] %s"):format(r.s.ClassName:sub(1,1),r.p),nil,function() sel=r.s end)
			end
		end

		local function disasm(inst)
			sel=inst
			setStatus("disassembling "..U.pathOf(inst).."...",C.warn)
			local lines,err=BC.disassembleScript(inst)
			if not lines then viewer.set({"error: "..tostring(err)}); setStatus(tostring(err),C.bad); return end
			viewer.set(lines); setStatus(("%d lines"):format(#lines),C.good)
		end

		button(page,"Refresh",U2(0.3,6,0,4),U2(0,65,0,21),refresh)
		button(page,"Disasm",U2(0.3,76,0,4),U2(0,65,0,21),function() if sel then disasm(sel) end end)
		button(page,"Decompile",U2(0.3,146,0,4),U2(0,80,0,21),function()
			if not sel then return end
			setStatus("decompiling...",C.warn)
			local lines,err=BC.decompileScript(sel)
			viewer.set(lines or {"error: "..tostring(err)})
			setStatus(lines and "decompiled" or tostring(err), lines and C.good or C.bad)
		end)
		button(page,"Copy",U2(0.3,232,0,4),U2(0,56,0,21),function()
			setStatus(U.clip(viewer.get()) and "copied" or "setclipboard missing",C.good)
		end)
		refresh()
		return function(inst) disasm(inst) end
	end

	-- ---------------------------------------------------------------- tab: Hooks
	local function buildHooks(page)
		local t0=os.clock()
		local list=newList(page,U2(0,6,0,30),U2(0.45,-8,1,-34))
		local viewer=newViewer(page,U2(0.45,2,0,30),U2(0.55,-8,1,-34))
		local KCOL={remote=C.accent,require=C.good,hook=C.warn}
		local function addEntry(e)
			list.add(("%7.2f %-7s %s"):format(e.t-t0,e.kind,e.title),KCOL[e.kind],function()
				viewer.set(e.body)
			end)
			list.toBottom()
		end
		for _,e in ipairs(Hooks.log) do addEntry(e) end
		Hooks.onLog(function(e) if page.Parent then addEntry(e) end end)

		local function toggle(text,x,flag,installer)
			local b
			b=button(page,text..":OFF",U2(0,x,0,4),U2(0,110,0,21),function()
				if not Hooks.flags[flag] then
					local ok,err=installer()
					if not ok then setStatus(tostring(err),C.bad); return end
				end
				Hooks.flags[flag]=not Hooks.flags[flag]
				b.Text=text..(Hooks.flags[flag] and ":ON" or ":OFF")
				b.TextColor3=Hooks.flags[flag] and C.good or C.text
			end)
		end
		toggle("Remotes",6,"remote",Hooks.installRemote)
		toggle("require",120,"require",Hooks.installRequire)
		local pauseBtn=button(page,"Pause",U2(0,234,0,4),U2(0,65,0,21),function()
			Hooks.flags.paused=not Hooks.flags.paused
			pauseBtn.Text=Hooks.flags.paused and "Paused" or "Pause"
			pauseBtn.TextColor3=Hooks.flags.paused and C.warn or C.text
		end)
		button(page,"Clear",U2(0,304,0,4),U2(0,56,0,21),function()
			Hooks.clear(); list.clear(); viewer.set({})
		end)
		button(page,"Copy",U2(0,364,0,4),U2(0,56,0,21),function()
			setStatus(U.clip(viewer.get()) and "copied" or "no clipboard",C.good)
		end)
	end

	-- ---------------------------------------------------------------- tab: Remote Spy
	local function buildRemoteSpy(page)
		label(page,"REMOTE SPY — FireServer / InvokeServer / BindableEvent:Fire",
			U2(0,6,0,2),U2(1,-12,0,14),C.remote)
		-- controls row
		local enableBtn,installed=nil,false
		enableBtn=button(page,"Enable",U2(0,6,0,20),U2(0,70,0,20),function()
			if not installed then
				local ok,err=RS.install()
				if not ok then setStatus(tostring(err),C.bad); return end
				installed=true
			end
			RS.flags.enabled=not RS.flags.enabled
			enableBtn.Text=RS.flags.enabled and "Enabled" or "Enable"
			enableBtn.TextColor3=RS.flags.enabled and C.good or C.text
			setStatus(RS.flags.enabled and "Remote spy active" or "Remote spy paused",
				RS.flags.enabled and C.good or C.dim)
		end)
		local pauseBtn=button(page,"Pause",U2(0,80,0,20),U2(0,60,0,20),function()
			RS.flags.paused=not RS.flags.paused
			pauseBtn.Text=RS.flags.paused and "Paused" or "Pause"
			pauseBtn.TextColor3=RS.flags.paused and C.warn or C.text
		end)
		local filterBox=input(page,"filter (path substring)",U2(0,144,0,20),U2(0.4,0,0,20))
		button(page,"Set Filter",U2(0.4,148,0,20),U2(0,80,0,20),function()
			local t=filterBox.Text:gsub("^%s+",""):gsub("%s+$","")
			table.clear(RS.filter.blacklist)
			if t~="" then RS.filter.blacklist[1]=t end
			setStatus("filter: "..t,C.dim)
		end)
		button(page,"Clear Log",U2(1,-130,0,20),U2(0,60,0,20),function()
			RS.clear(); list.clear(); viewer.set({})
		end)
		button(page,"Copy",U2(1,-66,0,20),U2(0,60,0,20),function()
			setStatus(U.clip(viewer.get()) and "copied" or "no clipboard",C.good)
		end)

		local list=newList(page,U2(0,6,0,44),U2(0.45,-8,1,-34))
		local viewer=newViewer(page,U2(0.45,2,0,44),U2(0.55,-8,1,-56))
		local selectedEntry

		local DCOL={ ["C→S"]=C.remote, ["C→S invoke"]=C.accent, ["S→all"]=C.warn, ["S→C"]=C.event }

		local countLbl=label(page,"0 calls",U2(0,6,1,-28),U2(0.45,-12,0,14),C.dim)
		local function addEntry(e)
			local col=DCOL[e.direction] or C.text
			list.add(("[%s] %s  %s"):format(e.direction,e.path:match("[^%.]+$") or e.path,
				e.path),col,function()
				selectedEntry=e
				viewer.set(RS.format(e))
			end)
			list.toBottom()
			countLbl.Text=("#%d calls"):format(#RS.log)
		end
		for _,e in ipairs(RS.log) do addEntry(e) end
		RS.onLog(function(e) if page.Parent then addEntry(e) end end)

		-- Generate script button
		button(page,"Gen Script",U2(0.45,6,1,-28),U2(0,80,0,20),function()
			if not selectedEntry then setStatus("select a remote entry first",C.warn); return end
			viewer.set(RS.generateScript(selectedEntry))
			setStatus("re-fire script generated",C.good)
		end)
		button(page,"Copy Script",U2(0.45,90,1,-28),U2(0,80,0,20),function()
			setStatus(U.clip(viewer.get()) and "copied" or "no clipboard",C.good)
		end)
	end

	-- ---------------------------------------------------------------- tab: HTTP Spy
	local function buildHttpSpy(page)
		label(page,"HTTP SPY — game:HttpGet / HttpPost / syn.request / http.request",
			U2(0,6,0,2),U2(1,-12,0,14),C.http)
		local enableBtn,installed=nil,false
		enableBtn=button(page,"Enable",U2(0,6,0,20),U2(0,70,0,20),function()
			if not installed then
				local ok,err=HS.install()
				if not ok then setStatus(tostring(err),C.bad); return end
				installed=true
			end
			HS.flags.enabled=not HS.flags.enabled
			enableBtn.Text=HS.flags.enabled and "Enabled" or "Enable"
			enableBtn.TextColor3=HS.flags.enabled and C.good or C.text
		end)
		local pauseBtn=button(page,"Pause",U2(0,80,0,20),U2(0,60,0,20),function()
			HS.flags.paused=not HS.flags.paused
			pauseBtn.Text=HS.flags.paused and "Paused" or "Pause"
			pauseBtn.TextColor3=HS.flags.paused and C.warn or C.text
		end)
		button(page,"Clear",U2(0,144,0,20),U2(0,56,0,20),function()
			HS.clear(); list.clear(); viewer.set({})
		end)
		button(page,"Copy",U2(0,204,0,20),U2(0,56,0,20),function()
			setStatus(U.clip(viewer.get()) and "copied" or "no clipboard",C.good)
		end)

		local list=newList(page,U2(0,6,0,44),U2(0.45,-8,1,-34))
		local viewer=newViewer(page,U2(0.45,2,0,44),U2(0.55,-8,1,-34))
		local countLbl=label(page,"0 requests",U2(0,6,1,-28),U2(0.45,-12,0,14),C.dim)

		local MCOL={GET=C.good, POST=C.warn, PATCH=C.event, PUT=C.accent, DELETE=C.bad}
		local function addEntry(e)
			local col=MCOL[e.method] or C.http
			local urlShort=e.url:match("https?://[^/]+(.*)") or e.url
			list.add(("[%s] %s"):format(e.method, U.trunc(urlShort,80)),col,function()
				viewer.set(HS.format(e))
			end)
			list.toBottom()
			countLbl.Text=("#%d requests"):format(#HS.log)
		end
		for _,e in ipairs(HS.log) do addEntry(e) end
		HS.onLog(function(e) if page.Parent then addEntry(e) end end)
	end

	-- ---------------------------------------------------------------- tab: Event Spy
	local function buildEventSpy(page)
		label(page,"EVENT SPY — BindableEvent:Fire / BindableFunction:Invoke",
			U2(0,6,0,2),U2(1,-12,0,14),C.event)
		local enableBtn,installed=nil,false
		enableBtn=button(page,"Enable",U2(0,6,0,20),U2(0,70,0,20),function()
			if not installed then
				local ok,err=ES.install()
				if not ok then setStatus(tostring(err),C.bad); return end
				installed=true
			end
			ES.flags.enabled=not ES.flags.enabled
			enableBtn.Text=ES.flags.enabled and "Enabled" or "Enable"
			enableBtn.TextColor3=ES.flags.enabled and C.good or C.text
		end)
		button(page,"Scan+Watch All",U2(0,80,0,20),U2(0,110,0,20),function()
			local n=ES.scanAndWatchAll()
			setStatus(("watching %d bindables"):format(n),C.good)
		end)
		local pauseBtn=button(page,"Pause",U2(0,194,0,20),U2(0,60,0,20),function()
			ES.flags.paused=not ES.flags.paused
			pauseBtn.Text=ES.flags.paused and "Paused" or "Pause"
			pauseBtn.TextColor3=ES.flags.paused and C.warn or C.text
		end)
		button(page,"Clear",U2(0,258,0,20),U2(0,56,0,20),function()
			ES.clear(); list.clear(); viewer.set({})
		end)

		local list=newList(page,U2(0,6,0,44),U2(0.45,-8,1,-34))
		local viewer=newViewer(page,U2(0.45,2,0,44),U2(0.55,-8,1,-34))
		local countLbl=label(page,"0 events",U2(0,6,1,-28),U2(0.45,-12,0,14),C.dim)

		local function addEntry(e)
			list.add(("[%s] %s"):format(e.kind,e.source),C.event,function()
				viewer.set(ES.format(e))
			end)
			list.toBottom()
			countLbl.Text=("#%d events"):format(#ES.log)
		end
		for _,e in ipairs(ES.log) do addEntry(e) end
		ES.onLog(function(e) if page.Parent then addEntry(e) end end)

		-- watch specific instance
		local watchBox=input(page,"instance path to watch...",U2(0,6,1,-28),U2(0.45,-96,0,20))
		button(page,"Watch",U2(0.45,-86,1,-28),U2(0,80,0,20),function()
			local path=watchBox.Text:gsub("^%s+",""):gsub("%s+$","")
			if path=="" then setStatus("enter a path",C.warn); return end
			local parts={}; for seg in path:gmatch("[^%.]+") do parts[#parts+1]=seg end
			local obj=game
			for _,seg in ipairs(parts) do
				local ok,next=pcall(function() return obj:FindFirstChild(seg) or game:GetService(seg) end)
				if not ok or not next then setStatus("not found: "..seg,C.bad); return end
				obj=next
			end
			local ok,err=ES.watchInstance(obj)
			setStatus(ok and ("watching: "..path) or tostring(err), ok and C.good or C.bad)
		end)
	end

	-- ---------------------------------------------------------------- tab: Exec / Invoke
	local function buildExec(page)
		label(page,"EXEC / RUN SCRIPT + INVOKE REMOTE",U2(0,6,0,2),U2(1,-12,0,14),C.exec)

		-- Left: script editor
		local left=mk("Frame",{Size=U2(0.56,-2,1,0),BackgroundTransparency=1},page)
		local right=mk("Frame",{Position=U2(0.56,2,0,0),Size=U2(0.44,-2,1,0),BackgroundTransparency=1},page)

		label(left,"Script Editor",U2(0,6,0,20),U2(1,-12,0,14),C.dim)
		local codeBox=mk("TextBox",{
			Position=U2(0,6,0,36),Size=U2(1,-12,1,-96),BackgroundColor3=C.row,BorderSizePixel=0,
			Text="print(\"Hello from R-CE!\")",TextColor3=C.text,Font=FONT,TextSize=12,
			ClearTextOnFocus=false,MultiLine=true,TextXAlignment=Enum.TextXAlignment.Left,
			TextYAlignment=Enum.TextYAlignment.Top,
		},left)
		mk("UIPadding",{PaddingLeft=UDim.new(0,6),PaddingTop=UDim.new(0,4)},codeBox)

		local histIdx=0
		button(left,"▶ Run",U2(0,6,1,-56),U2(0,70,0,22),function()
			SE.exec(codeBox.Text,"user_script")
		end)
		button(left,"Clear",U2(0,80,1,-56),U2(0,56,0,22),function()
			codeBox.Text=""
		end)
		button(left,"◀ Hist",U2(0,140,1,-56),U2(0,65,0,22),function()
			if #SE.history==0 then setStatus("no history",C.dim); return end
			histIdx=(histIdx % #SE.history)+1
			codeBox.Text=SE.history[histIdx]
		end)
		button(left,"Copy",U2(0,210,1,-56),U2(0,56,0,22),function()
			setStatus(U.clip(codeBox.Text) and "copied" or "no clipboard",C.good)
		end)
		label(left,"Output:",U2(0,6,1,-30),U2(1,-12,0,14),C.dim)

		-- output log on right side
		label(right,"Output Console",U2(0,6,0,20),U2(1,-12,0,14),C.dim)
		local outList=newList(right,U2(0,6,0,36),U2(1,-12,1,-30))
		local OCOL={print=C.text, warn=C.warn, error=C.bad, result=C.good, ok=C.dim, exec=C.exec}
		local function addOut(e)
			outList.add(("[%s] %s"):format(e.kind, U.trunc(e.text,200)), OCOL[e.kind] or C.text)
			outList.toBottom()
		end
		for _,e in ipairs(SE.output) do addOut(e) end
		SE.onOutput(function(e) if page.Parent then addOut(e) end end)
		button(right,"Clear Output",U2(0,6,1,-26),U2(0,96,0,20),function()
			SE.clearOutput(); outList.clear()
		end)
		button(right,"Copy Output",U2(0,106,1,-26),U2(0,88,0,20),function()
			local lines={}
			for _,e in ipairs(SE.output) do lines[#lines+1]="["..e.kind.."] "..e.text end
			setStatus(U.clip(table.concat(lines,"\n")) and "copied" or "no clipboard",C.good)
		end)

		-- Bottom invoke row
		label(page,"Invoke Remote/Bindable:",U2(0.56,8,1,-56),U2(0.3,0,0,14),C.dim)
		local invPath=input(page,"game.ReplicatedStorage.MyRemote",U2(0,6,1,-32),U2(0.4,-12,0,20))
		local invArgs=input(page,'args: "hello", 42, true',U2(0.4,8,1,-32),U2(0.3,-12,0,20))
		button(page,"Invoke",U2(0.7,10,1,-32),U2(0,70,0,20),function()
			local ok,result=SE.invokeRemote(invPath.Text, invArgs.Text)
			if ok then
				setStatus("result: "..U.trunc(U.ser(result),100),C.good)
			else
				setStatus("error: "..tostring(result),C.bad)
			end
		end)
	end

	-- ---------------------------------------------------------------- tab: Explorer
	local function buildExplorer(page)
		label(page,"EXPLORER  (DEX++ style)  — ServerStorage/ServerScriptService via gc scan",
			U2(0,6,0,2),U2(1,-12,0,14),C.accent)

		local left=mk("Frame",{Size=U2(0.42,-2,1,0),BackgroundTransparency=1},page)
		local mid=mk("Frame",{Position=U2(0.42,2,0,0),Size=U2(0.28,-2,1,0),BackgroundTransparency=1},page)
		local right=mk("Frame",{Position=U2(0.70,2,0,0),Size=U2(0.30,-2,1,0),BackgroundTransparency=1},page)

		label(left,"Instance Tree",U2(0,6,0,20),U2(1,-12,0,14),C.dim)
		label(mid,"Properties",U2(0,4,0,20),U2(1,-8,0,14),C.dim)
		label(right,"Source / Details",U2(0,4,0,20),U2(1,-8,0,14),C.dim)

		local treeList=newList(left,U2(0,6,0,36),U2(1,-12,1,-30))
		local propList=newList(mid,U2(0,4,0,36),U2(1,-8,1,-30))
		local srcViewer=newViewer(right,U2(0,4,0,36),U2(1,-8,1,-30))

		local expandedPaths={}
		local selectedInst=nil

		local function showProps(inst)
			propList.clear()
			if typeof(inst)~="Instance" then return end
			local props=EX.getProperties(inst)
			for _,p in ipairs(props) do
				propList.add(("%s = %s"):format(p.name, U.trunc(U.ser(p.value),80)), C.text)
			end
		end

		local function showSource(inst)
			if typeof(inst)~="Instance" then return end
			local src,method=EX.getScriptSource(inst)
			if src then
				local lines={}
				for line in (src.."\n"):gmatch("([^\n]*)\n") do lines[#lines+1]=line end
				srcViewer.set(lines)
				setStatus(("source via %s"):format(method),C.good)
			else
				srcViewer.set({"-- source unavailable","-- method: "..tostring(method)})
			end
		end

		local function renderTree(parent, depth, pathKey)
			local children
			if parent==game then
				children=EX.getRoots()
			else
				children=EX.getChildren(parent)
			end

			-- Check server services
			if parent==game then
				for _,svcName in ipairs({"ServerStorage","ServerScriptService"}) do
					local alreadyIn=false
					for _,c in ipairs(children) do
						if c.Name==svcName then alreadyIn=true; break end
					end
					if not alreadyIn then
						local items,method=EX.tryGetServerContent(svcName)
						if #items>0 then
							-- inject virtual node
							children[#children+1]={
								_virtual=true, _name=svcName, _items=items, _method=method
							}
						end
					end
				end
			end

			for _,child in ipairs(children) do
				local isVirtual=type(child)=="table" and child._virtual
				local name=isVirtual and child._name or child.Name
				local className=isVirtual and "Service*" or child.ClassName
				local icon=isVirtual and "🔒" or EX.getIcon(child)
				local childKey=(pathKey or "")..name.."/"
				local indent=string.rep("  ",depth)
				local hasChildren= isVirtual
					or (typeof(child)=="Instance" and #EX.getChildren(child)>0)

				treeList.add(
					("%s%s%s %s [%s]"):format(indent, expandedPaths[childKey] and "▼ " or (hasChildren and "▶ " or "  "),
						icon, name, className),
					className:find("Script") and C.exec or
					className:find("Remote") and C.remote or
					isVirtual and C.warn or C.text,
					function()
						selectedInst=not isVirtual and child or nil
						if hasChildren then
							expandedPaths[childKey]=not expandedPaths[childKey]
						end
						if not isVirtual then
							showProps(child)
							if className:find("Script") then showSource(child) end
						else
							propList.clear()
							propList.add(("🔒 %s — accessed via %s"):format(name,child._method),C.warn)
							for _,item in ipairs(child._items) do
								propList.add(("  "..EX.getIcon(item).." "..item.Name.." ["..item.ClassName.."]"),C.dim)
							end
						end
					end
				)
				-- recursively render children if expanded
				if expandedPaths[childKey] and not isVirtual then
					renderTree(child, depth+1, childKey)
				end
			end
		end

		local function refreshTree()
			treeList.clear()
			renderTree(game, 0, "")
		end

		button(left,"Refresh Tree",U2(0,6,1,-26),U2(0,96,0,20),refreshTree)
		button(left,"Collapse All",U2(0,106,1,-26),U2(0,88,0,20),function()
			table.clear(expandedPaths); refreshTree()
		end)
		button(mid,"Copy Props",U2(0,4,1,-26),U2(0,80,0,20),function()
			local lines={}
			for _,r in ipairs(propList.rows) do lines[#lines+1]=r.Text end
			setStatus(U.clip(table.concat(lines,"\n")) and "copied" or "no clipboard",C.good)
		end)
		button(right,"Get Source",U2(0,4,1,-26),U2(0,80,0,20),function()
			if selectedInst then showSource(selectedInst) end
		end)
		button(right,"Copy Src",U2(0,88,1,-26),U2(0,72,0,20),function()
			setStatus(U.clip(srcViewer.get()) and "copied" or "no clipboard",C.good)
		end)

		-- ServerStorage special access button
		button(page,"🔒 Peek ServerStorage",U2(1,-196,0,20),U2(0,190,0,20),function()
			local items,method=EX.tryGetServerContent("ServerStorage")
			local lines={("ServerStorage peek — method: %s"):format(method)}
			for _,item in ipairs(items) do
				lines[#lines+1]=("  "..EX.getIcon(item).." "..item.Name.." ["..item.ClassName.."]")
			end
			if #items==0 then lines[#lines+1]="  (nothing found — server-sided content is locked)" end
			srcViewer.set(lines)
			setStatus(("ServerStorage: %d items via %s"):format(#items,method),
				#items>0 and C.good or C.warn)
		end)

		refreshTree()
	end

	-- ---------------------------------------------------------------- tab: Live View
	local function buildLiveView(page)
		label(page,"LIVE VIEW — unified real-time feed of all events",
			U2(0,6,0,2),U2(1,-12,0,14),C.accent)

		-- top controls
		local enableBtn=button(page,"Enable",U2(0,6,0,20),U2(0,70,0,20),function()
			LV.flags.enabled=not LV.flags.enabled
			enableBtn.Text=LV.flags.enabled and "LIVE ●" or "Enable"
			enableBtn.TextColor3=LV.flags.enabled and C.good or C.text
			if LV.flags.enabled then
				-- auto-enable all spies
				if not RS._installed then pcall(RS.install); RS._installed=true end
				RS.flags.enabled=true
				if not HS._installed then pcall(HS.install); HS._installed=true end
				HS.flags.enabled=true
				if not ES._installed then pcall(ES.install); ES._installed=true end
				ES.flags.enabled=true
			end
		end)
		local pauseBtn=button(page,"Pause",U2(0,80,0,20),U2(0,60,0,20),function()
			LV.flags.paused=not LV.flags.paused
			pauseBtn.Text=LV.flags.paused and "Paused" or "Pause"
			pauseBtn.TextColor3=LV.flags.paused and C.warn or C.text
		end)
		button(page,"Clear",U2(0,144,0,20),U2(0,56,0,20),function()
			LV.clear(); list.clear(); statsLbl.Text="total:0"
		end)

		-- filter toggles
		local toggleRow=mk("Frame",{Position=U2(0,204,0,20),Size=U2(1,-410,0,20),BackgroundTransparency=1},page)
		mk("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,Padding=UDim.new(0,2)},toggleRow)
		local KIND_COL={remote=C.remote, http=C.http, event=C.event, hook=C.hook, error=C.bad, custom=C.exec}
		local FLAGS={
			{"Remote",   "showRemotes"},
			{"HTTP",     "showHttp"},
			{"Events",   "showEvents"},
			{"Hooks",    "showHooks"},
			{"Errors",   "showErrors"},
		}
		for _,f in ipairs(FLAGS) do
			local b
			b=button(toggleRow,f[1],U2(0,0,0,0),U2(0,68,1,0),function()
				LV.flags[f[2]]=not LV.flags[f[2]]
				b.BackgroundColor3=LV.flags[f[2]] and C.sel or C.row
			end)
			b.BackgroundColor3=C.sel  -- on by default
		end

		local filterBox=input(page,"filter text...",U2(1,-180,0,20),U2(0,174,0,20))
		filterBox:GetPropertyChangedSignal("Text"):Connect(function()
			LV.filter=filterBox.Text
		end)

		local list=newList(page,U2(0,6,0,44),U2(1,-12,1,-50))
		local statsLbl=label(page,"total:0",U2(0,6,1,-28),U2(0.5,-12,0,14),C.dim)
		local detailLbl=label(page,"",U2(0.5,6,1,-28),U2(0.5,-12,0,14),C.dim,Enum.TextXAlignment.Right)

		local selectedEntry=nil

		local function addEntry(e)
			local col=KIND_COL[e.kind] or C.dim
			list.add(("[%6.2f][%s] %s"):format(e.t,e.kind:upper():sub(1,3),e.text),col,function()
				selectedEntry=e
				-- show detail in status
				if e.data then
					if type(e.data.path)=="string" then
						detailLbl.Text=e.data.path
					end
				end
			end)
			list.toBottom()
			statsLbl.Text=("total:%d  remote:%d  http:%d  event:%d"):format(
				LV.stats.total, LV.stats.remotes, LV.stats.http, LV.stats.events)
		end

		for _,e in ipairs(LV.log) do addEntry(e) end
		LV.onLog(function(e) if page.Parent then addEntry(e) end end)

		-- inject custom message
		local injectBox=input(page,"inject custom message...",U2(0,6,1,-50),U2(0.6,-12,0,20))
		button(page,"Inject",U2(0.6,8,1,-50),U2(0,65,0,20),function()
			if injectBox.Text~="" then LV.inject(injectBox.Text); injectBox.Text="" end
		end)
	end

	-- ---------------------------------------------------------------- window
	function UI.Init()
		local parentGui=(E.gethui and E.gethui()) or game:GetService("CoreGui")
		local gui=mk("ScreenGui",{
			Name="RCE2_"..math.random(100000,999999), ResetOnSpawn=false,
			IgnoreGuiInset=true, ZIndexBehavior=Enum.ZIndexBehavior.Sibling, DisplayOrder=999999,
		},parentGui)

		local W,H=920,540
		local win=mk("Frame",{
			AnchorPoint=Vector2.new(0.5,0.5), Position=U2(0.5,0,0.5,0),
			Size=U2(0,W,0,H), BackgroundColor3=C.bg, BorderSizePixel=0, ClipsDescendants=true,
		},gui)
		mk("UIStroke",{Color=C.line,Thickness=1},win)
		mk("UICorner",{CornerRadius=UDim.new(0,4)},win)

		local titleBar=mk("Frame",{Size=U2(1,0,0,26),BackgroundColor3=Color3.fromRGB(14,14,18),BorderSizePixel=0},win)
		mk("UICorner",{CornerRadius=UDim.new(0,4)},titleBar)
		label(titleBar,"  🔬 R-CE v2  |  Roblox Cheat Engine   [RShift: hide]",
			U2(0,0,0,0),U2(1,-64,1,0),C.accent)

		local body=mk("Frame",{Position=U2(0,0,0,26),Size=U2(1,0,1,-26),BackgroundTransparency=1},win)
		local collapsed=false
		button(titleBar,"-",U2(1,-58,0,3),U2(0,24,0,20),function()
			collapsed=not collapsed; body.Visible=not collapsed
			win.Size=collapsed and U2(0,W,0,26) or U2(0,W,0,H)
		end)
		button(titleBar,"x",U2(1,-30,0,3),U2(0,24,0,20),function() RCE.Unload() end)

		-- drag
		local dragging,dragStart,startPos
		titleBar.InputBegan:Connect(function(i)
			if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
				dragging,dragStart,startPos=true,i.Position,win.Position
			end
		end)
		titleBar.InputEnded:Connect(function(i)
			if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
				dragging=false
			end
		end)
		local c1=UIS.InputChanged:Connect(function(i)
			if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
				local d=i.Position-dragStart
				win.Position=U2(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
			end
		end)
		local c2=UIS.InputBegan:Connect(function(i,gp)
			if not gp and i.KeyCode==Enum.KeyCode.RightShift then gui.Enabled=not gui.Enabled end
		end)

		-- tab bar (scrollable for many tabs)
		local tabScroll=mk("ScrollingFrame",{
			Size=U2(1,0,0,24),BackgroundColor3=C.tabBg,BorderSizePixel=0,
			ScrollBarThickness=0,CanvasSize=U2(0,0,0,0),AutomaticCanvasSize=Enum.AutomaticSize.X,
			ScrollingDirection=Enum.ScrollingDirection.X,
		},body)
		mk("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,Padding=UDim.new(0,1)},tabScroll)

		local content=mk("Frame",{Position=U2(0,0,0,26),Size=U2(1,0,1,-46),BackgroundTransparency=1},body)
		statusLabel=mk("TextLabel",{
			Position=U2(0,0,1,-18),Size=U2(1,0,0,18),BackgroundColor3=Color3.fromRGB(14,14,18),
			BorderSizePixel=0,Text="",TextColor3=C.text,Font=FONT,TextSize=12,
			TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd,
		},body)

		local pages,tabButtons={},{}
		local current
		local function select(name)
			current=name
			for n,p in pairs(pages) do
				p.Visible=n==name
				if tabButtons[n] then
					tabButtons[n].BackgroundColor3=n==name and C.tabSel or C.tabBg
					tabButtons[n].TextColor3=n==name and Color3.new(1,1,1) or C.dim
				end
			end
		end
		local TAB_ICONS={
			Memory="💾", ["GC Closures"]="🔍", Bytecode="⚙️", Hooks="🪝",
			["Remote Spy"]="📡", ["HTTP Spy"]="🌐", ["Event Spy"]="📶",
			Exec="▶️", Explorer="🗂️", ["Live View"]="📺",
		}
		local function addTab(name)
			local p=mk("Frame",{Size=U2(1,0,1,0),BackgroundTransparency=1,Visible=false},content)
			pages[name]=p
			local icon=TAB_ICONS[name] or ""
			local b=mk("TextButton",{
				Size=U2(0,0,1,0),AutomaticSize=Enum.AutomaticSize.X,
				BackgroundColor3=C.tabBg,BorderSizePixel=0,
				Text=" "..icon.." "..name.." ",TextColor3=C.dim,
				Font=Enum.Font.GothamMedium,TextSize=11,AutoButtonColor=false,
			},tabScroll)
			mk("UIPadding",{PaddingLeft=UDim.new(0,4),PaddingRight=UDim.new(0,4)},b)
			b.Activated:Connect(function() select(name) end)
			tabButtons[name]=b
			return p
		end

		local restore=Memory.load("state") or {}

		buildMemory(addTab("Memory"),restore)
		buildGC(addTab("GC Closures"),restore)
		local disasmFn=buildBytecode(addTab("Bytecode"))
		openScript=function(inst) select("Bytecode"); disasmFn(inst) end
		buildHooks(addTab("Hooks"))
		buildRemoteSpy(addTab("Remote Spy"))
		buildHttpSpy(addTab("HTTP Spy"))
		buildEventSpy(addTab("Event Spy"))
		buildExec(addTab("Exec"))
		buildExplorer(addTab("Explorer"))
		buildLiveView(addTab("Live View"))

		select(restore.tab and pages[restore.tab] and restore.tab or "Memory")

		local have,miss=E.report()
		setStatus(("%d/%d capabilities%s"):format(#have,#have+#miss,
			#miss>0 and ("  |  missing: "..table.concat(miss,", ")) or ""),
			#miss==0 and C.good or C.warn)

		RCE.OnUnload(function()
			pcall(function()
				Memory.save("state",{tab=current})
			end)
			c1:Disconnect(); c2:Disconnect(); gui:Destroy()
		end)

		U.log("R-CE v2 ready. RightShift toggles the window.")
	end

	return UI
end
