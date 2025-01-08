local cosock = require "cosock"

cosock.spawn(function()
  -- create socket, will be send-ready by default
  local s = cosock.socket.udp()
  assert(s:setsockname("localhost", 0))

  -- ensure select doesn't error with very large timeouts
  local recvr, sendr, err = cosock.socket.select({}, {s}, math.maxinteger)
  assert(err == nil, err)
end, "large timeout")

cosock.run()
