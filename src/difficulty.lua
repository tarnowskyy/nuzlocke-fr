-- Harder trainers: levels, smarter AI, better movesets, held items.
--
-- Only on a run that started on 0.4.0 or later (run.hard), so an older
-- run's trainers never change under it. Everything is decided from the
-- trainer's own data and the run's seed, so a rematch of the same fight
-- is the same team.
--
-- Levels (values from RESEARCH.md "Recommended values"):
--   * regular trainers: +10% (at least +1), never above the current level
--     cap unless the vanilla level already was;
--   * bosses: the ace (the strongest vanilla member) gets a fixed new
--     level (ACE below: gym aces = the cap for that gym, Elite Four and
--     Champion one or two over), and the rest of the party moves up by the
--     same amount but no lower than ace - FLOOR. Lab and early Route 22
--     rival stay vanilla. Post-game rematches (ace 64+) keep their levels.
-- Evolution stage: bosses evolve whenever the next stage is legal at the
--   new level, and are fully evolved from Lv 45; regular trainers only
--   evolve when clearly under-evolved (10 levels past the next stage).
-- Movesets: bosses, and regular trainers from Lv 20, get the best moves
--   from their level-up learnset (and earlier stages'): strong same-type
--   attacks, coverage of other types and one useful status move (two for
--   the Elite Four and Champion). Self-KO moves are never picked; the
--   deathtrap bans of src/randomizer.lua still apply.
-- Held items: the boss ace holds an Oran Berry before 3 badges, then a
--   Sitrus Berry; the Elite Four and Champion aces hold the type item of
--   their best attack.
-- AI: every trainer gets the three "smart" flags; bosses also HP_AWARE;
--   Elite Four also SETUP_FIRST_TURN; the Champion also
--   PREFER_STRONGEST_MOVE. RISKY is always removed.

local Difficulty = {}

local N, mod, E, State, Species, Rng

-- FireRed trainer classes (core/game3/constants/firered/trainer_classes.lua)
local KIND_OF = { [81] = "rival", [89] = "rival", [83] = "rocket", [84] = "leader",
  [87] = "elite", [90] = "champion" }

-- AI script bits (core/game3/battle/ai.lua)
local AI = { CHECK_BAD_MOVE = 0x1, CHECK_VIABILITY = 0x2, TRY_TO_FAINT = 0x4,
  SETUP_FIRST_TURN = 0x8, RISKY = 0x10, PREFER_STRONGEST_MOVE = 0x20, HP_AWARE = 0x100 }
local SMART = AI.CHECK_BAD_MOVE + AI.CHECK_VIABILITY + AI.TRY_TO_FAINT
local AI_BY_KIND = {
  trainer = SMART,
  rival = SMART + AI.HP_AWARE, rocket = SMART + AI.HP_AWARE, leader = SMART + AI.HP_AWARE,
  elite = SMART + AI.HP_AWARE + AI.SETUP_FIRST_TURN,
  champion = SMART + AI.HP_AWARE + AI.SETUP_FIRST_TURN + AI.PREFER_STRONGEST_MOVE,
}
local AI_BITS = { 0x1, 0x2, 0x4, 0x8, 0x10, 0x20, 0x40, 0x80, 0x100 }

-- Vanilla ace level -> new ace level, per boss kind (FireRed 1.0 data).
local ACE = {
  leader = { [14] = 15, [21] = 22, [24] = 26, [29] = 31, [43] = 45, [47] = 49, [50] = 52 },
  rocket = { [29] = 31, [41] = 44 },
  elite = { [54] = 57, [56] = 59, [58] = 60, [60] = 62 },
  champion = { [63] = 65 },
  rival = { [5] = 5, [9] = 9, [18] = 19, [20] = 22, [25] = 28, [40] = 43, [53] = 56 },
}
local FLOOR = { leader = 3, rocket = 3, elite = 3, champion = 4, rival = 4 }
local POSTGAME = 64 -- rematch teams from here on keep their levels
local NO_ITEM_UNTIL = 9 -- Lab and early Route 22 rival: no held item
local FULLY_EVOLVED = 45

local ORAN_BERRY, SITRUS_BERRY = 139, 142
-- Gen 3 type id -> type-boosting item
local TYPE_ITEM = { [0] = 217, [1] = 207, [2] = 210, [3] = 211, [4] = 203, [5] = 204,
  [6] = 188, [7] = 213, [8] = 199, [10] = 215, [11] = 209, [12] = 205, [13] = 208,
  [14] = 214, [15] = 212, [16] = 216, [17] = 206 }
local TYPE_ID = { NORMAL = 0, FIGHTING = 1, FLYING = 2, POISON = 3, GROUND = 4, ROCK = 5,
  BUG = 6, GHOST = 7, STEEL = 8, MYSTERY = 9, FIRE = 10, WATER = 11, GRASS = 12,
  ELECTRIC = 13, PSYCHIC = 14, ICE = 15, DRAGON = 16, DARK = 17 }

local function P() return E.req("src.core.game3.pokemon") end

local function has(flags, b) return math.floor(flags / b) % 2 == 1 end

function Difficulty.on()
  local run = State.run()
  return run ~= nil and run.state == "on" and not run.over and run.hard ~= nil
end

-- ------------------------------------------------------------ AI

function Difficulty.aiFlags(trainerClass, vanilla)
  vanilla = tonumber(vanilla) or 0
  if vanilla >= 0x20000000 then return vanilla end -- roamer / safari / first battle
  local add = AI_BY_KIND[KIND_OF[tonumber(trainerClass)] or "trainer"]
  local out = vanilla
  for _, b in ipairs(AI_BITS) do
    if has(add, b) and not has(out, b) then out = out + b end
  end
  if has(out, AI.RISKY) then out = out - AI.RISKY end
  return out
end

-- Battles read a trainer's AI flags from Trainers.get (via foeFromId and
-- Trainers.info), which builds a fresh table on every call.
local function patchTrainers()
  local T = E.req("src.core.game3.scripting.trainers")
  if not T or T.__nuzlockeFrWrapped or type(T.get) ~= "function" then return end
  local vanilla = T.get
  T.__nuzlockeFrWrapped = true
  T.get = function(trainerId, ...)
    local t = vanilla(trainerId, ...)
    if type(t) == "table" and Difficulty.on() then
      local ok, flags = pcall(Difficulty.aiFlags, t.class, t.aiFlags)
      if ok then
        t.aiFlags = flags
      else
        mod.log:error("trainer AI failed: %s", tostring(flags))
      end
    end
    return t
  end
