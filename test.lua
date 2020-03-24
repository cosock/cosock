print("----------------------------------------")
local cosock = require "init"

assert(cosock, "require something")
assert(type(cosock) == "table", "cosock is table")

for k,v in pairs({}) do print(k,v) end

local socket = cosock.socket --[[
local socket = require "socket"
--]]

function spawn_client(ip, port)
  cosock.spawn(function()
    print("running client")
    local t = socket.tcp()
    assert(t)

    print("client connect")
    local status, msg = t:connect(ip, port)
    assert(status, "connect: "..tostring(msg))

    print("client send")
    t:send("foo\n")

    local data, err = t:receive()
    print("client reveived:", data, err)
    assert(data == "foo") -- newline is removed because of recving by line (default for `receive`)
    print("client exit")
  end)
end

function spawn_double_client(ip, port)
  cosock.spawn(function()
    print("running client")
    local t1 = socket.tcp()
    local t2 = socket.tcp()
    assert(t1)
    assert(t2)

    print("dclient connect")
    local status, msg = t1:connect(ip, port)
    assert(status, "connect: "..tostring(msg))
    local status, msg = t2:connect(ip, port)
    assert(status, "connect: "..tostring(msg))

    print("dclient send")
    t1:send("foo\n")
    t2:send("bar\n")
    t1:send("baz\n")

    local data, err = t1:receive()
    print("dclient reveived:", data, err)
    assert(data == "foo")

    local data, err = t1:receive()
    print("dclient reveived:", data, err)
    assert(data == "baz")

    local data, err = t2:receive()
    print("dclient reveived:", data, err)
    assert(data == "bar")

    print("dclient exit")
  end)
end

cosock.spawn(function()
  print("running server")
  local t = socket.tcp()
  assert(t, "no sock")

  assert(t:bind("127.0.0.1", 0), "bind")

  t:listen()

  local ip, port = t:getsockname()

  print("spawn client")
  spawn_client(ip, port)
  spawn_double_client(ip, port)

  for i = 1,3 do
    print("server accept")
    local s = t:accept()
    print("server start recv")
      cosock.spawn(function()
      local d = s:receive()
      print("server received:", d)
      repeat
        if d then s:send(d.."\n") end
        d = s:receive()
      until d == nil
    end)
  end
end)

cosock.run()

print("----------------- exit -----------------")
