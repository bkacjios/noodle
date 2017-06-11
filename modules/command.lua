require("extensions.string")
local log = require("log")

local command = {
	commands = {},
}

function command.add(name, cb)
	command.commands[name] = {
		name = name,
		callback = cb,
	}
end

function command.alias(name, alias)
	local original = command.commands[name]
	command.commands[alias] = {
		name = alias,
		callback = original.callback,
		alias = name
	}
end

function command.poll(user, message)
	local marker = message:sub(1,1)
	if marker == '!' then
		local args = message:parseArgs()
		local cmd = table.remove(args,1)
		local info = command.commands[cmd:lower():sub(2)]
		if info then
			local suc, err = pcall(info.callback, user, cmd, args, message)
			if not suc then
				log.error("%s: %s (%q)", user["display-name"], message, err)
				return false, ("%s is currently broken.."):format(cmd)
			end
		else
			log.info("%s: %s (Unknown Command)", user["display-name"], message)
			return false, ("Unknown command: %s"):format(cmd)
		end
	end

	return true
end

return command