local cosock = require "cosock"

local handle
local function task_fn()
  assert(handle:is_alive())
  local s, err = pcall(handle.cancel, handle)
  assert(not s, "Expected cancel in own task to fail found " .. tostring(s))
  assert(err)
end

handle = cosock.spawn(task_fn)

cosock.run()
