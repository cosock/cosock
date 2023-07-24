local cosock = require "cosock"
local server_th_name = "server"
local client_th_name = "client"
local server = cosock.socket.tcp()
assert(server:bind("0.0.0.0", 0))
assert(server:listen())
local _, port = assert(server:getsockname())
local ass_num = 0
local function assert_state(info, assertions)
  ass_num = ass_num + 1
  for _, th in pairs(info) do
    local assertion = assertions[th.name]
    assert(assertion, string.format("%s Unexpected thread name: %s", ass_num, th.name or "nil"))
    assert(th.sendt == assertion.sendt, string.format("%s Unexpected sendt for %s found %s expected %s", ass_num, th.name or "nil", th.sendt or "nil", assertion.sendt or "nil"))
    assert(th.recvt == assertion.recvt, string.format("%s Unexpected recvt for %s found %s expected %s", ass_num, th.name or "nil", th.recvt or "nil", assertion.recvt or "nil"))
  end
end
local assertions = {
  {
    [server_th_name] = {
      sendt = 0,
      recvt = 1,
      status = "running"
    },
    [client_th_name] = {
      sendt = 1,
      recvt = 0,
      status = "suspended"
    }
  },
  {
    [server_th_name] = {
      sendt = 0,
      recvt = 0,
      status = "running"
    },
    [client_th_name] = {
      sendt = 0,
      recvt = 1,
      status = "suspended"
    }
  },
  {
    [server_th_name] = {
      sendt = 0,
      recvt = 1,
      status = "running"
    },
    [client_th_name] = {
      sendt = 0,
      recvt = 0,
      status = "suspended"
    }
  },
}

cosock.spawn(function()
  local client = server:accept()
  assert_state(
    cosock.get_thread_metadata(),
    table.remove(assertions, 1)
  )
  cosock.socket.sleep(0)
  assert_state(
    cosock.get_thread_metadata(),
    table.remove(assertions, 1)
  )
  client:send("bytes\n")
  client:receive()
end, server_th_name)

cosock.spawn(function()
  local client = cosock.socket.tcp()
  client:connect("0.0.0.0", port)
  client:receive()
  cosock.socket.sleep(0)
  assert_state(
    cosock.get_thread_metadata(),
    table.remove(assertions, 1)
  )
  client:send("bytes\n")
end, client_th_name)

cosock.run()
