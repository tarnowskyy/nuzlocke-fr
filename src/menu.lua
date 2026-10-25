-- START > NUZLOCKE: the run menu, a full-screen page in the game's own
-- window style: seed and rules, level cap, the party (HP, banked EXP,
-- dead), every area used and what was met or caught there, and the deaths.
-- Up/Down scroll, Left/Right a page, A or B closes.
--
-- Drawn on the Gen 3 screen stack through the mod UI bridge
-- (ui/game3/mod_ui.lua). The public mod.ui.push only reaches that bridge
-- for api 3 mods, so this api 2 mod pushes on the bridge's stack itself.
-- If that ever fails, the same text is shown in message boxes instead.
-- Only added on a save that is a Nuzlocke run.

local Menu = {}

local N, mod, E, State

local VIEW_W = 240
local ROW_H = 15
local LEFT, TOP, COLS, ROWS = 1, 1, 28, 18 -- window content in tiles (frame drawn around it)
local LIST_TOP = 8 + ROW_H + 3 -- pixels: below the title row
local VISIBLE = math.floor((ROWS * 8 - (LIST_TOP - 8)) / ROW_H)

-- ------------------------------------------------------------ text

local function areaName(key)
  local kind, id = tostring(key):match("^(%a+):(.*)$")
  if kind == "sec" then
    local okX, X = pcall(E.req, "src.import.gba.map_sections_extract")
    local okI, info = pcall(function() return X and X.getInfo and X.getInfo(tonumber(id) or id, nil, 0) end)
    if okX and okI and type(info) == "table" and info.resolved ~= false
        and type(info.name) == "string" and info.name ~= "" and info.name ~= "???" then
      return info.name
    end
    return "AREA " .. tostring(id)
  end
  local s = tostring(id or key):gsub("^MAP_", ""):gsub("_", " ")
  return s
end

