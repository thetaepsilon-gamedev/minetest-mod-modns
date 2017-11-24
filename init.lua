if minetest.global_exists("modns") then error("modns should not already be defined") end
local registered = {}
local compat = {}
local deprecated = {}
local checkpath = function(path)
	if type(path) ~= "string" then error("component path must be a string") end
end

local modname = minetest.get_current_modname()
local dirsep = "/"
local modpath = minetest.get_modpath(modname)..dirsep



-- I'm thinking of putting this in it's own mod.
local log_trace = "trace"
local log_error = "error"
local log_warning = "warning"
local logaction = function(severity, msg)
	print("[modns] ["..severity.."] "..msg)
end
-- simplified form of the logging system found in libmtlog.
local debugger = function(ev)
	local args = ""
	if ev.args then
		for k, v in pairs(ev.args) do
			args = args.." "..k.."="..string.format("%q", v)
		end
	end
	logaction(log_trace, ev.n..args)
end

local deepcopy = table.copy

local tvisit = dofile(modpath.."tvisit.lua")

local checkexists = function(path)
	return (registered[path] ~= nil) or (compat[path] ~= nil)
end

local handledeprecated = function(path, isdeprecated)
	if isdeprecated then
		deprecated[path] = true
	end
end



-- WIP
-- early start-up: check all installed mods for any namespace declarations.
-- mod conflicts cause errors; they should pick a unique namespace for themselves.
-- TODO: guidelines document
_modpath = modpath
local reservations = dofile(modpath.."reservations.lua")
_modpath = nil
local modpathioimpl = {
	open = function(self, modname, filename)
		return io.open(minetest.get_modpath(modname)..dirsep..filename, "r")
	end
}
local prefixes = reservations.new({debugger=debugger})
reservations.populate(prefixes, minetest.get_modnames(), modpathioimpl)



-- internal single-component registration.
local register = function(path, component, isdeprecated, invoker)
	checkpath(path)
	if checkexists(path) then error("duplicate component registration for "..path.." by "..invoker) end
	registered[path] = component
	handledeprecated(path, isdeprecated)
end

-- "require" equivalent for MT mods, performs lookup and retreival.
-- lint note: intentional global assigmnent
mtrequire = function(path)
	checkpath(path)
	local invoker = tostring(minetest.get_current_modname())
	local result
	local compat_alias = compat[path]

	-- woo, nested functions!
	local logaccess = function(msg)
		logaction(log_trace, "component "..path.." requested by "..invoker..": "..msg)
	end

	if deprecated[path] then
		logaction(log_warning, "component "..path.." has been marked deprecated!")
	end

	if compat_alias then
		return get(compat_alias)
	end

	local obj = registered[path]
	if obj then
		logaccess("retrieving mod object")
		result = deepcopy(obj)
	else
		logaction(log_error, "mod "..invoker.." tried to retrieve non-existant component "..path)
		error("component "..path.." does not exist")
	end

	return result
end



modns = {
	register = function(path, component, isdeprecated, opts)
		if not opts then opts = {} end
		local sep = opts.pathsep
		if not sep then
			sep = "."
		else
			if type(sep) ~= "string" then error("path separator not a string!") end
		end

		checkpath(path)
		if checkexists(path) then error("duplicate component registration for "..path) end
		local comptype = type(component)
		local invoker = tostring(minetest.get_current_modname())
		if comptype == "table" then
			-- search recursively inside the passed table to find sub-namespaces.
			local visitor = function(label, object) register(label, object, isdeprecated, invoker) end
			tvisit(component, path, sep, visitor)
			logaction(log_trace, "mod object registered for component "..path.." by mod "..invoker)
		else
			logaction(log_error, "mod "..invoker.." tried to register an unknown object of type "..comptype)
			error("modns.register(): unrecognised object type "..comptype)
		end
		handledeprecated(path, isdeprecated)
	end,
	register_compat_alias = function(path, totarget, isdeprecated)
		local aliaserror = function(msg)
			error("compatability alias from "..path.." to real target "..totarget.." "..msg)
		end
		checkpath(path)
		checkpath(totarget)
		if checkexists(path) then aliaserror("conflicts with an existing component") end
		if not checkexists(totarget) then aliaserror("does not reference an existing component!") end
		local invoker = tostring(minetest.get_current_modname())
		logaction(log_trace, invoker.." registered a compatability alias making "..totarget.." appear as "..path)
		compat[path] = totarget
		handledeprecated(path, isdeprecated)
	end,
	get = mtrequire,
	check = function(path)
		checkpath(path)
		return checkexists(path)
	end,
	deepcopy = deepcopy,
}

minetest.log("info", "modns interface now exported")
