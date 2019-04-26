local lfs = require("lfs")

--lfs.chdir(arg[0]:match("^(.*[/\\])[^/\\]-$"))

package.path = package.path .. ';./modules/?.lua;./modules/?/init.lua'

require("extensions.math")

local log = require("log")
local twitch = require("twitch")
local terminal = require("terminal")
local sqlite = require("lsqlite3")
local db = sqlite.open("twitch.db")
local lua = require("lua")
local concommand = require("concommand")
local socket = require("socket")

require("shunting")

local channels = {}

local CHANNEL_CONFIGS = {}
local CHANNEL_ADVERTS = {}
local ADVERT_TIMERS = {}
local ADVERT_NEXT = {}

local SETTINGS = {
	DISABLED = 0,
	ENABLED = 1,
	BAN_SMALL = 2,
	ADVERTS = 4,
}

db:exec([[CREATE TABLE IF NOT EXISTS channels (
	room_id INTEGER UNIQUE,
	channel TEXT PRIMARY KEY,
	settings INTEGER DEFAULT 0,
	advert_cooldown INTEGER DEFAULT 900,
	size_cooldown INTEGER DEFAULT 600,
	size_units TEXT DEFAULT 'inch',
	size_name TEXT DEFAULT 'donger',
	size_ban_min TEXT DEFAULT 0,
	size_ban_length INTEGER DEFAULT 120,
	size_min INTEGER DEFAULT 1,
	size_max INTEGER DEFAULT 24,
	size_average INTEGER DEFAULT 4,
	size_bonus_broadcaster INTEGER DEFAULT 8,
	size_bonus_staff INTEGER DEFAULT 5,
	size_bonus_mod INTEGER DEFAULT 4,
	size_bonus_vip INTEGER DEFAULT 3,
	size_bonus_sub INTEGER DEFAULT 2,
	size_bonus_prime INTEGER DEFAULT 1,
	size_king TEXT DEFAULT 'king',
	size_pleb TEXT DEFAULT 'pleb',
	size_format TEXT DEFAULT '{name} has a {size-length} {size-units} {size-name}',
	size_format_king TEXT DEFAULT '{name} is a {size-name} {size-king} with a {size-length} {size-units} {size-name}',
	size_format_pleb TEXT DEFAULT '{name} is a {size-name} {size-pleb} with a {size-length} {size-units} {size-name}',
	size_format_ban TEXT DEFAULT '{name} {size-name} is so pathetically small they have been banished for {size-ban-length} seconds'
);]])

db:exec([[CREATE TABLE IF NOT EXISTS adverts (
	room_id INTEGER NOT NULL,
	hash INTEGER NOT NULL,
	message TEXT NOT NULL
);]])

db:exec([[CREATE TABLE IF NOT EXISTS users (
	user_id INTEGER PRIMARY KEY AUTOINCREMENT,
	user_name TEXT NOT NULL,
	display_name TEXT NOT NULL,
	created INTEGER DEFAULT CURRENT_TIMESTAMP NOT NULL,
	updated INTEGER DEFAULT CURRENT_TIMESTAMP NOT NULL,
);]])

db:exec([[CREATE TABLE IF NOT EXISTS sizes (
	user_id INTEGER NOT NULL,
	room_id INTEGER NOT NULL,
	updated INTEGER DEFAULT CURRENT_TIMESTAMP NOT NULL,
	size REAL DEFAULT 0 NOT NULL,
	flags INTEGER DEFAULT 0
);]])

local function diderror(stmt, db)
	if not stmt then
		log.error("sqlite error: %s", db:errmsg())
		return true
	end
	return false
end

function twitch.start()
	twitch.connect("oauth:huehuehuehuehuehuehue")

	local stmt = db:prepare("SELECT * FROM channels WHERE settings&? > 0")
	if not diderror(stmt, db) then
		stmt:bind_values(SETTINGS.ENABLED)

		for row in stmt:nrows() do
			local room_id = row["room_id"]

			twitch.join(row["channel"])

			local seconds = math.random(1, row["advert_cooldown"])

			ADVERT_TIMERS[room_id] = os.time() + seconds

			for key, value in pairs(row) do
				CHANNEL_CONFIGS[room_id] = CHANNEL_CONFIGS[room_id] or {}
				CHANNEL_CONFIGS[room_id][key] = value
			end
		end
		stmt:finalize()
	end

	local stmt = db:prepare("SELECT room_id, hash, message FROM adverts")
	if not diderror(stmt, db) then
		for room_id, hash, message in stmt:urows() do
			CHANNEL_ADVERTS[room_id] = CHANNEL_ADVERTS[room_id] or {}
			CHANNEL_ADVERTS[room_id][hash] = message
		end
		stmt:finalize()
	end
