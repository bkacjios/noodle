local terminal = require("terminal")
local irc = require("irc")
local ltn12 = require( "ltn12" )
local http = require("socket.http")
local https = require("ssl.https")
local json = require("dkjson")
local log = require("log")

require("extensions.string")
require("extensions.table")

local twitch = {
	chat = irc.new {
		nick = "dongerai",
		track_users = false,
	},
	chatters = {},
	users = {},
	user = {},
	cool = os.time(),
	command = require("command"),
}

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
	return ("twitch.user %s[%q]"):format(self["user-name"], self["display-name"])
end

function twitch.user:getName()
	return self["display-name"]
end

function twitch.user:getUserName()
	return self["user-name"]
end

function twitch.user:getID()
	return tonumber(self["user-id"])
end

function twitch.user:isMod()
	return self.mod
end

function twitch.user:isSubscriber()
	return self.subscriber
end

function twitch.user:isPrime()
	return self.turbo
end

function twitch.user:isBroadcaster()
	return self.broadcaster
end

function twitch.user:getChannel()
	return self.channel
end

function twitch.user:getChannelID()
	return tonumber(self["room-id"])
end

function twitch.user:message(text, ...)
	twitch.message(self.channel, text:gsub("%{name%}", self["display-name"]), ...)
end

function twitch.user:getFollowTime(channel)
	local username = self:getUserName()
	local channel = channel or self:getChannel()

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
			["Client-ID"] = "p59zoqvt4joe9gqzqbs5cycbhc3nr6",
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

twitch.chat:hook("OnRaw", function(raw)
	local tags, hostmask, channel, message = raw:match("^@(%S+)%s+:(%S+)%s+PRIVMSG[^#]+#(%S+)%s+:?(.+)")

	if tags and channel and message then
		local username = hostmask:match("([^!]+)")

		twitch.users[channel] = twitch.users[channel] or {}

		local user = twitch.users[channel][username] or setmetatable({
			channel = channel,
			["user-name"] = username,
			["display-name"] = username:firstToUpper(),
			["broadcaster"] = username == channel,
			follow_cache = {},
		}, twitch.user)

		twitch.users[channel][username] = user

		for key, value in string.gmatch(tags, ";([^=]+)=([^;]+)") do
			if key == "subscriber" or key == "mod" or key == "turbo" then
				user[key] = value == "1"
			else
				user[key] = value
			end
		end

		if not user["user-id"] or not user["user-name"] or not user["display-name"] then
			print("USER MALFORMED")
			print(raw)
			for k,v in pairs(user) do print(k,v) end
			return
		end

		twitch.command.poll(user, message)
	end
end)

function twitch.message(channel, text, ...)
	twitch.chat:sendChat("#" .. channel, text:format(...):gsub("%{host%}", channel))
end

return twitch