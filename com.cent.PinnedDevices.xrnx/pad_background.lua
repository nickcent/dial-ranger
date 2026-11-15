-- The transparent canvas owns the gesture above the background image.
local M = {}
local default = "images/flux-radar-grid.png"
local effective = default
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
  local label = vb:text {width = 172, text = ""}
  local reset = vb:button {text = "Restore default", notifier = function()
    if picture then picture.bitmap = default end
    effective, pref.value = default, ""
    label.text, label.tooltip = "FLUX Radar Grid", "FLUX Radar Grid"
  end}
  local function select_image(path)
    local image = fit_image(path)
    -- Validate decoding even when the pad is collapsed.
    if picture then picture.bitmap = image else vb:bitmap {bitmap = image} end
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
  effective = default
  label.text, label.tooltip = "FLUX Radar Grid", "FLUX Radar Grid"
  if pref.value ~= "" then
    local ok = pcall(select_image, pref.value)
    if not ok then
      label.text, label.tooltip = "FLUX (image unavailable)", pref.value
    end
  end
  return vb:row {vb:text {text = "XY background", width = 94}, label,
    vb:button {text = "Choose image…", notifier = choose}, reset}
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
  picture = vb:bitmap {bitmap = effective, mode = "plain"}
  cursor = vb:canvas {width = size, height = size, mode = "transparent",
    tooltip = "Left-drag to adjust. Right-drag to record both axes.",
    mouse_events = {"down", "drag", "up"}, mouse_handler = mouse, render = function(ctx)
    local x = math.max(5, math.min(size - 5, (panel.x or 0.5) * (size - 1)))
    local y = math.max(5, math.min(size - 5, (1 - (panel.y or 0.5)) * (size - 1)))
    ctx:begin_path()
    ctx:arc(x, y, 4, 0, 2 * math.pi)
    ctx.fill_color = {247, 249, 245}
    ctx:fill()
    ctx.stroke_color, ctx.line_width = {16, 21, 24}, 2
    ctx:stroke()
  end}
  return vb:stack {picture, cursor}
end

return M
