-- HM safety: a random team plus permadeath can leave nobody alive who knows
-- (or can even learn) CUT, SURF or STRENGTH. On a Nuzlocke run, when nobody
-- in the party knows the move but the HM itself is in the bag, a stand-in
-- uses it: the first living party Pokemon that can learn that HM, otherwise
-- the first living one. The badge is still required (the game's own scripts
-- and checks ask for it before they look for a user).
--
-- Two places look for a user (both checked in the v0.3.96 source):
--   * fieldmove.eligibility hook (core/game3/field_moves.lua partyMoveUser:
--     SURF prompt, field move use);
--   * the checkpartymove script command (cut trees, boulders, rocks), which
--     doesn't call that hook, so its result is filled in afterwards.

local Hms = {}

local N, mod, E, State

-- move id -> HM item id (FireRed)
local HM_ITEM = {
  [15] = 339,  -- CUT
  [19] = 340,  -- FLY
  [57] = 341,  -- SURF
  [70] = 342,  -- STRENGTH
  [148] = 343, -- FLASH
  [249] = 344, -- ROCK SMASH
  [127] = 345, -- WATERFALL
}
Hms.HM_ITEM = HM_ITEM

local VAR_RESULT, VAR_SPECIAL_4 = 0x800D, 0x8004
local NOBODY = 6

local function enforced()
  local run = State.run()
  return run ~= nil and run.state == "on" and not run.over
end

local function hasItem(item)
  local s = E.session()
  local Bag = E.req("src.core.game3.bag")
  if not (s and s.bag and Bag and Bag.has) then return false end
  local ok, has = pcall(Bag.has, s.bag, item, 1)
  return ok and has and true or false
end

local function canLearn(mon, item)
  local P = E.req("src.core.game3.pokemon")
  if not (P and P.canLearnTmItem) then return false end
  local ok, yes = pcall(P.canLearnTmItem, E.species(mon), item)
  return ok and yes and true or false
end

-- The stand-in for `moveId`, or nil. Returns mon, slot (1-based).
function Hms.standIn(party, moveId)
  if not enforced() or type(party) ~= "table" then return nil end
  local item = HM_ITEM[tonumber(moveId) or 0]
  if not item or not hasItem(item) then return nil end
  local anyone, anySlot
  for slot = 1, math.min(6, #party) do
    local mon = party[slot]
    if type(mon) == "table" and not E.isEgg(mon) and (E.species(mon) or 0) > 0
        and not N.permadeath.isDead(mon) then
      if canLearn(mon, item) then return mon, slot end
      if not anyone then anyone, anySlot = mon, slot end
    end
  end
  return anyone, anySlot
end

local function setVar(sctx, id, value)
  local vm = type(sctx) == "table" and (sctx.runner or sctx.vm) or nil
  local Flags = E.req("src.core.game3.scripting.flags")
  if vm and vm.store and Flags and Flags.setVar then
    Flags.setVar(vm.store, vm.ctx, id, value)
    return
  end
  local C = E.req("src.mods.Gen3Compat")
  if C and C.setVar then C.setVar(id, value) end
end

local function getVar(sctx, id)
  local vm = type(sctx) == "table" and (sctx.runner or sctx.vm) or nil
  local Flags = E.req("src.core.game3.scripting.flags")
  if vm and vm.store and Flags and Flags.getVar then
    return tonumber(Flags.getVar(vm.store, vm.ctx, id))
  end
  local C = E.req("src.mods.Gen3Compat")
  return C and C.getVar and tonumber(C.getVar(id)) or nil
end

function Hms.install(ctx)
  N, mod, E, State = ctx, ctx.mod, ctx.engine, ctx.state

  mod.hooks:wrap("fieldmove.eligibility", function(nextFn, moveId, fctx)
    local mon = nextFn(moveId, fctx)
    if mon or not enforced() then return mon end
    local ok, standIn = pcall(Hms.standIn, type(fctx) == "table" and fctx.party, moveId)
    if ok and standIn then return standIn end
    return mon
  end)

  mod.hooks:wrap("script.command", function(nextFn, sctx, name, row)
    local result = nextFn(sctx, name, row)
    if name ~= "checkpartymove" or type(row) ~= "table" or not enforced() then return result end
    local ok, err = pcall(function()
      if getVar(sctx, VAR_RESULT) ~= NOBODY then return end
      local s = E.session()
      local mon, slot = Hms.standIn(s and s.party, tonumber(row[1] or row.move))
      if not mon then return end
      setVar(sctx, VAR_RESULT, slot - 1)
      setVar(sctx, VAR_SPECIAL_4, E.species(mon))
    end)
    if not ok then mod.log:error("HM stand-in failed: %s", tostring(err)) end
    return result
  end)
end

return Hms
