-- The seeded Gen-1-only randomizer: starters, wild Pokemon and trainers.
--
-- Only on a run that started on 0.3.0 or later (run.rando), so a run begun
-- without it never has its world reshuffled. Everything comes from the run's
-- seed and a fixed name per decision (src/rng.lua), so reloading or playing
-- in another order gives the same world.
--
-- Wild: each map's encounter table is planned once, slot by slot: every
-- slot gets its own Gen 1 replacement (distinct within the map), legal at
-- the slot's top level (src/species.lua). With one catch per area, the
-- first encounter is what counts, so how far a pick may stray depends on
-- how often its slot comes up (TIERS below): everyday slots stay close to
-- the vanilla Pokemon's strength, rare slots lean stronger and may be a
-- few levels ahead of their normal evolution level -- sometimes a lucky
-- find, never a legendary out of place. A lower-level encounter gets an
-- earlier evolution stage. Slot rates and levels stay vanilla. Covers
-- walking, surfing, fishing, Rock Smash and Sweet Scent. Statics, gifts,
-- legendaries, roamers and the Old Man's tutorial are never touched.
--
-- Trainers (all of them, rival and bosses too): every party member gets a
-- Gen 1 replacement the same way, keyed by trainer id and slot. The rival's
-- starter line becomes the randomized starter in the vanilla slot, so he
-- always carries "his" starter. Moves are the new species' level-up moves.
--
-- Starters: three different families, unevolved, able to evolve, base
-- stat total 250-330, no legendaries, and a damaging move at Lv 5. They
-- take the places of Bulbasaur, Charmander and Squirtle in that order:
-- Oak's lab script, its picture and its question show the new species.
--
-- Deathtraps: OHKO moves are removed from every wild and trainer Pokemon;
-- Self-Destruct/Explosion from wild ones and from trainers before 4 badges;
-- Sonic Boom and Super Fang below Lv 20; Dragon Rage below Lv 25; before 4
-- badges a trainer team keeps at most one sleep move.
-- Evolutions: trade evolutions happen at Lv 37; evolving into a Gen 2
-- species is blocked.

local Randomizer = {}

local N, mod, E, State, Rng, Species, Families

local LAST = 151
local BANDS = { 0.15, 0.25, 0.40 }
local MIN_POOL = 6
local NO_TRAINER = { [150] = true, [151] = true } -- Mewtwo, Mew
local VANILLA_STARTER = { [1] = 1, [4] = 2, [7] = 3 } -- species -> ball slot

local MOVE = {
  SELFDESTRUCT = 120, EXPLOSION = 153, SONICBOOM = 49, SUPERFANG = 162, DRAGONRAGE = 82,
}
local OHKO = { [12] = true, [32] = true, [90] = true, [329] = true }
-- Sing, Sleep Powder, Hypnosis, Lovely Kiss, Spore, Yawn, GrassWhistle
local SLEEP = { [47] = true, [79] = true, [95] = true, [142] = true, [147] = true,
  [281] = true, [320] = true }

-- Plans for the current seed (rebuilt from the seed whenever needed).
local cache = { seed = nil }

local function P() return E.req("src.core.game3.pokemon") end

function Randomizer.on()
  local run = State.run()
  return run ~= nil and run.state == "on" and not run.over
    and run.rando ~= nil and run.seed ~= nil
end

local function plans()
  local seed = State.run().seed
  if cache.seed ~= seed then
    cache = { seed = seed, areas = {}, starters = nil }
  end
  return cache
end

-- ------------------------------------------------------------ choosing

-- Strength windows for trainers: base stat total within 15% of the vanilla
-- Pokemon, widened to 25% and 40% only if fewer than MIN_POOL fit.
local TRAINER_RULE = { trainer = true, relax = 0, bands = {} }
for i, b in ipairs(BANDS) do TRAINER_RULE.bands[i] = { -b, b } end

