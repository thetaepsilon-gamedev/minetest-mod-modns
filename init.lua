if minetest.global_exists("modns") then error("modns should not already be defined") end
local registered = {}
local constructors = {}
local compat = {}
local deprecated = {}
local checkpath = function(path)
	if type(path) ~= "string" then error("component path must be a string") end
end



-- I'm thinking of putting this in it's own mod.
local log_trace = "trace"
local log_error = "error"
local log_warning = "warning"
local logaction = function(severity, msg)
	print("[modns] ["..severity.."] "..msg)
end

local deepcopy = table.copy



local checkexists = function(path)
	return (registered[path] ~= nil) or (constructors[path] ~= nil) or (compat[path] ~= nil)
end

local handledeprecated = function(path, isdeprecated)
	if isdeprecated then
		deprecated[path] = true
	end
end


modns = {
	register = function(path, component, isdeprecated)
		checkpath(path)
		if checkexists(path) then error("duplicate component registration for "..path) end
		local comptype = type(component)
		local invoker = tostring(minetest.get_current_modname())
		if comptype == "function" then
			constructors[path] = component
			logaction(log_trace, "constructor function registered for component "..path.." by mod "..invoker)
		elseif comptype == "table" then
			registered[path] = component
			logaction(log_trace, "mod object registered for component "..path.." by mod "..invoker)
		else
			logaction(log_error, "mod "..invoker.." tried to register an unknown object of type "..comptype)
			error("modns.register(): unrecognised object type "..comptype)
		end
		handledeprecated(path, isdeprecated)

		--[[
		-- old code here from before constructor functions were added
		if component == nil then error("component cannot be nil") end
		registered[path] = component
		logaction(log_trace, "component "..path.." set by mod "..minetest.get_current_modname()..": "..tostring(component))
		]]
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
	get = function(path)
		checkpath(path)
		local invoker = tostring(minetest.get_current_modname())
		local result
		local compat_alias = compat[path]
		local fn = constructors[path]

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

		if fn then
			-- note that it is the constructor's responsiblity to perform defensive copies.
			logaccess("running object constructor")
			result = fn()
		else
			local obj = registered[path]
			if obj then
				logaccess("retrieving mod object")
				result = deepcopy(obj)
			else
				logaction(log_error, "mod "..invoker.." tried to retrieve non-existant component "..path)
				error("modns.get(): component "..path.." does not exist")
			end
		end
		return result

		--[[
		local exists = checkexists(path)
		if not exists then error("component does not exist: "..path) end
		logaction(log_trace, "component "..path.." retrieved by mod "..minetest.get_current_modname())
		return exists
		]]
	end,
	check = function(path)
		checkpath(path)
		return checkexists(path)
	end,
	deepcopy = deepcopy,
}

minetest.log("info", "modns interface now exported")
