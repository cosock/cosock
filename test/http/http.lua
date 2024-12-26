-- disable this test for 5.1 since we can't asyncify
if _VERSION == "Lua 5.1" then os.exit(0) end
local cosock = require "cosock"
local perform_test = require "test.http.perform_test"
local port = tonumber(table.pack(...)[1] or "8080")

perform_test("http", "http", cosock.asyncify("socket.http").request, port)

cosock.run()

print("--------------- SUCCESS ----------------")
