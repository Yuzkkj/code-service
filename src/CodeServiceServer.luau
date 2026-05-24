local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local DataService = require(script.Parent.Parent.DataService).server
local Networker = require(script.Parent.Parent.Networker)
local ServicePlayerData = require(script.Parent.Parent.ServicePlayerData)

local CodeServiceUtils = require(script.Parent.CodeServiceUtils)

if RunService:IsClient() then
	return {} :: CodeServiceServer
end

--[=[
	@interface Code
	@within CodeServiceServer
	.reward string | { string } -- The reward identifier(s) (as a string or array of strings) to grant on redemption.
	.params { any } | { { any } } | nil -- Optional parameters passed to the corresponding reward callback(s).
	.userIds { number }? -- Optional array of specific Roblox User IDs permitted to redeem this code.
	.active boolean -- Whether the code is active and eligible for redemption.
	.expiration number? -- Optional Unix timestamp (seconds since epoch) after which the code is expired.
	.uses number? -- Optional maximum number of uses remaining for this code.

	Represents a promotional code's configuration and status in the DataStore.
]=]
type Code = {
	reward: string | { string },
	params: { any } | { { any } } | nil,
	userIds: { number }?,
	active: boolean,
	expiration: number?,
	uses: number?,
}

--[=[
	@type Codes { [string]: Code }
	@within CodeServiceServer

	A dictionary mapping promotional code names to their configuration structures.
]=]
type Codes = { [string]: Code }

--[=[
	@type InventoryCodes { [string]: boolean }
	@within CodeServiceServer

	A dictionary mapping code names to booleans, indicating which codes a player has redeemed.
]=]
type InventoryCodes = { [string]: boolean }

--[=[
	@type RewardCallbacks { [string]: (...any?) -> () }
	@within CodeServiceServer

	A dictionary mapping reward identifiers to their execution callback functions.
]=]
type RewardCallbacks = { [string]: (...any?) -> () }

local DATA_STORE_KEY = "Codes"
local UPDATE_FREQUENCY = 60
local REDEEM_ENUMS = CodeServiceUtils.REDEEM_ENUMS

local PLAYER_DATA_TEMPLATE = {
	redeeming = false,
}

--[=[
	@type PlayerData { redeeming: boolean }
	@within CodeServiceServer

	Temporary session state for each player redeeming a code.
]=]
type PlayerData = {
	redeeming: boolean,
}

--[=[
	@class CodeServiceServer

	Server-side service that handles the management, persistence, validation, and redemption of promotional codes.
]=]
local CodeService = {
	--[=[
		@prop debug boolean
		@within CodeServiceServer

		When enabled, prints detailed debug logs to the console.
	]=]
	debug = false,

	--[=[
		@prop dataStore DataStore
		@within CodeServiceServer

		The Roblox DataStore instance used for persisting code information.
	]=]
	dataStore = DataStoreService:GetDataStore("Codes"),
}

local function log(...)
	if CodeService.debug then
		print(...)
	end
end

--[=[
	@method init
	@within CodeServiceServer
	@param rewardCallbacks RewardCallbacks -- The dictionary of reward callback functions.

	Initializes the CodeService server-side, starts the periodic code update loop, and registers the networking channel.

	```lua
	local DataService = require(path.to.DataService).server
	local CodeService = require(path.to.CodeService).server

	CodeService:init({
		money = function(player: Player, amount: number)
			DataService:update(player, "money", function(money)
				return money + amount
			end)
		end
	})
	```
]=]
function CodeService.init(self: CodeServiceServer, rewardCallbacks: RewardCallbacks): ()
	self.rewardCallbacks = rewardCallbacks
	self.networker = Networker.server.new("CodeService", self, { self.redeem })
	self.codes = {}
	self.playerData = ServicePlayerData.new(PLAYER_DATA_TEMPLATE)

	task.spawn(function()
		while true do
			self:_update()
			task.wait(UPDATE_FREQUENCY)
		end
	end)
end

function CodeService._update(self: CodeServiceServer): ()
	log("Updating codes")
	local s, result = pcall(function()
		return self.dataStore:GetAsync(DATA_STORE_KEY)
	end)

	if not s then
		warn("Failed to get codes", result)
		return
	end

	self.codes = result
	log("Updated codes", result)
