-- One mapping per source parameter per panel. A mapping travels with its pin
-- when tracks/devices move. Captured strings are the device's native units.
local scaling = require("scaling")
local M = {}

M.slots = 8 -- stored pad positions per panel
local STEP_LEAD = 1 / 256 -- one unit of Renoise's automation sub-line grid

local function mapped_value(p, value)
  local low, high, quantum = p.value_min, p.value_max, p.value_quantum
  value = math.max(low, math.min(high, value))
  if quantum > 0 and value ~= high then
    value = math.min(high, low + math.floor((value - low) / quantum + 0.5) * quantum)
  end
  return value
end

function M.write(p, value)
  value = mapped_value(p, value)
  if value ~= p.value then
    if p.is_automatable then p:record_value(value) else p.value = value end
  end
end

function M.assign(source, index, axis, p, use_full_range)
  if not source.maps then source.maps = {} end
  if not axis then
    source.maps[index] = nil
    return
  end
  local map = source.maps[index] or {
    scaling = scaling.linear, low = p.value, high = p.value, low_text = p.value_string, high_text = p.value_string,
  }
  if use_full_range and not source.maps[index] then
    map.low, map.high = p.value_min, p.value_max
    map.low_text, map.high_text = tostring(map.low), tostring(map.high)
  end
  map.axis = axis
  source.maps[index] = map
end

function M.capture(map, endpoint, p)
  map[endpoint] = p.value
  map[endpoint .. "_text"] = p.value_string
end

-- `step` marks a jump: recording holds the old value right up to the line,
-- so a linear or curved envelope plays the jump instead of a ramp. A hold
-- already on that line stays, or a repeated jump would flatten the first.
function M.move(panel, x, y, pins, resolve, recording, step)
  local pattern, line
  if recording then
    local song = renoise.song()
    local transport = song.transport
    local pos = transport.playing and transport.playback_pos or transport.edit_pos
    pattern = song.patterns[song.sequencer.pattern_sequence[pos.sequence]]
    line = pos.line
  end
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
            local value = mapped_value(p, map.low + (map.high - map.low) * t)
            local previous = p.value
            if previous ~= value then p.value = value end
            if recording and p.is_automatable and p.value_max > p.value_min then
              local lane = pattern.tracks[source.track_index]
              local envelope = lane:find_automation(p) or lane:create_automation(p)
              local range = p.value_max - p.value_min
              local hold = line - STEP_LEAD
              if step and line > 1 and previous ~= value and not envelope:has_point_at(hold) then
                envelope:add_point_at(hold, (previous - p.value_min) / range)
              end
              envelope:add_point_at(line, (value - p.value_min) / range)
            end
          end
        end
      end
    end
  end
end

-- Pad position that reproduces the parameter's current value; nil while the
-- mapping has no range.
local function position(map, p)
  if map.high == map.low then return nil end
  local t = (p.value - map.low) / (map.high - map.low)
  return scaling.invert(map.scaling, math.max(0, math.min(1, t)))
end

-- Calls report(axis, position) whenever a mapped parameter changes, as when
-- automation plays. The first mapping with a range leads its axis, so several
-- parameters on one axis cannot pull the cursor apart.
function M.follow(panel, pins, resolve, watch, report)
  local mapped = {x = {}, y = {}}
  local function sync(axis)
    for _, m in ipairs(mapped[axis]) do
      local at = position(m.map, m.parameter)
      if at then return report(axis, at) end
    end
  end
  for _, source in ipairs(pins) do
    if source.panel == panel and source.maps then
      local track, device = resolve(source)
      if track then
        for _, index in ipairs(source.params) do
          local map, parameter = source.maps[index], device.parameters[index]
          if map and parameter then
            local axis = map.axis
            mapped[axis][#mapped[axis] + 1] = {map = map, parameter = parameter}
            watch(parameter.value_observable, function() sync(axis) end)
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

-- Appends this module's tagged records for the pads and their mappings.
function M.save(out, panels, pins)
  for _, panel in ipairs(panels) do
    if panel.x or panel.y then
      out[#out + 1] = table.concat({"xy-pad", panel.id,
        number(panel.x or 0.5), number(panel.y or 0.5)}, "\t")
    end
    if panel.auto_reset or panel.reset_x or panel.reset_y then
      out[#out + 1] = table.concat({"xy-reset", panel.id, panel.auto_reset and 1 or 0,
        number(panel.reset_x or 0.5), number(panel.reset_y or 0.5)}, "\t")
    end
    for i = 1, M.slots do
      local slot = panel.slots and panel.slots[i]
      if slot then
        out[#out + 1] = table.concat({"xy-slot", panel.id, i, number(slot.x), number(slot.y)}, "\t")
      end
    end
  end
  for _, source in ipairs(pins) do
    if source.panel and source.maps then
      for _, index in ipairs(source.params) do
        local m = source.maps[index]
        if m then
          out[#out + 1] = table.concat({"xy-range", source.panel.id,
            source.track_index, source.device_index, index, m.axis,
            number(m.low), number(m.high), escape(m.low_text), escape(m.high_text),
            number(m.scaling or scaling.linear)}, "\t")
        end
      end
    end
  end
end

local function finite(text)
  local n = tonumber(text)
  if n and math.abs(n) < math.huge then return n end
end

-- A stored pad coordinate; nil unless the text is a number from 0 to 1.
local function coordinate(text)
  local n = finite(text)
  if n and n >= 0 and n <= 1 then return n end
end

function M.restore(records, panels_by_id, pins)
  for line in records:gmatch("[^\n]+") do
    local id, x, y = line:match("^xy%-pad\t(%d+)\t([^\t]+)\t([^\t]+)$")
    local panel = panels_by_id[id]
    if panel then
      x, y = coordinate(x), coordinate(y)
      if x and y then panel.x, panel.y = x, y end
    end
    local enabled
    id, enabled, x, y = line:match("^xy%-reset\t(%d+)\t([01])\t([^\t]+)\t([^\t]+)$")
    panel = panels_by_id[id]
    if panel then
      x, y = coordinate(x), coordinate(y)
      if x and y then panel.auto_reset, panel.reset_x, panel.reset_y = enabled == "1", x, y end
    end
    local slot
    id, slot, x, y = line:match("^xy%-slot\t(%d+)\t(%d+)\t([^\t]+)\t([^\t]+)$")
    panel = panels_by_id[id]
    if panel then
      slot, x, y = tonumber(slot), coordinate(x), coordinate(y)
      if x and y and slot >= 1 and slot <= M.slots then
        panel.slots = panel.slots or {}
        panel.slots[slot] = {x = x, y = y}
      end
    end
    local track, device, index, axis, low, high, low_text, high_text, curve
    id, track, device, index, axis, low, high, low_text, high_text, curve =
      line:match("^xy%-range\t(%d+)\t(%d+)\t(%d+)\t(%d+)\t([xy])\t([^\t]+)\t([^\t]+)\t([^\t]*)\t([^\t]*)\t?([^\t]*)$")
    panel = panels_by_id[id]
    if panel then
      low, high, curve = finite(low), finite(high), finite(curve)
      for _, source in ipairs(pins) do
        if low and high and source.panel == panel and source.track_index == tonumber(track)
          and source.device_index == tonumber(device) then
          for _, i in ipairs(source.params) do
            if i == tonumber(index) then
              source.maps = source.maps or {}
              source.maps[i] = {axis = axis, low = low, high = high,
                scaling = curve and curve >= 0 and curve <= 6 and curve or scaling.linear,
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
