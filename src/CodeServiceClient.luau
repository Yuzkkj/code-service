local Networker = require(script.Parent.Parent.Networker)

local CodeServiceUtils = require(script.Parent.CodeServiceUtils)

--[=[
	@class CodeServiceClient

	Client-side controller that interfaces with the server-side CodeService to redeem promotional codes.
]=]
local CodeServiceClient = {}

--[=[
	@method init
	@within CodeServiceClient

	Initializes the CodeServiceClient.
]=]
function CodeServiceClient.init(self: CodeServiceClient): ()
	self.networker = Networker.client.new("CodeService", self)
end

--[=[
	@method redeeem
	@within CodeServiceClient
	@param code string
	@return boolean
	@return string

	Sends a promotional code redemption request to the server and returns a success status along with a user-friendly status/error message.

	```lua
	local CodeService = require(path.to.CodeService).client

	local result = CodeService:redeem("Update1")
	print(result)
	```
]=]
function CodeServiceClient.redeem(self: CodeServiceClient, code: string): (boolean, string)
	local response = self.networker:fetch("redeem", code)
	local success = response == CodeServiceUtils.REDEEM_ENUMS.success
	local str = CodeServiceUtils.ERROR_CODES[response] or "Unknown Error!"
	return success, str
end

type CodeServiceClient = typeof(CodeServiceClient) & {
	networker: Networker.Client,
}

return CodeServiceClient :: CodeServiceClient
