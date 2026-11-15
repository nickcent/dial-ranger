-- Dashboard: one non-modal dialog with a pin panel (follows the DSP chain
-- selection) and one card per pin, side by side. Cards are rebuilt from
-- indices on every structural change; live values flow through notifiers.

local pins = require("pins")
local background = require("pad_background")
local theme = require("theme")
local xy = require("xy")
local window_views = require("window_views")

local M = {}

local VB = renoise.ViewBuilder
local CARD_WIDTH = 530
local NAME_WIDTH = 110
local SLIDER_WIDTH = 130
local VALUE_WIDTH = 70

local dlg = nil
local vb = nil               -- root ViewBuilder
local cards_view = nil       -- row holding the cards
local xy_view               -- the current skin's XY parameters
local pad_view              -- holds the XY pad, right of the controls
local header_view           -- the logo; hidden when folded
local controls_view         -- pin panel, XY parameters and cards; hidden when folded
local displayed_device -- "track:device" of the device shown in the popup

-- The current skin's XY, created on first use.
local function destination()
  local skin = theme.current()
  return pins.panel(skin) or pins.create_panel(skin)
end
local card_children = {}     -- views currently inside cards_view
local card_notifiers = {}    -- { {obs, fn}, ... } song observables per card
local sel_notifiers = {}     -- { {obs, fn}, ... } selection observables

local function song()
  return renoise.song()
end

local function display_name(device)
  if device.display_name ~= "" then return device.display_name end
  return device.name
end

local function status(msg)
  renoise.app():show_status("Dial Ranger: " .. msg)
end

