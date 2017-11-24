local interface = {}
interface.patterns = {}

local strutil = dofile(_modpath.."strutil.lua")

-- component type matching
-- return an enum identifier depending on classification.
local enum_pathtype = {}
interface.enum_pathtype = enum_pathtype



-- URI scheme test
-- pattern match information based on IETF RFC3986
-- we don't support hierachical splitting for URIs,
-- as if a URL like http://github.com/... is used,
-- adding sub-component paths would likely form an invalid URL.
-- (e.g. github often requires /blob/master/... inserted to access a file)
local safeschemechar = "[a-zA-Z0-9+.-]"
local safeurichar = "[a-zA-Z0-9+.%/_-]"
local schemepart = "[a-z]"..safeschemechar.."*:"
local urimatch = "^"..schemepart..safeurichar.."*$"
interface.patterns.urimatch = urimatch
-- strip the scheme and hierachial indicator (the "//") if present
local uri_handler = function(path)
	path = path:gsub("^"..schemepart, "", 1)
	path = path:gsub("^//", "", 1)
	if #path == 0 then return nil end
	return { path }
end
enum_pathtype.uri = { label="uri", matchpattern=urimatch, handler=uri_handler }



-- java-style package names.
-- we can't specify * on () in lua patterns.
-- and we can't have any external deps when *we are* the dependency loader.
-- instead, use a simpler initial test and validate more closely by splitting and checking the package levels.
local javamatch = "^[a-z][a-zA-Z0-9_.]*$"
interface.patterns.javamatch = javamatch
local java_handler = function(path)
	local tokens = strutil.split(path, ".", true)
	if #tokens < 1 then return nil end
	for _, token in ipairs(tokens) do
		if #token == 0 then return nil end
		-- note absence of dot separator
		if token:find("^[a-z][a-zA-Z0-9_]*$") == nil then return nil end
	end
	return tokens
end
enum_pathtype.java = {
	label="java",
	matchpattern=javamatch,
	handler=java_handler,
}



-- classify a path by looking for different path pattern types.
-- if this succeeds, a hierachical list of tokens is returned.
local classifypath = function(path, label)
	if not label then label = "component path" end
	if type(path) ~= "string" then error(label.." must be a string") end
	for _, enum in pairs(enum_pathtype) do
		if path:find(enum.matchpattern) == 1 then
			-- run the handler function to check that the initial classification check was correct.
			local result = enum.handler(path)
			if type(result) == "table" then return { type=enum, tokens=result } end
		end
	end
	error(label.." did not match any known types of component path")
end
interface.parse = classifypath



return interface
