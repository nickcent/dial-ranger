-- Local bitmap looks and explicitly applied, application-wide Renoise themes.
local background = require("pad_background")
local M = {}

local looks = {
  {"CNT Night Circuit", "night-circuit"},
  {"CNT Circuit", "circuit"},
  {"CNT Microchip", "microchip"},
  {"CNT Terminal Grid", "terminal-grid"},
  {"CNT Sage Afterdark Brushed", "brushed-sage"},
  {"CNT Sage Logo Tiles", "logo-tiles"},
}

local function look_index()
  local name = renoise.tool().preferences.panel_look.value
  for i, look in ipairs(looks) do
    if look[1] == name then return i end
  end
  return 1
end

function M.bitmap()
  return "images/" .. looks[look_index()][2] .. ".bmp"
end

local function installed_themes()
  local names, files = {}, {}
  local bundle = renoise.tool().bundle_path:gsub("\\", "/")
  local profile = bundle:match("^(.*)/Scripts/Tools/[^/]+/?$")
  if profile then
    for _, group in ipairs({"Creator 5 CNT", "Creator 5"}) do
      local dir = profile .. "/Themes/" .. group .. "/"
      local ok, entries = pcall(os.filenames, dir, {"*.xrnc"})
      if ok then
        table.sort(entries)
        for _, file in ipairs(entries) do
          names[#names + 1] = file:gsub("%.[xX][rR][nN][cC]$", "")
          files[#files + 1] = dir .. file
        end
      end
    end
  end
  return names, files
end

function M.header(vb, rebuild)
  local names = {}
  for i, look in ipairs(looks) do names[i] = look[1] end
  local themes, files = installed_themes()
  local picker = vb:popup {width = 196, items = #themes > 0 and themes or {"Choose a theme file…"}}
  local strip = vb:bitmap {bitmap = M.bitmap(), mode = "plain"}
  local function apply()
    local path = files[picker.value]
    if not path then
      path = renoise.app():prompt_for_filename_to_read({"*.xrnc"}, "Apply Renoise theme")
    end
    if not path or path == "" then return end
    local ok, err = pcall(function() renoise.app():load_theme(path) end)
    if not ok then renoise.app():show_warning(tostring(err)) end
  end
  return vb:row {spacing = renoise.ViewBuilder.DEFAULT_DIALOG_SPACING,
    vb:bitmap {bitmap = "images/dial-ranger.bmp", mode = "plain", tooltip = "Dial Ranger by nickcent"},
    vb:column {spacing = renoise.ViewBuilder.DEFAULT_CONTROL_SPACING,
      vb:row {vb:text {text = "Panel look", width = 94},
        vb:popup {width = 196, items = names, value = look_index(), notifier = function(i)
          renoise.tool().preferences.panel_look.value = names[i]
          strip.bitmap = M.bitmap()
          rebuild()
        end}, strip},
      vb:row {vb:text {text = "Renoise theme", width = 94}, picker,
        vb:button {text = "Apply to Renoise", tooltip = "Change the colour theme of the entire application", notifier = apply}},
      background.settings(vb),
    },
  }
end

return M
