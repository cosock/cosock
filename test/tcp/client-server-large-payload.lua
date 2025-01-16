local cosock = require 'cosock'
local socket = cosock.socket

local size = 65535
local chunks = { 1, 4096, 8191, 8192, 8193, 16384, 65535 }

local sock = assert(socket.tcp());
sock:bind('0.0.0.0', 0, 16)
sock:setoption('reuseaddr', true)
sock:listen(1)

print('listening on:', sock:getsockname())
local addr, port = sock:getsockname()

local running = #chunks
local killer, killed = cosock.channel.new()

cosock.spawn(function()
  while true do
    local recvr, _, err = socket.select({sock, killed}, {})

    if err or recvr[1] == killed then
      break
    end

    -- accept a new client
    local client = assert(sock:accept())
    print("server accepted")

    -- spawn handler for new client
    cosock.spawn(function()
      -- receive a request for a certian number of bytes
      local size = assert(client:receive())
      print("size", size)
      local size = tonumber(size)
      print('recieved request for:', size, client)

      -- echo bytes back to client
      local ct = assert(client:send(string.rep('*', size, '')))
      print('sent', ct)
      assert(ct == size, "send incomplete")

      -- clean up socket
      print("server close", size)
      client:close()
    end)
  end
  print("close server socket")
  sock:close()
end, 'blob server')

for i, chunk in ipairs(chunks) do
  cosock.spawn(function()
    socket.select({}, {}, i* 0.1)
    print("client connect", chunk)
    local client = assert(socket.tcp())
    -- connect to the server
    assert(client:connect(addr, port))
    -- send a large number of bytes
    local request = tostring(size).."\n"
    print("client", chunk, "requesting", request)
    assert(client:send(request), "failed to send in chunk "..chunk)
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
      --print('recvd', #s, 'so far')
    end
    assert(#s == size)
    print("client close", chunk)
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
