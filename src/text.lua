-- Formats plain text for FireRed's two-line message box.
-- "\n" is a line break and "\f" a new box in the engine's ASCII text
-- (src/core/game3/scripting/text_ir.lua fromAscii). A "|" in our own
-- strings forces a new box.

local Text = {}

local WIDTH = 30 -- characters per line; the box fits a little more, this stays safe

local function wrapParagraph(para)
  local lines, line = {}, ""
  for word in para:gmatch("%S+") do
    if line == "" then
      line = word
    elseif #line + 1 + #word <= WIDTH then
      line = line .. " " .. word
    else
      lines[#lines + 1] = line
      line = word
    end
  end
  if line ~= "" then lines[#lines + 1] = line end
  return lines
end

function Text.box(s)
  local pages = {}
  for para in (tostring(s or "") .. "|"):gmatch("(.-)|") do
    local lines = wrapParagraph(para)
    for i = 1, #lines, 2 do
      pages[#pages + 1] = lines[i] .. (lines[i + 1] and ("\n" .. lines[i + 1]) or "")
    end
  end
  return table.concat(pages, "\f")
end

return Text