local function watch(list, obs, fn)
  obs:add_notifier(fn)
  list[#list + 1] = { obs = obs, fn = fn }
end

local function unwatch_all(list)
  for _, w in ipairs(list) do
    -- the observed object may be gone (deleted track/device, released song)
    pcall(function() w.obs:remove_notifier(w.fn) end)
  end
  for i = #list, 1, -1 do list[i] = nil end
end

-- ---------------------------------------------------------------------------
-- Pin panel
-- ---------------------------------------------------------------------------

local function refresh_selection()
  if not vb then return end
  local s = song()
  local dev = s.selected_track_device
  -- Renoise objects have no __eq; compare the selection by position.
  local key = dev and (s.selected_track_index .. ":" .. s.selected_track_device_index)
  local index = key == displayed_device and vb.views.param_popup.value or 1
  displayed_device = key
  local items = {}
  if dev then
    for i, p in ipairs(dev.parameters) do items[i] = p.name end
  end
  local available = #items > 0
  -- Badges: the track in its own Renoise colour, the device in the accent.
  vb.views.track_name.text = s.selected_track.name
  vb.views.track_name.color = s.selected_track.color
  local badge = dev and theme.accent({}) or theme.button({})
  vb.views.device_name.text = dev and display_name(dev) or "Select a device in the DSP chain"
  vb.views.device_name.tooltip = vb.views.device_name.text
  vb.views.device_name.color, vb.views.device_name.secondary_color = badge.color, badge.secondary_color
  vb.views.param_popup.items = available and items or {"No parameters"}
  vb.views.param_popup.value = math.min(index, #vb.views.param_popup.items)
  vb.views.param_popup.active = available
  vb.views.assign_x.active = available
  vb.views.assign_y.active = available
  vb.views.pin_device.active = dev ~= nil
  vb.views.pin_param.active = dev ~= nil and #dev.parameters > 0
end

local function pin_selected_device()
  local s = song()
  if not s.selected_track_device then return end
  pins.pin_device(s.selected_track_index, s.selected_track_device_index)
end

local function pin_selected_param(panel)
  local s = song()
  local dev = s.selected_track_device
  if not dev or #dev.parameters == 0 then return end
  local idx = vb.views.param_popup.value
  if idx < 1 or idx > #dev.parameters then return end
  pins.pin_param(s.selected_track_index, s.selected_track_device_index, idx, panel)
end

local function assign_selected(axis)
  local s = song()
  local dev = s.selected_track_device
  local index = vb.views.param_popup.value
  local parameter = dev and dev.parameters[index]
  if not parameter then return end
  local panel = destination()
  local source = pins.pin_param(s.selected_track_index, s.selected_track_device_index, index, panel)
  xy.assign(source, index, axis, parameter, true)
  pins.save()
  M.rebuild()
  status(parameter.name .. " assigned to " .. axis:upper())
end

local function attach_selection()
  if #sel_notifiers > 0 then return end
  local s = song()
  watch(sel_notifiers, s.selected_track_device_observable, refresh_selection)
  watch(sel_notifiers, s.selected_track_index_observable, refresh_selection)
end

local function build_root()
  vb = renoise.ViewBuilder()

  local panel = theme.panel(vb, {
    vb:text(theme.dim {text = "Select a track and a device in Renoise."}),
    vb:row {vb:text(theme.dim {text = "Track", width = 76}), vb:button {id = "track_name", width = 330, height = 22}},
    vb:row {vb:text(theme.dim {text = "Device", width = 76}), vb:button {id = "device_name", width = 330, height = 22}},
    vb:row {
      spacing = VB.DEFAULT_CONTROL_SPACING,
      vb:text(theme.dim {text = "Parameter", width = 76}),
      vb:popup {id = "param_popup", items = {"No parameters"}, width = 220},
      vb:button(theme.button {id = "assign_x", text = "Assign to X", notifier = function() assign_selected("x") end}),
      vb:button(theme.button {id = "assign_y", text = "Assign to Y", notifier = function() assign_selected("y") end}),
    },
    vb:row {
      spacing = VB.DEFAULT_CONTROL_SPACING,
      vb:button(theme.accent {
        id = "pin_device", text = "Pin device", width = 90,
        tooltip = "Pin the selected device with all its parameters",
        notifier = pin_selected_device,
      }),
      vb:button(theme.button {
        id = "pin_param", text = "Pin parameter", width = 100,
        tooltip = "Pin only the chosen parameter of the selected device",
        notifier = function() pin_selected_param() end,
      }),
      vb:button(theme.button {
        text = "Clear all", width = 90,
        tooltip = "Remove every pin and every XY for this project",
        notifier = function() pins.clear() end,
      }),
    },
  }, 520)
  pad_view = vb:column {spacing = VB.DEFAULT_CONTROL_SPACING}
  xy_view = vb:column {}
  cards_view = vb:row { id = "cards", spacing = VB.DEFAULT_DIALOG_SPACING }

  local folded = renoise.tool().preferences.folded.value
  header_view = vb:bitmap {bitmap = "images/dial-ranger.bmp", mode = "plain",
    tooltip = "Dial Ranger by nickcent", visible = not folded}
  controls_view = vb:column {spacing = VB.DEFAULT_DIALOG_SPACING, visible = not folded,
    panel, xy_view, cards_view}

  -- Controls and pinned parameters on the left, the XY pad on the right.
  return vb:column {
    spacing = VB.DEFAULT_DIALOG_SPACING,
    header_view,
    vb:row {spacing = VB.DEFAULT_DIALOG_SPACING, controls_view, pad_view},
  }
end

-- ---------------------------------------------------------------------------
-- Cards
-- ---------------------------------------------------------------------------

local function step_pair(p)
  if p.value_quantum > 0 then
    return { p.value_quantum, p.value_quantum * 10 }
  end
  local range = p.value_max - p.value_min
  return { range / 100, range / 10 }
end

local function clamp(value, low, high)
  return math.max(low, math.min(high, value))
end

-- Value boxes hold thousandths so the display has three exact decimals.
local function thousandths(value)
  return clamp(math.floor(value * 1000 + 0.5), 0, 1000)
end

local function format_thousandths(n)
  return ("%.3f"):format(n / 1000)
end

local function parse_thousandths(text)
  local n = tonumber(text)
  if n then return thousandths(n) end
end

local function build_param_row(cvb, pin, i, p)
  local syncing = false
  local slider = cvb:slider {
    min = p.value_min,
    max = p.value_max,
    value = p.value,
    default = p.value_default,
    polarity = (p.polarity == renoise.DeviceParameter.POLARITY_BIPOLAR)
      and "bipolar" or "unipolar",
    steps = step_pair(p),
    width = SLIDER_WIDTH,
    notifier = function(v)
      if not syncing then xy.write(p, v) end
    end,
  }
  local value_text
  value_text = cvb:textfield {
    value = p.value_string, width = VALUE_WIDTH, align = "right",
    tooltip = "Enter a value in the device's own units",
    notifier = function(text)
      if syncing or text == p.value_string then return end
      local previous = p.value
      local ok = pcall(function() p.value_string = text end)
      if ok and p.value ~= previous and p.is_automatable then p:record_value(p.value) end
      if not ok then status("invalid value for " .. p.name) end
      syncing = true
      value_text.value = p.value_string
      syncing = false
    end,
  }

  watch(card_notifiers, p.value_observable, function()
    syncing = true
    slider.value = p.value
    syncing = false
  end)
  watch(card_notifiers, p.value_string_observable, function()
    syncing = true
    value_text.value = p.value_string
    syncing = false
  end)

  local friction = renoise.Document.ObservableNumber(pin.friction[i] or 0)
  local arrows = 26
  local travel = SLIDER_WIDTH - arrows
  local anchor
  local track = cvb:canvas {
    origin = {arrows, 0}, width = travel, height = slider.height,
    mode = "transparent", render = function() end,
    mouse_events = {"down", "drag", "up"},
    mouse_handler = function(event)
      if event.type == "down" and event.button == "left" then
        anchor = {x = event.position.x, value = p.value,
          scale = (p.value_max - p.value_min) / travel * 1000 ^ (-friction.value / 1000)}
      elseif anchor and (event.type == "drag" or event.type == "up") then
        xy.write(p, anchor.value + (event.position.x - anchor.x) * anchor.scale)
        if event.type == "up" then anchor = nil end
      else
        return event
      end
    end,
  }
  local mini = cvb:minislider {
    min = 0, max = 1, width = 70, value = friction.value / 1000,
    notifier = function(v)
      local n = clamp(math.floor(v * 1000 + 0.5), 0, 1000)
      if friction.value ~= n then friction.value = n end
    end,
  }
  watch(card_notifiers, friction, function()
    pins.set_friction(pin, i, friction.value)
    local exact = friction.value / 1000
    if mini.value ~= exact then mini.value = exact end
  end)
  local box = cvb:valuebox {
    min = 0, max = 1000, width = 65, steps = {1, 10}, bind = friction,
    tostring = format_thousandths, tonumber = parse_thousandths,
    tooltip = "Mouse friction. 1.000 gives 1000 times finer drag control.",
  }
  local views = {
    cvb:text(theme.text { text = p.name, width = NAME_WIDTH, tooltip = p.name }),
    cvb:stack { slider, track }, value_text,
    cvb:text(theme.dim { text = "Friction" }), mini, box,
    cvb:button(theme.button {
      text = "×", width = 18, tooltip = "Unpin this parameter",
      notifier = function() pins.unpin_param(pin, i) end,
    }),
  }
  if not pin.panel then
    views[#views + 1] = cvb:button(theme.button {
      text = "+ XY", tooltip = "Copy this parameter to the XY on show",
      notifier = function()
        pins.pin_param(pin.track_index, pin.device_index, i, destination(), pin.friction[i])
      end,
    })
  end
  if not pin.panel then return cvb:row {spacing = VB.DEFAULT_CONTROL_SPACING, views = views} end

  local map = pin.maps and pin.maps[i]
  local axes = {[2] = "x", [3] = "y"}
  local axis_index = map and (map.axis == "x" and 2 or 3) or 1
  views[#views + 1] = cvb:popup {
    items = {"XY off", "Axis X", "Axis Y"}, value = axis_index, width = 78,
    tooltip = "Assign this parameter to one axis. Switching axes keeps its range.",
    notifier = function(n)
      xy.assign(pin, i, axes[n], p)
      pins.save()
      M.rebuild()
    end,
  }
  local row = cvb:row {spacing = VB.DEFAULT_CONTROL_SPACING, views = views}
  if not map then return row end
  local range = cvb:row {spacing = VB.DEFAULT_CONTROL_SPACING, cvb:space {width = NAME_WIDTH}}
  local function add_endpoint(key, caption)
    local label = cvb:text(theme.text {text = map[key .. "_text"], width = 100})
    range:add_view(cvb:button(theme.button {text = caption, tooltip = "Capture the current " .. p.name,
      notifier = function()
        xy.capture(map, key, p)
        label.text = map[key .. "_text"]
        pins.save()
      end}))
    range:add_view(label)
  end
  add_endpoint("low", "Set Min")
  add_endpoint("high", "Set Max")
  range:add_view(window_views.curve_editor(cvb, map, pins.save))
  return cvb:column {row, range}
end

local function param_indices(pin, device)
  local count = #device.parameters
  local out = {}
  if pin.mode == "device" then
    for i = 1, count do out[i] = i end
  else
    for _, i in ipairs(pin.params) do
      if i <= count then out[#out + 1] = i end -- UNTESTED (U5): plug-in param count may shrink
    end
  end
  return out
end

local function build_card(pin, track, device)
  local cvb = renoise.ViewBuilder()

  -- UNTESTED (U1): selected_track_index / selected_track_device_index writability
  local function jump()
    local ok = pcall(function()
      local s = song()
      s.selected_track_index = pin.track_index
      s.selected_track_device_index = pin.device_index
    end)
    if not ok then status("cannot select device from here") end
  end

  local header = cvb:button {
    text = track.name,
    color = track.color,
    width = "100%",
    tooltip = ("Track %d — click to show this device in the DSP chain"):format(pin.track_index),
    notifier = jump,
  }
  watch(card_notifiers, track.name_observable, function()
    header.text = track.name
  end)
  watch(card_notifiers, track.color_observable, function()
    header.color = track.color
  end)

  local active_box = cvb:checkbox {
    value = device.is_active,
    tooltip = "Active (bypass when off)",
    notifier = function(v) device.is_active = v end,
  }
  local title = cvb:text(theme.text { text = display_name(device), width = 190, font = "bold" })
  watch(card_notifiers, device.is_active_observable, function()
    active_box.value = device.is_active
  end)
  watch(card_notifiers, device.display_name_observable, function()
    title.text = display_name(device)
  end)

  local title_views = { active_box, title, cvb:space { width = 8 } }
  if device.external_editor_available then
    title_views[#title_views + 1] = cvb:button(theme.button {
      text = "Editor", tooltip = "Show/hide the plug-in's own editor window",
      notifier = function()
        device.external_editor_visible = not device.external_editor_visible
      end,
    })
  end
  title_views[#title_views + 1] = cvb:button(theme.button {
    text = "Unpin", tooltip = "Remove this card",
    notifier = function() pins.unpin(pin) end,
  })

  local card, body = theme.panel(cvb, {
    header,
    cvb:row { spacing = VB.DEFAULT_CONTROL_SPACING, views = title_views },
  }, CARD_WIDTH)
  for _, i in ipairs(param_indices(pin, device)) do
    body:add_view(build_param_row(cvb, pin, i, device.parameters[i]))
  end
  return card
