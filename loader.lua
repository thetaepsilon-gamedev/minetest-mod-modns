-- dynamic loader for registered components
-- given a reservation object (see reservations.lua),
-- a modpath lookup implementation,
-- a "does this file exist?" implementation,
-- a list of platform target directores*,
-- a script loader implementation**,
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

** This is used instead of directly calling dofile() to make using a testing harness somewhat easier.
]]

local strutil = dofile(_modpath.."strutil.lua")
local paths = dofile(_modpath.."paths.lua")
local interface = {}

local evprefix = "modns.loader."
local entirelen = function(t) return t, #t end



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


-- work out the safe representation of a parsed path.
-- see naming-conventions.md for details;
-- characters are "escaped" as needed to produce a path that is unambiguous and valid on all relevant OSes.
-- namely windows, linux-based, osx and the other unix-likes.
local encode_safe_filename = function(path)
	local result = ""
	local first = true
	for index, element in ipairs(path) do
		-- ternaries in lua make my head hurt.
		local sep = first and "" or "."
		result = result..sep..strutil.escape(element, "[0-9a-z_-]", "+")
		first = false
	end
	return result
end
interface.encode_safe_filename = encode_safe_filename

-- counterpart of the above which is used when treating each component as a sub-directory.
-- the dot "." is allowed to be used unescaped in this case.
-- this makes URI-style paths more readable in that case,
-- instead of "github.com" becoming something like "github+2ecom".
local encode_safe_path_component = function(element)
	return strutil.escape(element, "[0-9a-z_.-]", "+")
end
interface.encode_safe_path_component = encode_safe_path_component



local filter = function(table, f)
	local ret = {}
	for key, value in pairs(table) do
		ret[key] = f(value)
	end
	return ret
end

-- constructs the list of modpath-relative files to attempt loading.
local calculate_relative_paths = function(targetlist, dirsep, path)
	local result = {}
	local initfile = "init"
	local ext = ".lua"
	local allinone = encode_safe_filename(path)
	local safepath = filter(path, encode_safe_path_component)

	for _, target in ipairs(targetlist) do
		target = target..dirsep
		table.insert(result, target..allinone..ext)
		local basepath = table.concat(safepath, dirsep)
		table.insert(result, target..basepath..ext)
		table.insert(result, target..basepath..dirsep..initfile..ext)
	end

	return result
end
interface.calculate_relative_paths = calculate_relative_paths



-- find the mod diretory that should own a given path string.
local ev_modfail = evprefix.."mod_lookup_failed"
local ev_modfound = evprefix.."owning_mod_located"
local ev_modnexist = evprefix.."mod_path_failed"
local ev_modpathfound = evprefix.."mod_path_found"
local get_modpath = function(self, pathresult)
	local modpathfinder = self.modpathfinder
	local reservations = self.reservations
	local debugger = self.debugger

	local result = pathresult
	local path = result.tokens

	local modname, closest = reservations:locateparsed(path)
	if modname == nil then
		-- convert the closest match prefix back to a string for error messages
		local longest = result.type.tostring(path, closest)
		debugger({n=ev_modfail, args={path=path, closest=longest}})
		return nil
	end
	debugger({n=ev_modfound, args={path=path, modname=modname}})

	-- this is basically equivalent to minetest.get_modpath(modname),
	-- but is wrapped up so that it can be mimicked outside of MT.
	local modpath = modpathfinder:get(modname)
	local ev
	if modpath ~= nil then
		ev = {n=ev_modnexist, args={modname=modname}}
	else
		ev = {n=ev_modpathfound, args={modname=modname, modpath=modpath}}
	end
	debugger(ev)
	return modpath, modname
end



-- try to locate the file that should be loaded for a given component.
local ev_testpath = evprefix.."attempt_load_component"
local ev_located = evprefix.."component_file_found"
local ev_notfound = evprefix.."component_file_not_found"
local find_component_file = function(self, pathresult, original)
	local debugger = self.debugger
	local filetester = self.filetester
	local dirsep = self.dirsep

	-- work out relative paths, and which mod directory should contain them.
	local relatives = calculate_relative_paths(self.targetlist, dirsep, pathresult.tokens)
	local modpath_base, modname = get_modpath(self, pathresult)
	if modpath_base == nil then return nil end

	local attempts = 0
	for index, relpath in ipairs(relatives) do
		attempts = attempts + 1
		-- construct the full path and ask if it exists.
		fullpath = modpath_base..dirsep..relpath
		debugger({n=ev_testpath, args={component=original, fullpath=fullpath, attempt=index}})
		if filetester:exists(fullpath) then
			debugger({n=ev_located, args={component=original, at=fullpath}})
			return fullpath
		end
	end
	debugger({n=ev_notfound, args={component=original, attempts=attempts}})
end



-- loads a component from file when it is not already in the cache in getcomponent() below.
local load_component_from_file = function(self, pathresult, original)
	local filepath = find_component_file(self, pathresult, original)
	if filepath == nil then error("unable to locate source file for component "..original) end
	return self.fileloader:load(filepath)
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

	-- first check that we're being asked to load something valid.
	-- note: this throws on parse failure
	local pathresult = paths.parse(pathstring)
	-- re-serialise the string to get the normalised path.
	local original = pathresult.type.tostring(entirelen(pathresult.tokens))
	pathstring = original

	-- if we're already in-flight loading this same component,
	-- something somewhere is causing a dependency cycle.
	if loadstate.inflight[pathstring] then
		-- TODO: print out the chain of components causing the cycle
		error("dependency cycle!")
	end

	-- check whether we have the component already cached.
	-- if so, return that directly.
	local cached = caches[pathstring]
	if cached ~= nil then return cached end

	-- else we need to go out to a file.
	-- mark this path as in-flight to catch circular errors.
	loadstate.inflight[pathstring] = true

	-- catch any errors so we can unwind the inflight state first.
	local success, result = pcall(load_component_from_file, self, pathresult, original)

	-- clean up at the end.
	loadstate.inflight[pathstring] = nil

	-- throw any error if not success;
	-- else insert object into cache and return component to caller
	if success then
		caches[pathstring] = result
		return result
	else
		error(result)
	end
end



return interface
