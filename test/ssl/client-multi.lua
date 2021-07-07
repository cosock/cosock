print("----------------------------------------")
local cosock = require "cosock"

assert(cosock, "require something")
assert(type(cosock) == "table", "cosock is table")

for k, v in pairs({}) do
  print(k, v)
end

local socket = cosock.socket
local ssl = cosock.ssl

local function spawn_client(ip, port)
  cosock.spawn(
    function()
      print("client running")
      local tcp_sock = socket.tcp()
      assert(tcp_sock)

      print("client tcp connect")
      local status, msg = tcp_sock:connect(ip, port)
      assert(status, "connect: " .. tostring(msg))

      local config = {
        mode = "client",
        protocol = "any",
        cafile = "./test/ssl/certs/root.crt.pem",
        certificate = "./test/ssl/certs/leafA_intermediate1_chain.crt.pem",
        key = "./test/ssl/certs/private/leafA.key.pem",
        password = "cosock",
        verify = {"peer", "fail_if_no_peer_cert"},
        options = {"all", "no_sslv3"}
      }

      print("client ssl wrap tcp")
      local ssl_sock, wrap_err = ssl.wrap(tcp_sock, config)
      assert(ssl_sock, "ssl wrap on client socket: " .. tostring(wrap_err))

      print("client ssl dohandshake")
      do
        local success, err = ssl_sock:dohandshake()
        assert(success, "ssl handshake on client socket: " .. tostring(err))
      end

      print("client send")
      ssl_sock:send("foo\n")

      local data, err = ssl_sock:receive()
      print("client reveived:", data, err)
      assert(data == "foo") -- newline is removed because of recving by line (default for `receive`)
      print("client exit")

      ssl_sock:close()
    end,
    "client"
  )
end

local function spawn_double_client(ip, port)
  cosock.spawn(
    function()
      print("dclient running")
      local tcp_sock1 = socket.tcp()
      local tcp_sock2 = socket.tcp()
      assert(tcp_sock1)
      assert(tcp_sock2)

      print("dclient tcp connect")
      do
        local status, msg = tcp_sock1:connect(ip, port)
        assert(status, "connect: " .. tostring(msg))
      end

      do
        local status, msg = tcp_sock2:connect(ip, port)
        assert(status, "connect: " .. tostring(msg))
      end

      local config1 = {
        mode = "client",
        protocol = "any",
        cafile = "./test/ssl/certs/root.crt.pem",
        certificate = "./test/ssl/certs/leafB_intermediate1_chain.crt.pem",
        key = "./test/ssl/certs/private/leafB.key.pem",
        password = "cosock",
        verify = {"peer", "fail_if_no_peer_cert"},
        options = {"all", "no_sslv3"}
      }

      print("dclient1 ssl wrap tcp")
      local ssl_sock1, wrap_err1 = ssl.wrap(tcp_sock1, config1)
      assert(ssl_sock1, "ssl wrap on dclient1 socket: " .. tostring(wrap_err1))

      print("dclient1 ssl dohandshake")
      do
        local success, err = ssl_sock1:dohandshake()
        assert(success, "ssl handshake on dclient1 socket: " .. tostring(err))
      end

      local config2 = {
        mode = "client",
        protocol = "any",
        cafile = "./test/ssl/certs/root.crt.pem",
        certificate = "./test/ssl/certs/leafC_intermediate2_chain.crt.pem",
        key = "./test/ssl/certs/private/leafC.key.pem",
        password = "cosock",
        verify = {"peer", "fail_if_no_peer_cert"},
        options = {"all", "no_sslv3"}
      }

      print("dclient2 ssl wrap tcp")
      local ssl_sock2, wrap_err2 = ssl.wrap(tcp_sock2, config2)
      assert(ssl_sock2, "ssl wrap on dclient2 socket: " .. tostring(wrap_err2))

      print("dclient2 ssl dohandshake")
      do
        local success, err = ssl_sock2:dohandshake()
        assert(success, "ssl handshake on dclient2 socket: " .. tostring(err))
      end

      print("dclient send")
      ssl_sock1:send("foo\n")
      ssl_sock2:send("bar\n")
      ssl_sock1:send("baz\n")

      local expect_recv = {[ssl_sock1] = {"foo", "baz"}, [ssl_sock2] = {"bar"}}

      while true do
        local recvt = {}
        for sock, list in pairs(expect_recv) do
          if #list > 0 then
            table.insert(recvt, sock)
          end
        end
        if #recvt == 0 then
          break
        end

        print("ssl dclient call select")
        local recvr, sendr, err = socket.select({ssl_sock1, ssl_sock2}, nil, nil)

        print("ssl dclient select ret", recvr, sendr, err)
        assert(not err, err)
        assert(recvr, "nil recvr")
        assert(type(recvr) == "table", "non-table recvr")
        assert(#recvr > 0, "empty recvr")

        for _, s in pairs(recvr) do
          local data, rerr = s:receive()
          assert(not rerr, rerr)
          print("dclient received:", data)
          for k, v in pairs(expect_recv) do
            print(k, v)
          end
          local expdata = table.remove(expect_recv[s], 1)
          assert(data == expdata, string.format("wrong data, expected '%s', got '%s'", expdata, data))
        end

        local sum = 0
        for _, list in pairs(expect_recv) do
          sum = sum + #list
        end
        print("@@@@@@@@@@@@@@@ dclient left#:", sum)
        if sum == 0 then
          break
        end
      end

      ssl_sock1:close()
      ssl_sock2:close()

      print("dclient exit")
    end,
    "double client"
  )
end

cosock.spawn(
  function()
    print("server running")
    local t = socket.tcp()
    assert(t, "no sock")

    assert(t:bind("127.0.0.1", 0), "bind")

    t:listen()

    local ip, port = t:getsockname()

    print("server spawn clients")
    spawn_client(ip, port)
    spawn_double_client(ip, port)

    local config = {
      mode = "server",
      protocol = "any",
      cafile = "./test/ssl/certs/root.crt.pem",
      certificate = "./test/ssl/certs/leafD_intermediate2_chain.crt.pem",
      key = "./test/ssl/certs/private/leafD.key.pem",
      password = "cosock",
      verify = {"peer", "fail_if_no_peer_cert"},
      options = {"all", "no_sslv3"}
    }

    for i = 1, 3 do
      print("server accept")
      local s = t:accept()
      assert(s, "accepted socket")

      print("server ssl wrap accepted socket")
      local ssl_sock, wrap_err = ssl.wrap(s, config)
      assert(ssl_sock, "ssl wrap on accepted socket: " .. tostring(wrap_err))

      print("server ssl dohandshake")
      local success, err = ssl_sock:dohandshake()
      assert(success, "ssl handshake on accepted socket: " .. tostring(err))

      print("server spawn recv")
      cosock.spawn(
        function()
          print("coserver recvive")
          local d = ssl_sock:receive()
          print("coserver received:", d)
          repeat
            if d then
              ssl_sock:send(d .. "\n")
            end
            d = ssl_sock:receive()
          until d == nil
        end,
        "server " .. i
      )
    end
  end,
  "listen server"
)

cosock.run()

print("----------------- exit -----------------")