end

-- The current XY: its parameters with their axes, ranges and curves.
local function build_xy(panel)
  local cvb = renoise.ViewBuilder()
  local number
  for i, candidate in ipairs(pins.panels()) do
    if candidate == panel then number = i end
  end
  local view, body = theme.panel(cvb, {
    cvb:row {spacing = VB.DEFAULT_CONTROL_SPACING,
      cvb:text(theme.text {text = "XY " .. number, font = "bold", width = 240}),
      cvb:button(theme.button {text = "Clear XY",
        tooltip = "Remove this XY: its parameters, slots and reset position. Recorded automation stays.",
        notifier = function() pins.remove_panel(panel) end}),
    },
  })
  local rows = cvb:column {spacing = VB.DEFAULT_CONTROL_SPACING}
  body:add_view(rows)
  for _, source in ipairs(pins.list()) do
    if source.panel == panel then
      local track, device = pins.resolve(source)
      local label = cvb:text(theme.text {font = "bold", width = 420})
      local function update_label()
        label.text = ("%02d %s  ·  %02d %s"):format(source.track_index, track.name,
          source.device_index, display_name(device))
      end
      update_label()
      watch(card_notifiers, track.name_observable, update_label)
      watch(card_notifiers, device.display_name_observable, update_label)
      rows:add_view(label)
      for _, i in ipairs(param_indices(source, device)) do
        rows:add_view(build_param_row(cvb, source, i, device.parameters[i]))
      end
    end
  end
  return view
