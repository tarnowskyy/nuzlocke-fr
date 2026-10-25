-- Permadeath and the wipe.
--
-- A Pokemon that faints while the rules are live is recorded as dead by
-- identity (personality + original trainer id, which survive battles, the
-- PC, the Day-Care and evolution). Outside battle, every frame, any dead mon
-- in the party is put back to 0 HP, so a Pokemon Center, a PC withdrawal or
-- anything else that heals it changes nothing. Revives are refused in and
-- out of battle (battle side: catches.lua's bag wrapper).
--
-- Whole party dead = the run is over: a message, a durable "over" marker
-- (state.lua), then the game's own soft reset to the title screen, where
-- NEW GAME starts a fresh run in the same slot. CONTINUE on a finished run
-- shows the same message and returns to the title.

local Permadeath = {}

local N, mod, E, State

Permadeath.REVIVE_REFUSAL = "NUZLOCKE: Fainted POKEMON are dead. They can't be revived."

local function hpOf(mon)
  return type(mon) == "table" and type(mon.hp) == "number" and mon.hp or nil
end

local function markDead(run, mon)
  local key = E.monKey(mon)
  if not key or run.dead[key] then return false end
  local name = E.monName(mon)
  run.dead[key] = { name = name, species = E.species(mon), level = tonumber(mon.level) }
  run.deadOrder[#run.deadOrder + 1] = key
  mod.log:info("%s died", name)
  N.prompt.say("NUZLOCKE: " .. name .. " has died. Rest in peace.")
  return true
end

local function countable(mon)
  return type(mon) == "table" and not E.isEgg(mon) and (E.species(mon) or 0) > 0
end

-- Returns living and total (non-egg) party members after enforcing deaths.
local function enforceParty(run, party)
  local alive, total = 0, 0
  for _, mon in ipairs(party or {}) do
    if countable(mon) then
      total = total + 1
      local key = E.monKey(mon)
      local hp = hpOf(mon)
      if key and run.dead[key] then
        if hp and hp > 0 then mon.hp = 0 end
      elseif hp and hp <= 0 then
        markDead(run, mon)
      else
        alive = alive + 1
      end
    end
  end
  return alive, total
end

local function wipe()
  local run = State.run()
  if not run or run.over then return end
  State.markOver()
  mod.log:info("party wiped; run over (seed %s)", tostring(run.seed))
  N.prompt.say("NUZLOCKE: Your whole party has fallen. The run is over.|"
    .. "On the title screen, choose NEW GAME to start a fresh run in this slot.",
    function() E.softReset() end)
end

function Permadeath.tick(game)
  if not State.live() then return end
  if not game or game.phase ~= "field" or E.inBattle() then return end
  local session = E.session()
  local alive, total = enforceParty(State.run(), session and session.party)
  if total > 0 and alive == 0 then wipe() end
end

function Permadeath.isDead(mon)
  local run = State.run()
  local key = E.monKey(mon)
  return run and key and run.dead and run.dead[key] ~= nil or false
end

function Permadeath.install(ctx)
  N, mod, E, State = ctx, ctx.mod, ctx.engine, ctx.state

  -- core/game3/battle/adapter.lua: raised when any battler faints.
  mod.events:on("battle.fainted", function(ev)
    if not State.live() or type(ev) ~= "table" then return end
    local battler = ev.battler
    local side = ev.sideName or (type(battler) == "table" and battler.side)
    if side ~= "player" or type(battler) ~= "table" then return end
    pcall(markDead, State.run(), battler.mon)
  end)

  -- Raised after the battle party is written back to the save
  -- (core/game3/battle_bridge.lua), before a black-out heals anyone.
  mod.events:on("battle.ended", function()
    if not State.live() then return end
    local session = E.session()
    pcall(enforceParty, State.run(), session and session.party)
  end)

  -- Field item use (core/game3/item_use.lua useField).
  mod.hooks:wrap("item.use", function(nextFn, game, battle, id, partySlot, bag, ...)
    if E.isRevive(id) and State.live() then
      return false, "noeffect", Permadeath.REVIVE_REFUSAL
    end
    return nextFn(game, battle, id, partySlot, bag, ...)
  end)
end

return Permadeath
