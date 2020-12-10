print("----------------------------------------")
local cosock = require "cosock"

assert(cosock, "require something")
assert(type(cosock) == "table", "cosock is table")

for k, v in pairs({}) do
  print(k, v)
end

local socket = cosock.socket
local ssl = cosock.ssl

local function nobl_client(ip, port) -- doesn't block at all
  cosock.spawn(
    function()
      print("nobl client running")
      local tcp_sock = socket.tcp()
      assert(tcp_sock)

      print("nobl client connect")
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

      print("nobl client send")
      ssl_sock:send("foo\n")

      ssl_sock:settimeout(0)

      local data, err = ssl_sock:receive()
      print("nobl client reveived:", data, err)
      assert(err == "timeout")
      print("nobl client exit")

      ssl_sock:close()
    end,
    "nobl client"
  )
end

local function fast_client(ip, port) -- waits very little
  cosock.spawn(
    function()
      print("fast client running")
      local tcp_sock = socket.tcp()
      assert(tcp_sock)

      print("fast client connect")
      local status, msg = tcp_sock:connect(ip, port)
      assert(status, "connect: " .. tostring(msg))

      local config = {
        mode = "client",
        protocol = "any",
        cafile = "./test/ssl/certs/root.crt.pem",
        certificate = "./test/ssl/certs/leafB_intermediate1_chain.crt.pem",
        key = "./test/ssl/certs/private/leafB.key.pem",
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

      print("fast client send")
      ssl_sock:send("foo\n")

      ssl_sock:settimeout(0.001)

      local data, err = ssl_sock:receive()
      print("fast client reveived:", data, err)
      assert(err == "timeout")
      print("fast client exit")

      ssl_sock:close()
    end,
    "fast client"
  )
end

local function slow_client(ip, port) -- waits longer
  cosock.spawn(
    function()
      print("slow client running")
      local tcp_sock = socket.tcp()
      assert(tcp_sock)

      print("slow client connect")
      local status, msg = tcp_sock:connect(ip, port)
      assert(status, "connect: " .. tostring(msg))

      local config = {
        mode = "client",
        protocol = "any",
        cafile = "./test/ssl/certs/root.crt.pem",
        certificate = "./test/ssl/certs/leafC_intermediate2_chain.crt.pem",
        key = "./test/ssl/certs/private/leafC.key.pem",
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

      print("slow client send")
      ssl_sock:send("foo\n")

      ssl_sock:settimeout(.5)

      local data, err = ssl_sock:receive()
      print("slow client reveived:", data, err)
      assert(data == "foo") -- newline is removed because of recving by line (default for `receive`)
      print("slow client exit")

      ssl_sock:close()
    end,
    "slow client"
  )
end

cosock.spawn(
  function()
    print("server running")
    local server = socket.tcp()
    assert(server, "no sock")

    assert(server:bind("127.0.0.1", 0), "bind")

    server:listen()

    local ip, port = server:getsockname()

    print("server spawn clients")
    nobl_client(ip, port)
    fast_client(ip, port)
    slow_client(ip, port)

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
      local tcp_sock = server:accept()
      assert(tcp_sock, "accepted socket")
      print("server spawn recv")

      print("server ssl wrap accepted socket")
      local ssl_sock, wrap_err = ssl.wrap(tcp_sock, config)
      assert(ssl_sock, "ssl wrap on accepted socket: " .. tostring(wrap_err))

      print("server ssl dohandshake")
      local success, err = ssl_sock:dohandshake()
      assert(success, "ssl handshake on accepted socket: " .. tostring(err))

      cosock.spawn(
        function()
          print("coserver recvive")
          local d = ssl_sock:receive()
          print("coserver received:", d)
          repeat
            socket.select(nil, nil, 0.25) -- sleep
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