end

local function clear_cards()
  unwatch_all(card_notifiers)
  if cards_view then
    for _, child in ipairs(card_children) do
      child.parent:remove_view(child.view)
    end
  end
  card_children = {}
end

local function add_card(parent, view)
  parent:add_view(view)
  card_children[#card_children + 1] = {parent = parent, view = view}
end

-- Stored pad positions. Renoise buttons report no right-click, so a
-- transparent canvas above them reads the mouse button.
local function build_slots(panel, editable, pad)
  local width, height = background.size / xy.slots, 22
  local cells = {}
  local row = vb:row {}
  local function paint(i)
    local look = panel.slots and panel.slots[i] and theme.accent({}) or theme.button({})
    cells[i].color, cells[i].secondary_color = look.color, look.secondary_color
  end
  for i = 1, xy.slots do
    cells[i] = vb:button {text = tostring(i), width = width, height = height, active = editable}
    paint(i)
    row:add_view(cells[i])
  end
  if not editable then return row end
  local overlay = vb:canvas {
    width = background.size, height = height, mode = "transparent", render = function() end,
    tooltip = "Left-click jumps to a stored position. Right-click stores the dot's position."
      .. " With Renoise's record mode on, the jump is written to automation.",
    mouse_events = {"down"},
    mouse_handler = function(event)
      local i = clamp(math.floor(event.position.x / width) + 1, 1, xy.slots)
      local slot = panel.slots and panel.slots[i]
      if event.button == "right" then
        panel.slots = panel.slots or {}
        panel.slots[i] = {x = panel.x or 0.5, y = panel.y or 0.5}
        paint(i)
      elseif event.button == "left" and slot then
        pad.jump(slot.x, slot.y, song().transport.edit_mode, true)
      else
        return event
      end
      pins.save()
    end,
  }
  return vb:stack {row, overlay}
end

-- The strip under the pad: the fold toggle and the pad's Auto Reset settings.
-- `editable` is false for the default pad, which has no panel to store them.
-- `rest()` sends the pad to its reset position while Auto Reset is on.
local function build_pad_controls(panel, editable, rest)
  local folded = renoise.tool().preferences.folded
  local fold
  fold = vb:button(theme.button {
    text = folded.value and "Unfold" or "Fold", width = 58,
    tooltip = "Show only the XY pad, or the whole window",
    notifier = function()
      folded.value = not folded.value
      fold.text = folded.value and "Unfold" or "Fold"
      header_view.visible = not folded.value
      controls_view.visible = not folded.value
      window_views.refit()
    end,
  })
  local boxes = {}
  local capturing = false -- the capture button fills both boxes before applying
  local function reset_box(axis)
    local key = "reset_" .. axis
    boxes[axis] = vb:valuebox {
      min = 0, max = 1000, width = 65, steps = {1, 10}, active = editable,
      value = thousandths(panel[key] or 0.5),
      tostring = format_thousandths, tonumber = parse_thousandths,
      tooltip = "Where Auto Reset puts the " .. axis:upper() .. " axis",
      notifier = function(n)
        panel[key] = n / 1000
        if capturing then return end
        rest(false)
        pins.save()
      end,
    }
    return boxes[axis]
  end
  return vb:row {spacing = VB.DEFAULT_CONTROL_SPACING,
    fold,
    vb:checkbox {
      value = panel.auto_reset == true, active = editable,
      tooltip = "Return the pad to the reset position when the mouse button is released",
      notifier = function(on)
        panel.auto_reset = on
        rest(false)
        pins.save()
      end,
    },
    vb:text(theme.text {text = "Auto Reset"}),
    vb:text(theme.dim {text = "X"}), reset_box("x"),
    vb:text(theme.dim {text = "Y"}), reset_box("y"),
    vb:button(theme.button {
      text = "Set", active = editable,
      tooltip = "Use the dot's current position as the reset position",
      notifier = function()
        capturing = true
        boxes.x.value = thousandths(panel.x or 0.5)
        boxes.y.value = thousandths(panel.y or 0.5)
        capturing = false
        rest(false)
        pins.save()
      end,
    }),
  }
end

-- One button per XY in that XY's skin colours, then "+" for the next free
-- skin. Showing another XY switches the window to its skin.
local function build_switcher()
  local row = vb:row {spacing = VB.DEFAULT_CONTROL_SPACING}
  for i, panel in ipairs(pins.panels()) do
    local look = theme.look(panel.skin)
    local shown = panel.skin == theme.current()
    row:add_view(vb:button {
      text = tostring(i), width = 28, height = 22,
      color = shown and look.accent or look.button,
      secondary_color = shown and look.accent_text or look.accent,
      tooltip = shown and "This XY" or "Show this XY",
      notifier = function() M.set_skin(panel.skin) end,
    })
  end
  local free
  for _, key in ipairs(theme.keys()) do
    if not pins.panel(key) then free = key; break end
  end
  row:add_view(vb:button(theme.button {
    text = "+", width = 28, height = 22, active = free ~= nil,
    tooltip = free and "Add an XY in the next free skin" or "Every skin already has an XY",
    notifier = function()
      pins.create_panel(free)
      M.set_skin(free)
    end,
  }))
  return row
end

-- With XYs in the project the window always shows one of them. Returns true
-- when that changed the skin.
local function settle_skin()
  local first = pins.panels()[1]
  if not first or pins.panel(theme.current()) then return false end
  theme.set(first.skin)
  return true
end

-- Views take their colours when built, so a new skin rebuilds the window's
-- content in place. The chosen parameter survives the swap.
local function restyle()
  local chosen = vb.views.param_popup.value
  M.detach_all()
  card_children = {} -- the new root owns fresh card containers
  window_views.replace(build_root())
  M.rebuild()
  vb.views.param_popup.value = math.min(chosen, #vb.views.param_popup.items)
end

function M.rebuild()
  if not vb then return end
  if settle_skin() then return restyle() end
  clear_cards()
  if pins.prune() then pins.save() end
  local current = pins.panel(theme.current())
  local active = current or {}
  local layer, pad = background.layer(vb, active, function(x, y, recording, step)
    xy.move(active, x, y, pins.list(), pins.resolve, recording, step)
  end, pins.save)
  add_card(pad_view, build_switcher())
  add_card(pad_view, layer)
  add_card(pad_view, build_slots(active, current ~= nil, pad))
  add_card(pad_view, build_pad_controls(active, current ~= nil, pad.rest))
  xy.follow(active, pins.list(), pins.resolve, function(observable, fn)
    watch(card_notifiers, observable, fn)
  end, pad.follow)
  if current then add_card(xy_view, build_xy(current)) end
  for _, pin in ipairs(pins.list()) do
    if not pin.panel then
      local track, device = pins.resolve(pin)
      add_card(cards_view, build_card(pin, track, device))
    end
  end
  attach_selection()
  refresh_selection()
  window_views.refit()
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function M.visible()
  return dlg ~= nil and dlg.visible
end

-- Drop every song notifier (cards + selection). Call before the song goes away.
function M.detach_all()
  unwatch_all(card_notifiers)
  unwatch_all(sel_notifiers)
end

function M.show()
  if M.visible() then
    dlg:show()
    return
  end
  M.detach_all()
  card_children = {} -- The new root owns a fresh cards_view.
  settle_skin()
  local content = build_root()
  local root = window_views.frame(vb, content)
  -- returning the key hands it back to Renoise's global shortcuts
  dlg = renoise.app():show_custom_dialog("Dial Ranger", root,
    function(_, key) return key end)
  M.rebuild()
end

function M.set_skin(key)
  if key == theme.current() then return end
  theme.set(key)
  if M.visible() then restyle() end
end

pins.on_change(function()
  if M.visible() then
    M.rebuild()
  else
    M.detach_all()
  end
end)

return M
