local terminal = require("terminal")
local irc = require("irc")
local ltn12 = require( "ltn12" )
local http = require("socket.http")
local https = require("ssl.https")
local json = require("json")
local log = require("log")

require("extensions.string")
require("extensions.table")

local twitch = {
	chatters = {},
	users = {},
	user = {},
	cool = os.time(),
	command = require("command"),
}

function twitch.initialize()
	log.warn("twitch.initialize() called")
	return irc.new {
		nick = "dongerai",
		track_users = false,
	}
end

function twitch.cooldown(secs)
	if os.time() < twitch.cool then
		return true
	end
	if secs then
		twitch.cool = os.time() + secs
	end
	return false
end

twitch.user.__index = twitch.user

function twitch.user:__tostring()
	return ("%d %s[%q]"):format(self:getID(), self:getUserName(), self:getName())
end

function twitch.user:getName()
	return self["display-name"]
end

function twitch.user:getUserName()
	return self["user-name"]
end

function twitch.user:getID()
	return self["user-id"]
end

function twitch.user:isMod()
	return self.badges["moderator"] and self.badges["moderator"] > 0
end

function twitch.user:getModLevel()
	return self.badges["moderator"] or 0
end

function twitch.user:isTurbo()
	return self.badges["turbo"] and self.badges["turbo"] > 0
end

function twitch.user:isSubscriber()
	return self.badges["subscriber"] and self.badges["subscriber"] > 0
end

function twitch.user:getSubscriberLevel()
	return self.badges["subscriber"] or 0
end

function twitch.user:isAdmin()
	return self.badges["admin"] and self.badges["admin"] > 0
end

function twitch.user:isStaff()
	return self.badges["staff"] and self.badges["staff"] > 0
end

function twitch.user:getStaffLevel()
	return self.badges["staff"] or 0
end

function twitch.user:isGlobalMod()
	return self.badges["global_mod"] and self.badges["global_mod"] > 0
end

function twitch.user:isPrime()
	return self.badges["premium"] and self.badges["premium"] > 0
end

function twitch.user:getPrimeLevel()
	return self.badges["premium"] or 0
end

function twitch.user:isPartner()
	return self.badges["partner"] and self.badges["partner"] > 0
end

function twitch.user:getPartnerLevel()
	return self.badges["partner"] or 0
end

function twitch.user:isBroadcaster()
	return self.badges["broadcaster"] and self.badges["broadcaster"] > 0
end

function twitch.user:isBanable()
	return not self:isStaff() and not self:isGlobalMod() and not self:isAdmin() and not self:isMod()
end

function twitch.user:getChannel()
	return self.channel
end

function twitch.user:getChannelID()
	return self["room-id"]
end

function twitch.user:getFollowTime(channel)
	local username = self:getUserName()
	local channel = channel or self:getChannel()

	self.follow_cache = self.follow_cache or {}

	local gmt = os.date("!*t")
	local now = os.time(gmt)
	local start = self.follow_cache[channel]

	if not start then
		local r, c = twitch.https("https://api.twitch.tv/kraken/users/%s/follows/channels/%s", username, channel)
		if c ~= 200 then return end

		local data = json.decode(r)

		if data.created_at then
			local year, month, day, hour, min, sec = data.created_at:match("(%d%d%d%d)-(%d%d)-(%d%d)T(%d%d):(%d%d):(%d%d)Z")
			start = os.time({year=year, month=month, day=day, hour=hour, min=min, sec=sec, isdst=gmt.isdst})
			self.follow_cache[channel] = start
		end
	end

	return math.SecondsToHuman(now - start)
end

function twitch.https(url, ...)
	local t = {}
	local r, c, h = https.request({
		url = url:format(...),
		sink = ltn12.sink.table(t),
		headers = {
			["Client-ID"] = "jzkbprff40iqj646a697cyrvl0zt2m6",
		},
	})

	r = table.concat(t, "")
	return r, c, h
end

function twitch.getUpTime(channel)
	local r, c = twitch.https("https://api.twitch.tv/kraken/streams/%s", channel)
	if c ~= 200 then return end

	local data = json.decode(r)
	
	if data.stream then
		local year, month, day, hour, min, sec = data.stream.created_at:match("(%d%d%d%d)-(%d%d)-(%d%d)T(%d%d):(%d%d):(%d%d)Z")
		local gmt = os.date("!*t")
		local now = os.time(gmt)
		local start = os.time({year=year, month=month, day=day, hour=hour, min=min, sec=sec, isdst=gmt.isdst})
		return math.SecondsToHuman(now - start)
	end
end

function twitch.getUsersInChat(channel)
	local r, c = http.request(("http://tmi.twitch.tv/group/user/%s/chatters"):format(channel))

	local chatters = {}

	if not r or c ~= 200 then return chatters end

	local data = json.decode(r)

	for _,group in pairs(data.chatters) do
		for _, name in pairs(group) do
			chatters[name] = true
		end
	end

	return chatters
