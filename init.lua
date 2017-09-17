if minetest.global_exists("modns") then error("modns should not already be defined") end
local registered = {}
local checkpath = function(path)
	if type(path) ~= "string" then error("component path must be a string") end
end

modns = {
	register = function(path, component)
		checkpath(path)
		if registered[path] then error("duplicate component registration for "..path) end
		registered[path] = component
	end,
	get = function(path)
		checkpath(path)
		exists = registered[path]
		if not exists then error("component does not exist: "..path) end
		return exists
	end,
	check = function(path)
		checkpath(path)
		return (registered[path] ~= nil)
	end
}
