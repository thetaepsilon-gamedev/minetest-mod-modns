local interface = {}

interface.split = function(str, sep, plainmode)
	-- why does this not exist as a lua built-in...
	local tokens = {}
	local position = 1
	local stop = false
	while not stop do
		local istart, iend = str:find(sep, position, plainmode)
		local token
		if istart == nil then
			token = str:sub(position)
			stop = true
		else
			token = str:sub(position, istart-1)
			position = iend+1
		end
		if token == "" then error("null components not allowed in component path!") end
		table.insert(tokens,  token)
	end

	return tokens
end

return interface