end

function twitch.connect(password)
	twitch.chat = twitch.initialize()

	twitch.setHooks()
	
	twitch.chat:connect({
		host = "irc.chat.twitch.tv",
		port = 6667,
		timeout = 1,
		password = password,
	})

	log.info("Connected to irc.chat.twitch.tv:6667")

	twitch.chat:send("CAP REQ :twitch.tv/tags")
	twitch.chat:send("CAP REQ :twitch.tv/membership")

	log.info("Requested tags + membership")
end

function twitch.join(channel)
	twitch.chat:join("#" .. channel)
	twitch.chat:send(("PRIVMSG %s :.color red"):format(channel))
	twitch.chatters["#" .. channel] = twitch.getUsersInChat(channel)
	log.info("Joined channel %s", channel)
end

function twitch.setHooks()
	twitch.chat:hook("OnJoin", function(user, channel)
		if not twitch.chatters[channel][user.username] then
			--log.info("[%s] %s joined", channel, user.username)
			twitch.chatters[channel][user.username] = true
		end
	end)

	twitch.chat:hook("OnPart", function(user, channel)
		if twitch.chatters[channel][user.username] then
			--log.info("[%s] %s left", channel, user.username)
			twitch.chatters[channel][user.username] = nil
		end
	end)

	twitch.chat:hook("OnDisconnect", function(err, status)
		log.info("twitch chat OnDisconnect called: %s", err)
	end)

	local default_colors = {
		[0] = "#FF0000",
		[1] = "#0000FF",
		[2] = "#00FF00",
		[3] = "#B22222",
		[4] = "#FF7F50",
		[5] = "#9ACD32",
		[6] = "#FF4500",
		[7] = "#2E8B57",
		[8] = "#DAA520",
		[9] = "#D2691E",
		[10] = "#5F9EA0",
		[11] = "#1E90FF",
		[12] = "#FF69B4",
		[13] = "#8A2BE2",
		[14] = "#00FF7F",
	}

	local function get_username_color(username)
		local n = string.byte(username, 1) + string.byte(username, #username)
		return default_colors[n % #default_colors]
	end

	local function createUserTable(tags, hostmask, target)
		local username = hostmask and hostmask:match("(.-)!") or "anonymous"

		local user = twitch.users[target][username] or setmetatable({
			["user-name"] = username,
			channel = target:gsub("#", ""),
		}, twitch.user)

		tags = tags:gsub("\\s", " ")

		for key, value in string.gmatch(tags, ";?([^=]+)=([^;]+)") do
			user[key] = tonumber(value) or value
		end

		user["badges"] = user["badges"] or ""

		if type(user["badges"]) == "string" then
			local badges = user["badges"]
			user["badges"] = {}
			for badge, version in string.gmatch(badges, ",?([^/]+)/([^,]+)") do
				user["badges"][badge] = tonumber(version) or version
			end
		end

		if not user["display-name"] then
			user["display-name"] = user["user-name"]:firstToUpper()
		end

		if not user["color"] then
			user["color"] = get_username_color(username)
		end

		return user
	end

	twitch.chat:hook("OnRaw", function(raw)
		local tags, hostmask, mode, target, message = raw:match("^@(%S+)%s+:(%S+)%s+(%S+)%s+(%S+)%s+:?(.+)$")
		if not tags then
			tags, hostmask, mode, target = raw:match("^@(%S+)%s+:(%S+)%s+(%S+)%s+(%S+)$")
		end

		if not tags then return end

		--log.info("tags = %q, hostmask = %q, target = %q, message = %q", tags, hostmask, target, message)

		if mode == "PRIVMSG" then
			twitch.users[target] = twitch.users[target] or {}

			local user = createUserTable(tags, hostmask, target)
			twitch.users[target][user["user-name"]] = user

			local low = message:lower()

			if (low:find("n1ger") or low:find("n1gger") or low:find("n1g3r") or low:find("n1gg3r") or low:find("niger") or low:find("nigger")) then
				twitch.message(user.channel, "/ban %s", user["user-name"])
				twitch.message(user.channel, "%s is a massive edgelord LUL SEE YA NERD.", user["user-name"])
			end

			twitch.command.poll(user, message)
		elseif mode == "WHISPER" then
			if message:lower() == "!join" then
				
			else
				
			end
		end
	end)
end

function twitch.message(channel, text, ...)
	local args = {...}
	if #args > 0 then
		text = text:format(...)
	end	

	text = text:gsub("%{host%}", channel)

	if string.find(text, "{uptime}", 1, true) then
		local uptime = twitch.getUpTime(channel)
		text = text:gsub("%{uptime%}", uptime or "OFFLINE")
	end

	twitch.chat:sendChat("#" .. channel, text)
end

return twitch