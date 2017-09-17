if minetest.global_exists("modns") then error("modns should not already be defined") end
local registered = {}
local checkpath = function(path)
	if type(path) ~= "string" then error("component path must be a string") end
end



-- I'm thinking of putting this in it's own mod.
local log_trace = "trace"
local log_error = "error"
local logaction = function(severity, msg)
	print("[modns] ["..severity.."] "..msg)
end



modns = {
	register = function(path, component)
		checkpath(path)
		if registered[path] then error("duplicate component registration for "..path) end
		if component == nil then error("component cannot be nil") end
		registered[path] = component
		logaction(log_trace, "component "..path.." set by mod "..minetest.get_current_modname()..": "..tostring(component))
	end,
	get = function(path)
		checkpath(path)
		local exists = registered[path]
		if not exists then error("component does not exist: "..path) end
		logaction(log_trace, "component "..path.." retrieved by mod "..minetest.get_current_modname())
		return exists
	end,
	check = function(path)
		checkpath(path)
		return (registered[path] ~= nil)
	end
}

minetest.log("modns interface now exported")
