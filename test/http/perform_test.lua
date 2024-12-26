local cosock = require "cosock"
local socket = require "cosock.socket"

local function slow_request(id, scheme, request, requests_started, requests_finished, port)
  return function()
    print("id", id)
    table.insert(requests_started, tostring(id))

    local starttime = socket.gettime()
    local url = string.format("%s://127.0.0.1:%s/delay/3", scheme, port)
    print("requesting from", url)
    local body, status = request(url)
    local endtime = socket.gettime()

    print(string.format("request took %s seconds", endtime - starttime))

    print("body", body)
    print("status", status)
    assert(status == 200, "request failed")
    table.insert(requests_finished, tostring(id))

    return endtime - starttime
  end
end

return function (name, scheme, request, port)
  print(string.format("start->%s", name), port)
  local requests_started = {}
  local requests_finished = {}
  -- check that after 1 second that 3 requests have started, but that 0 have finished
  cosock.spawn(function()
    socket.select(nil, nil, 1)

    print("requests started", #requests_started)
    assert(#requests_started == 3, name.." not all requests (or too many) started")
    print("requests finished", #requests_finished)
    assert(#requests_finished == 0, name.." some requests already finished")
  end,
  "checker")
  cosock.spawn(slow_request(1, scheme, request, requests_started, requests_finished, port), name.."-slow1")
  cosock.spawn(slow_request(2, scheme, request, requests_started, requests_finished, port), name.."-slow2")
  cosock.spawn(slow_request(3, scheme, request, requests_started, requests_finished, port), name.."-slow3")
  cosock.run()
  print(name.." requests finished", #requests_finished)
  assert(#requests_finished == 3, name..": not all requests (or too many) finished")
end
