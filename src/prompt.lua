-- Field messages and YES/NO questions, shown one at a time when the
-- overworld is idle. Uses the game's own message box and YES/NO box
-- (src/ui/game3/message.lua, choice.lua); the field HUD already routes the
-- buttons to them, exactly as for a script's yesnobox.

local Prompt = {}

local N, E
local queue = {}
local current = nil

function Prompt.say(text, onDone)
  queue[#queue + 1] = { kind = "say", text = text, cb = onDone }
end

function Prompt.ask(text, onAnswer)
  queue[#queue + 1] = { kind = "ask", text = text, cb = onAnswer }
end

function Prompt.busy()
  return current ~= nil or #queue > 0
end

-- Drop anything pending (used when leaving the game, e.g. a soft reset).
function Prompt.clear()
  queue = {}
  current = nil
end

local function finish(job, ...)
  current = nil
  if job.cb then
    local ok, err = pcall(job.cb, ...)
    if not ok then N.mod.log:error("prompt callback failed: %s", tostring(err)) end
  end
end

local function onLastPage(Message)
  if not (Message.isOpen() and Message.isWaiting()) then return false end
  if Message.isTyping and Message.isTyping() then return false end
  local pages = Message._pages
  return not pages or (Message._page or 1) >= #pages
end

local function step(game)
  local Message, Choice = E.message(), E.choice()
  if not (Message and Choice) then return end
  local job = current
  if job then
    if job.kind == "say" then
      if job.done or not Message.isOpen() then finish(job) end
    elseif not job.asked then
      if onLastPage(Message) and not Choice.isOpen() then
        job.asked = true
        Choice.yesNo(function(yes)
          pcall(Message.close)
          finish(job, yes and true or false)
        end)
      elseif not Message.isOpen() then
        -- Something closed our box before the question appeared; retry later.
        current = nil
        table.insert(queue, 1, job)
      end
    end
    return
  end
  if #queue == 0 or not E.fieldIdle(game) then return end
  job = table.remove(queue, 1)
  current = job
  local body = N.text.box(job.text)
  if job.kind == "ask" then
    job.asked = false
    Message.show(body, { stay = true })
  else
    Message.show(body, { done = function() job.done = true end })
  end
end

function Prompt.tick(game)
  local ok, err = pcall(step, game)
  if not ok then
    N.mod.log:error("prompt failed: %s", tostring(err))
    current = nil
  end
end

function Prompt.install(ctx)
  N, E = ctx, ctx.engine
end

return Prompt
