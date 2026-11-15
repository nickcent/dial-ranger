-- The transparent canvas owns the gesture above the background. Without a
-- chosen image the pad draws its own grid in the theme's colours.
local theme = require("theme")
local M = {}
local DEFAULT_LABEL = "Default grid"
local effective -- fitted custom image path, nil for the drawn grid
local picture

local function quote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- Express UTF-8 paths as numeric bytes inside the fixed PowerShell command.
local function windows_path(path)
  local bytes = {}
  for i = 1, #path do bytes[i] = path:byte(i) end
  return "[Text.Encoding]::UTF8.GetString([byte[]](" .. table.concat(bytes, ",") .. "))"
end

local function fit_image(path)
  local output = os.tmpname("png")
  local platform = os.platform()
  local command
  if platform == "MACINTOSH" then
    command = "/usr/bin/sips -s format png -Z 400 -p 400 400 --padColor 15191F "
      .. quote(path) .. " --out " .. quote(output)
  elseif platform == "WINDOWS" then
    command = 'powershell.exe -NoProfile -NonInteractive -Command "'
      .. "$ErrorActionPreference='Stop'; Add-Type -AssemblyName System.Drawing; "
      .. "$src=[Drawing.Image]::FromFile(" .. windows_path(path) .. "); "
      .. "$dst=New-Object Drawing.Bitmap 400,400; $g=[Drawing.Graphics]::FromImage($dst); "
      .. "$g.Clear([Drawing.Color]::FromArgb(21,25,31)); "
      .. "$s=400.0/[Math]::Max($src.Width,$src.Height); "
      .. "$w=[int]($s*$src.Width); $h=[int]($s*$src.Height); "
      .. "$g.DrawImage($src,[int]((400-$w)/2),[int]((400-$h)/2),$w,$h); "
      .. "$dst.Save(" .. windows_path(output) .. ',[Drawing.Imaging.ImageFormat]::Png)"'
  else
    command = "magick " .. quote(path .. "[0]")
      .. " -auto-orient -thumbnail 400x400 -background '#15191F' -gravity center -extent 400x400 "
      .. quote(output)
  end
  local rc = os.execute(command)
  if rc ~= 0 and rc ~= true then
    error(platform == "LINUX" and "Could not read image. Linux requires ImageMagick (magick)." or "Could not read image.")
  end
  return output
end

function M.settings(vb)
  picture = nil
  local pref = renoise.tool().preferences.pad_image
  local label = vb:text(theme.dim {width = 172, text = ""})
  local reset = vb:button(theme.button {text = "Restore default", notifier = function()
    if picture then picture.visible = false end
    effective, pref.value = nil, ""
    label.text, label.tooltip = DEFAULT_LABEL, DEFAULT_LABEL
  end})
  local function select_image(path)
    local image = fit_image(path)
    -- Validate decoding even when the pad is collapsed.
    if picture then
      picture.bitmap, picture.visible = image, true
    else
      vb:bitmap {bitmap = image}
    end
    effective, pref.value = image, path
    label.text, label.tooltip = path:match("[^/\\]+$") or path, path
  end
  local function choose()
    local path = renoise.app():prompt_for_filename_to_read({"*.*"}, "Choose XY pad background")
    if path and path ~= "" then
      local ok, err = pcall(select_image, path)
      if not ok then renoise.app():show_warning("XY pad background: " .. tostring(err)) end
    end
  end
  effective = nil
  label.text, label.tooltip = DEFAULT_LABEL, DEFAULT_LABEL
  if pref.value ~= "" then
    local ok = pcall(select_image, pref.value)
    if not ok then
      label.text, label.tooltip = "Default grid (image unavailable)", pref.value
    end
  end
  return vb:row {spacing = renoise.ViewBuilder.DEFAULT_CONTROL_SPACING,
    vb:text(theme.text {text = "XY background", width = 94}), label,
    vb:button(theme.button {text = "Choose image…", notifier = choose}), reset}
end

local function draw_grid(ctx, size)
  local palette = theme.palette
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

function M.layer(vb, panel, move, save)
  local size = 400
  local held
  local cursor
  local function mouse(event)
    if event.type == "down" then
      if event.button ~= "left" and event.button ~= "right" then return event end
      held = event.button
    elseif event.type == "up" then
      if event.button == held then
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
    render = function(ctx) draw_grid(ctx, size) end}
  -- A placeholder bitmap keeps the view valid until an image is chosen.
  picture = vb:bitmap {bitmap = effective or "images/scale-1.bmp", mode = "plain",
    visible = effective ~= nil}
  cursor = vb:canvas {width = size, height = size, mode = "transparent",
    tooltip = "Left-drag to adjust. Right-drag to record both axes.",
    mouse_events = {"down", "drag", "up"}, mouse_handler = mouse, render = function(ctx)
    local x = math.max(6, math.min(size - 6, (panel.x or 0.5) * (size - 1)))
    local y = math.max(6, math.min(size - 6, (1 - (panel.y or 0.5)) * (size - 1)))
    ctx:begin_path()
    ctx:arc(x, y, 5, 0, 2 * math.pi)
    ctx.fill_color = theme.palette.cursor
    ctx:fill()
    ctx.stroke_color, ctx.line_width = theme.palette.pad, 2
    ctx:stroke()
  end}
  return vb:stack {grid, picture, cursor}
end

return M
