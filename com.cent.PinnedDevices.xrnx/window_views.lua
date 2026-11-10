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

function M.curve_editor(vb, map, save)
  local width, height, pad = 360, 144, 7
  local w, h = width - 2 * pad, height - 2 * pad
  -- Renoise reports the Mac Command key as "control" in canvas mouse events.
  local fine_key = os.platform() == "MACINTOSH" and "Command" or "Control"
  local graph, last_y
  local function y_at(t)
    return pad + h * (1 - scaling.apply(map.scaling, t))
  end
  local function render(ctx)
    ctx.fill_color = {22, 27, 34}
    ctx:fill_rect(0, 0, width, height)
    ctx.fill_color = {41, 64, 87}
    ctx:begin_path()
    ctx:move_to(pad, height - pad)
    for x = 0, w, 1 do ctx:line_to(pad + x, y_at(x / w)) end
    ctx:line_to(width - pad, height - pad)
    ctx:close_path()
    ctx:fill()
    ctx.fill_color = {73, 86, 105}
    ctx:fill_rect(width / 2, pad, 1, h)
    ctx.stroke_color = {155, 188, 226}
    ctx.line_width = 1.5
    ctx:begin_path()
    ctx:move_to(pad, y_at(0))
    for x = 1, w do ctx:line_to(pad + x, y_at(x / w)) end
    ctx:stroke()
    ctx.fill_color = {234, 239, 246}
    for _, t in ipairs({0, 1}) do ctx:fill_rect(pad + t * w - 2, y_at(t) - 2, 4, 4) end
    ctx:fill_rect(width / 2 - 4, y_at(0.5) - 4, 8, 8)
  end
  local function mouse(e)
    if e.type == "down" and e.button == "left" then
      local dy = e.position.y - y_at(0.5)
      if math.abs(e.position.x - width / 2) <= 10 and math.abs(dy) <= 10 then
        last_y = e.position.y
      end
    elseif last_y and e.type == "drag" then
      local distance = last_y - e.position.y
      last_y = e.position.y
      if distance == 0 then return end
      local sensitivity = e.modifier_flags.control and 0.1 or 1
      local midpoint = scaling.apply(map.scaling, 0.5) + distance * sensitivity / h
      local value = scaling.from_midpoint(midpoint)
      if value ~= map.scaling then
        map.scaling = value
        graph:update()
      end
    elseif last_y and e.type == "up" then
      last_y = nil
      save()
    end
  end
  graph = vb:canvas {width = width, height = height, render = render,
    tooltip = "Drag the centre handle up or down. Hold " .. fine_key .. " for fine adjustment.", mouse_events = {"down", "drag", "up"},
    mouse_handler = mouse}
  local presets = vb:row {}
  for i, name in ipairs(scaling.names) do
    presets:add_view(vb:button {bitmap = ("images/scale-%d.bmp"):format(i), width = 42,
      tooltip = name, notifier = function()
        map.scaling = i
        graph:update()
        save()
      end})
  end
  local editor = vb:column {visible = false, graph, presets}
  return vb:column {
    vb:button {text = "Curve", width = 58, tooltip = "Edit mapping curve",
      notifier = function() editor.visible = not editor.visible end},
    editor,
  }
end

return M
