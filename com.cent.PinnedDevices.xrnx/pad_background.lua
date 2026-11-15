-- The XY pad: a grid drawn in its skin's colours, and above it a transparent
-- canvas that owns the gestures and draws the dot.
local M = {}

local function draw_grid(ctx, size, palette)
  ctx.fill_color = palette.pad
  ctx:fill_rect(0, 0, size, size)
  ctx.stroke_color, ctx.line_width = palette.grid, 1
  for i = 1, 9 do
    local at = i * size / 10
    ctx:begin_path(); ctx:move_to(at, 0); ctx:line_to(at, size); ctx:stroke()
    ctx:begin_path(); ctx:move_to(0, at); ctx:line_to(size, at); ctx:stroke()
  end
  local mid = size / 2
  ctx.stroke_color, ctx.line_width = palette.ring, 1.5
  for _, r in ipairs({0.14, 0.28, 0.42}) do
    ctx:begin_path()
    ctx:arc(mid, mid, r * size, 0, 2 * math.pi)
    ctx:stroke()
  end
  ctx.stroke_color, ctx.line_width = palette.cross, 1.5
  ctx:begin_path(); ctx:move_to(mid, 0); ctx:line_to(mid, size); ctx:stroke()
  ctx:begin_path(); ctx:move_to(0, mid); ctx:line_to(size, mid); ctx:stroke()
  ctx.stroke_color, ctx.line_width = palette.corner, 4
  local inset, arm = 24, 44
  for _, c in ipairs({{inset, inset, 1, 1}, {size - inset, inset, -1, 1},
      {inset, size - inset, 1, -1}, {size - inset, size - inset, -1, -1}}) do
    ctx:begin_path()
    ctx:move_to(c[1] + c[3] * arm, c[2])
    ctx:line_to(c[1], c[2])
    ctx:line_to(c[1], c[2] + c[4] * arm)
    ctx:stroke()
  end
  ctx.stroke_color, ctx.line_width = palette.border, 2
  ctx:stroke_rect(1, 1, size - 2, size - 2)
end

M.size = 400 -- pad edge in pixels; the strips under the pad match it

-- Returns the pad view, drawn in the palette `look`, and its controls:
-- `follow(axis, position)` for outside writers, `jump(x, y, recording, step)`
-- and `rest(recording)` to place it.
function M.layer(vb, panel, look, move, save)
  local size = M.size
  local held
  local moving -- true while the pad itself writes the parameters
  local cursor
  -- Places the pad without a gesture: slot recalls and the Auto Reset return.
  local function jump(x, y, recording, step)
    moving = true
    move(x, y, recording, step)
    moving = false
    cursor:update()
  end
  -- Like Renoise's XY pad: with Auto Reset on, an idle pad sits at its reset
  -- position. A recording gesture records the return too.
  local function rest(recording)
    if panel.auto_reset then jump(panel.reset_x or 0.5, panel.reset_y or 0.5, recording) end
  end
  local function mouse(event)
    if event.type == "down" then
      if event.button ~= "left" and event.button ~= "right" then return event end
      held = event.button
    elseif event.type == "up" then
      if event.button == held then
        rest(held == "right")
        held = nil
        save()
      end
      return
    elseif event.type ~= "drag" or not held then
      return event
    end
    local x = math.max(0, math.min(1, event.position.x / (size - 1)))
    local y = 1 - math.max(0, math.min(1, event.position.y / (size - 1)))
    local recording = held == "right"
    if not recording then
      if x == (panel.x or 0.5) then x = nil end
      if y == (panel.y or 0.5) then y = nil end
    end
    move(x, y, recording)
    cursor:update()
  end
  local grid = vb:canvas {width = size, height = size, mode = "plain",
    render = function(ctx) draw_grid(ctx, size, look) end}
  cursor = vb:canvas {width = size, height = size, mode = "transparent",
    tooltip = "Left-drag to adjust. Right-drag to record both axes.",
    mouse_events = {"down", "drag", "up"}, mouse_handler = mouse, render = function(ctx)
    local x = math.max(6, math.min(size - 6, (panel.x or 0.5) * (size - 1)))
    local y = math.max(6, math.min(size - 6, (1 - (panel.y or 0.5)) * (size - 1)))
    ctx:begin_path()
    ctx:arc(x, y, 5, 0, 2 * math.pi)
    ctx.fill_color = look.cursor
    ctx:fill()
    ctx.stroke_color, ctx.line_width = look.pad, 2
    ctx:stroke()
  end}
  -- Automation and other writers move the cursor; the pad's own moves win.
  local function follow(axis, position)
    if held or moving or panel[axis] == position then return end
    panel[axis] = position
    cursor:update()
  end
  return vb:stack {grid, cursor}, {follow = follow, jump = jump, rest = rest}
end

return M