end
Difficulty.patchTrainers = patchTrainers

-- ------------------------------------------------------------ levels

function Difficulty.kindOf(trainerClass, trainerId)
  local cls = tonumber(trainerClass)
  if not cls and trainerId then
    local T = E.req("src.core.game3.scripting.trainers")
    local ok, t = pcall(function() return T and T.get and T.get(trainerId) end)
    cls = ok and type(t) == "table" and tonumber(t.class) or nil
  end
  return KIND_OF[cls] or "trainer"
end

local function regularLevel(level, cap)
  local up = math.max(1, math.ceil(level * 0.10))
  local out = level + up
  if cap then out = math.min(out, math.max(level, cap)) end
  return math.min(out, 100)
end

-- The plan for one trainer's party: its kind, every member's new level and
-- which member is the ace.
function Difficulty.plan(trainerClass, trainerId, party)
  local kind = Difficulty.kindOf(trainerClass, trainerId)
  local levels, ace, aceLevel = {}, 1, 0
  for i, row in ipairs(party) do
    local lv = tonumber(row.level) or 5
    levels[i] = lv
    if lv >= aceLevel then ace, aceLevel = i, lv end
  end
  local plan = { kind = kind, boss = kind ~= "trainer", ace = ace,
    vanillaAce = aceLevel, levels = levels }
  if kind == "trainer" then
    local okC, cap = pcall(N.caps.current)
    cap = okC and tonumber(cap) or nil
    for i, lv in ipairs(levels) do levels[i] = regularLevel(lv, cap) end
    return plan
  end
  if aceLevel >= POSTGAME then return plan end
  local newAce = ACE[kind][aceLevel] or regularLevel(aceLevel, nil)
  local delta = newAce - aceLevel
  local floor = FLOOR[kind]
  if kind == "leader" and #party <= 2 then floor = 2 end
  for i, lv in ipairs(levels) do
    if i == ace then
      levels[i] = newAce
    else
      levels[i] = math.max(math.min(lv + delta, newAce), newAce - floor, lv)
    end
  end
  return plan
end

-- ------------------------------------------------------------ evolution

