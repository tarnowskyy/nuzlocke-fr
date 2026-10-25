-- Level caps, banked EXP and the Rare Candy block.
--
-- The cap comes from the badge count (table below, from RESEARCH.md), then
-- Lv 64 once Lance is beaten, and no cap after the Hall of Fame. It never
-- goes back down (the Elite Four flags reset after a loss).
--
-- EXP (exp.gain hook, core/game3/battle/experience.lua): a Pokemon gets at
-- most the EXP that takes it to exactly the cap; the rest is banked under
-- its identity (personality + OT id) in the run record. The bank is paid
-- out the next time that Pokemon earns EXP in battle with room under the
-- cap, so level-ups, new moves and evolutions all go through the game's
-- own battle screens. The Day-Care is capped and banked the same way.
--
-- Rare Candy: the party menu uses it without going through the item.use
-- hook (ui/game3/party_menu.lua "Case 2"), so its input handler is wrapped
-- to refuse a candy on a Pokemon at or above the cap. item.use is guarded
-- too, for any other path.

local Caps = {}

local N, mod, E, State

-- Cap by number of badges owned. The cap applies before the next gym.
Caps.BY_BADGES = { [0] = 15, 22, 26, 31, 45, 45, 49, 52, 61 }
Caps.AFTER_LANCE = 64
Caps.NONE = 100

local function enforced()
  local run = State.run()
  return run ~= nil and run.state == "on" and not run.over
end
Caps.enforced = enforced

local function badgeCount()
  local n = 0
  for i = 1, 8 do
    if E.getFlag(string.format("FLAG_BADGE%02d_GET", i)) then n = n + 1 end
  end
  return n
end

Caps.badgeCount = badgeCount

function Caps.current()
  local cap
  if E.getFlag("FLAG_SYS_GAME_CLEAR") then
    cap = Caps.NONE
  elseif E.getFlag("FLAG_DEFEATED_LANCE") then
    cap = Caps.AFTER_LANCE
  else
    cap = Caps.BY_BADGES[badgeCount()] or Caps.BY_BADGES[0]
  end
  local run = State.run()
  if run then
    if (tonumber(run.capMax) or 0) > cap then
      cap = run.capMax
    else
      run.capMax = cap
    end
  end
  return cap
end

local function bankOf(run)
  if type(run.bank) ~= "table" then run.bank = {} end
  return run.bank
end

function Caps.banked(mon)
  local run = State.run()
  local key = E.monKey(mon)
  if not (run and key and type(run.bank) == "table") then return 0 end
  return tonumber(run.bank[key]) or 0
end

-- How much of `amount` a mon may take now (bank first paid out, if asked),
-- banking whatever is over the cap. Returns the amount to give.
local function split(mon, amount, payOut)
  local run = State.run()
  local key = E.monKey(mon)
  amount = math.max(0, math.floor(tonumber(amount) or 0))
  if not (run and key) then return amount end
  local cap = Caps.current()
  local level = tonumber(mon.level) or 1
  local room = E.expRoom(mon, cap)
  if room == nil then
    -- Experience module unavailable: fall back to "EXP stops at the cap".
    return level >= cap and 0 or amount
  end
  local bank = bankOf(run)
  local stored = payOut and (tonumber(bank[key]) or 0) or 0
  local total = amount + stored
  local give = math.min(total, room)
  local over = (tonumber(bank[key]) or 0) - stored + (total - give)
  bank[key] = over > 0 and over or nil
  if total > give and run.capNoticeAt ~= cap then
    run.capNoticeAt = cap
    Caps.pendingNotice = { name = E.monName(mon), cap = cap }
  end
  return give
end
Caps.split = split

-- Rare Candy, by FireRed item id (68) or the item table's field-use kind.
local function isRareCandy(id)
  local num = tonumber(id)
  local D = E.req("src.core.game3.items_data")
  if not num and D and D.toNumericId then
    local ok, n = pcall(D.toNumericId, id)
    if ok then num = tonumber(n) end
  end
  if num == 68 then return true end
  if num == 175 then return false end -- Enigma Berry (RS only)
  if D and D.fieldUseKind then
    local ok, kind = pcall(D.fieldUseKind, id)
    return ok and kind == "level"
  end
  return false
end
Caps.isRareCandy = isRareCandy

local function candyRefusal(mon)
  if not enforced() or type(mon) ~= "table" or E.isEgg(mon) then return nil end
  local cap = Caps.current()
  if (tonumber(mon.level) or 1) < cap then return nil end
  return "NUZLOCKE: The level cap is Lv " .. cap .. ".|"
    .. "RARE CANDY can't be used on " .. E.monName(mon) .. " right now."
end
Caps.candyRefusal = candyRefusal

