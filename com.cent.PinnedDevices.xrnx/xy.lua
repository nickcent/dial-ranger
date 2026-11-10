-- One mapping per source parameter per panel. A mapping travels with its pin
-- when tracks/devices move. Captured strings are the device's native units.
local scaling = require("scaling")
local M = {}

function M.write(p, value)
  local low, high, quantum = p.value_min, p.value_max, p.value_quantum
  value = math.max(low, math.min(high, value))
  if quantum > 0 and value ~= high then
    value = math.min(high, low + math.floor((value - low) / quantum + 0.5) * quantum)
  end
  if value ~= p.value then
    if p.is_automatable then p:record_value(value) else p.value = value end
  end
end

function M.assign(source, index, axis, p)
  if not source.maps then source.maps = {} end
  if not axis then
    source.maps[index] = nil
    return
  end
  local map = source.maps[index] or {
    scaling = scaling.linear, low = p.value, high = p.value, low_text = p.value_string, high_text = p.value_string,
  }
  map.axis = axis
  source.maps[index] = map
end

function M.capture(map, endpoint, p)
  map[endpoint] = p.value
  map[endpoint .. "_text"] = p.value_string
end

function M.move(panel, x, y, pins, resolve)
  if x ~= nil then panel.x = x end
  if y ~= nil then panel.y = y end
  for _, source in ipairs(pins) do
    if source.panel == panel and source.maps then
      local track, device = resolve(source)
      if track then
        for index, map in pairs(source.maps) do
          local position
          if map.axis == "x" then position = x else position = y end
          local p = device.parameters[index]
          if p and position ~= nil then
            local t = scaling.apply(map.scaling, position)
            M.write(p, map.low + (map.high - map.low) * t)
          end
        end
      end
    end
  end
end

local function escape(text)
  return (text:gsub("[%%%c]", function(c) return ("%%%02X"):format(c:byte()) end))
end

local function unescape(text)
  return (text:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

local function number(value)
  return ("%.17g"):format(value)
end

-- Extra tagged records keep legacy pin and panel records intact.
function M.save(file, out, panels, pins)
  for _, panel in ipairs(panels) do
    if panel.x or panel.y then
      out[#out + 1] = table.concat({file, "xy-pad", panel.id,
        number(panel.x or 0.5), number(panel.y or 0.5)}, "\t")
    end
  end
  for _, source in ipairs(pins) do
    if source.panel and source.maps then
      for _, index in ipairs(source.params) do
        local m = source.maps[index]
        if m then
          out[#out + 1] = table.concat({file, "xy-range", source.panel.id,
            source.track_index, source.device_index, index, m.axis,
            number(m.low), number(m.high), escape(m.low_text), escape(m.high_text),
            m.scaling or scaling.linear}, "\t")
        end
      end
    end
  end
end

local function finite(text)
  local n = tonumber(text)
  if n and math.abs(n) < math.huge then return n end
end

function M.restore(file, records, panels_by_id, pins)
  for line in records:gmatch("[^\n]+") do
    local project, id, x, y = line:match("^([^\t]*)\txy%-pad\t(%d+)\t([^\t]+)\t([^\t]+)$")
    local panel = panels_by_id[id]
    if project == file and panel then
      x, y = finite(x), finite(y)
      if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then panel.x, panel.y = x, y end
    end
    local track, device, index, axis, low, high, low_text, high_text, curve
    project, id, track, device, index, axis, low, high, low_text, high_text, curve =
      line:match("^([^\t]*)\txy%-range\t(%d+)\t(%d+)\t(%d+)\t(%d+)\t([xy])\t([^\t]+)\t([^\t]+)\t([^\t]*)\t([^\t]*)\t?(%d*)$")
    panel = panels_by_id[id]
    if project == file and panel then
      low, high = finite(low), finite(high)
      for _, source in ipairs(pins) do
        if low and high and source.panel == panel and source.track_index == tonumber(track)
          and source.device_index == tonumber(device) then
          for _, i in ipairs(source.params) do
            if i == tonumber(index) then
              source.maps = source.maps or {}
              source.maps[i] = {axis = axis, low = low, high = high,
                scaling = scaling.names[tonumber(curve)] and tonumber(curve) or scaling.linear,
                low_text = unescape(low_text), high_text = unescape(high_text)}
              break
            end
          end
          break
        end
      end
    end
  end
end

return M
