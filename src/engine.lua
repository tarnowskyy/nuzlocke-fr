-- Every engine-internals touch in one place, each behind pcall, so an
-- engine change breaks one helper (and logs) instead of crashing the game.
-- Module paths are from the gen1recomp v0.3.96 source (src/core/game3, src/ui/game3).

local E = {}

local cache = {}
local function req(name)
  local m = cache[name]
  if m then return m end
  local ok, value = pcall(require, name)
  if ok and type(value) == "table" then
    cache[name] = value
    return value
  end
  return nil
end
E.req = req

function E.runtime() return req("src.core.game3.runtime") end

function E.game()
  local R = E.runtime()
  return R and R._game or nil
end

-- The live save. Prefer the game's own session: Runtime can still point at
-- the previous one for a moment after returning to the title screen.
function E.session()
  local game = E.game()
  if game then
    return type(game.session) == "table" and game.session or nil
  end
  local R = E.runtime()
  if not (R and R.getSession) then return nil end
  local ok, s = pcall(R.getSession)
  return ok and type(s) == "table" and s or nil
end

function E.inBattle()
  local B = req("src.core.game3.battle")
  if not (B and B.isActive) then return false end
  local ok, active = pcall(B.isActive)
  return ok and active and true or false
end

function E.mapId()
  local M = req("src.core.game3.map")
  return M and M.current or nil
end

function E.mapSec(session)
  local P = req("src.core.game3.pokemon")
  if not (P and P.currentMapSec) then return nil end
  local ok, sec = pcall(P.currentMapSec, session)
  return ok and sec or nil
end

function E.isShiny(mon)
  local P = req("src.core.game3.pokemon")
  if not (P and P.isShiny and type(mon) == "table") then return false end
  local ok, shiny = pcall(P.isShiny, mon)
  return ok and shiny and true or false
end

function E.isEgg(mon)
  if type(mon) ~= "table" then return false end
  local P = req("src.core.game3.pokemon")
  if P and P.isEgg then
    local ok, egg = pcall(P.isEgg, mon)
    if ok then return egg and true or false end
  end
  return mon.isEgg and true or false
end

function E.species(mon)
  if type(mon) ~= "table" then return nil end
  return tonumber(mon.species or mon.speciesId)
end

function E.monName(mon)
  local P = req("src.core.game3.pokemon")
  if P and P.displayMonName and type(mon) == "table" then
    local ok, name = pcall(P.displayMonName, mon)
    if ok and type(name) == "string" and name ~= "" then return name end
  end
  return "POKEMON"
end

-- A stable identity for a party/box mon: personality + original trainer.
-- Battle copies, PC deposits and withdrawals all keep these two numbers.
function E.monKey(mon)
  if type(mon) ~= "table" then return nil end
  local p = tonumber(mon.personality)
  local ot = tonumber(mon.otId or mon.trainerId)
  if not (p and ot) then return nil end
  return string.format("%d:%d", p, ot)
end

function E.medicineKind(itemId)
  local D = req("src.core.game3.items_data")
  if not (D and D.medicineKind) then return nil end
  local ok, kind = pcall(D.medicineKind, itemId)
  return ok and kind or nil
end

function E.isRevive(itemId)
  local num = tonumber(itemId)
  local D = req("src.core.game3.items_data")
  if not num and D and D.toNumericId then
    local ok, n = pcall(D.toNumericId, itemId)
    if ok then num = tonumber(n) end
  end
  -- 24 Revive, 25 Max Revive, 33 Revival Herb, 45 Sacred Ash (FireRed item ids)
  if num == 24 or num == 25 or num == 33 or num == 45 then return true end
  return E.medicineKind(itemId) == "revive"
end

function E.getFlag(name)
  local C = req("src.mods.Gen3Compat")
  if not (C and C.getFlag) then return nil end
  local ok, on = pcall(C.getFlag, name)
  return ok and on and true or false
end

-- True when the overworld is idle: no script, message, menu, fade or battle.
function E.fieldIdle(game)
  game = game or E.game()
  if not game or game.phase ~= "field" then return false end
  if E.inBattle() then return false end
  local Field = req("src.core.game3.field")
  if not Field or not Field.running then return false end
  if Field.isLocked and Field.isLocked() then return false end
  local Space = req("src.core.game3.scripting.space")
  if Space and Space.vm and Space.vm.isRunning and Space.vm:isRunning() then return false end
  local Hud = req("src.ui.game3.hud")
  if Hud and Hud.busy then
    local ok, busy = pcall(Hud.busy)
    if not ok or busy then return false end
  end
  return true
end

-- The engine's own soft reset (Game3:fixedUpdate picks this up next frame
-- and calls returnToTitle). Nothing is saved.
function E.softReset(game)
  game = game or E.game()
  if game then game.softResetRequested = true end
end

function E.message() return req("src.ui.game3.message") end
function E.choice() return req("src.ui.game3.choice") end

return E
