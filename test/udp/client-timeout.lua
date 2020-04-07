local cosock = require "init"
local socket = cosock.socket

local fast_client_finished = false
local slow_client_finished = false

function fast_client(host, port)
  cosock.spawn(function()
    print("fast client spawn")
    local s = socket.udp()
    s:setpeername(host, port)

    s:send("foo")

    s:settimeout(0.01)

    local resp, err = s:receive()
    assert(resp == nil)
    assert(err == "timeout")


    fast_client_finished = true
    print("fast client exit")
  end, "single client")

end

function slow_client(host, port)
  cosock.spawn(function()
    print("slow client spawn")
    local s = socket.udp()
    s:setpeername(host, port)

    s:send("foo")

    s:settimeout(0.3) -- more than 2x server sleep, other req blocks

    local resp, err = s:receive()
    print(resp, err)
    assert(resp == "foo")

    slow_client_finished = true
    print("slow client exit")
  end, "single client")
end

cosock.spawn(function()
  print("server spawn")
  local s = socket.udp()
  print("sock")
  assert(s:setsockname("*", 0), "bind server")
  local ip, port = s:getsockname()
  assert(ip, port)

  fast_client(ip, port)
  slow_client(ip, port)

  for i=1,2 do
    local pkt, ip, port = s:receivefrom()
    assert(pkt, "receivefrom")
    socket.select(nil, nil, 0.1)
    s:sendto(pkt, ip, port)
  end

  print("server exit")
end)



cosock.run()

assert(fast_client_finished, "fast client not finished")
assert(slow_client_finished, "slow client not finished")

print("--------------- SUCCESS ----------------")
