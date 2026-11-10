-- Dashboard: one non-modal dialog with a pin panel (follows the DSP chain
-- selection) and one card per pin, side by side. Cards are rebuilt from
-- indices on every structural change; live values flow through notifiers.

local pins = require("pins")

local M = {}

local VB = renoise.ViewBuilder
local CARD_WIDTH = 330
local NAME_WIDTH = 110
local SLIDER_WIDTH = 130
local VALUE_WIDTH = 70

local dlg = nil
local vb = nil               -- root ViewBuilder
local cards_view = nil       -- row holding the cards
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
  renoise.app():show_status("Pinned Devices: " .. msg)
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
  local label = "Select a device in the DSP chain"
  local items = { "—" }
  if dev then
    label = ("Selected: %s · %s"):format(s.selected_track.name, display_name(dev))
    items = {}
    for i, p in ipairs(dev.parameters) do items[i] = p.name end
    if #items == 0 then items = { "—" } end
  end
  vb.views.sel_label.text = label
  vb.views.param_popup.items = items
  vb.views.param_popup.value = 1
  vb.views.pin_device.active = dev ~= nil
  vb.views.pin_param.active = dev ~= nil and #dev.parameters > 0
end

local function pin_selected_device()
  local s = song()
  if not s.selected_track_device then return end
  pins.pin_device(s.selected_track_index, s.selected_track_device_index)
end

local function pin_selected_param()
  local s = song()
  local dev = s.selected_track_device
  if not dev or #dev.parameters == 0 then return end
  local idx = vb.views.param_popup.value
  if idx < 1 or idx > #dev.parameters then return end
  pins.pin_param(s.selected_track_index, s.selected_track_device_index, idx)
end

local function attach_selection()
  if #sel_notifiers > 0 then return end
  local s = song()
  watch(sel_notifiers, s.selected_track_device_observable, refresh_selection)
  watch(sel_notifiers, s.selected_track_index_observable, refresh_selection)
end

local function build_root()
  vb = renoise.ViewBuilder()

  local panel = vb:column {
    background = "group",
    margin = VB.DEFAULT_CONTROL_MARGIN,
    spacing = VB.DEFAULT_CONTROL_SPACING,
    vb:text { id = "sel_label", text = "", font = "bold" },
    vb:row {
      spacing = VB.DEFAULT_CONTROL_SPACING,
      vb:button {
        id = "pin_device", text = "Pin device", width = 90,
        tooltip = "Pin the selected device with all its parameters",
        notifier = pin_selected_device,
      },
      vb:popup { id = "param_popup", items = { "—" }, width = 180 },
      vb:button {
        id = "pin_param", text = "Pin parameter", width = 100,
        tooltip = "Pin only the chosen parameter of the selected device",
        notifier = pin_selected_param,
      },
    },
    vb:row {
      vb:button {
        text = "Clear all", width = 90,
        tooltip = "Remove every pin for this project",
        notifier = function() pins.clear() end,
      },
    },
  }

  cards_view = vb:row { id = "cards", spacing = VB.DEFAULT_DIALOG_SPACING }

  return vb:column {
    margin = VB.DEFAULT_DIALOG_MARGIN,
    spacing = VB.DEFAULT_DIALOG_SPACING,
    panel,
    cards_view,
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
      if not syncing then p.value = v end
    end,
  }
  local value_text = cvb:text {
    text = p.value_string, width = VALUE_WIDTH, align = "right",
  }

  watch(card_notifiers, p.value_observable, function()
    syncing = true
    slider.value = p.value
    syncing = false
  end)
  watch(card_notifiers, p.value_string_observable, function()
    value_text.text = p.value_string
  end)

  local views = {
    cvb:text { text = p.name, width = NAME_WIDTH, tooltip = p.name },
    slider,
    value_text,
  }
  if pin.mode == "params" then
    views[#views + 1] = cvb:button {
      text = "×", width = 18, tooltip = "Unpin this parameter",
      notifier = function() pins.unpin_param(pin, i) end,
    }
  end
  return cvb:row { spacing = VB.DEFAULT_CONTROL_SPACING, views = views }
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
  local title = cvb:text { text = display_name(device), font = "bold" }
  watch(card_notifiers, device.is_active_observable, function()
    active_box.value = device.is_active
  end)
  watch(card_notifiers, device.display_name_observable, function()
    title.text = display_name(device)
  end)

  local title_views = { active_box, title, cvb:space { width = 8 } }
  if device.external_editor_available then
    title_views[#title_views + 1] = cvb:button {
      text = "Editor", tooltip = "Show/hide the plug-in's own editor window",
      notifier = function()
        device.external_editor_visible = not device.external_editor_visible
      end,
    }
  end
  title_views[#title_views + 1] = cvb:button {
    text = "Unpin", tooltip = "Remove this card",
    notifier = function() pins.unpin(pin) end,
  }

  local card = cvb:column {
    background = "group",
    margin = VB.DEFAULT_CONTROL_MARGIN,
    spacing = VB.DEFAULT_CONTROL_SPACING,
    width = CARD_WIDTH,
    header,
    cvb:row { spacing = VB.DEFAULT_CONTROL_SPACING, views = title_views },
  }
  for _, i in ipairs(param_indices(pin, device)) do
    card:add_view(build_param_row(cvb, pin, i, device.parameters[i]))
  end
  return card
end

local function clear_cards()
  unwatch_all(card_notifiers)
  if cards_view then
    for _, child in ipairs(card_children) do
      cards_view:remove_view(child)
    end
  end
  card_children = {}
end

local function add_card(view)
  cards_view:add_view(view)
  card_children[#card_children + 1] = view
end

function M.rebuild()
  if not vb then return end
  clear_cards()
  if pins.prune() then pins.save() end
  for _, pin in ipairs(pins.list()) do
    local track, device = pins.resolve(pin)
    add_card(build_card(pin, track, device))
  end
  if #card_children == 0 then
    add_card(vb:text {
      text = "No pinned devices. Select a device in the DSP chain and press Pin.",
      style = "disabled",
    })
  end
  attach_selection()
  refresh_selection()
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
  local root = build_root()
  -- returning the key hands it back to Renoise's global shortcuts
  dlg = renoise.app():show_custom_dialog("Pinned Devices", root,
    function(_, key) return key end)
  M.rebuild()
end

pins.on_change(function()
  if M.visible() then
    M.rebuild()
  else
    M.detach_all()
  end
end)

return M