end

twitch.start()

local FLAGS = {
	NONE = 0,
	IS_BROADCASTER = 1,
	IS_PRIME = 2,
	IS_VIP = 4,
	IS_SUBSCRIBER = 8,
	IS_MODERATOR = 16,
	IS_ADMIN = 32,
}

function twitch.getChannelSetting(room_id, setting)
	return CHANNEL_CONFIGS[room_id][setting]
end

function twitch.user:message(text, ...)
	text = text:gsub("%{username%}", self["user-name"])
	text = text:gsub("%{name%}", self["display-name"])

	text = string.gsub(text, "(%{.-%})", function(setting)
		setting = setting:gsub("%{(.-)%}", "%1")
		setting = setting:gsub("-", "_")
		return CHANNEL_CONFIGS[self["room-id"]][setting]
	end)

	twitch.message(self.channel, text, ...)
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

function twitch.getTotalSizes(room_id, flag)
	local stmt
	if flag then
		stmt = db:prepare("SELECT COUNT(user_id), SUM(size) FROM sizes WHERE flags & ? > 0 AND room_id = ?;")
	else
		stmt = db:prepare("SELECT COUNT(user_id), SUM(size) FROM sizes WHERE room_id = ?;")
	end
	if not diderror(stmt, db) then
		if flag then
			stmt:bind_values(flag, room_id)
		else
			stmt:bind_values(room_id)
		end
		stmt:step()
		local users, total = stmt:get_uvalues()
		stmt:finalize()
		return users, total
	end
	return 0, 0
end

function twitch.getBiggestSize(room_id)
	local max_size

	local stmt = db:prepare("SELECT MAX(size) as size FROM sizes WHERE cast(strftime('%s',updated) AS INT) + ? > cast(strftime('%s','now') AS INT) AND room_id = ?;")
	if not diderror(stmt, db) then
		stmt:bind_values(CHANNEL_CONFIGS[room_id]["size_cooldown"], room_id)
		stmt:step()
		max_size = stmt:get_value(0)
		stmt:finalize()
	end

	return max_size
end

function twitch.getSmallestSize(room_id)
	local min_size

	local stmt = db:prepare("SELECT MIN(size) FROM sizes WHERE cast(strftime('%s',updated) + ? > cast(strftime('%s','now') AS INT) AND room_id = ?;")
	if not diderror(stmt, db) then
		stmt:bind_values(CHANNEL_CONFIGS[room_id]["size_cooldown"], room_id)
		stmt:step()
		min_size = stmt:get_value(0)
		stmt:finalize()
	end

	return min_size
end

function twitch.getKings(room_id)
	local users = {}
	local max_size = twitch.getBiggestSize(room_id)

	if not max_size or max_size <= 0 then
		return max_size, users
	end

	local stmt = db:prepare("SELECT display_name FROM sizes, users WHERE cast(strftime('%s', sizes.updated) AS INT) + ? > cast(strftime('%s','now') AS INT) AND sizes.size >= ? AND sizes.room_id = ? AND users.user_id = sizes.user_id;")
	if not diderror(stmt, db) then
		stmt:bind_values(CHANNEL_CONFIGS[room_id]["size_cooldown"], max_size, room_id)

		for display_name in stmt:urows() do
			table.insert(users, display_name)
		end

		stmt:finalize()
	end

	return max_size, users
end

function twitch.getPlebs(room_id)
	local users = {}
	local min_size = twitch.getSmallestSize(room_id)

	if not min_size or min_size <= 0 then
		return min_size, users
	end

	local stmt = db:prepare("SELECT display_name FROM sizes, users WHERE cast(strftime('%s', sizes.updated) AS INT) + ? > cast(strftime('%s','now') AS INT) AND size <= ? AND sizes.room_id = ? AND users.user_id = sizes.user_id;")
	if not diderror(stmt, db) then
		stmt:bind_values(CHANNEL_CONFIGS[room_id]["size_cooldown"], min_size, room_id)

		for display_name in stmt:urows() do
			table.insert(users, display_name)
		end

		stmt:finalize()
	end

	return min_size, users