-- Highest legal level a pick may have: `level`, plus the rule's relax for
-- anything that isn't legendary.
local function legalFor(sp, level, rule)
  return Species.legal(sp) <= level + (Species.LEGENDARY[sp] and 0 or (rule.relax or 0))
end

-- rule = { trainer = bool, relax = levels, bands = { {lo, hi}, ... } }:
-- each band is the allowed BST change as a fraction of the vanilla one.
local function choose(stream, vanillaSp, level, used, rule)
  local ref = Species.bst(vanillaSp) or 300
  local legal = {}
  for sp = 1, LAST do
    if legalFor(sp, level, rule) and not (rule.trainer and NO_TRAINER[sp]) then
      legal[#legal + 1] = sp
    end
  end
  if #legal == 0 then
    for sp = 1, LAST do
      if Species.isBase(sp) and not Species.LEGENDARY[sp] then legal[#legal + 1] = sp end
    end
  end
  for _, band in ipairs(rule.bands) do
    local pool = {}
    for _, sp in ipairs(legal) do
      local bst = Species.bst(sp)
      local d = bst and bst - ref
      if not used[sp] and d and d >= ref * band[1] and d <= ref * band[2] then pool[#pool + 1] = sp end
    end
    if #pool >= MIN_POOL then return stream:pick(pool) end
  end
  local pool = {}
  for _, sp in ipairs(legal) do
    if not used[sp] then pool[#pool + 1] = sp end
  end
  if #pool == 0 then pool = legal end
  return stream:pick(pool)
end

-- ------------------------------------------------------------ moves

local function banned(move, level, opts)
  if OHKO[move] then return true end
  if move == MOVE.SELFDESTRUCT or move == MOVE.EXPLOSION then
    return opts.wild or (opts.badges or 0) < 4
  end
  if (move == MOVE.SONICBOOM or move == MOVE.SUPERFANG) and level < 20 then return true end
  if move == MOVE.DRAGONRAGE and level < 25 then return true end
  return false
end

local function sleepBlocked(move, opts)
  return SLEEP[move] and opts.limitSleep and opts.sleepTaken
end

-- The species' moves at `level` (or `moves`) without deathtrap moves, topped
-- back up from its level-up learnset. Returns the list and whether it changed.
-- `opts` is shared by a whole team (it carries the sleep-move count).
function Randomizer.cleanMoves(species, level, moves, opts)
  local Pk = P()
  local base = moves
  if not base then
    local ok, m = pcall(Pk.movesAtLevel, species, level)
    base = ok and type(m) == "table" and m or {}
  end
  local out, have, changed = {}, {}, false
  local function take(mv)
    out[#out + 1] = mv
    have[mv] = true
    if SLEEP[mv] and opts.limitSleep then opts.sleepTaken = true end
  end
  for _, mv in ipairs(base) do
    mv = tonumber(mv)
    if mv and mv > 0 and not have[mv] then
      if banned(mv, level, opts) or sleepBlocked(mv, opts) then
        changed = true
      else
        take(mv)
      end
    end
  end
  if changed then
    local okL, set = pcall(Pk.learnset, species)
    set = okL and type(set) == "table" and set or {}
    for i = #set, 1, -1 do
      if #out >= 4 then break end
      local e = set[i]
      local lv, mv = tonumber(e[1] or e.level) or 0, tonumber(e[2] or e.move) or 0
      if lv <= level and mv > 0 and not have[mv] and not banned(mv, level, opts)
          and not sleepBlocked(mv, opts) then
        take(mv)
      end
    end
  end
  if #out == 0 then return base, false end
  return out, changed
end

-- ------------------------------------------------------------ starters

local function hasDamagingMove(sp, level)
  local Pk = P()
  local ok, moves = pcall(Pk.movesAtLevel, sp, level)
  for _, mv in ipairs(ok and type(moves) == "table" and moves or {}) do
    local okB, info = pcall(Pk.battleMove, mv)
    if okB and type(info) == "table" and (tonumber(info.power) or 0) > 0 then return true end
  end
  return false
end

function Randomizer.starters()
  local c = plans()
  if c.starters then return c.starters end
  local pool = {}
  for sp = 1, LAST do
    local bst = Species.bst(sp) or 0
    if Species.isBase(sp) and #Species.children(sp) > 0 and not Species.LEGENDARY[sp]
        and bst >= 250 and bst <= 330 and hasDamagingMove(sp, 5) then
      pool[#pool + 1] = sp
    end
  end
  local stream = Rng.stream(c.seed, "starters")
  local picks, families = {}, {}
  while #picks < 3 and #pool > 0 do
    local sp = table.remove(pool, stream:int(#pool))
    local fam = Families.of(sp)
    if not families[fam] then
      families[fam] = true
      picks[#picks + 1] = sp
    end
  end
  for _, fallback in ipairs({ 1, 4, 7 }) do
    if #picks >= 3 then break end
    if not families[Families.of(fallback)] then
      families[Families.of(fallback)] = true
      picks[#picks + 1] = fallback
    end
  end
  c.starters = picks
  return picks
end

-- The randomized starter's line at the stage of a vanilla starter species
-- (1-9), e.g. Wartortle -> the third ball's starter, evolved once -- but
-- only into a stage that is legal at `level` (a stone evolution waits).
local function starterLine(vanillaSp, level)
  if not vanillaSp or vanillaSp < 1 or vanillaSp > 9 then return nil end
  local stage = (vanillaSp - 1) % 3
  local sp = Randomizer.starters()[VANILLA_STARTER[vanillaSp - stage]]
  for k = 1, stage do
    local kids = Species.children(sp)
    if #kids == 0 then break end
    local child = kids[Rng.stream(plans().seed, "line:" .. sp .. ":" .. k):int(#kids)]
    if Species.legal(child) > (tonumber(level) or 100) then break end
    sp = child
  end
  return sp
end
Randomizer.starterLine = starterLine

-- ------------------------------------------------------------ wild

local METHODS = { "land", "grass", "water", "rocks", "fishing" }

-- FireRed slot weights: core/game3/encounters.lua LAND_WEIGHTS/WATER_WEIGHTS
-- (rocks use the water ones), fishing per rod from encounter_rules/frlg.lua
-- (old rod slots 1-2, good rod 3-5, super rod 6-10).
local WEIGHTS = {
  land = { 20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1 },
  water = { 60, 30, 5, 4, 1 },
  rocks = { 60, 30, 5, 4, 1 },
  fishing = { 70, 30, 60, 20, 20, 40, 40, 15, 4, 1 },
}
WEIGHTS.grass = WEIGHTS.land

-- How far a slot's pick may stray from its vanilla Pokemon depends on how
-- often the slot comes up. The everyday slots stay close; the rarer the
-- slot, the more it leans toward something stronger or more evolved, so a
-- first encounter is sometimes a lucky find. relax = levels a pick may be
-- ahead of its normal legal level (never for legendaries).
local TIERS = {
  { min = 20, name = "common", relax = 0,
    bands = { { -0.20, 0.20 }, { -0.30, 0.30 }, { -0.45, 0.45 } } },
  { min = 10, name = "varied", relax = 2,
    bands = { { -0.15, 0.30 }, { -0.25, 0.40 }, { -0.40, 0.55 } } },
  { min = 4, name = "uncommon", relax = 4,
    bands = { { -0.10, 0.40 }, { -0.20, 0.50 }, { -0.35, 0.70 } } },
  { min = 0, name = "rare", relax = 8,
    bands = { { 0.00, 0.60 }, { -0.10, 0.75 }, { -0.30, 1.00 } } },
}
Randomizer.TIERS = TIERS

local function tierFor(weight)
  for _, tier in ipairs(TIERS) do
    if weight >= tier.min then return tier end
  end
  return TIERS[#TIERS]
end

local function slotsOf(area)
  if type(area) ~= "table" then return nil end
  if type(area.slots) == "table" then return area.slots end
  if type(area.mons) == "table" then return area.mons end
  if #area > 0 then return area end
  return nil
end

-- One map's plan: every slot of its encounter table (walking, surfing,
-- Rock Smash, fishing) with its own replacement, distinct within the map
-- where possible, judged at the slot's top level and by its tier.
local function areaPlan(mapId)
  local c = plans()
  local key = tostring(mapId)
  local plan = c.areas[key]
  if plan then return plan end
  plan = { slots = {}, extra = {} }
  local Enc = E.req("src.core.game3.encounters")
  local ok, t = pcall(function() return Enc and Enc.tableFor and Enc.tableFor(mapId) end)
  local stream = Rng.stream(c.seed, "wild:" .. key)
  local used = {}
  if ok and type(t) == "table" then
    for _, method in ipairs(METHODS) do
      for i, entry in ipairs(slotsOf(t[method]) or {}) do
        local sp = type(entry) == "table" and Species.id(entry.species or entry[1])
        if sp and sp > 0 then
          local lo = tonumber(entry.minLevel or entry.level or entry[2]) or 1
          local hi = tonumber(entry.maxLevel or entry.level or entry[2]) or lo
          if hi < lo then lo, hi = hi, lo end
          local weight = (WEIGHTS[method] or {})[i] or 1
          local tier = tierFor(weight)
          local pick = choose(stream, sp, math.max(1, hi), used, tier)
          used[pick] = true
          plan.slots[#plan.slots + 1] = { vanilla = sp, lo = lo, hi = hi,
            weight = weight, tier = tier, pick = pick }
        end
      end
    end
  end
  c.areas[key] = plan
  return plan
end
Randomizer.areaPlan = areaPlan

-- The engine rolled a vanilla species and level but not which slot it came
-- from. Pick among the slots that could have produced it, in proportion to
-- how likely each one was to (slot weight / its number of levels), which
-- gives exactly the odds the game's own roll had.
local function rollUnit()
  if love and love.math and love.math.random then
    local ok, v = pcall(love.math.random)
    if ok and type(v) == "number" then return v end
  end
  return math.random()
end

local function slotFor(plan, vanillaSp, level)
  local fits, total = {}, 0
  for _, slot in ipairs(plan.slots) do
    if slot.vanilla == vanillaSp and level >= slot.lo and level <= slot.hi then
      local w = slot.weight / (slot.hi - slot.lo + 1)
      fits[#fits + 1] = { slot = slot, w = w }
      total = total + w
    end
  end
  if #fits == 0 then return nil end
  local r = rollUnit() * total
  for _, f in ipairs(fits) do
    r = r - f.w
    if r < 0 then return f.slot end
  end
  return fits[#fits].slot
end

local COMMON = TIERS[1]

-- The replacement for one encounter of `vanillaSp` at `level` on a map, at
-- the evolution stage that is legal at `level` for its slot's tier: a slot
-- can span Lv 5-40 (FireRed's surf tables), so a low-level encounter gets
-- an earlier stage of the same pick. A pick with no earlier stage that is
-- still too strong for this level gets its own pick for that level.
function Randomizer.wildSpecies(mapId, vanillaSp, level)
  level = math.max(1, tonumber(level) or 1)
  local plan = areaPlan(mapId)
  local slot = slotFor(plan, vanillaSp, level)
  local sp, tier
  if slot then
    sp, tier = slot.pick, slot.tier
  else
    -- Not in this map's table (shouldn't happen): its own stream.
    sp = plan.extra[vanillaSp]
    if not sp then
      local stream = Rng.stream(plans().seed, "wild:" .. tostring(mapId) .. ":" .. tostring(vanillaSp))
      sp = choose(stream, vanillaSp, level, {}, COMMON)
      plan.extra[vanillaSp] = sp
    end
    tier = COMMON
  end
  for _ = 1, 3 do
    if legalFor(sp, level, tier) then return sp end
    local before = Species.pre(sp)
    if not before then break end
    sp = before
  end
  if legalFor(sp, level, tier) then return sp end
  local stream = Rng.stream(plans().seed,
    "wild:" .. tostring(mapId) .. ":" .. tostring(vanillaSp) .. ":L" .. level)
  return choose(stream, vanillaSp, level, {}, tier)
end

local function currentMap()
  local s = E.session()
  return (s and s.map) or E.mapId()
end

-- An unscripted wild encounter (step, surf, fishing, Rock Smash, Sweet
-- Scent) is about to start: give it its randomized species.
local function randomizeWild(enc)
  local vanillaSp = Species.id(enc.species or enc.speciesId)
  if not vanillaSp or vanillaSp < 1 then return end
  local level = tonumber(enc.level) or 5
  local sp = Randomizer.wildSpecies(currentMap(), vanillaSp, level)
  if not sp then return end
  enc.species = sp
  enc.speciesId = nil
  local moves, changed = Randomizer.cleanMoves(sp, level, nil, { wild = true })
  if changed then
    enc.moves, enc.pp, enc.maxPp = moves, nil, nil
  else
    enc.moves = nil
  end
end
Randomizer.randomizeWild = randomizeWild

local function scriptedWild(enc, opts)
  if type(opts) == "table" and next(opts) ~= nil then return true end
  return type(enc) ~= "table" or enc.roamer or enc.wildScripted or enc.legendary
    or enc.oldManTutorial or enc.firstBattle or false
end

local function patchStartWild()
  local BB = E.req("src.core.game3.battle_bridge")
  if not BB or BB.__nuzlockeFrWrapped or type(BB.startWild) ~= "function" then return end
  local vanilla = BB.startWild
  BB.__nuzlockeFrWrapped = true
  BB.startWild = function(m, game, encounter, opts, ...)
    if Randomizer.on() and not scriptedWild(encounter, opts) then
      local copy = {}
      for k, v in pairs(encounter) do copy[k] = v end
      local ok, err = pcall(randomizeWild, copy)
      if ok then
        encounter = copy
      else
        mod.log:error("wild randomizer failed: %s", tostring(err))
      end
    end
    return vanilla(m, game, encounter, opts, ...)
  end
end
Randomizer.patchStartWild = patchStartWild

-- ------------------------------------------------------------ trainers

local function randomizeTrainer(trainerId, party)
  local stream = Rng.stream(plans().seed, "trainer:" .. tostring(trainerId))
  local badges = N.caps.badgeCount()
  local opts = { wild = false, badges = badges, limitSleep = badges < 4 }
  local used, out = {}, {}
  for i, row in ipairs(party) do
    local copy = {}
    for k, v in pairs(row) do copy[k] = v end
    local vanillaSp = Species.id(row.speciesId) or Species.id(row.species) or 16
    local level = tonumber(row.level) or 5
    local sp = starterLine(vanillaSp, level) or choose(stream, vanillaSp, level, used, TRAINER_RULE)
    used[sp] = true
    copy.species, copy.speciesId = sp, sp
    copy.moves = Randomizer.cleanMoves(sp, level, nil, opts)
    copy.moveIds, copy.pp, copy.maxPp = nil, nil, nil
    out[i] = copy
  end
  return out
end
Randomizer.randomizeTrainer = randomizeTrainer

-- ------------------------------------------------------------ Oak's Lab

local VAR_PLAYER_STARTER, VAR_RIVAL_STARTER = 0x4002, 0x4003
local GSTRINGVAR4 = 0x020234CC -- text pointer the engine reads from stringVars[4]
local labPic = false

local function inLab()
  local id = tostring(E.mapId() or "")
  if id:upper():find("OAKS_LAB", 1, true) then return true end
  return id == "4:3" or id == "4_3"
end

local function noStarterYet()
  local s = E.session()
  return s ~= nil and (type(s.party) ~= "table" or #s.party == 0)
end

local function starterQuestion(sctx)
  local vm = type(sctx) == "table" and (sctx.runner or sctx.vm) or nil
  local vctx = type(vm) == "table" and vm.ctx or nil
  if not vctx then return nil end
  local C = E.req("src.mods.Gen3Compat")
  local sp = C and C.getVar and tonumber(C.getVar(VAR_PLAYER_STARTER)) or nil
  if not sp or sp < 1 then return nil end
  local name = Species.name(sp)
  return vctx, N.text.box("This is " .. name .. "!|So, you want the POKEMON " .. name .. "?")
end

local function copyRow(row, fields)
  local copy = {}
  for k, v in pairs(row) do copy[k] = v end
  for k, v in pairs(fields) do copy[k] = v end
  return copy
end

local function labCommand(nextFn, sctx, name, row)
  if name == "setvar" then
    local var = tonumber(row[1] or row.var)
    local value = tonumber(row[2] or row.value)
    local slot = value and VANILLA_STARTER[value]
    if slot and (var == VAR_PLAYER_STARTER or var == VAR_RIVAL_STARTER) then
      local sp = Randomizer.starters()[slot]
      return nextFn(sctx, name, copyRow(row, { [2] = sp, value = sp }))
    end
  elseif name == "showmonpic" then
    labPic = true
  elseif name == "hidemonpic" then
    labPic = false
  elseif name == "message" and labPic then
    local vctx, text = starterQuestion(sctx)
    if vctx then
      if type(vctx.stringVars) ~= "table" then vctx.stringVars = {} end
      local old = vctx.stringVars[4]
      vctx.stringVars[4] = text
      local ok, result = pcall(nextFn, sctx, name, copyRow(row, { [1] = GSTRINGVAR4, ptr = GSTRINGVAR4 }))
      vctx.stringVars[4] = old
      if ok then return result end
      mod.log:error("starter text failed: %s", tostring(result))
    end
  end
  return nextFn(sctx, name, row)
end

-- ------------------------------------------------------------ install

function Randomizer.install(ctx)
  N, mod, E, State = ctx, ctx.mod, ctx.engine, ctx.state
  Rng, Species, Families = ctx.rng, ctx.species, ctx.families

  mod.hooks:wrap("script.command", function(nextFn, sctx, name, row)
    if type(row) == "table" and Randomizer.on() and inLab() and noStarterYet() then
      local ok, result = pcall(labCommand, nextFn, sctx, name, row)
      if ok then return result end
      mod.log:error("starter randomizer failed: %s", tostring(result))
    end
    return nextFn(sctx, name, row)
  end)

  mod.hooks:wrap("trainer.party", function(nextFn, trainerClass, trainerId, party)
    local out = nextFn(trainerClass, trainerId, party)
    if not Randomizer.on() or type(out) ~= "table" or #out == 0 then return out end
    local ok, result = pcall(randomizeTrainer, trainerId, out)
    if ok and type(result) == "table" then return result end
    mod.log:error("trainer randomizer failed: %s", tostring(result))
    return out
  end)

  -- core/game3/evolution.lua scan_normal: called per evolution row on level up.
  mod.hooks:wrap("evolution.check", function(nextFn, game, mon, view, ectx)
    local ok = nextFn(game, mon, view, ectx)
    local run = State.run()
    if not (run and run.state == "on" and run.rando) or type(view) ~= "table" then return ok end
    local target = tonumber(view.speciesId) or 0
    if target > LAST then return false end
    if tonumber(view.methodId) == Species.EVO_TRADE and type(mon) == "table"
        and (tonumber(mon.level) or 0) >= 37 then
      return true
    end
    return ok
  end)

  mod.events:on("game.ready", function() patchStartWild() end)
  mod.events:on("save.loaded", function()
    patchStartWild()
    labPic = false
    cache = { seed = nil }
  end)
end

return Randomizer