end

--[=[
	@method listActiveCodes
	@within CodeServiceServer

	Prints a list of all currently active codes to the console.

	```lua
	local CodeService = require(path.to.CodeService).server

	CodeService:listActiveCodes()
	```
]=]
function CodeService.listActiveCodes(self: CodeServiceServer): ()
	for name, code in self.codes do
		if
			code.active
			and (not code.expiration or code.expiration > os.time())
			and (not code.uses or code.uses > 0)
		then
			print(name, code)
		end
	end
end

--[=[
	@method addUserIdsToCode
	@within CodeServiceServer
	@param code string
	@param userIds {number}

	Appends a list of Roblox User IDs to an existing code's restricted user list.

	```lua
	local CodeService = require(path.to.CodeService).server

	CodeService:addUserIdsToCode("Update1", { 1234567, 7654321 })
	```
]=]
function CodeService.addUserIdsToCode(self: CodeServiceServer, code: string, userIds: { number }): ()
	code = string.lower(code)
	print("Adding user ids to code", code, userIds)
	local s, e = pcall(function()
		self.dataStore:UpdateAsync(DATA_STORE_KEY, function(codes: Codes)
			if not codes or not codes[code] then
				error("Code not found" .. code)
				return
			end

			local users = codes[code].userIds or {}
			for _, userId in ipairs(userIds) do
				if not table.find(users, userId) then
					table.insert(users, userId)
				end
			end
			codes[code].userIds = users
			return codes
		end)
	end)

	if s then
		print("Successfully added user ids to code", code)
	else
		warn("Failed to add user ids to code", e)
	end

	self:_update()
end

--[=[
	@method add
	@within CodeServiceServer
	@param code string 
	@param info Code
	
	Registers a new code with the specified configuration and saves it to the DataStore.

	```lua
	local CodeService = require(path.to.CodeService).server

	CodeService:add("Update1", {
		reward = { "money" },
		params = { 1000 },
		uses = 500,
	})
	```
]=]
function CodeService.add(self: CodeServiceServer, code: string, info: Code): ()
	code = string.lower(code)
	print("Adding code", code, info)
	info.active = true
	local s, e = pcall(function()
		self.dataStore:UpdateAsync(DATA_STORE_KEY, function(codes: Codes)
			if not codes then
				codes = {}
			end

			if codes[code] then
				error("Code already exists: " .. code)
				return
			end

			codes[code] = info
			return codes
		end)
	end)

	if s then
		print("Successfully added code", code)
	else
		warn("Failed to add code", e)
	end

	self:_update()
end

--[=[
	@method remove
	@within CodeServiceServer
	@param code string
	
	Deletes a code from the DataStore completely.

	```lua
	local CodeService = require(path.to.CodeService).server

	CodeService:remove("Update1")
	```
]=]
function CodeService.remove(self: CodeServiceServer, code: string): ()
	code = string.lower(code)
	print("Removing code", code)
	local s, e = pcall(function()
		self.dataStore:UpdateAsync(DATA_STORE_KEY, function(codes: Codes)
			codes[code] = nil
			return codes
		end)
	end)

	if s then
		print("Successfully removed code", code)
	else
		warn("Failed to remove code", e)
	end

	self:_update()
end

--[=[
	@method deactivate
	@within CodeServiceServer
	@param code string
	
	Marks a code as inactive without deleting its data from the DataStore.

	```lua
	local CodeService = require(path.to.CodeService).server

	CodeService:deactivate("Update1")
	```
]=]
function CodeService.deactivate(self: CodeServiceServer, code: string): ()
	code = string.lower(code)
	print("Deactivating code", code)
	local s, e = pcall(function()
		self.dataStore:UpdateAsync(DATA_STORE_KEY, function(codes: Codes)
			if not codes or not codes[code] then
				error("Code not found" .. code)
				return
			end

			codes[code].active = false
			return codes
		end)
	end)

	if s then
		print("Successfully deactivated code", code)
	else
		warn("Failed to deactivate code", e)
	end

	self:_update()
end

