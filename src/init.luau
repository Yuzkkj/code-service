local CodeServiceClient = require(script.CodeServiceClient)
local CodeServiceServer = require(script.CodeServiceServer)

return {
	client = CodeServiceClient,
	server = CodeServiceServer,
}