function Difficulty.evolve(sp, level, plan, trainerId, slot)
  local stream = Rng.stream(State.run().seed, "evo:" .. tostring(trainerId) .. ":" .. slot)
  for _ = 1, 3 do
    local kids = Species.children(sp)
    if #kids == 0 then break end
    local child = kids[stream:int(#kids)]
    local need = Species.legal(child)
    local ok
    if plan.boss then
      ok = need <= level or level >= FULLY_EVOLVED
    else
      ok = need + 10 <= level
    end
    if not ok then break end
    sp = child
  end
  return sp
end

-- ------------------------------------------------------------ movesets

-- Damage for moves whose listed power isn't what they really do.
local FIXED = {
  [69] = "level", [101] = "level", -- Seismic Toss, Night Shade
  [49] = 20, [82] = 40, [162] = 45, [149] = 40, -- Sonic Boom, Dragon Rage, Super Fang, Psywave
  [67] = 60, [216] = 40, [218] = 40, [237] = 40, [222] = 70, -- Low Kick, Return, Frustration, Hidden Power, Magnitude
  [175] = 30, [179] = 30, [217] = 30, [167] = 40, -- Flail, Reversal, Present, Triple Kick
}
local MULTI = { [3] = 3, [4] = 3, [31] = 3, [42] = 3, [131] = 3, [140] = 3, [154] = 3,
  [198] = 3, [292] = 3, [331] = 3, [333] = 3, [350] = 3, [24] = 2, [41] = 2, [155] = 2 }
-- Charge turns, recharge, unreliable moves.
local SCALE = { [13] = 0.5, [76] = 0.5, [130] = 0.5, [143] = 0.5, [19] = 0.8, [91] = 0.8,
  [291] = 0.8, [340] = 0.8, [63] = 0.85, [264] = 0.3, [252] = 0.4, [248] = 0.5,
  [205] = 0.6, [301] = 0.6, [99] = 0.6, [284] = 0.8, [323] = 0.8 }
-- Never picked: self-KO, Dream Eater (needs a sleeping target), Snore,
-- Sleep Talk, and moves that do nothing for a trainer's Pokemon.
local NEVER = { [120] = true, [153] = true, [138] = true, [173] = true, [214] = true,
  [117] = true, [283] = true, [255] = true, [100] = true, [18] = true, [46] = true,
  [150] = true, [148] = true }

-- Useful status moves by role.
local STATUS = {
  sleep = { [47] = true, [79] = true, [95] = true, [142] = true, [147] = true, [281] = true, [320] = true },
  physicalSetup = { [14] = true, [339] = true, [349] = true, [96] = true, [159] = true },
  specialSetup = { [347] = true, [133] = true },
  speed = { [97] = true },
  disable = { [86] = true, [92] = true, [109] = true, [73] = true, [78] = true, [137] = true,
    [261] = true },
  recover = { [105] = true, [135] = true, [208] = true, [234] = true, [235] = true,
    [236] = true, [303] = true },
  screen = { [113] = true, [115] = true },
}
local STATUS_SCORE = { sleep = 100, physicalSetup = 80, specialSetup = 80, speed = 65,
  disable = 70, recover = 60, screen = 40 }

local function typeId(t)
  if type(t) == "number" then return t end
  if type(t) == "string" then return TYPE_ID[t:upper()] end
  return nil
end

-- Every level-up move this species (or an earlier stage) knows by `level`.
local function candidates(sp, level)
  local Pk = P()
  local out, seen = {}, {}
  local cur, depth = sp, 0
  while cur and depth < 3 do
    local ok, set = pcall(Pk.learnset, cur)
    for _, e in ipairs(ok and type(set) == "table" and set or {}) do
      local lv, mv = tonumber(e[1] or e.level) or 0, tonumber(e[2] or e.move) or 0
      if lv <= level and mv > 0 and not seen[mv] then
        seen[mv] = true
        out[#out + 1] = mv
      end
    end
    cur, depth = Species.pre(cur), depth + 1
  end
  table.sort(out)
  return out
end

local function moveInfo(mv)
  local ok, info = pcall(P().battleMove, mv)
  return ok and type(info) == "table" and info or {}
end

local function statusRole(mv, physical)
  for role, set in pairs(STATUS) do
    if set[mv] then
      if role == "physicalSetup" and not physical then return nil end
      if role == "specialSetup" and physical then return nil end
      return role
    end
  end
  return nil
end

-- Up to four moves for `sp` at `level`, best first; also returns the type of
-- the strongest attack (for the ace's held item). `opts` is the team's
-- deathtrap options from src/randomizer.lua (it carries the sleep count).
function Difficulty.bestMoves(sp, level, opts, plan)
  local Pk = P()
  local R = N.randomizer
  local okS, st = pcall(Pk.stats, sp)
  st = okS and type(st) == "table" and st or {}
  local atk, spa = tonumber(st.atk) or 0, tonumber(st.spa) or 0
  local physical = atk >= spa
  local okT, types = pcall(Pk.types, sp)
  types = okT and type(types) == "table" and types or {}
  local t1, t2 = typeId(types[1]), typeId(types[2])

  local attacks, statuses, others = {}, {}, {}
  for _, mv in ipairs(candidates(sp, level)) do
    if not NEVER[mv] and R.moveAllowed(mv, level, opts) then
      local info = moveInfo(mv)
      local power = FIXED[mv] or tonumber(info.power) or 0
      if power == "level" then power = level end
      if power > 1 then
        local ty = typeId(info.type)
        local acc = tonumber(info.accuracy) or 100
        if acc <= 0 then acc = 100 end
        local score = power * (MULTI[mv] or 1) * (SCALE[mv] or 1) * acc / 100
        if ty ~= nil and not FIXED[mv] and (ty == t1 or ty == t2) then score = score * 1.5 end
        if ty ~= nil and not FIXED[mv] then
          local isPhys = ty < 9
          local best = math.max(atk, spa, 1)
          score = score * (0.5 + 0.5 * (isPhys and atk or spa) / best)
        end
        attacks[#attacks + 1] = { mv = mv, score = score, ty = ty }
      else
        local role = statusRole(mv, physical)
        if role then
          statuses[#statuses + 1] = { mv = mv, score = STATUS_SCORE[role], role = role }
        else
          others[#others + 1] = mv
        end
      end
    end
  end
  local function byScore(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.mv < b.mv
  end
  table.sort(attacks, byScore)
  table.sort(statuses, byScore)

  local out, have, types = {}, {}, {}
  local function take(mv)
    if #out < 4 and not have[mv] then
      out[#out + 1] = mv
      have[mv] = true
      if R.SLEEP[mv] and opts.limitSleep then opts.sleepTaken = true end
      return true
    end
    return false
  end
  -- 1. the best attack; 2. up to two more attacks of new types
  if attacks[1] then
    take(attacks[1].mv)
    if attacks[1].ty then types[attacks[1].ty] = true end
    local floor = attacks[1].score * 0.35
    for _, a in ipairs(attacks) do
      if #out >= 3 then break end
      if not have[a.mv] and a.ty and not types[a.ty] and a.score >= floor then
        take(a.mv)
        types[a.ty] = true
      end
    end
  end
  -- 3. status moves (one role each)
  local maxStatus = (plan.kind == "elite" or plan.kind == "champion") and 2 or 1
  local roles, nStatus = {}, 0
  for _, s in ipairs(statuses) do
    if nStatus >= maxStatus then break end
    if not roles[s.role] and R.moveAllowed(s.mv, level, opts) then
      if take(s.mv) then
        roles[s.role] = true
        nStatus = nStatus + 1
      end
    end
  end
  -- 4. fill: more attacks, then anything left
  for _, a in ipairs(attacks) do take(a.mv) end
  for _, s in ipairs(statuses) do
    if not roles[s.role] and R.moveAllowed(s.mv, level, opts) then
      if take(s.mv) then roles[s.role] = true end
    end
  end
  for _, mv in ipairs(others) do take(mv) end
  if #out == 0 then
    return R.cleanMoves(sp, level, nil, opts), nil
  end
  return out, attacks[1] and attacks[1].ty or nil
end

-- ------------------------------------------------------------ held items

function Difficulty.heldItem(plan, topType, badges)
  if not plan.boss or plan.vanillaAce <= NO_ITEM_UNTIL or plan.vanillaAce >= POSTGAME then
    return nil
  end
  if plan.kind == "elite" or plan.kind == "champion" then
    return (topType and TYPE_ITEM[topType]) or SITRUS_BERRY
  end
  return (badges or 0) < 3 and ORAN_BERRY or SITRUS_BERRY
end

-- ------------------------------------------------------------ install

function Difficulty.install(ctx)
  N, mod, E, State = ctx, ctx.mod, ctx.engine, ctx.state
  Species, Rng = ctx.species, ctx.rng
  mod.events:on("game.ready", function() patchTrainers() end)
  mod.events:on("save.loaded", function() patchTrainers() end)
end

return Difficulty
