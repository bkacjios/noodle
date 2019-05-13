require("extensions.string")
local log = require("log")

local command = {
	commands = {},
	room_commands = {},
}

function command.add(name, cb)
	name = name:lower()
	command.commands[name] = {
		name = name,
		callback = cb,
	}
end

function command.alias(name, alias)
	local original = command.commands[name]
	name = name:lower()
	command.commands[alias] = {
		name = alias,
		callback = original.callback,
		alias = name
	}
end

function command.channelAlias(room_id, name, alias)
	local original = command.commands[name]
	alias = alias:lower()
	command.room_commands[room_id] = command.room_commands[room_id] or {}
	command.room_commands[room_id][alias] = {
		name = alias,
		callback = original.callback,
	}
end

function command.poll(user, message)
	local marker = message:sub(1,1)
	if marker == '!' then
		local room_id = user:getChannelID()
		local args = message:parseArgs()
		local cmd = table.remove(args,1)
		local cmd_key = cmd:lower():sub(2)
		local info = command.commands[cmd_key] or command.room_commands[room_id][cmd_key]
		if info then
			local suc, err = pcall(info.callback, user, cmd, args, message)
			if not suc then
				log.error("%s: %s (%q)", user:getName(), message, err)
				return false, ("%s is currently broken.."):format(cmd)
			end
		else
			--log.info("%s: %s (Unknown Command)", user:getName(), message)
			return false, ("Unknown command: %s"):format(cmd)
		end
	end

	return true
end

return command