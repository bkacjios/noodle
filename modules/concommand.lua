local concommand = {
	commands = {},
}

local log = require("log")

require("extensions.math")
require("extensions.string")
require("extensions.table")

function concommand.Add(name, cb, help)
	concommand.commands[name] = {
		name = name,
		callback = cb,
		help = help,
	}
end

function concommand.Alias(name, alias)
	local original = concommand.commands[name]
	concommand.commands[alias] = {
		name = name,
		callback = original.callback,
		help = original.help,
	}
end

concommand.Add("help", function(cmd, args)
	print("Command List")
	for name, cmd in pairs(concommand.commands) do
		if name == cmd.name then
			print(("> %-12s"):format(cmd.name) .. (cmd.help and (" - " .. cmd.help) or ""))
		end
	end
end, "Display a list of all commands")
concommand.Alias("help", "commands")

concommand.Add("exit", function(cmd, args)
	os.exit()
end, "Close the program")
concommand.Alias("exit", "quit")
concommand.Alias("exit", "quti")

function concommand.loop()
	local msg = io.read()
	if not msg then return end
	local args = string.parseArgs(msg)
	local cmd = table.remove(args,1)
	if not cmd then return end
	local info = concommand.commands[cmd:lower()]
	if info then
		local suc, err = pcall(info.callback, cmd, args, msg)
		if not suc then
			log.error("%s (%q)", msg, err)
		end
	else
		print(("Unknown command: %s"):format(cmd))
	end
end

return concommand