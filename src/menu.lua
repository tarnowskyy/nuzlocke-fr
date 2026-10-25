-- START > NUZLOCKE: a status page for the run (seed, level cap, areas,
-- catches, deaths).
-- Only added on a save that is a Nuzlocke run.

local Menu = {}

local N, mod, E, State

local function summary()
  local run = State.run()
  if not run then return "NUZLOCKE: No run on this save." end
  local parts = {}
  parts[#parts + 1] = "NUZLOCKE RUN  Seed " .. tostring(run.seed)
    .. (run.over and "  (OVER)" or "")
  if not run.started then
    parts[#parts + 1] = "Rules start once PROF. OAK gives you POKE BALLS."
  end
  local okCap, capLine = pcall(N.caps.summary)
  if okCap and capLine then parts[#parts + 1] = capLine end
  parts[#parts + 1] = "Areas used: " .. tostring(run.areaCount or 0)
    .. "  Caught: " .. tostring(run.caught or 0)
  local order = run.deadOrder or {}
  parts[#parts + 1] = "Deaths: " .. tostring(#order)
  if #order > 0 then
    local names = {}
    for i = math.max(1, #order - 5), #order do
      local d = run.dead[order[i]]
      if d then
        names[#names + 1] = tostring(d.name) .. (d.level and (" Lv" .. d.level) or "")
      end
    end
    parts[#parts + 1] = "Fallen: " .. table.concat(names, ", ")
  end
  return table.concat(parts, "|")
end
Menu.summary = summary

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
        N.prompt.say(summary())
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
