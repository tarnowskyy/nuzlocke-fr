-- No shop purchases.
--
-- FireRed has no shop hook, so this wraps the script commands
-- (script.command, core/game3/scripting/ops_a.lua):
--   * pokemart: the clerk says the shop is closed instead of opening it;
--   * checkmoney always answers "not enough" and removemoney takes nothing,
--     which also closes vending machines, Game Corner coins, the Magikarp
--     salesman and the museum ticket.
-- Exception: anything on a Safari Zone map, so the entrance fee can be paid
-- (HM03 Surf and the Gold Teeth for Strength are inside).
-- Healing, found items and gifts are untouched. The Saffron guards also
-- accept the free TEA from Celadon Mansion, so nothing story-critical needs money.

local Shops = {}

local N, mod, E, State

local CLOSED = "NUZLOCKE: Shops are closed on a Nuzlocke run. "
  .. "Find items in the field, or use your GameShark balls."

local function inSafari()
  local id = E.mapId()
  return type(id) == "string" and id:upper():find("SAFARI_ZONE", 1, true) ~= nil
end

local function enforced()
  local run = State.run()
  return run ~= nil and run.state == "on" and not run.over
end

-- Show our message and hold the script until it is dismissed, the way the
-- engine's own native waits do (ctx.mode "native" + nativePoll, see vm.lua).
local function closedShop(ctx)
  local vm = type(ctx) == "table" and (ctx.runner or ctx.vm) or nil
  local vctx = type(vm) == "table" and vm.ctx or nil
  local Message = E.message()
  if not (vctx and Message) then return nil end
  local done = false
  Message.show(N.text.box(CLOSED), { done = function() done = true end })
  vctx.mode = "native"
  vctx.status = "waiting"
  vctx.nativePoll = function() return done or not Message.isOpen() end
  return true
end

local function withAmount(row, amount)
  local copy = {}
  for k, v in pairs(row) do copy[k] = v end
  copy[1] = amount
  if copy.amount ~= nil then copy.amount = amount end
  return copy
end

function Shops.install(ctx)
  N, mod, E, State = ctx, ctx.mod, ctx.engine, ctx.state

  mod.hooks:wrap("script.command", function(nextFn, sctx, name, row)
    if type(row) ~= "table" or not enforced() then return nextFn(sctx, name, row) end
    if name == "pokemart" or name == "pokemartdecoration" or name == "pokemartdecoration2" then
      local ok, result = pcall(closedShop, sctx)
      if ok and result ~= nil then return result end
      return nil -- couldn't show the message: just skip the shop
    end
    if (name == "checkmoney" or name == "removemoney") and not inSafari() then
      -- Player money tops out at 999999, so this check always fails.
      local amount = name == "checkmoney" and 99999999 or 0
      return nextFn(sctx, name, withAmount(row, amount))
    end
    return nextFn(sctx, name, row)
  end)
end

return Shops