-- Rows for the page: { text, kind } with kind "head" for section titles.
local function rows()
  local run = State.run()
  local out = {}
  local function add(text, kind) out[#out + 1] = { text = text, kind = kind } end
  if not run then
    add("No run on this save.")
    return out
  end
  add("RUN", "head")
  add("Seed " .. tostring(run.seed) .. (run.over and "   RUN OVER" or ""))
  if not run.started and not run.over then add("Rules start with OAK's POKE BALLS.") end
  local okCap, capLine = pcall(N.caps.summary)
  if okCap and capLine then
    local cap, bank = capLine:match("^(.-)  Banked EXP %(party%): (%d+)$")
    add(cap or capLine)
    if bank then add("Banked EXP (party): " .. bank) end
  end
  if run.rando then add("Randomized: starters, wild, trainers") end
  if run.hard then add("Trainers: tougher (Lv, AI, moves)") end

  local s = E.session()
  local party = s and s.party or {}
  add("PARTY", "head")
  if #party == 0 then add("  (empty)") end
  for _, mon in ipairs(party) do
    local name = E.monName(mon)
    local lv = tonumber(mon.level) or 0
    local line
    if E.isEgg(mon) then
      line = "  EGG"
    elseif N.permadeath.isDead(mon) then
      line = ("  %s Lv%d  DEAD"):format(name, lv)
    else
      local hp = tonumber(mon.hp) or 0
      local maxHp = tonumber(mon.maxHp or mon.maxHP) or hp
      line = ("  %s Lv%d  HP %d/%d"):format(name, lv, hp, maxHp)
      local okB, bank = pcall(N.caps.banked, mon)
      if okB and (bank or 0) > 0 then line = line .. "  +" .. bank end
    end
    add(line)
  end

  local areas = {}
  for key, area in pairs(run.areas or {}) do
    if type(area) == "table" then areas[#areas + 1] = { key = key, area = area } end
  end
  table.sort(areas, function(a, b)
    local na, nb = tonumber(a.area.n) or 1e9, tonumber(b.area.n) or 1e9
    if na ~= nb then return na < nb end
    return tostring(a.key) < tostring(b.key)
  end)
  local caughtAreas = 0
  for _, a in ipairs(areas) do if a.area.status == "caught" then caughtAreas = caughtAreas + 1 end end
  add(("AREAS  %d used, %d caught"):format(#areas, caughtAreas), "head")
  if #areas == 0 then add("  (none yet)") end
  for _, a in ipairs(areas) do
    local sp = tonumber(a.area.species)
    local what = sp and N.species.name(sp) or "?"
    add("  " .. areaName(a.key))
    add("    " .. what .. (a.area.status == "caught" and "  CAUGHT" or "  missed"))
  end

  local order = run.deadOrder or {}
  add(("DEATHS  %d"):format(#order), "head")
  if #order == 0 then add("  (none)") end
  for i, key in ipairs(order) do
    local d = run.dead and run.dead[key]
    if d then add(("  %d. %s%s"):format(i, tostring(d.name), d.level and (" Lv" .. d.level) or "")) end
  end
  return out
end
Menu.rows = rows

-- The old message-box page (fallback), built from the same rows.
local function summary()
  local parts = {}
  for _, r in ipairs(rows()) do
    if r.kind ~= "head" then parts[#parts + 1] = (r.text:gsub("^%s+", "")) end
  end
  return "NUZLOCKE RUN|" .. table.concat(parts, "|")
end
Menu.summary = summary

-- ------------------------------------------------------------ screen

local Screen = {}
Screen.__index = Screen

function Menu.newScreen(game)
  local self = setmetatable({ game = game, rows = rows(), scroll = 0, frames = 0,
    isOpaque = true, gbaCanvas = true }, Screen)
  return self
end

function Screen:maxScroll() return math.max(0, #self.rows - VISIBLE) end

function Screen:update()
  self.frames = self.frames + 1
  local input = self.game and self.game.input
  if not input or self.frames < 3 then return end
  local function pressed(k) return input.wasPressed and input:wasPressed(k) end
  if pressed("b") or pressed("a") or pressed("start") then
    E.sound("SE_SELECT")
    self.game.stack:pop()
    return
  end
  local before = self.scroll
  if pressed("down") then self.scroll = self.scroll + 1 end
  if pressed("up") then self.scroll = self.scroll - 1 end
  if pressed("right") then self.scroll = self.scroll + VISIBLE end
  if pressed("left") then self.scroll = self.scroll - VISIBLE end
  self.scroll = math.max(0, math.min(self.scroll, self:maxScroll()))
  if self.scroll ~= before then E.sound("SE_SELECT") end
end

function Screen:draw()
  local Window = E.req("src.ui.game3.window")
  local Font = E.req("src.ui.game3.frlg_font")
  if not (Window and Font) then return end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, VIEW_W, 160)
  Window.stdFrame(Window.template(LEFT, TOP, COLS, ROWS))
  local x0, w = LEFT * 8 + 2, COLS * 8 - 4
  local blue = { fg = Font.STDPAL[8], shadow = Font.STDPAL[9], bg = Font.STDPAL[0] }
  local normal = Font.COLOR.NORMAL
  Font.draw("NUZLOCKE FR", x0, 8, { colors = blue })
  local pos = #self.rows > VISIBLE
    and ("%d-%d/%d"):format(self.scroll + 1, math.min(#self.rows, self.scroll + VISIBLE), #self.rows)
    or ""
  if pos ~= "" then
    local okM, pw = pcall(Font.measure, pos)
    Font.draw(pos, x0 + w - (okM and pw or 0), 8, { colors = normal })
  end
  for i = 1, VISIBLE do
    local r = self.rows[self.scroll + i]
    if not r then break end
    Font.draw(r.text, x0, LIST_TOP + (i - 1) * ROW_H,
      { colors = r.kind == "head" and blue or normal, maxWidth = w })
  end
  love.graphics.setColor(1, 1, 1, 1)
end

local function openScreen()
  local game = E.game()
  local Bridge = E.req("src.ui.game3.mod_ui")
  if not (game and Bridge and Bridge.stackFor) then return false end
  local ok, err = pcall(function() Bridge.stackFor(game):push(Menu.newScreen(game)) end)
  if not ok then mod.log:error("run menu failed to open: %s", tostring(err)) end
  return ok
end
Menu.open = openScreen

local function closeStartMenu()
  local SM = E.req("src.ui.game3.start_menu")
  if SM and SM.isOpen and SM.isOpen() and SM.close then pcall(SM.close, true) end
end

function Menu.install(ctx)
  N, mod, E, State = ctx, ctx.mod, ctx.engine, ctx.state

  mod.hooks:wrap("ui.start_menu.items", function(nextFn, game, items)
    local out = nextFn(game, items)
    if type(out) ~= "table" or not State.active() then return out end
    local entry = {
      id = "nuzlocke_fr", label = "NUZLOCKE",
      onSelect = function()
        closeStartMenu()
        if not openScreen() then N.prompt.say(summary()) end
      end,
    }
    local at = #out + 1
    for i, item in ipairs(out) do
      if type(item) == "table" and (item.id == "save" or item.label == "SAVE") then
        at = i
        break
      end
    end
    table.insert(out, at, entry)
    return out
  end)
end

return Menu