end

function twitch.getAverageSizes(flag)
	local stmt
	if flag then
		stmt = db:prepare("SELECT COUNT(user_id), AVG(size) FROM sizes WHERE flags&? > 0;")
	else
		stmt = db:prepare("SELECT COUNT(user_id), AVG(size) FROM sizes;")
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

function twitch.user:update()
	local stmt = db:prepare("INSERT OR IGNORE INTO users (user_id, user_name, display_name) VALUES (?, ?, ?);")
	if diderror(stmt, db) then return false end
	stmt:bind_values(self:getID(), self:getUserName(), self:getName())
	stmt:step()
	stmt:finalize()

	local stmt = db:prepare("UPDATE users SET display_name = ?, updated = datetime('now') WHERE display_name != ? AND user_id = ?;")
	if diderror(stmt, db) then return false end
	stmt:bind_values(self:getName(), self:getName(), self:getID())
	stmt:step()
	stmt:finalize()
	return true
end

function twitch.user:getSize()
	local stmt = db:prepare("INSERT OR IGNORE INTO sizes (user_id, room_id, flags) VALUES (?, ?, ?);")
	if diderror(stmt, db) then return false end
	stmt:bind_values(self:getID(), self:getChannelID(), self:getFlags())
	stmt:step()
	stmt:finalize()

	local stmt = db:prepare("SELECT size, cast(strftime('%s', updated) AS INT) AS updated, flags FROM sizes WHERE user_id = ? AND room_id = ?;")
	if not diderror(stmt, db) then
		stmt:bind_values(self:getID(), self:getChannelID())
		stmt:step()
		local size = stmt:get_value(0)
		local updated = stmt:get_value(1)
		local flags = stmt:get_value(2)
		stmt:finalize()
		return size, updated, flags
	end
end

function twitch.user:updateSize()
	local size, updated, flags = self:getSize()

	if not size or updated + CHANNEL_CONFIGS[self:getChannelID()]["size_cooldown"] < os.time() then
		size = self:randomSize()

		local stmt = db:prepare("UPDATE sizes SET size = ?, updated = CURRENT_TIMESTAMP WHERE user_id = ? AND room_id = ?;")
		if diderror(stmt, db) then return false end
		stmt:bind_values(size, self:getID(), self:getChannelID())
		stmt:step()
		stmt:finalize()
	end

	return size, updated, flags
end

function twitch.user:randomSize()
	local config = CHANNEL_CONFIGS[self["room-id"]]

	local average = config["size_average"]

	if self:isBroadcaster() then
		average = average + config["size_bonus_broadcaster"]
	end
	if self:isMod() then
		average = average + self:getModLevel() * config["size_bonus_mod"]
	end
	if self:isSubscriber() then
		average = average + self:getSubscriberLevel() * config["size_bonus_sub"]
	end
	if self:isPrime() then
		average = average + self:getPrimeLevel() * config["size_bonus_prime"]
	end

	return math.round(math.randombias(config["size_min"], config["size_max"], average, 0.5), 1)
end

concommand.Add("say", function(cmd, args, raw)
	twitch.message(args[1], args[2])
end)

concommand.Add("lel", function(cmd, args, raw)
	twitch.message(args[1], args[2]:gsub(".", function(a) return a .. "\n" end))
end)

local crc16 = require("crc16")

