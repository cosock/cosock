local cosock = require "init"

local childran = false

local function child()
  cosock.spawn(function()
    print("child spawn")

    childran = true

    print("child exit")
  end, "child")

end

cosock.spawn(function()
  print("parent spawn")

  child()

  print("parent exit")
end, "parent")

cosock.run()

assert(childran, "child didn't run")

print("--------------- SUCCESS ----------------")
