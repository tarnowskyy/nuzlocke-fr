-- Nuzlocke FR -- an enforced Nuzlocke for FireRed on Gen1Recomp 0.3.96.
--
-- Nothing here runs on a save unless that save answered YES to the
-- setup question asked right after a NEW GAME (src/state.lua). Every
-- handler checks that first and returns straight away otherwise, so an
-- existing save is never read for rules and never written to.
--
-- The mod is split across src/*.lua. A mod's require is sandboxed to
-- engine modules, so its own files are read with mod:read and compiled
-- into this chunk's environment, the same way Gen1Sprint does it.

local MODULE_DIR = "src/"

-- Load order matters: later modules use the earlier ones through `N`.
local MODULES = {
  "families", "engine", "text", "state", "prompt",
  "catches", "permadeath", "shops", "menu",
}

return function(mod)
  local function loadModule(name)
    local relative = MODULE_DIR .. name .. ".lua"
    local source = mod:read(relative)
    if not source then
      mod.log:error("%s is missing from %s -- reinstall the mod", relative, tostring(mod.path))
      return nil
    end
    local chunk, compileError = load(source, "@" .. tostring(mod.path) .. "/" .. relative)
    if not chunk then
      mod.log:error("%s did not compile: %s", relative, tostring(compileError))
      return nil
    end
    local ok, value = pcall(chunk)
    if not ok then
      mod.log:error("%s failed to run: %s", relative, tostring(value))
      return nil
    end
    return value
  end

  -- Shared context every module receives in install(N).
  local N = { mod = mod }
  for _, name in ipairs(MODULES) do
    local m = loadModule(name)
    if not m then
      mod.log:error("Nuzlocke FR is disabled because %s did not load", name)
      return
    end
    N[name] = m
  end
  for _, name in ipairs(MODULES) do
    local m = N[name]
    if type(m.install) == "function" then
      local ok, err = pcall(m.install, N)
      if not ok then mod.log:error("%s.install failed: %s", name, tostring(err)) end
    end
  end
  -- One tick per fixed frame (core/Game3.lua fixedUpdate raises input.step).
  -- Saves without a Nuzlocke run return on the first line.
  local lastError
  local function tick(game)
    if not game or not N.state.run() then return end
    N.state.tick(game)
    N.catches.tick(game)
    N.permadeath.tick(game)
    N.prompt.tick(game)
  end
  mod.hooks:wrap("input.step", function(nextFn, game, dt)
    local result = nextFn(game, dt)
    local ok, err = pcall(tick, game)
    if not ok and err ~= lastError then
      lastError = err
      mod.log:error("tick failed: %s", tostring(err))
    end
    return result
  end)

  mod.exports.version = mod.version
  mod.exports.active = function() return N.state.active() end
end
