package.path = package.path .. ';./modules/?.lua;./modules/?/init.lua'

require("extensions.math")

local log = require("log")
local twitch = require("twitch")
local terminal = require("terminal")
local sqlite = require("lsqlite3")
local db = sqlite.open("twitch.db")

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
	flags INTEGER
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

function twitch.user:getFlags(ignoreDonger)
	local flags = 0

	if not ignoreDonger then
		flags = self:getDongerFlags()
	end
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

function twitch.getDongerAverage()
	local stmt = db:prepare("SELECT COUNT(user_id), AVG(size) FROM dongers")
	if not diderror(stmt, db) then
		stmt:step()
		local users, average = stmt:get_uvalues()
		stmt:finalize()
		return users, average
	end
	return 0, 0
end	

function twitch.user:getDongerFlags()
	local stmt = db:prepare("SELECT flags FROM dongers WHERE user_id = ? COLLATE NOCASE;")
	if not diderror(stmt, db) then
		stmt:bind_values(self:getID())
		stmt:step()
		local flags = stmt:get_uvalues()
		stmt:finalize()
		return flags
	end
	return 0
end

function twitch.user:registeredDonger()
	local stmt = db:prepare("INSERT OR IGNORE INTO dongers (user_id, user_name, updated, size) VALUES (?, ?, ?, ?);")
	if diderror(stmt, db) then return false end
	stmt:bind_values(self:getID(), self:getUserName(), os.time(), self:randomDongerSize())
	stmt:step()
	stmt:finalize()

	local stmt = db:prepare("UPDATE dongers SET display_name=?, flags=? WHERE user_id=?;")
	if diderror(stmt, db) then return false end
	stmt:bind_values(self:getName(), self:getFlags(true), self:getID())
	stmt:step()
	stmt:finalize()
	return true
end

function twitch.user:getDonger()
	local stmt = db:prepare("SELECT size, updated, flags FROM dongers WHERE user_id = ? COLLATE NOCASE;")
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

	local centimeters = bit.band(flags, FLAGS.WANTS_CENTIMETERS) > 0

	if updated + minutes < os.time() then
		size, updated = self:randomDongerSize(), os.time()

		local stmt = db:prepare("UPDATE dongers SET size=?, updated=? WHERE user_id=?;")
		if diderror(stmt, db) then return false end
		stmt:bind_values(size, updated, self:getID())
		stmt:step()
		stmt:finalize()
	end

	if centimeters then
		return size * 2.54, "centimeter"
	else
		return size, "inch"
	end
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
		local size, units = user:getDongerSize()
		user:message("{name} has %s %.1f %s donger", string.AOrAn(size), size, units)
	end
end)

twitch.command.add("dongerking", function(user, cmd, args, raw)
	local size, users = twitch.getBiggestDongers()

	local list = table.concatList(users)

	if not size then
		user:message("There are currently no donger kings..")
	elseif #users > 1 then
		user:message("%s are the current donger kings with a %.1f inch dong", list, size)
	else
		user:message("%s is the current donger king with a %.1f inch dong", list, size)
	end	
end)

twitch.command.add("dongeraverage", function(user, cmd, args, raw)
	local users, average = twitch.getDongerAverage()
	user:message("The average donger size of %d %s is %.1f inches", users, string.Plural("user", users), average)
end)

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

	user:message("/me The commands available to dongerbot are: %s", table.concat(cmds, ", "))
end)
twitch.command.alias("commands", "help")
twitch.command.alias("commands", "?")

local function main()
	twitch.chat:think()
end

terminal.new(main, input)
terminal.loop()

print("Done")