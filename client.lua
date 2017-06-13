package.path = package.path .. ';./modules/?.lua;./modules/?/init.lua'

require("extensions.math")

local log = require("log")
local twitch = require("twitch")
local terminal = require("terminal")
local sqlite = require("lsqlite3")
local db = sqlite.open("twitch.db")
local lua = require("lua")

local channels = {
	"super_noodle",
	"bkacjios",
	--"amerabu",
	--"atsudota",
}

twitch.connect("oauth:lelgofukurselfnerd")

for _,channel in pairs(channels) do
	twitch.join(channel)
end

local minutes = 20 * 60

db:exec([[CREATE TABLE IF NOT EXISTS dongers (
	user_id INTEGER PRIMARY KEY, 
	user_name TEXT,
	display_name TEXT,
	updated INTEGER,
	size REAL,
	flags INTEGER DEFAULT 0
);]])

local FLAGS = {
	IS_SUBSCRIBER = 1,
	IS_PRIME = 2,
	IS_MODERATOR = 4,
	IS_BROADCASTER = 8,
	WANTS_CENTIMETERS = 16,
}

local function diderror(stmt, db)
	if not stmt then
		log.error("sqlite error: %s", db:errmsg())
		return true
	end
	return false
end

function twitch.user:getFlags()
	local flags = 0
	if self:isSubscriber() then
		flags = bit.bor(flags, FLAGS.IS_SUBSCRIBER)
	end
	if self:isPrime() then
		flags = bit.bor(flags, FLAGS.IS_PRIME)
	end
	if self:isMod() then
		flags = bit.bor(flags, FLAGS.IS_MODERATOR)
	end
	if self:isBroadcaster() then
		flags = bit.bor(flags, FLAGS.IS_BROADCASTER)
	end
	return flags
end

function twitch.getBiggestDongers()
	local max_size
	local users = {}

	local stmt = db:prepare("SELECT MAX(size) FROM dongers WHERE updated + ? > cast(strftime('%s','now') as int)")
	if not diderror(stmt, db) then
		stmt:bind_values(minutes)
		stmt:step()
		max_size = stmt:get_value(0)
		stmt:finalize()
	end

	local stmt = db:prepare("SELECT display_name FROM dongers WHERE updated + ? > cast(strftime('%s','now') as int) AND size >= ?")
	if not diderror(stmt, db) and max_size then
		stmt:bind_values(minutes, max_size)

		for display_name in stmt:urows() do
			table.insert(users, display_name)
		end

		stmt:finalize()
	end

	return max_size, users
end

function twitch.getDongerAverage(flag)
	local stmt
	if flag then
		stmt = db:prepare("SELECT COUNT(user_id), AVG(size) FROM dongers WHERE flags&? > 0")
	else
		stmt = db:prepare("SELECT COUNT(user_id), AVG(size) FROM dongers")
	end
	if not diderror(stmt, db) then
		if flag then
			stmt:bind_values(flag)
		end
		stmt:step()
		local users, average = stmt:get_uvalues()
		stmt:finalize()
		return users, average
	end
	return 0, 0
end	

function twitch.user:registeredDonger()
	local stmt = db:prepare("INSERT OR IGNORE INTO dongers (user_id, user_name, updated, size) VALUES (?, ?, ?, ?);")
	if diderror(stmt, db) then return false end
	stmt:bind_values(self:getID(), self:getUserName(), os.time(), self:randomDongerSize())
	stmt:step()
	stmt:finalize()

	local stmt = db:prepare("UPDATE dongers SET display_name=?, flags=flags|? WHERE user_id=?;")
	if diderror(stmt, db) then return false end
	stmt:bind_values(self:getName(), self:getFlags(), self:getID())
	stmt:step()
	stmt:finalize()
	return true
end

function twitch.user:getDonger()
	local stmt = db:prepare("SELECT size, updated, flags FROM dongers WHERE user_id = ?;")
	if not diderror(stmt, db) then
		stmt:bind_values(self:getID())
		stmt:step()
		local size, updated, flags = stmt:get_uvalues()
		stmt:finalize()
		return size, updated, flags
	end
end

function twitch.user:getDongerSize()
	local size, updated, flags = self:getDonger()

	if updated + minutes < os.time() then
		size, updated = self:randomDongerSize(), os.time()

		local stmt = db:prepare("UPDATE dongers SET size=?, updated=? WHERE user_id=?;")
		if diderror(stmt, db) then return false end
		stmt:bind_values(size, updated, self:getID())
		stmt:step()
		stmt:finalize()
	end

	return size, updated, flags
end

function twitch.user:randomDongerSize()
	local average = 6

	if self:isBroadcaster() then
		average = 9
	elseif self:isMod() then
		average = 7.5
	elseif self:isSubscriber() then
		average = 6
	elseif self:isPrime() then
		average = 5.5
	end

	return math.randombias(1, average, 6)
