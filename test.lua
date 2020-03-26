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
    print("client running")
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

    t:close()
  end, "client")
end

function spawn_double_client(ip, port)
  cosock.spawn(function()
    print("dclient running")
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

    local expect_recv = {[t1] = {"foo", "baz"}, [t2] = {"bar"}}

    while true do
      local recvt = {}
      for socket, list in pairs(expect_recv) do
        if #list > 0 then table.insert(recvt, socket) end
      end
      if #recvt == 0 then break end

      print("dclient call select")
      local recvr, sendr, err = socket.select({t1, t2}, nil, nil)

      print("dclient select ret", recvr, sendr, err)
      assert(not err, err)
      assert(recvr, "nil recvr")
      assert(type(recvr) == "table", "non-table recvr")
      assert(#recvr > 0, "empty recvr")

      for _, t in pairs(recvr) do
        local data, err = t:receive()
        print("dclient received:", data)
        for k,v in pairs(expect_recv) do print(k,v) end
        local expdata = table.remove(expect_recv[t], 1)
        assert(data == expdata, string.format("wrong data, expected '%s', got '%s'", expdata, data))
      end

      local sum = 0
      for _skt, list in pairs(expect_recv) do
        sum = sum + #list
      end
      print("@@@@@@@@@@@@@@@ dclient left#:", sum)
      if sum == 0 then break end
    end

    t1:close()
    t2:close()

    print("dclient exit")
  end, "double client")
end

cosock.spawn(function()
  print("server running")
  local t = socket.tcp()
  assert(t, "no sock")

  assert(t:bind("127.0.0.1", 0), "bind")

  t:listen()

  local ip, port = t:getsockname()

  print("server spawn clients")
  spawn_client(ip, port)
  spawn_double_client(ip, port)

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
        if d then s:send(d.."\n") end
        d = s:receive()
      until d == nil
    end, "server "..i)
  end
end, "listen server")

cosock.run()

print("----------------- exit -----------------")
