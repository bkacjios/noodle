local terminal = {}

local ev = require("ev")
local log = require("log")

local loop = ev.Loop.default

local function exit(loop, sig, revents)
	loop:unloop()
end

function terminal.new(main, input)
	local sig = ev.Signal.new(exit, ev.SIGINT)
	sig:start(loop)

	local timer = ev.Timer.new(function()
		local succ, err = xpcall(main, debug.traceback)
		if not succ then log.error(err) end
	end, 0.1, 0.1)

	if input then
		local evt = ev.IO.new(function()
			local succ, err = xpcall(input, debug.traceback)
			if not succ then log.error(err) end
		end, 0, ev.READ)
		evt:start(loop)
	end
	
	timer:start(loop)
end

function terminal.loop()
	ev.Loop.default:loop()
	print()
end

return terminal