--[=[
	@method hasRedeemedCode
	@within CodeServiceServer
	@param player Player
	@param code string
	@return boolean

	Checks if a specific player has already redeemed the given code.

	```lua
	local CodeService = require(path.to.CodeService).server

	local alreadyRedeemed = CodeService:hasRedeemedCode(player, "Update1")
	print(alreadyRedeemed)
	```
]=]
function CodeService.hasRedeemedCode(_: CodeService, player: Player, code: string): boolean
	local alreadyRedeemedCodes = DataService:get(player, "_codes")
	if alreadyRedeemedCodes and alreadyRedeemedCodes[code] then
		return true
	end

	return false
end

function CodeService._redeem(self: CodeServiceServer, player: Player, codeId: string): number
	local code = self.codes[codeId]
	if not code then
		return REDEEM_ENUMS.invalid
	end

	local isExpired = code.expiration and code.expiration < os.time()
	if not code.active or isExpired then
		return REDEEM_ENUMS.expired
	end

	if code.uses and code.uses <= 0 then
		return REDEEM_ENUMS.outOfUses
	end

	if self:hasRedeemedCode(player, codeId) then
		return REDEEM_ENUMS.alreadyRedeemed
	end

	if code.userIds then
		local userId = player.UserId
		local index = table.find(code.userIds, userId)
		if not index then
			return REDEEM_ENUMS.wrongUser
		end
	end

	if not code.uses then
		return REDEEM_ENUMS.success
	end

	local s, e = pcall(function()
		self.dataStore:UpdateAsync(DATA_STORE_KEY, function(codes: Codes)
			if not codes or not codes[codeId] then
				error("Code not found" .. codeId)
				return
			end

			local uses = codes[codeId].uses
			if not uses then
				return
			end

			codes[codeId].uses = uses - 1
			return codes
		end)
	end)

	if not s then
		warn("Failed to decrement uses", e)
		return REDEEM_ENUMS.err
	end

	return REDEEM_ENUMS.success
end

function CodeService._reward(self: CodeServiceServer, player: Player, reward: string, ...: any?): number?
	log("Rewarding player", player, reward, ...)
	local callback = self.rewardCallbacks[reward]
	if not callback then
		warn("No callback found for reward", reward)
		return
	end

	return callback(player, ...)
end

--[=[
	@method redeem
	@within CodeServiceServer
	@param player Player
	@param code string
	@return number

	Handles a code redemption request from a client. Performs validation, updates player data, and awards rewards.

	```lua
	local CodeService = require(path.to.CodeService).server

	local result = CodeService:redeem(player, "Update1")
	print(result)
	```
]=]
function CodeService.redeem(self: CodeServiceServer, player: Player, code: string)
	local playerData = self.playerData:get(player)
	if playerData.redeeming then
		return REDEEM_ENUMS.err
	end
	playerData.redeeming = true

	code = string.lower(code)
	local redeemStatus = self:_redeem(player, code)
	log("Redeem status", redeemStatus)
	if redeemStatus ~= REDEEM_ENUMS.success then
		playerData.redeeming = false
		return redeemStatus
	end

	log("Updating player codes")
	DataService:update(player, "_codes", function(codes: InventoryCodes)
		if not codes then
			codes = {}
		end

		codes[code] = true
		return codes
	end)

	playerData.redeeming = false

	local codeInfo = self.codes[code]

	local rewardTbl = codeInfo.reward
	local paramsTbl = codeInfo.params
	if type(codeInfo.reward) == "string" then
		rewardTbl = { rewardTbl }
		paramsTbl = { paramsTbl }
	end

	for i = 1, #rewardTbl do
		local reward = rewardTbl[i]
		local params = paramsTbl[i]
		local s, e = pcall(self._reward, self, player, reward, params[1], params[2], params[3], params[4], params[5])
		if not s then
			warn("Failed to reward player", player, codeInfo.reward, e)
			return REDEEM_ENUMS.err
		end
	end

	return REDEEM_ENUMS.success
end

type CodeServiceServer = typeof(CodeService) & {
	networker: Networker.Server,
	codes: Codes,
	debug: boolean,
	dataStore: DataStore,
	rewardCallbacks: RewardCallbacks,
	playerData: ServicePlayerData.ServicePlayerData<PlayerData>,
}

return CodeService :: CodeServiceServer
