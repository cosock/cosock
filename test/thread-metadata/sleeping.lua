local cosock = require "cosock"
local named = "some-name"
local capture = "capture-thread"
cosock.spawn(function()
  cosock.socket.sleep(1)
  cosock.socket.sleep(1)
  cosock.socket.sleep(1)
end, named)

cosock.spawn(function()
  cosock.socket.sleep(2)
  cosock.socket.sleep(1)
end)
local thread_info
cosock.spawn(function()
  cosock.socket.sleep(2.1)
  thread_info = cosock.get_thread_metadata()
end, capture)
cosock.run()
local completed = os.time()
local threads = {}
assert(thread_info, "thread_info was nil")
assert(#thread_info == 3, string.format("Thread info was not 3: %s", #thread_info))

for _, info in pairs(thread_info) do
  local age = os.difftime(completed, info.last_wake)
  assert(threads[info.name or "anon"] == nil, "about to clobber " .. (info.name or "anon"))
  threads[info.name or "anon"] = {
    data = info,
    age = age,
  }
end

local function assert_thread_info(
  dets,
  expectations,
  name
)
  local assert_prefix = string.format("Error from s", name)
  assert(
    dets.data.name == expectations.name,
    string.format(
      "%s expected name to be %s, found %q",
      assert_prefix,
      expectations.name or "nil",
      dets.data.name or "nil"
    )
  )

  assert(dets.age < 3.1, string.format("%s found too old thread %s", assert_prefix, dets.age))
  assert(
    dets.data.name == expectations.name,
    string.format(
      "%s expected status to be %s, found %q",
      assert_prefix,
      expectations.status or "nil",
      dets.data.status or "nil"
    )
  )
end

assert_thread_info(threads.anon,
  {status = "suspended", recvt = 0, sendt = 0},
  "anon"
)
assert_thread_info(threads[named],
  {name = "some-name", status = "suspended", recvt = 0, sendt = 0},
  "named"
)
assert_thread_info(threads[capture],
  {name = "capture-thread", status = "running", recvt = 0, sendt = 0},
  "capture"
)
