local scaling = require("scaling")
local M = {}

-- Every edge shares the same two colours. At least one band contrasts with
-- any host theme; the content sets the stack's size as panels expand/shrink.
function M.frame(vb, content)
  return vb:stack {
    vb:canvas {width = "100%", height = "100%", mode = "transparent", render = function(ctx)
      local w, h = ctx.size.width, ctx.size.height
      for i, color in ipairs({{19, 25, 24}, {248, 220, 122}, {19, 25, 24}}) do
        local offset = (i - 1) * 2
        ctx.stroke_color, ctx.line_width = color, 2
        ctx:stroke_rect(offset + 1, offset + 1, w - 2 * offset - 2, h - 2 * offset - 2)
      end
    end},
    vb:column {margin = 6, content},
  }
end

local function icon(index)
  return ("images/scale-%d.bmp"):format(index)
end

-- Native popups take text items only. Use themed bitmap buttons in a
-- collapsible list so all five options show their actual transfer curves.
function M.scaling_picker(vb, map, save)
  local choices = vb:column {visible = false}
  local function toggle() choices.visible = not choices.visible end
  local current = map.scaling or scaling.linear
  local preview = vb:button {bitmap = icon(current), width = 42, height = 20,
    tooltip = "Scaling: " .. scaling.names[current], notifier = toggle}
  for i, name in ipairs(scaling.names) do
    local function select()
      map.scaling = i
      preview.bitmap = icon(i)
      preview.tooltip = "Scaling: " .. name
      choices.visible = false
      save()
    end
    choices:add_view(vb:row {
      vb:button {bitmap = icon(i), width = 42, height = 20, tooltip = name, notifier = select},
      vb:button {text = name, width = 76, height = 20, notifier = select},
    })
  end
  return vb:column {
    vb:row {vb:text {text = "Scaling"}, preview,
      vb:button {text = "▾", width = 18, tooltip = "Choose scaling curve", notifier = toggle}},
    choices,
  }
end

return M
