local M = {}

local systeminfo;

function M.info()
  if not systeminfo then
    local c = assert(io.popen("uname"))
    local kernel = assert(c:read("*l"))
    c:close()

    -- put it in a table so we can add more info later
    systeminfo = { kernel = kernel }
  end

  return systeminfo
end

return M
