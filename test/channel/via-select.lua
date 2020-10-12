local cosock = require "cosock"
local socket = cosock.socket
local channel = cosock.channel

cosock.spawn(function()
  print("receiver spawn")
  local sender, receiver = channel.new()

  cosock.spawn(function()
    sender:send(true)
  end)

  -- sleep to force ^ thread to finish
  socket.sleep(0.01)

  -- call select after send in thread has finished
  socket.select({receiver}, {})

  assert(true == receiver:receive())

  print("server exit")
end, "receiver")

cosock.run()

print("--------------- SUCCESS ----------------")
