local lua = {}

local log = require("log")
local twitch = require("twitch")

local env = {
	json = require("json"),
	crc16 = require("crc16"),
	assert = assert,
	error = error,
	ipairs = ipairs,
	next = next,
	pairs = pairs,
	pcall = pcall,
	select = select,
	tonumber = tonumber,
	tostring = tostring,
	type = type,
	unpack = unpack,
	_VERSION = _VERSION,
	xpcall = xpcall,
	bit = {
		tobit = bit.tobit,
		tohex = bit.tohex,
		bnot = bit.bnot,
		band = bit.band,
		bor = bit.bor,
		bxor = bit.bxor,
		lshift = bit.lshift,
		rshift = bit.rshift,
		arshift = bit.arshift,
		rol = bit.rol,
		ror = bit.ror,
		bswap = bit.bswap,
	},
	math = {
		abs = math.abs, acos = math.acos, asin = math.asin, 
		atan = math.atan, atan2 = math.atan2, ceil = math.ceil, cos = math.cos, 
		cosh = math.cosh, deg = math.deg, exp = math.exp, floor = math.floor, 
		fmod = math.fmod, frexp = math.frexp, huge = math.huge, 
		ldexp = math.ldexp, log = math.log, log10 = math.log10, max = math.max, 
		min = math.min, modf = math.modf, pi = math.pi, pow = math.pow, 
		rad = math.rad, random = math.random, sin = math.sin, sinh = math.sinh, 
		sqrt = math.sqrt, tan = math.tan, tanh = math.tanh,
	},
	string = {
		byte = string.byte, char = string.char, find = string.find, 
		format = string.format, gmatch = string.gmatch, gsub = string.gsub, 
		len = string.len, lower = string.lower, match = string.match, 
		rep = string.rep, reverse = string.reverse, sub = string.sub, 
		upper = string.upper,
	},
	table = {
		concat = table.concat,
		foreach = table.foreach,
		foreachi = table.foreachi,
		getn = table.getn,
		insert = table.insert,
		maxn = table.maxn,
		pack = table.pack,
		unpack = table.unpack or unpack,
		remove = table.remove, 
		sort = table.sort,
	},
	coroutine = {
		create = coroutine.create,
		resume = coroutine.resume,
		running = coroutine.running,
		status = coroutine.status,
		wrap = coroutine.wrap,
		yield = coroutine.yield,
	},
	jit = {
		version = jit.version,
		version_num = jit.version_num,
		os = jit.os,
		arch = jit.arch,
	},
	os = {
		clock = os.clock,
		date = os.date,
		difftime = os.difftime,
		time = os.time,
	},
}
env._G = env
env.__newindex = env

local function sandbox(user, func, buffer)
	local getPlayer = function(name)
		for username,user in pairs(twitch.users["#" .. user.channel]) do
			if user:getName() == name or user:getUserName() == name then
				return user
			end
		end
	end

	env.__index = function(self, index)
		return rawget(env, index) or getPlayer(index)
	end,

	setfenv(func, setmetatable({
		print = function(...)
			local txts = {}
			for k,v in ipairs({...}) do
				table.insert(txts, v == nil and "nil" or tostring(v))
			end
			table.insert(buffer, table.concat(txts, ", "))
		end,
		me = user,
		twitch = twitch,
		users = twitch.users["#" .. user.channel],
		channel = user:getChannel(),
	}, env))
end

function lua.run(user, str)
	local lua, err = loadstring(str, user:getName())

	log.debug("%s ran: %s", user, str)
	
	if not lua then
		log.warn("%s compile error: (%s)", user, err)
		user:message("/me compile error: %s", err)
	else
		local buffer = {}
		sandbox(user, lua, buffer)

		local quota = 5000

		local timeout = function()
			error("instructions exceeded", 2)
		end

		jit.off()
		debug.sethook(timeout, "", quota)

		local status, err = pcall(lua)

		if #buffer > 0 then
			user:message(table.concat(buffer, "    "):ellipse(512))
		end

		if not status then
			log.warn("%s runtime error: (%s)", user, err)
			user:message("/me runtime error: %s", err)
		elseif err then
			user:message(tostring(err))
		end

		debug.sethook()
		jit.on()
	end
end

return lua