-- Wrap the party menu's input so an A press on a capped Pokemon with a
-- Rare Candy selected shows our message instead of using the candy.
local function patchPartyMenu()
  local PM = E.req("src.ui.game3.party_menu")
  if not PM or PM.__nuzlockeFrWrapped or type(PM.handleInput) ~= "function" then return end
  local vanillaInput = PM.handleInput
  PM.__nuzlockeFrWrapped = true
  PM.handleInput = function(input, ...)
    local okCheck, refusal = pcall(function()
      if not (PM.open and PM.mode == "use" and not PM._onSelect and not PM._battle) then return nil end
      if not (type(input) == "table" and input.wasPressed and input:wasPressed("a")) then return nil end
      local slot = tonumber(PM.cursor)
      if not slot or slot < 1 or slot > 6 then return nil end
      if not isRareCandy(PM._item) then return nil end
      return candyRefusal(PM._party and PM._party[slot])
    end)
    if okCheck and refusal and PM.showMessage then
      E.sound("SE_FAILURE")
      PM.showMessage(N.text.box(refusal), function() PM.mode = "use" end)
      return
    end
    return vanillaInput(input, ...)
  end
end
Caps.patchPartyMenu = patchPartyMenu

-- Day-Care (core/game3/daycare.lua): the "grown by N levels" quote and fee
-- stop at the cap, and steps over the cap are banked on withdrawal.
local function patchDaycare()
  local D = E.req("src.core.game3.daycare")
  if not D or D.__nuzlockeFrWrapped then return end
  D.__nuzlockeFrWrapped = true
  local vanillaLevel, vanillaApply = D.levelAfterSteps, D.applyExperience
  if type(vanillaLevel) == "function" then
    D.levelAfterSteps = function(mon, steps, ...)
      local level = vanillaLevel(mon, steps, ...)
      local ok, capped = pcall(function()
        if not enforced() or type(level) ~= "number" then return nil end
        local now = tonumber(mon and mon.level) or 1
        return math.min(level, math.max(Caps.current(), now))
      end)
      if ok and capped then return capped end
      return level
    end
  end
  if type(vanillaApply) == "function" then
    D.applyExperience = function(mon, steps, ...)
      if enforced() and type(mon) == "table" then
        local ok, allowed = pcall(split, mon, steps, false)
        if ok and allowed then steps = allowed end
      end
      return vanillaApply(mon, steps, ...)
    end
  end
end
Caps.patchDaycare = patchDaycare

local tickCount = 0
function Caps.tick(game)
  if not State.live() then return end
  tickCount = tickCount + 1
  if tickCount % 15 ~= 0 then return end
  if not E.fieldIdle(game) then return end
  local run = State.run()
  local cap = Caps.current()
  if run.capShown ~= cap then
    local first = run.capShown == nil
    run.capShown = cap
    if cap >= Caps.NONE then
      N.prompt.say("NUZLOCKE: You are the CHAMPION! There is no level cap any more.")
    elseif first then
      N.prompt.say("NUZLOCKE: The level cap is Lv " .. cap .. ". "
        .. "EXP over the cap is banked and paid out when the cap rises.")
    else
      N.prompt.say("NUZLOCKE: The level cap is now Lv " .. cap .. "! "
        .. "Banked EXP is added the next time each POKEMON earns EXP in battle.")
    end
  end
  local notice = Caps.pendingNotice
  if notice then
    Caps.pendingNotice = nil
    N.prompt.say("NUZLOCKE: " .. tostring(notice.name) .. " reached the level cap (Lv "
      .. notice.cap .. "). Extra EXP is banked for when the cap rises.")
  end
end

-- One line for the START > NUZLOCKE page.
function Caps.summary()
  local cap = Caps.current()
  local line = cap >= Caps.NONE and "Level cap: none" or ("Level cap: Lv " .. cap)
  local s = E.session()
  local total = 0
  for _, mon in ipairs(s and s.party or {}) do total = total + Caps.banked(mon) end
  if total > 0 then line = line .. "  Banked EXP (party): " .. total end
  return line
end

function Caps.install(ctx)
  N, mod, E, State = ctx, ctx.mod, ctx.engine, ctx.state

  mod.hooks:wrap("exp.gain", function(nextFn, info)
    local amount = nextFn(info)
    if not enforced() then return amount end
    local mon = type(info) == "table" and info.mon or nil
    if type(mon) ~= "table" then return amount end
    local ok, give = pcall(split, mon, amount, true)
    if ok and give then return give end
    if not ok then mod.log:error("level cap check failed: %s", tostring(give)) end
    return amount
  end)

  mod.hooks:wrap("item.use", function(nextFn, game, battle, id, partySlot, bag, ...)
    if isRareCandy(id) and enforced() then
      local s = E.session()
      local mon = s and s.party and s.party[tonumber(partySlot) or 0]
      local ok, refusal = pcall(candyRefusal, mon)
      if ok and refusal then return false, "noeffect", N.text.box(refusal) end
    end
    return nextFn(game, battle, id, partySlot, bag, ...)
  end)

  mod.events:on("game.ready", function()
    patchPartyMenu()
    patchDaycare()
  end)
  mod.events:on("save.loaded", function()
    patchPartyMenu()
    patchDaycare()
    Caps.pendingNotice = nil
  end)
end

return Caps