twitch.command.add("advert", function(user, cmd, args, raw)

	if not user:isBroadcaster() then return end

	if not args[1] then
		user:message("{name}, the advert usage is %s <add, remove, list> [ID or message]", cmd, args[1])
		return
	end

	local room_id = user:getChannelID()

	CHANNEL_ADVERTS[room_id] = CHANNEL_ADVERTS[room_id] or {}

	if args[1]:lower() == "add" then
		local message = raw:sub(#cmd + 6)

		if #message <= 0 then
			user:message("{name}, please provide an advert message %s %s <message>", cmd, args[1])
			return
		end

		local hash = crc16(message)

		if not CHANNEL_ADVERTS[room_id][hash] then
			local stmt = db:prepare("INSERT OR IGNORE INTO adverts (room_id, hash, message) VALUES (?, ?, ?);")
			if diderror(stmt, db) then return false end

			stmt:bind_values(room_id, hash, message)
			stmt:step()
			stmt:finalize()

			user:message("Successfully added advert as ID: %x", hash)

			CHANNEL_ADVERTS[room_id][hash] = message
		else
			user:message("/me Error: Duplicate advertisement")
		end
	elseif args[1]:lower() == "remove" then
		if not args[2] then
			user:message("{name}, please provide a advert ID %s %s <advert ID>", cmd, args[1])
			return
		end

		local hash = tonumber(args[2], 16)

		local stmt = db:prepare("DELETE FROM adverts WHERE room_id = ? AND hash = ?;")
		if diderror(stmt, db) then return false end
		stmt:bind_values(room_id, hash)
		stmt:step()
		stmt:finalize()

		if CHANNEL_ADVERTS[room_id] then
			CHANNEL_ADVERTS[room_id][hash] = nil
			user:message("Successfully removed advert")
		else
			user:message("/me Error: Advertisement not found")
		end
	elseif args[1]:lower() == "list" then
		local stmt = db:prepare("SELECT hash, message FROM adverts WHERE room_id = ?;")
		if not diderror(stmt, db) then
			stmt:bind_values(room_id)

			for hash, message in stmt:urows() do
				user:message("%x: %s", hash, message)
			end

			stmt:finalize()
		end
	end
end)

twitch.command.add("donger", function(user, cmd, args, raw)
	if user:update() then
		local king_size = twitch.getBiggestSize(user:getChannelID())
		local size, flags = user:updateSize()

		if not king_size or size >= king_size then
			user:message(CHANNEL_CONFIGS[user["room-id"]]["size_format_king"]:gsub("%{size%-length%}", size))
		else
			user:message(CHANNEL_CONFIGS[user["room-id"]]["size_format"]:gsub("%{size%-length%}", size))
		end

		print(size, CHANNEL_CONFIGS[user["room-id"]]["size_ban_min"])

		if size <= CHANNEL_CONFIGS[user["room-id"]]["size_ban_min"] then
			user:message(CHANNEL_CONFIGS[user["room-id"]]["size_format_ban"]:gsub("%{size%-length%}", size))
			user:message("/timeout {username} {size-ban-length}")
		end
	end
end)

twitch.command.add("king", function(user, cmd, args, raw)
	local size, users = twitch.getKings(user:getChannelID())

	local list = table.concatList(users)

	if not size then
		user:message("There are currently no {size-name} {size-king}..")
	elseif #users > 1 then
		user:message("%s are the current {size-name} {size-king} with a %.1f {size-units} {size-name}", list, size)
	else
		user:message("%s is the current {size-name} {size-king} with a %.1f {size-units} {size-name}", list, size)
	end	
end)

twitch.command.add("pleb", function(user, cmd, args, raw)
	local size, users = twitch.getPlebs(user:getChannelID())

	local list = table.concatList(users)

	if not size then
		user:message("There are currently no {size-name} {size-name} {size-pleb}..")
	elseif #users > 1 then
		user:message("%s are the current {size-name} {size-pleb} with a %.1f inch {size-name}", list, size)
	else
		user:message("%s is the current {size-name} {size-pleb} with a %.1f inch {size-name}", list, size)
	end
end)

twitch.command.add("dongs", function(user, cmd, args, raw)
	local users, total = twitch.getTotalSizes(user:getChannelID())
	user:message("The collective total of %i {size-name}s is %.1f inches", users, total)
end)

twitch.command.add("math", function(user, cmd, args, raw)
	local stack, err = math.postfix(raw:sub(#cmd+2))

	if not stack then
		user:message("/me {name}, error: %s", err)
		return
	end

	local total = math.solve_postfix(stack)
	local node = math.postfix_to_infix(stack)
	local expression = math.infix_to_string(node)

	user:message("%s = %s", expression, total)
end)

local advantage_shortcuts = {
	"advantage",
	"advan",
	"adv",
}

local disadvantage_shortcuts = {
	"disadvantage",
	"disadvan",
	"disadv",
	"dadvan",
	"disad",
	"dadv",
}

twitch.command.add("roll", function(user, cmd, args, raw)
	local str = raw:sub(#cmd+2)

	for _, dadv in pairs(disadvantage_shortcuts) do
		str = str:gsub(dadv, "min(d20, d20)")
	end
	for _, adv in pairs(advantage_shortcuts) do
		str = str:gsub(adv, "max(d20, d20)")
	end

	if not str:match("%d-[Dd]%d+") then
		str = "d20" .. (str ~= "" and (" %s"):format(str) or "")
	end

	local rolls = {}
	local orig_str = str

	str = string.gsub(str, "(%d-)[Dd](%d+)", function(num, dice)
		num = tonumber(num) or 1
		dice = tonumber(dice)
		local results, total = math.roll(dice, num)
		rolls[dice] = rolls[dice] or {}
		for k, result in pairs(results) do
			table.insert(rolls[dice], result)
		end
		return ("(%s)"):format(table.concat(results, "+"))
	end)

	local stack, err = math.postfix(str)

	if not stack then
		local message = ("/me {name} error: %s"):format(err)
		user:message(message)
		return
	end

	local node = math.postfix_to_infix(stack)
	local equation = math.infix_to_string(node)
	local total = math.solve_postfix(stack)

	user:message(("{name} rolled %s and got %s"):format(orig_str, total))
end)

local rank_translation = {
	["mod"] = FLAGS.IS_MODERATOR,
	["moderator"] = FLAGS.IS_MODERATOR,
	["sub"] = FLAGS.IS_SUBSCRIBER,
	["subsciber"] = FLAGS.IS_SUBSCRIBER,
}

twitch.command.add("average", function(user, cmd, args, raw)
	local rank = args[1]
	if rank and rank_translation[rank:lower()] then
		rank = rank:lower()
	else
		rank = "user"
	end

	local flag = rank_translation[rank]

	local users, average = twitch.getAverageSizes(flag)
	user:message("The average snorf size of %d %s is %.1f inches", users, string.Plural(rank, users), average)
end)

twitch.command.add("uptime", function(user, cmd, args, raw)
	if twitch.cooldown(10) then return end

	local channel = user:getChannel()
	local uptime = twitch.getUpTime(channel)

	if uptime then
		user:message("{host} has been streaming for %s", uptime)
	else
		user:message("{host} is currently offline", uptime)
	end
end)

twitch.command.add("commands", function(user, cmd, args, raw)
	local cmds = {}

	for name, cmd in pairs(twitch.command.commands) do
		if not cmd.alias and cmd.name ~= "lua" then
			table.insert(cmds, "!" .. name)
		end
	end

	user:message("/me The commands available to DongerAI are: %s", table.concatList(cmds))
end)
twitch.command.alias("commands", "help")
twitch.command.alias("commands", "?")

twitch.command.add("following", function(user, cmd, args, raw)
	local time = user:getFollowTime()

	if time then
		user:message("{name} has been following {host} for %s", time)
	else
		user:message("{name} isn't following {host}...")
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
	["super_noodle"] = {
		"/me Check out the Stream group: http://steamcommunity.com/groups/SuperNoodleGroup",
		"/me Check out the Discord: https://discord.gg/6GzcwWH",
		"/me {host} has been streaming for {uptime}",
	},
}

local current_advert = {}

local next_advert = os.time() + 15 * 60
local advert = 1

local function main()
	if twitch.chat.think then
		local succ, err = pcall(twitch.chat.think, twitch.chat)
		if not succ then
			log.warn("twitch chat error: %s", err)
		end
	else
		log.warn("reconnecting to twitch...")
		socket.sleep(3)
		twitch.start()
	end

	for room_id, next_advert in pairs(ADVERT_TIMERS) do
		if CHANNEL_ADVERTS[room_id] and next_advert <= os.time() then
			ADVERT_TIMERS[room_id] = os.time() + CHANNEL_CONFIGS[room_id]["advert_cooldown"]

			local key, message = next(CHANNEL_ADVERTS[room_id], ADVERT_NEXT[room_id])

			if not key then -- End of the table? Try again at the start
				ADVERT_NEXT[room_id] = nil
				key, message = next(CHANNEL_ADVERTS[room_id], ADVERT_NEXT[room_id])
			end

			if key and message then
				ADVERT_NEXT[room_id] = key
				twitch.message(CHANNEL_CONFIGS[room_id]["channel"], message)
			end
		end
	end
end

terminal.new(main, concommand.loop)
terminal.loop()

db:close_vm()
db:close()

print("Done")