local core = require('core')
local package = require('../package')

local API = require('./API')
local Socket = require('./Socket')

local defaultOptions = {
	maxMessages = 100,
	largeThreshold = 100,
	fetchMembers = false,
}

local Client = core.Emitter:extend()

function Client:initialize(customOptions)
	self.api = API(self)
	self.socket = Socket(self)
	if customOptions then
		self:loadOptions(customOptions)
	else
		self.options = defaultOptions
	end
end

function Client:loadOptions(customOptions)
	local options = {}
	for k, v in pairs(defaultOptions) do
		options[k] = customOptions[k] or defaultOptions[k]
	end
	self.options = options
end

Client.meta.__tostring = function(self)
	return 'instance of Client'
end

-- overwrite emit method to make it non-blocking
-- original code copied from core.lua
function Client:emit(name, ...)
	local handlers = rawget(self, 'handlers')
	if not handlers then return end
	local namedHandlers = rawget(handlers, name)
	if not namedHandlers then return end
	for i = 1, #namedHandlers do
		local handler = namedHandlers[i]
		if handler then coroutine.wrap(handler)(...) end
	end
	for i = #namedHandlers, 1, -1 do
		if not namedHandlers[i] then
			table.remove(namedHandlers, i)
		end
	end
end

function Client:run(a, b)
	return coroutine.wrap(function()
		if b then
			self:loginWithEmail(a, b)
		else
			self:loginWithToken(a)
		end
		self:connectWebSocket()
	end)()
end

function Client:loginWithEmail(email, password)
	warning('Email login is discouraged, use token login instead')
	local data = self.api:getToken({email = email, password = password})
	if not data.token then
		failure(data.email and data.email[1] or data.password and data.password[1])
	end
	self:loginWithToken(data.token)
end

function Client:loginWithToken(token)
	self.token = token
	self.api:setToken(token)
end

function Client:connectWebSocket()

	local gateway, connected
	local filename = 'gateway.cache'
	local cache = io.open(filename, 'r')

	if cache then
		gateway = cache:read()
		connected = self.socket:connect(gateway)
		cache:close()
	end

	if not connected then
		gateway = self.api:getGateway().url
		connected = self.socket:connect(gateway)
		cache = nil
	end

	if connected then
		if not cache then
			cache = io.open(filename, 'w')
			if cache then cache:write(gateway):close() end
		end
		self.socket:handlePayloads()
	else
		failure('Bad gateway: ' .. gateway)
	end

end

-- cache accessors --

function Client:getPrivateChannelById(id)
	return self.privateChannels:get(id)
end

function Client:getUserById(id)
	return self.users:get(id)
end

function Client:getUserByName(username)
	return self.users:get('username', username)
end

function Client:getGuildById(id)
	return self.guilds:get(id)
end

function Client:getGuildByName(name)
	return self.guilds:get('name', name)
end

function Client:getChannelById(id)
	return self:getPrivateChannelById(id) or self:getGuildChannelById(id) or nil
end

function Client:getTextChannelById(id)
	return self:getPrivateChannelById(id) or self:getGuildTextChannelById(id) or nil
end

function Client:getGuildChannelById(id)
	for guild in self:getGuilds() do
		local channel = guild:getChannelById(id)
		if channel then return channel end
	end
end

function Client:getGuildTextChannelById(id)
	for guild in self:getGuilds() do
		local channel = guild:getTextChannelById(id)
		if channel then return channel end
	end
end

function Client:getGuildVoiceChannelById(id)
	for guild in self:getGuilds() do
		local channel = guild:getVoiceChannelById(id)
		if channel then return channel end
	end
end

function Client:getGuildRoleById(id)
	for guild in self:getGuilds() do
		local role = guild:getRoleById(id)
		if role then return role end
	end
end

-- cache iterators --

function Client:getPrivateChannels()
	return self.privateChannels:iter()
end

function Client:getGuilds()
	return self.guilds:iter()
end

function Client:getUsers()
	return self.users:iter()
end

function Client:getChannels()
	return coroutine.wrap(function()
		for channel in self:getPrivateChannels() do
			coroutine.yield(channel)
		end
		for guild in self:getGuilds() do
			for channel in guild:getChannels() do
				coroutine.yield(channel)
			end
		end
	end)
end

function Client:getTextChannels()
	return coroutine.wrap(function()
		for channel in self:getPrivateChannels() do
			coroutine.yield(channel)
		end
		for guild in self:getGuilds() do
			for channel in guild:getTextChannels() do
				coroutine.yield(channel)
			end
		end
	end)
end

function Client:getGuildChannels()
	return coroutine.wrap(function()
		for guild in self:getGuilds() do
			for channel in guild:getChannels() do
				coroutine.yield(channel)
			end
		end
	end)
end

function Client:getGuildTextChannels()
	return coroutine.wrap(function()
		for guild in self:getGuilds() do
			for channel in guild:getTextChannels() do
				coroutine.yield(channel)
			end
		end
	end)
end

function Client:getGuildVoiceChannels()
	return coroutine.wrap(function()
		for guild in self:getGuilds() do
			for channel in guild:getVoiceChannels() do
				coroutine.yield(channel)
			end
		end
	end)
end

function Client:getGuildRoles()
	return coroutine.wrap(function()
		for guild in self:getGuilds() do
			for role in guild:getRoles() do
				coroutine.yield(role)
			end
		end
	end)
end

function Client:getGuildMembers()
	return coroutine.wrap(function()
		for guild in self:getGuilds() do
			for member in guild:getMembers() do
				coroutine.yield(member)
			end
		end
	end)
end

-- aliases --

Client.getRoles = Client.getGuildRoles
Client.getMembers = Client.getGuildMembers
Client.getVoiceChannels = Client.getGuildVoiceChannels

Client.getRoleById = Client.getGuildRoleById
Client.getVoiceChannelById = Client.getGuildVoiceChannelById

return Client
