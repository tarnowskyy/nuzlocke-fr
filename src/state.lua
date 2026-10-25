-- Per-save activation, the run record, and the setup question.
--
-- The run lives in the save's own mod bucket (session.modData.nuzlocke_fr,
-- which is what mod.save reads and writes). It is only ever created by the
-- save.new_game hook, i.e. for a brand-new game, starting as "pending";
-- the player then answers the setup question:
--   YES -> state "on"   (rules enforced on this save from now on)
--   NO  -> state "off"  (after a second confirmation; the mod stays dormant)
-- A save without a bucket (every existing save, e.g. CHRIS) is never written.

local State = {}

local N, mod, E
local KEY

-- Engine detail (core/Game3.lua adoptSave): when a save is loaded, mod
-- buckets left in memory from an earlier game in the same session are
-- copied into it if it has none. We record whether the file itself had our
-- bucket and drop anything that was only copied in.
local rawHadBucket = nil
local askedThisBoot = false

function State.session() return E.session() end

function State.run()
  local s = E.session()
  local md = s and s.modData
  local bucket = type(md) == "table" and md[KEY] or nil
  local run = type(bucket) == "table" and bucket.run or nil
  return type(run) == "table" and run or nil
end

-- The save is a Nuzlocke run (answered YES), whether or not rules are live yet.
function State.active()
  local run = State.run()
  return run ~= nil and run.state == "on"
end

-- Rules are enforced: an active run that isn't over, once the player has
-- received the Pokedex and Poke Balls from Prof. Oak. Before that (the lab
-- fight, Route 1 before the parcel) nothing counts, as in a standard run.
function State.live()
  local run = State.run()
  if not (run and run.state == "on") or run.over then return false end
  if not run.started then
    if not E.getFlag("FLAG_SYS_POKEDEX_GET") then return false end
    run.started = true
    N.prompt.say("NUZLOCKE: The rules are now live! "
      .. "Only your first encounter in each area can be caught, "
      .. "and a POKEMON that faints is dead.")
  end
  return true
end

local function newSeed(session)
  local r
  if love and love.math and love.math.random then
    local ok, v = pcall(love.math.random, 1, 2147483646)
    if ok then r = v end
  end
  r = r or math.random(1, 2147483646)
  local tid = tonumber(session and session.trainerId) or 0
  return (r + tid * 7919) % 2147483647
end

local function startRun(run)
  local s = E.session()
  run.state = "on"
  run.seed = newSeed(s)
  run.started = false
  run.areas = {}
  run.areaCount = 0
  run.owned = {}
  run.dead = {}
  run.deadOrder = {}
  run.caught = 0
  run.over = false
  run.rando = 1 -- randomizer version this run was started with (src/randomizer.lua)
  mod.log:info("Nuzlocke run started, seed %d", run.seed)
  N.prompt.say("Nuzlocke run started! Seed " .. tostring(run.seed) .. ".|"
    .. "The rules begin once PROF. OAK gives you your POKE BALLS. "
    .. "Check START > NUZLOCKE any time for your run status.")
end

local function askSetup(run)
  askedThisBoot = true
  N.prompt.ask("NUZLOCKE FR|Start a Nuzlocke run on this save?|"
    .. "One catch per area, fainted POKEMON are dead, a full wipe ends the run, "
    .. "shops are closed, and levels are capped by badges. "
    .. "Starters, wild POKEMON and trainers are randomized (Gen 1 only).", function(yes)
      if run.state ~= "pending" then return end
      if yes then
        startRun(run)
        return
      end
      N.prompt.ask("Play this save as a normal game? Nuzlocke FR will stay off "
        .. "on this save for good.", function(sure)
          if run.state ~= "pending" then return end
          if sure then
            run.state = "off"
            mod.log:info("Nuzlocke declined on this save; mod stays dormant")
          else
            askedThisBoot = false -- ask the first question again
          end
        end)
    end)
end

-- Durable "run over" marker kept outside the save file (mod.storage is per
-- playthrough), so reloading an older save can't undo a wipe.
function State.markOver()
  local run = State.run()
  if not run then return end
  run.over = true
  local game = mod.game
  if game and mod.storage then
    local ok, wrote, code = pcall(mod.storage.write, mod.storage, game, "run_over",
      { over = true, seed = run.seed })
    if not ok or not wrote then
      mod.log:warn("could not record run over in mod storage: %s", tostring(code or wrote))
    end
  end
end

local function storedOver()
  local game = mod.game
  if not (game and mod.storage) then return false end
  local ok, value = pcall(mod.storage.read, mod.storage, game, "run_over")
  return ok and type(value) == "table" and value.over == true
end

function State.tick(game)
  local run = State.run()
  if not run then return end
  if run.state == "pending" and not askedThisBoot and not N.prompt.busy() then
    askSetup(run)
  end
end

function State.install(ctx)
  N, mod, E = ctx, ctx.mod, ctx.engine
  KEY = mod.id

  -- New game only: give the fresh save a "pending" run. This is the one
  -- place the mod's bucket is ever created.
  mod.hooks:wrap("save.new_game", function(nextFn, session)
    local out = nextFn(session)
    local target = type(out) == "table" and out or session
    if type(target) == "table" then
      if type(target.modData) ~= "table" then target.modData = {} end
      target.modData[KEY] = { run = { schema = 1, state = "pending" } }
      askedThisBoot = false
      N.prompt.clear()
    end
    return out
  end)

  mod.events:on("save.loading", function(ev)
    local raw = ev and ev.raw
    rawHadBucket = type(raw) == "table" and type(raw.modData) == "table"
      and raw.modData[KEY] ~= nil or false
  end)

  mod.events:on("save.loaded", function(ev)
    N.prompt.clear()
    local s = (ev and ev.save) or E.session()
    if rawHadBucket == false and type(s) == "table" and type(s.modData) == "table"
        and s.modData[KEY] ~= nil then
      s.modData[KEY] = nil
      mod.log:info("dropped a Nuzlocke record that was not in this save's file")
    end
    rawHadBucket = nil
    askedThisBoot = false
    local run = State.run()
    if run and run.state == "on" and (run.over or storedOver()) then
      run.over = true
      N.prompt.say("NUZLOCKE: This run is over. Your whole party fell.|"
        .. "Choose NEW GAME to start a fresh run.", function() E.softReset() end)
    end
  end)
end

return State
