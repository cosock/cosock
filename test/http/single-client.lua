-- disable this test for 5.1 since we can't asyncify
if _VERSION == "Lua 5.1" then os.exit(0) end
local cosock = require "cosock"
local socket = require "cosock.socket"
local http = cosock.asyncify "socket.http"

print("start")

local requests_started = {}
local requests_finished = {}

local function slow_request(id)
  return function()
    print("id", id)
    requests_started[id] = true

    local starttime = socket.gettime()
    local body, status = http.request("http://httpbin.org/delay/3")
    local endtime = socket.gettime()

    print(string.format("request took %s seconds", endtime - starttime))

    print("body", body)
    print("status", status)
    assert(status == 200, "request failed")

    requests_finished[id] = true

    return endtime - starttime
  end
end

-- check that after 1 second that 3 requests have started, but that 0 have finished
cosock.spawn(function()
  socket.select(nil, nil, 1)

  print("requests started", #requests_started)
  assert(#requests_started == 3, "not all requests (or too many) started")
  print("requests finished", #requests_finished)
  assert(#requests_finished == 0, "some requests already finished")
end,
"checker")

cosock.spawn(slow_request(1), "slow1")
cosock.spawn(slow_request(2), "slow2")
cosock.spawn(slow_request(3), "slow3")

cosock.run()

print("requests finished", #requests_finished)
assert(#requests_finished == 3, "not all requests (or too many) finished")

print("--------------- SUCCESS ----------------")
