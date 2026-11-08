-- Explorer: DEX++ inspired instance explorer with icons, properties, ServerService/ServerStorage peek
-- ServerService/ServerStorage access uses: getgc() scan for the hidden service reference tricks
return function(RCE)
	local E = RCE.require("src/core/Env.lua")
	local U = RCE.require("src/core/Util.lua")

	local EX = {
		listeners = {},
	}

	-- Icon map (class -> emoji icon for text UI)
	EX.ICONS = {
		Workspace           = "🌍",
		Players             = "👥",
		Lighting            = "💡",
		ReplicatedStorage   = "📦",
		ReplicatedFirst     = "⚡",
		ServerScriptService = "🔒",
		ServerStorage       = "🗄️",
		StarterGui          = "🖼️",
		StarterPack         = "🎒",
		StarterPlayer       = "🧍",
		Teams               = "🏳️",
		SoundService        = "🔊",
		TextChatService     = "💬",
		RunService          = "▶️",
		TweenService        = "🎞️",
		UserInputService    = "🖱️",
		HttpService         = "🌐",
		Script              = "📜",
		LocalScript         = "📄",
		ModuleScript        = "📁",
		Part                = "🔷",
		MeshPart            = "🔮",
		UnionOperation      = "🔗",
		Model               = "📐",
		Folder              = "📂",
		Frame               = "⬜",
		TextLabel           = "🔤",
		TextButton          = "🔘",
		ImageLabel          = "🖼️",
		ImageButton         = "🖼️",
		ScreenGui           = "🖥️",
		BillboardGui        = "🏷️",
		SurfaceGui          = "📋",
		RemoteEvent         = "📡",
		RemoteFunction      = "📡",
		BindableEvent       = "📶",
		BindableFunction    = "📶",
		Camera              = "📷",
		SpawnLocation       = "🚩",
		Tool                = "🔧",
		Humanoid            = "🧠",
		HumanoidRootPart    = "⚙️",
		Animation           = "🎬",
		StringValue         = "🔤",
		NumberValue         = "🔢",
		BoolValue           = "✅",
		ObjectValue         = "🔗",
		IntValue            = "🔢",
		Color3Value         = "🎨",
		Vector3Value        = "📍",
		Sound               = "🔊",
		Decal               = "🖼️",
		Texture             = "🎨",
		WeldConstraint      = "🔩",
		Motor6D             = "🦾",
		Attachment          = "📌",
		BodyPosition        = "🎯",
		SelectionBox        = "📦",
		Configuration       = "⚙️",
		__default           = "▫️",
	}

	function EX.getIcon(inst)
		if typeof(inst) ~= "Instance" then return "▪️" end
		return EX.ICONS[inst.ClassName] or EX.ICONS.__default
	end

	-- Get children safely (handles locked services)
	function EX.getChildren(inst)
		if typeof(inst) ~= "Instance" then return {} end
		local ok, children = pcall(function() return inst:GetChildren() end)
		return ok and children or {}
	end

	-- Get all top-level services
	function EX.getRoots()
		local services = {
			"Workspace", "Players", "Lighting", "ReplicatedStorage", "ReplicatedFirst",
			"StarterGui", "StarterPack", "StarterPlayer", "Teams", "SoundService",
			"TextChatService", "RunService", "TweenService", "UserInputService",
			"HttpService", "CoreGui",
		}
		-- Try to add server-side services via sneaky methods
		local extras = { "ServerScriptService", "ServerStorage" }
		for _, svc in ipairs(extras) do
			local ok, inst = pcall(function() return game:GetService(svc) end)
			if ok and inst then
				services[#services + 1] = svc
			end
		end
		local result = {}
		for _, name in ipairs(services) do
			local ok, svc = pcall(function() return game:GetService(name) end)
			if ok and svc then
				result[#result + 1] = svc
			end
		end
		return result
	end

	-- ServerStorage/ServerScriptService content access
	-- Method 1: getgc() scan for Script instances whose Parent is ServerScriptService
	-- Method 2: Look through require() cache (Ketamine technique)
	-- Method 3: Check if game.ServerStorage is accessible (some exploits expose it)
	function EX.tryGetServerContent(serviceName)
		local results = {}
		-- Try direct access first
		local ok, svc = pcall(function() return game:GetService(serviceName) end)
		if ok and svc then
			local childOk, children = pcall(function() return svc:GetChildren() end)
			if childOk and #children > 0 then
				return children, "direct"
			end
		end
		-- Ketamine technique: scan getgc() for Instances whose parent chain leads to this service
		if E.getgc then
			local ok2, gc = pcall(E.getgc, true)
			if ok2 then
				for _, obj in ipairs(gc) do
					if typeof(obj) == "Instance" then
						local ok3, parent = pcall(function() return obj.Parent end)
						if ok3 and typeof(parent) == "Instance" then
							local ok4, pname = pcall(function() return parent.Name end)
							if ok4 and pname == serviceName then
								results[#results + 1] = obj
							end
						end
					end
				end
			end
		end
		-- Also try: scan through require module cache
		if E.getrenv then
			local ok5, renv = pcall(E.getrenv)
			if ok5 and type(renv) == "table" then
				local ok6, pkg = pcall(function() return renv.__require end)
				if ok6 and type(pkg) == "table" then
					for mod, _ in pairs(pkg) do
						if typeof(mod) == "Instance" then
							local ok7, p = pcall(function()
								return mod:FindFirstAncestorOfClass(serviceName == "ServerStorage"
									and "ServerStorage" or "ServerScriptService")
							end)
							if ok7 and p then
								results[#results + 1] = mod
							end
						end
					end
				end
			end
		end
		return results, #results > 0 and "gc_scan" or "none"
	end

	-- Get all properties of an instance
	function EX.getProperties(inst)
		if typeof(inst) ~= "Instance" then return {} end
		local props = {}
		-- Use getproperties if available (Ketamine exposes this)
		if E.getproperties then
			local ok, raw = pcall(E.getproperties, inst)
			if ok and type(raw) == "table" then
				for k, v in pairs(raw) do
					props[#props + 1] = { name = tostring(k), value = v }
				end
				return props
			end
		end
		-- Fallback: iterate known property names
		local knownProps = {
			"Name", "ClassName", "Parent", "Archivable",
			-- Part props
			"Position", "Size", "Orientation", "CFrame", "Anchored", "CanCollide",
			"Transparency", "BrickColor", "Material", "Color",
			-- Script props
			"Source", "Disabled", "LinkedSource",
			-- Humanoid
			"Health", "MaxHealth", "WalkSpeed", "JumpPower",
			-- GUI
			"Text", "Visible", "BackgroundColor3", "BackgroundTransparency",
			"ZIndex", "AbsolutePosition", "AbsoluteSize",
		}
		for _, name in ipairs(knownProps) do
			local ok, val = pcall(function() return inst[name] end)
			if ok then
				props[#props + 1] = { name = name, value = val }
			end
		end
		return props
	end

	-- Get script source (uses getscriptsource / decompile)
	function EX.getScriptSource(inst)
		if typeof(inst) ~= "Instance" then return nil, "not an instance" end
		if inst.ClassName ~= "Script" and inst.ClassName ~= "LocalScript" and inst.ClassName ~= "ModuleScript" then
			return nil, "not a script"
		end
		if E.getscriptsource then
			local ok, src = pcall(E.getscriptsource, inst)
			if ok and type(src) == "string" and #src > 0 then
				return src, "getscriptsource"
			end
		end
		if E.getscriptbytecode and decompile then
			local ok, bc = pcall(E.getscriptbytecode, inst)
			if ok then
				local ok2, src = pcall(decompile, inst)
				if ok2 and src then return src, "decompile" end
			end
		end
		return nil, "source unavailable"
	end

	return EX
end
