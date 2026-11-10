-- Pin model: which devices/parameters are pinned, index remapping when the
-- song structure changes, and persistence per project file.
-- UI-free: dashboard.lua listens through M.on_change.
--
-- one pin = one card
-- { track_index = integer, device_index = integer,
--   mode = "device" | "params",   -- "device" = all parameters, live count
--   params = { integer, ... },    -- sorted param indices; empty when mode == "device"
--   friction = { [param_index] = integer thousandths },
--   device_name = string }        -- device.name at pin time, for restore validation

local xy = require("xy")
local M = {}

local pins = {}
local panels = {}
local listener = nil

-- song-level notifier bookkeeping
local tracks_handler = nil           -- fn registered on song.tracks_observable
local device_handlers = {}           -- { {obs = devices_observable, fn = fn}, ... }

-- persistence
local prefs = renoise.Document.create("PinnedDevicesPreferences") {
  pins = "",
  pad_image = "",
  panel_look = "CNT Night Circuit",
}
renoise.tool().preferences = prefs

local function song()
  return renoise.song()
end

local function current_file()
  local f = song().file_name
  if f == nil or f == "" then return nil end -- UNTESTED (U7): unsaved song => ""
  return f
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

-- The optional seventh column stores nonzero friction as index:thousandths.
local function encode_friction(pin)
  local indices, fields = {}, {}
  for i in pairs(pin.friction) do indices[#indices + 1] = i end
  table.sort(indices)
  for _, i in ipairs(indices) do
    fields[#fields + 1] = i .. ":" .. pin.friction[i]
  end
  return table.concat(fields, ",")
end

local function decode_friction(field)
  local values = {}
  for item in field:gmatch("[^,]+") do
    local index, amount = item:match("^(%d+):(%d+)$")
    index, amount = tonumber(index), tonumber(amount)
    if index and index >= 1 and amount >= 1 and amount <= 1000 then
      values[index] = amount
    end
  end
  return values
end
function M.save()
  local file = current_file()
  if not file then return end
  local out = {}
  for line in prefs.pins.value:gmatch("[^\n]+") do
    local f = line:match("^([^\t]*)\t")
    if f and f ~= file then out[#out + 1] = line end
  end
  for _, panel in ipairs(panels) do
    out[#out + 1] = table.concat({file, "panel", panel.id, panel.color, panel.name}, "\t")
  end
  for _, p in ipairs(pins) do
    local fields = {
      file, tostring(p.track_index), tostring(p.device_index),
      p.device_name, p.mode, table.concat(p.params, ","), encode_friction(p),
    }
    if p.panel then fields[#fields + 1] = p.panel.id end
    out[#out + 1] = table.concat(fields, "\t")
  end
  xy.save(file, out, panels, pins)
  prefs.pins.value = table.concat(out, "\n")
end

-- Appends pins stored for `file`; silent (no save, no listener).
function M.restore(file)
  if file == nil or file == "" then return end
  local by_id = {}
  for line in prefs.pins.value:gmatch("[^\n]+") do
    local project, id, color, title = line:match("^([^\t]+)\tpanel\t(%d+)\t(%x%x%x%x%x%x)\t([^\t]+)$")
    if project == file then
      local panel = {id = tonumber(id), name = title, color = color}
      by_id[id] = panel
      panels[#panels + 1] = panel
    end
    local f, t, d, name, mode, plist, friction, panel_id =
      line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t?([^\t]*)\t?(%d*)$")
    if f == file then
      local ti, di = tonumber(t), tonumber(d)
      if (panel_id == "" or by_id[panel_id]) and ti and di and name ~= "" and (mode == "device" or mode == "params") then
        local params = {}
        for n in plist:gmatch("[^,]+") do
          local idx = tonumber(n)
          if idx then params[#params + 1] = idx end
        end
        table.sort(params)
        if mode == "device" or #params > 0 then
          pins[#pins + 1] = {
            track_index = ti, device_index = di,
            mode = mode, params = params, device_name = name,
            friction = decode_friction(friction), panel = by_id[panel_id],
          }
        end
      end
    end
  end
  xy.restore(file, prefs.pins.value, by_id, pins)
end

-- ---------------------------------------------------------------------------
-- Model
-- ---------------------------------------------------------------------------

local resync_device_handlers -- forward

-- resync=false only from inside a devices_observable notifier: re-registering
-- handlers on the observable that is dispatching is not safe. A handler left
-- on a track with no pins is harmless (its filter matches nothing).
local function notify(resync)
  M.prune()
  M.save()
  if resync ~= false then resync_device_handlers() end
  if listener then listener() end
end

local function find(track_index, device_index, panel)
  for i, p in ipairs(pins) do
    if p.panel == panel and p.track_index == track_index and p.device_index == device_index then
      return p, i
    end
  end
  return nil
end

function M.list()
  return pins
end

function M.set_friction(pin, index, amount)
  if (pin.friction[index] or 0) == amount then return end
  pin.friction[index] = amount > 0 and amount or nil
  M.save()
end

function M.panels()
  return panels
end

function M.create_panel()
  local id = 1
  for _, panel in ipairs(panels) do id = math.max(id, panel.id + 1) end
  local panel = {id = id, name = "Panel " .. id, color = "557647"}
  panels[#panels + 1] = panel
  notify()
  return panel
end

function M.update_panel(panel, name, color)
  name = name:gsub("[%c]", " "):match("^%s*(.-)%s*$")
  color = color:match("^#?(%x%x%x%x%x%x)$")
  if name == "" or not color then return false end
  panel.name, panel.color = name, color:upper()
  notify()
  return true
end

function M.remove_panel(panel)
  for i = #pins, 1, -1 do
    if pins[i].panel == panel then table.remove(pins, i) end
  end
  for i, candidate in ipairs(panels) do
    if candidate == panel then table.remove(panels, i); break end
  end
  notify()
end

function M.on_change(fn)
  listener = fn
end

function M.pin_device(track_index, device_index)
  local pin = find(track_index, device_index)
  if pin then
    pin.mode = "device"
    pin.params = {}
  else
    pin = {
      track_index = track_index, device_index = device_index,
      mode = "device", params = {}, friction = {},
      device_name = song().tracks[track_index].devices[device_index].name,
    }
    pins[#pins + 1] = pin
  end
  notify()
  return pin
end

function M.pin_param(track_index, device_index, param_index, panel, friction)
  local pin = find(track_index, device_index, panel)
  if pin then
    if pin.mode == "device" then return pin end -- already covered
    for _, i in ipairs(pin.params) do
      if i == param_index then return pin end
    end
    pin.params[#pin.params + 1] = param_index
    table.sort(pin.params)
  else
    pin = {
      track_index = track_index, device_index = device_index,
      mode = "params", params = { param_index }, friction = {}, panel = panel,
      device_name = song().tracks[track_index].devices[device_index].name,
    }
    pins[#pins + 1] = pin
  end
  if panel and friction == nil then
    local original = find(track_index, device_index)
    friction = original and original.friction[param_index]
  end
  if friction and friction > 0 then pin.friction[param_index] = friction end
  notify()
  return pin
end

local function remove_pin(pin)
  for i, p in ipairs(pins) do
    if p == pin then
      table.remove(pins, i)
      return true
    end
  end
  return false
end

function M.unpin(pin)
  if remove_pin(pin) then notify() end
end

function M.unpin_param(pin, param_index)
  if pin.mode == "device" then
    local track, device = M.resolve(pin)
    if not track or not device.parameters[param_index] then return end
    for i = 1, #device.parameters do pin.params[i] = i end
    pin.mode = "params"
  end
  for i, idx in ipairs(pin.params) do
    if idx == param_index then
      if pin.maps then pin.maps[param_index] = nil end
      pin.friction[param_index] = nil
      table.remove(pin.params, i)
      break
    end
  end
  if #pin.params == 0 then remove_pin(pin) end
  notify()
end

-- User action: forget every pin for this song (and persist that).
function M.clear()
  pins, panels = {}, {}
  notify()
end

-- Lifecycle: drop the in-memory model without saving or notifying.
function M.reset()
  pins, panels = {}, {}
end

-- Returns track, device or nil, reason.
function M.resolve(pin)
  local s = song()
  if pin.track_index < 1 or pin.track_index > #s.tracks then
    return nil, "track no longer exists"
  end
  local track = s.tracks[pin.track_index]
  if pin.device_index < 1 or pin.device_index > #track.devices then
    return nil, "device no longer exists"
  end
  local device = track.devices[pin.device_index]
  if device.name ~= pin.device_name then
    return nil, "a different device now sits at that position"
  end
  return track, device
end

local function report_dropped(pin)
  renoise.app():show_status(("Dial Ranger: dropped %s (track or device no longer exists)")
    :format(pin.device_name))
end

-- Removes pins that no longer resolve. Returns true when anything was dropped.
-- Does not save or notify: callers rebuild afterwards.
function M.prune()
  local kept, dropped = {}, false
  for _, p in ipairs(pins) do
    local track, device = M.resolve(p)
    if track then
      for index in pairs(p.maps or {}) do
        if not device.parameters[index] then
          p.maps[index] = nil
          dropped = true
        end
      end
      kept[#kept + 1] = p
    else
      report_dropped(p)
      dropped = true
    end
  end
  pins = kept
  return dropped
end

-- ---------------------------------------------------------------------------
-- Song notifiers: keep indices valid across insert / remove / swap
-- ---------------------------------------------------------------------------

local function apply_list_change(change, field, filter)
  if change.type == "insert" then
    for _, p in ipairs(pins) do
      if filter(p) and p[field] >= change.index then
        p[field] = p[field] + 1
      end
    end
  elseif change.type == "remove" then
    local kept = {}
    for _, p in ipairs(pins) do
      if not filter(p) or p[field] < change.index then
        kept[#kept + 1] = p
      elseif p[field] > change.index then
        p[field] = p[field] - 1
        kept[#kept + 1] = p
      else
        report_dropped(p)
      end
    end
    pins = kept
  elseif change.type == "swap" then
    for _, p in ipairs(pins) do
      if filter(p) then
        if p[field] == change.index1 then
          p[field] = change.index2
        elseif p[field] == change.index2 then
          p[field] = change.index1
        end
      end
    end
  end
end

local function all(_) return true end

local function on_tracks_changed(change)
  apply_list_change(change, "track_index", all)
  notify()
end

local function make_device_handler(track_index)
  return function(change)
    apply_list_change(change, "device_index", function(p)
      return p.track_index == track_index
    end)
    notify(false)
  end
end

local function remove_device_handlers()
  for _, h in ipairs(device_handlers) do
    -- the track may have just been deleted; its observable is then invalid
    pcall(function() h.obs:remove_notifier(h.fn) end)
  end
  device_handlers = {}
end

resync_device_handlers = function()
  if not tracks_handler then return end -- song not attached
  remove_device_handlers()
  local s = song()
  local seen = {}
  for _, p in ipairs(pins) do
    local ti = p.track_index
    if not seen[ti] and ti >= 1 and ti <= #s.tracks then
      seen[ti] = true
      local obs = s.tracks[ti].devices_observable
      local fn = make_device_handler(ti)
      obs:add_notifier(fn)
      device_handlers[#device_handlers + 1] = { obs = obs, fn = fn }
    end
  end
end

function M.attach_song()
  if tracks_handler then return end
  tracks_handler = on_tracks_changed
  song().tracks_observable:add_notifier(tracks_handler)
  resync_device_handlers()
end

function M.detach_song()
  remove_device_handlers()
  if tracks_handler then
    pcall(function() song().tracks_observable:remove_notifier(tracks_handler) end)
    tracks_handler = nil
  end
end

return M
