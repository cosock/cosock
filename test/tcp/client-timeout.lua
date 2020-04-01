print("----------------------------------------")
local cosock = require "init"

assert(cosock, "require something")
assert(type(cosock) == "table", "cosock is table")

for k,v in pairs({}) do print(k,v) end

local socket = cosock.socket --[[
local socket = require "socket"
--]]

local function nobl_client(ip, port) -- doesn't block at all
  cosock.spawn(function()
    print("nobl client running")
    local t = socket.tcp()
    assert(t)

    print("nobl client connect")
    local status, msg = t:connect(ip, port)
    assert(status, "connect: "..tostring(msg))

    print("nobl client send")
    t:send("foo\n")

    t:settimeout(0)

    local data, err = t:receive()
    print("nobl client reveived:", data, err)
    assert(err == "timeout")
    print("nobl client exit")

    t:close()
  end, "nobl client")
end

local function fast_client(ip, port) -- waits very little
  cosock.spawn(function()
    print("fast client running")
    local t = socket.tcp()
    assert(t)

    print("fast client connect")
    local status, msg = t:connect(ip, port)
    assert(status, "connect: "..tostring(msg))

    print("fast client send")
    t:send("foo\n")

    t:settimeout(0.001)

    local data, err = t:receive()
    print("fast client reveived:", data, err)
    assert(err == "timeout")
    print("fast client exit")

    t:close()
  end, "fast client")
end

local function slow_client(ip, port) -- waits longer
  cosock.spawn(function()
    print("slow client running")
    local t = socket.tcp()
    assert(t)

    print("slow client connect")
    local status, msg = t:connect(ip, port)
    assert(status, "connect: "..tostring(msg))

    print("slow client send")
    t:send("foo\n")

    t:settimeout(.5)

    local data, err = t:receive()
    print("slow client reveived:", data, err)
    assert(data == "foo") -- newline is removed because of recving by line (default for `receive`)
    print("slow client exit")

    t:close()
  end, "slow client")
end

cosock.spawn(function()
  print("server running")
  local t = socket.tcp()
  assert(t, "no sock")

  assert(t:bind("127.0.0.1", 0), "bind")

  t:listen()

  local ip, port = t:getsockname()

  print("server spawn clients")
  nobl_client(ip, port)
  fast_client(ip, port)
  slow_client(ip, port)

  for i = 1,3 do
    print("server accept")
    local s = t:accept()
    assert(s, "accepted socket")
    print("server spawn recv")
    cosock.spawn(function()
      print("coserver recvive")
      local d = s:receive()
      print("coserver received:", d)
      repeat
        socket.select(nil,nil, 0.25) -- sleep
        if d then s:send(d.."\n") end
        d = s:receive()
      until d == nil
    end, "server "..i)
  end
end, "listen server")

cosock.run()

print("----------------- exit -----------------")
