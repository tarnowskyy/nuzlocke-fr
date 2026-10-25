-- One catch per area, with the dupes and shiny clauses.
--
-- Decided once per wild battle at battle.started (core/game3/battle_bridge.lua):
--   * statics and gifts (scripted battles: Snorlax, Lapras, the birds, ...)
--     never use the area and can always be caught;
--   * a shiny can always be caught and doesn't use the area;
--   * a Pokemon Tower ghost (no Silph Scope) doesn't count;
--   * otherwise the first encounter in an area is the area's encounter --
--     unless its evolution family is already owned (dupes clause), in which
--     case the area stays open for the next new family.
-- Area = map section (route, cave, town); each Safari Zone map is its own area.
--
-- A throw at a mon that can't be caught is refused before the ball is used
-- (battle bag wrapper below). catch.rate is a second line for paths that
-- skip the bag, e.g. Safari Balls.

local Catches = {}

local N, mod, E, State, Families

-- The current wild battle's verdict.
local current = nil

local REASON = {
  used = "NUZLOCKE: You already had your encounter in this area.",
  dupe = "NUZLOCKE: You already own this family (dupes clause). "
    .. "The next new one here counts.",
  over = "NUZLOCKE: This run is over.",
}

local function areaKey(st)
  local mapId = E.mapId()
  if st and st.safari then return "map:" .. tostring(mapId) end
  local sec = E.mapSec(E.session())
  if sec then return "sec:" .. tostring(sec) end
  return "map:" .. tostring(mapId)
end

local function own(run, species)
  local fam = Families.of(species)
  if fam then run.owned[fam] = true end
end

-- Every family in the party counts as owned (starter, gifts, trades, evolutions).
local function scanParty(run, session)
  for _, mon in ipairs(session and session.party or {}) do
    if not E.isEgg(mon) then
      local sp = E.species(mon)
      if sp and sp > 0 then own(run, sp) end
    end
  end
end

local function decide(ev)
  current = nil
  if not State.live() then return end
  if not ev or ev.kind ~= "wild" then return end
  local st = ev.battle
  if type(st) ~= "table" then return end
  if st.oldManTutorial or st.pokedude or st.firstBattle then return end
  local run = State.run()
  scanParty(run, E.session())

  if st.wildScripted or st.legendary or st.roamer then
    current = { battle = st, catchable = true, why = "static" }
    return
  end
  if st.ghostBattle and not st.ghostUnveiled then
    current = { battle = st, catchable = true, why = "ghost" }
    return
  end
  local mon = st.enemy and st.enemy.mon
  local species = tonumber(ev.speciesId) or E.species(mon)
  if E.isShiny(mon) then
    current = { battle = st, catchable = true, why = "shiny" }
    return
  end

  local key = areaKey(st)
  if run.areas[key] then
    current = { battle = st, catchable = false, why = "used", key = key }
    return
  end
  local fam = Families.of(species)
  if fam and run.owned[fam] then
    current = { battle = st, catchable = false, why = "dupe", key = key }
    return
  end
  run.areaCount = (run.areaCount or 0) + 1
  run.areas[key] = { species = species, status = "met", n = run.areaCount }
  current = { battle = st, catchable = true, why = "first", key = key }
end

-- Why a ball thrown in this battle must be refused, or nil to allow it.
function Catches.refusal(st)
  if not State.active() then return nil end
  if State.run().over then return REASON.over end
  if not (current and current.battle == st) then return nil end
  if current.catchable then return nil end
  return REASON[current.why] or REASON.used
end

local function onCaught(ev)
  if not State.live() then return end
  local run = State.run()
  local sp = tonumber(ev and ev.speciesId) or E.species(ev and ev.mon)
  if sp then own(run, sp) end
  run.caught = (run.caught or 0) + 1
  if current and current.key and current.why == "first" then
    local area = run.areas[current.key]
    if area then area.status = "caught" end
  end
end

-- Battle bag: refuse a ball before it is taken from the bag, the same way
-- the game refuses a ball in a trainer battle (core/game3/battle/items.lua).
local function patchBattleBag()
  local BI = E.req("src.core.game3.battle.items")
  if not BI or BI.__nuzlockeFrWrapped or type(BI.use) ~= "function" then return end
  local vanillaUse = BI.use
  BI.__nuzlockeFrWrapped = true
  BI.use = function(st, adapter, bag, session, itemId, partySlot, battlerId, moveSlot, ...)
    local okCheck, refusal = pcall(function()
      if not State.active() then return nil end
      if BI.isBall and BI.isBall(itemId) and st and st.wild then
        return Catches.refusal(st)
      end
      if E.isRevive(itemId) and State.live() then
        return N.permadeath.REVIVE_REFUSAL
      end
      return nil
    end)
    if okCheck and refusal then
      if adapter and adapter.say then pcall(adapter.say, adapter, refusal) end
      return "error", { refusal }, false, false
    end
    return vanillaUse(st, adapter, bag, session, itemId, partySlot, battlerId, moveSlot, ...)
  end
end
Catches.patchBattleBag = patchBattleBag

function Catches.tick(game)
  if not State.live() then return end
  scanParty(State.run(), E.session())
end

function Catches.install(ctx)
  N, mod, E, State, Families = ctx, ctx.mod, ctx.engine, ctx.state, ctx.families

  mod.events:on("battle.started", function(ev)
    patchBattleBag()
    local ok, err = pcall(decide, ev)
    if not ok then mod.log:error("encounter check failed: %s", tostring(err)) end
  end)
  mod.events:on("battle.ended", function() current = nil end)
  mod.events:on("pokemon.caught", function(ev)
    local ok, err = pcall(onCaught, ev)
    if not ok then mod.log:error("catch record failed: %s", tostring(err)) end
  end)
  -- Gifts (Eevee, Lapras, fossils, ...) make their family owned.
  mod.events:on("pokemon.before_give", function(ev)
    if not State.live() then return end
    -- core/game3/scripting/ops_a.lua (givemon): speciesId is the number,
    -- species the name. The party scan in tick() covers later changes.
    local sp = type(ev) == "table" and tonumber(ev.speciesId)
    if sp then own(State.run(), sp) end
  end)

  mod.hooks:wrap("catch.rate", function(nextFn, ball, mon, def, opts)
    local st = type(opts) == "table" and opts.battle or nil
    if Catches.refusal(st) then return false, 0 end
    return nextFn(ball, mon, def, opts)
  end)

  mod.events:on("game.ready", function() patchBattleBag() end)
end

return Catches
