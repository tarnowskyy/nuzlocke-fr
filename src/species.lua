-- Gen 1 species facts for the randomizer, read from the game's own data
-- (core/game3/pokemon.lua: base stats, evolutions, learnsets) the first
-- time they are needed. Nothing here is shipped with the mod.
--
-- "Legal level" = the lowest level a species could normally be met at:
--   * an unevolved species: 1;
--   * evolves by level: that level;
--   * by stone: 9 levels after its previous stage, at least 22;
--   * by trade (Kadabra, Machoke, ...): 37, the level this mod lets them evolve;
--   * very strong species are held back further (BST 450+: 20, 500+: 30),
--     and the legendary birds to 50, Mewtwo and Mew to 60.

local Species = {}

local N, E
local LAST = 151

local LEGENDARY_LEVEL = { [144] = 50, [145] = 50, [146] = 50, [150] = 60, [151] = 60 }
Species.LEGENDARY = { [144] = true, [145] = true, [146] = true, [150] = true, [151] = true }

-- FireRed evolution methods (core/game3/evolution.lua)
local EVO_FRIENDSHIP, EVO_FRIENDSHIP_NIGHT = 1, 3
local EVO_TRADE, EVO_TRADE_ITEM, EVO_ITEM = 5, 6, 7
Species.EVO_TRADE = EVO_TRADE

local data -- built once: { bst = {}, pre = {}, children = {}, legal = {} }

local function P() return E.req("src.core.game3.pokemon") end

local function row(evo)
  return tonumber(evo.method or evo[1]) or 0, tonumber(evo.param or evo[2]) or 0,
    tonumber(evo.target or evo[3]) or 0
end

local function bstOf(sp)
  local Pk = P()
  local ok, s = pcall(function() return Pk and Pk.stats and Pk.stats(sp) end)
  if not ok or type(s) ~= "table" then return nil end
  local total = (tonumber(s.hp) or 0) + (tonumber(s.atk) or 0) + (tonumber(s.def) or 0)
    + (tonumber(s.spe) or 0) + (tonumber(s.spa) or 0) + (tonumber(s.spd) or 0)
  return total > 0 and total or nil
end

local function build()
  local d = { bst = {}, pre = {}, children = {}, legal = {} }
  local Pk = P()
  for sp = 1, LAST do
    d.bst[sp] = bstOf(sp)
    d.children[sp] = {}
  end
  for sp = 1, LAST do
    local ok, evos = pcall(function() return Pk and Pk.evolutions and Pk.evolutions(sp) end)
    for _, evo in ipairs(ok and type(evos) == "table" and evos or {}) do
      local method, param, target = row(evo)
      if target >= 1 and target <= LAST and target ~= sp then
        d.pre[target] = { from = sp, method = method, param = param }
        local list = d.children[sp]
        list[#list + 1] = target
      end
    end
  end
  local function legal(sp, depth)
    if d.legal[sp] then return d.legal[sp] end
    local lv = 1
    local p = d.pre[sp]
    if p and depth < 4 then
      local before = legal(p.from, depth + 1)
      if p.method == EVO_ITEM then
        lv = math.max(before + 9, 22)
      elseif p.method == EVO_TRADE or p.method == EVO_TRADE_ITEM then
        lv = math.max(before, 37)
      elseif p.method >= EVO_FRIENDSHIP and p.method <= EVO_FRIENDSHIP_NIGHT then
        lv = math.max(before + 10, 20)
      elseif p.param > 0 then
        lv = math.max(before, p.param)
      else
        lv = before + 10
      end
    end
    local bst = d.bst[sp] or 0
    if bst >= 500 then lv = math.max(lv, 30) elseif bst >= 450 then lv = math.max(lv, 20) end
    lv = math.max(lv, LEGENDARY_LEVEL[sp] or 0)
    d.legal[sp] = lv
    return lv
  end
  for sp = 1, LAST do legal(sp, 0) end
  return d
end

local function get()
  if not data then
    local ok, d = pcall(build)
    if not ok then
      N.mod.log:error("could not read species data: %s", tostring(d))
      return nil
    end
    data = d
  end
  return data
end

function Species.ready() return get() ~= nil end

-- Base stat total, or nil when the game has no data for it.
function Species.bst(sp)
  sp = tonumber(sp)
  if not sp then return nil end
  local d = get()
  if d and d.bst[sp] then return d.bst[sp] end
  if sp > LAST then return bstOf(sp) end
  return nil
end

function Species.legal(sp)
  local d = get()
  return d and d.legal[tonumber(sp) or 0] or 100
end

-- Gen 1 species this one evolves into (in data order).
function Species.children(sp)
  local d = get()
  return d and d.children[tonumber(sp) or 0] or {}
end

-- The Gen 1 species this one evolves from, or nil.
function Species.pre(sp)
  local d = get()
  local p = d and d.pre[tonumber(sp) or 0]
  return p and p.from or nil
end

-- No Gen 1 pre-evolution (babies from Gen 2 don't count).
function Species.isBase(sp)
  local d = get()
  return d ~= nil and d.pre[tonumber(sp) or 0] == nil
end

-- The species number for a number or a name like "PIDGEY".
function Species.id(ref)
  if type(ref) == "number" then return ref end
  local n = tonumber(ref)
  if n then return n end
  if type(ref) ~= "string" then return nil end
  local Pk = P()
  if not (Pk and Pk.speciesFromName) then return nil end
  local ok, sp = pcall(Pk.speciesFromName, ref)
  return ok and tonumber(sp) or nil
end

function Species.name(sp)
  local Pk = P()
  if Pk and Pk.name then
    local ok, n = pcall(Pk.name, sp)
    if ok and type(n) == "string" and n ~= "" then return n end
  end
  return "POKEMON"
end

function Species.install(ctx)
  N, E = ctx, ctx.engine
end

return Species
