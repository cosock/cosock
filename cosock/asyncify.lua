local m = {}

local realrequire = require
local asyncify_loaded = {}
local function wrappedrequire(name)
  --[[ Our API is incomplete, just choose a few specific modules for now
  if string.sub(name, 1, 6) == "socket" then
    name = "cosock."..name
  end
  ]]
  local subbed
  if name == "socket" then
    subbed = "cosock.socket"
  elseif name == "ssl" then
    subbed = "cosock.ssl"
  end
  return subbed and realrequire(subbed) or m.asyncify(name)
end

local fakeenv = {
  require = wrappedrequire
}
setmetatable(fakeenv, {__index = _ENV })

function m.asyncify(name)
  local err
  if name == "socket" then name = "cosock.socket" end
  if name == "ssl" then name = "cosock.ssl" end
  
  if asyncify_loaded[name] then
    return asyncify_loaded[name]
  end
  for _,searcher in ipairs(package.searchers) do
    local loader, loc = searcher(name)
    if type(loader) == "function" then
      -- figure out which upvalue is env
      local upvalueidx = 0
      repeat
        upvalueidx = upvalueidx + 1
        local uvname, _ = debug.getupvalue(loader, upvalueidx)
        if not uvname then upvalueidx = nil; break end
      until uvname == "_ENV"

      -- set loader env to fake env to override calls to `require`
      if upvalueidx then
        debug.setupvalue(loader, upvalueidx, fakeenv)
      end

      -- load module with loader
      local module = loader(name, loc)
      asyncify_loaded[name] = module
      return module
    -- If the last searcher returns nil we need to check the
    -- package.loaded or we may miss some std lib packages
    elseif loader == nil and package.loaded[name] then
      asyncify_loaded[name] = package.loaded[name]
      return package.loaded[name]
    else
      -- non-function values mean error, keep last non-nil value
      err = loader or err
    end
  end

  return err
end

return m.asyncify
