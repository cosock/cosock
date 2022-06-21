local cosock = require "cosock"

cosock.spawn(function()
  local _, rx = cosock.channel.new()
  rx:settimeout(0.5)
  local msg, err = rx:receive()
  assert(msg == nil, "Expected no message on receieve, got " .. tostring(msg))
  assert(err == "timeout", "expected err on receive to be `timeout` found " .. tostring(msg))
end)

cosock.run()
print("--------------- SUCCESS ----------------")