end

twitch.command.add("donger", function(user, cmd, args, raw)
	if user:registeredDonger() then
		local king_size, kings = twitch.getBiggestDongers()
		local size, updated, flags = user:getDongerSize()

		local centimeters = bit.band(flags, FLAGS.WANTS_CENTIMETERS) > 0

		local units = "inch"
		local print_size = size

		if centimeters then
			units = "centimeter"
			print_size = size * 2.54
		end

		if not king_size or size >= king_size then
			user:message("/me {name} is a donger king with their %.1f %s donger", print_size, units)
		else
			user:message("{name} has %s %.1f %s donger", string.AOrAn(size), print_size, units)
		end
	end
end)
twitch.command.alias("donger", "dong")

twitch.command.add("dongerking", function(user, cmd, args, raw)
	local size, users = twitch.getBiggestDongers()

	local list = table.concatList(users)

	if not size then
		user:message("/me There are currently no donger kings..")
	elseif #users > 1 then
		user:message("%s are the current donger kings with a %.1f inch dong", list, size)
	else
		user:message("%s is the current donger king with a %.1f inch dong", list, size)
	end	
end)
twitch.command.alias("dongerking", "dongerkings")
twitch.command.alias("dongerking", "kingdonger")
twitch.command.alias("dongerking", "kingdong")

twitch.command.add("centimeters", function(user, cmd, args, raw)
	local stmt = db:prepare("UPDATE dongers SET flags=flags|? WHERE user_id=?;")
	if diderror(stmt, db) then return false end
	stmt:bind_values(FLAGS.WANTS_CENTIMETERS, user:getID())
	stmt:step()
	stmt:finalize()

	user:message("{name} will now get their donger size in centimeters")
end)
twitch.command.alias("centimeters", "centimeter")

twitch.command.add("inches", function(user, cmd, args, raw)
	local stmt = db:prepare("UPDATE dongers SET flags=flags&~? WHERE user_id=?;")
	if diderror(stmt, db) then return false end
	stmt:bind_values(FLAGS.WANTS_CENTIMETERS, user:getID())
	stmt:step()
	stmt:finalize()

	user:message("{name} will now get their donger size in inches")
end)
twitch.command.alias("inches", "inch")

twitch.command.add("dongeraverage", function(user, cmd, args, raw)
	local users, average = twitch.getDongerAverage()
	user:message("The average donger size of %d %s is %.1f inches", users, string.Plural("user", users), average)
end)
twitch.command.alias("dongeraverage", "dongeraverages")

twitch.command.add("uptime", function(user, cmd, args, raw)
	if twitch.cooldown(10) then return end

	local channel = user:getChannel()
	local uptime = twitch.getUpTime(channel)

	if uptime then
		user:message("/me {host} has been streaming for %s", uptime)
	else
		user:message("/me {host} is currently offline", uptime)
	end
end)

twitch.command.add("commands", function(user, cmd, args, raw)
	local cmds = {}

	for name, cmd in pairs(twitch.command.commands) do
		if not cmd.alias then
			table.insert(cmds, "!" .. name)
		end
	end

	user:message("/me The commands available to dongerbot are: %s", table.concatList(cmds))
end)
twitch.command.alias("commands", "help")
twitch.command.alias("commands", "?")

twitch.command.add("about", function(user, cmd, args, raw)
	user:message("/me is open source! Check out the code here: https://github.com/bkacjios/noodle")
end)

twitch.command.add("following", function(user, cmd, args, raw)
	local time = user:getFollowTime()

	if time then
		user:message("{name} has been following for %s", time)
	else
		user:message("{name} isn't following...")
	end
end)
twitch.command.alias("following", "followage")

local allowed_lua = {
	["aiarena"] = true,
	["bkacjios"] = true,
	["super_noodle"] = true,
}

twitch.command.add("lua", function(user, cmd, args, raw)
	if allowed_lua[user:getUserName()] then
		lua.run(user, raw:sub(6))
	end
end)

local adverts = {
	"/me DongerAI is open source! Check out the code here: https://github.com/bkacjios/noodle",
	"/me "
}

local next_advert = os.time() + 10 * 60
local advert = 1

local function main()
	twitch.chat:think()

	if next_advert <= os.time() then
		for id, channel in pairs(channels) do
			if advert == 1 then
				twitch.message(channel, "/me is open source! Check out the code here: https://github.com/bkacjios/noodle")
			elseif advert == 2 then
				local time = twitch.getUpTime(channel)
				if time then
					twitch.message(channel, "/me {host} has been streaming for %s", time)
				end
			end
		end

		next_advert = os.time() + 30 * 60
		advert = advert + 1

		if advert > 2 then
			advert = 1
		end
	end
end

terminal.new(main, input)
terminal.loop()

print("Done")