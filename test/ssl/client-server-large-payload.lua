local cosock = require 'cosock'
local socket = cosock.socket
local ssl = cosock.ssl

local size = 65535
local chunks = { 1, 4096, 8191, 8192, 8193, 16384, 65535 }

local sock = assert(socket.tcp());
sock:bind('0.0.0.0', 0)
sock:setoption('reuseaddr', true)
sock:listen(32)

print('listening on:', sock:getsockname())
local addr, port = sock:getsockname()

local running = #chunks
local killer, killed = cosock.channel.new()

cosock.spawn(function()
  local accepted = 0
  while true do
    local recvr, _, err = socket.select({sock, killed}, {})

    if err or recvr[1] == killed then
      break
    end
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
    -- accept a new client
    local client = assert(sock:accept())
    accepted = accepted + 1
    print("server ssl wrap accepted socket")
    client = assert(ssl.wrap(client, config))
    assert(client:dohandshake())
    -- spawn handler for new client
    cosock.spawn(function()
      local sock_num = accepted
      local chunk_size = math.floor(size / sock_num)
      local sent = 0
      local size = tonumber(assert(client:receive()))
      print(sock_num, 'received request for:', size)
      while sent < size do
        local send_size = chunk_size
        if sent + chunk_size > size then
          send_size = size - sent
        end
        local ct = assert(client:send(string.rep('*', send_size)))
        -- print('sent', ct)
        sent = sent + ct
        -- yield
        cosock.socket.sleep(0.25)
      end
      -- echo bytes back to client
      assert(sent == size, "send incomplete")

      -- clean up socket
      client:close()
    end, string.format("accepted-%s", accepted))
  end
  sock:close()
end, 'blob server')

for _, chunk in ipairs(chunks) do
  cosock.spawn(function()
    local client = assert(socket.tcp())
    -- connect to the server
    assert(client:connect(addr, port))
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
    client = assert(ssl.wrap(client, config))
    assert(client:dohandshake())
    -- send a large number of bytes
    assert(client:send(tostring(size).."\n"))
    local s = ''
    local byte_ct = chunk
    -- receive those bytes in chunks
    while #s < size do
      -- NOTE: This loop must be silent or GH actions dies from too much logging
      --       uncomment locally for debugging

      -- if the last chunk would block forever because the chunk size isn't
      -- equal, reduce the byte_ct to the appropriate value
      if size - #s < byte_ct then
        --print(string.format('%s - %s = %s', size, #s, size - #s))
        byte_ct = size - #s
      end
      --print('receiving', byte_ct)
      s = s .. assert(client:receive(byte_ct))
      -- print('recvd', #s, 'so far')
    end
    assert(#s == size)
    client:close()

    -- last one alive, lock the door (aka, kill the server)
    running = running - 1
    if running <= 0 then
      killer:send()
    end
  end, 'blob client')
end

cosock.run()
print('Exited successfully')
