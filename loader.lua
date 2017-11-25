-- dynamic loader for registered components
-- given a reservation object (see reservations.lua),
-- a modpath lookup implementation,
-- a "does this file exist?" implementation,
-- a list of platform target directores*,
-- and a loaded component cache implementation,
-- this object will take care of loading components as needed.
-- it supports those component scripts requesting others in turn
-- (detected cycles cause a hard error).

--[[
* Where possible, it is encouraged that mods split apart portable code and code which accesses MT apis.
For portable code for a component com.foo, where the mod to look up the path is known,
the file could be in any of the following:
modname/lib/com.foo.lua
modname/lib/com/foo.lua
modname/lib/com/foo/init.lua

However, minetest "natives" would be searched like so:
modname/natives/minetest/com.foo.lua
...
The reason for this split is so that components that would do something different in MT vs an external test script can be separate.
E.g. some components that use the MT api or other MT-specific globals would be in natives,
but "pure" components and algorithms can go in lib.
The first found match is always the winner;
the target directory order for this elsewhere in this mod prefers portable code first.
]]

-- object allocation/initialisation steps
local init_loadstate = function(self)
	self.loadstate = {}
	self.loadstate.inflight = {}
end

local allocself = function()
	local self = {}
	init_loadstate(self)
	self.caches = {}
	return self
end



-- actual component retrieval.
-- takes the path string to use.
local getcomponent = function(self, pathstring)
	-- objects are only added to the array when completely loaded.
	-- however, if two files circularly depend on each other via mtrequire(),
	-- an infinite recursion will occur.
	-- prevent this by marking the currently loading component so that re-entrancy is detected.
	-- circular references result in an error.
	local loadstate = self.loadstate
	local caches = self.cache

	-- common function to reset the state if we have to throw.
	-- this ensures that the "locks" for mods won't stay held.
	local reset_and_throw = function(throwable)
		init_loadstate(self)
		error(throwable)
	end

	if loadstate.inflight[pathstring] then
		-- TODO: print out the chain of components causing the cycle
		reset_and_throw("dependency cycle!")
	end

	-- check whether we have the component already cached.
	-- if so, return that directly.
	local cached = caches[pathstring]
	if cached ~= nil then return cached end

	reset_and_throw("NotImplemented: modload-dofile")

	-- else we need to go out to a file.
	-- mark this path as in-flight to catch circular errors.
	loadstate.inflight[pathstring] = true

	-- clean up at the end.
	loadstate.inflight[pathstring] = nil
end
