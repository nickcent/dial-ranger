-- Pinned Devices: keep chosen track/send DSP devices visible and editable in
-- one detached, non-modal window.

local pins = require("pins")
local dashboard = require("dashboard")

local tool = renoise.tool()

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

local function has_selected_device()
  local s = renoise.song()
  return s ~= nil and s.selected_track_device ~= nil
end

local function pin_selected_device()
  local s = renoise.song()
  if not s.selected_track_device then return end
  pins.pin_device(s.selected_track_index, s.selected_track_device_index)
  dashboard.show()
end

-- ---------------------------------------------------------------------------
-- Entry points
-- ---------------------------------------------------------------------------

tool:add_menu_entry {
  name = "Main Menu:Tools:Pinned Devices...",
  invoke = dashboard.show,
}

tool:add_menu_entry {
  name = "DSP Device:Pin Device to Pinned Devices",
  invoke = pin_selected_device,
  active = has_selected_device,
}

tool:add_menu_entry {
  name = "DSP Device Header:Pin Device to Pinned Devices",
  invoke = pin_selected_device,
  active = has_selected_device,
}

tool:add_keybinding {
  name = "Global:Tools:Show Pinned Devices",
  invoke = function(repeated)
    if not repeated then dashboard.show() end
  end,
}

-- ---------------------------------------------------------------------------
-- Document lifecycle
-- ---------------------------------------------------------------------------

local function on_release_document()
  pins.detach_song()
  dashboard.detach_all()
end

local function on_new_document()
  pins.reset()
  pins.restore(renoise.song().file_name)
  pins.attach_song()
  if dashboard.visible() then dashboard.rebuild() end
end

tool.app_release_document_observable:add_notifier(on_release_document)
tool.app_new_document_observable:add_notifier(on_new_document)
-- file_name changes on Save As; keep the stored pins under the new name
tool.app_saved_document_observable:add_notifier(pins.save)

-- "Reload All Tools" does not fire app_new_document (only the auto_reload
-- debugging path does); attach now when a song is already open.
do
  local ok, s = pcall(renoise.song)
  if ok and s then on_new_document() end
end
