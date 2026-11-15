local background = require("pad_background")
local theme = require("theme")
local M = {}

-- `on_skin(key)` runs when the user picks another skin.
function M.header(vb, on_skin)
  local items, current = {}, 1
  for i, skin in ipairs(theme.skins) do
    items[i] = skin.label
    if skin.key == theme.current() then current = i end
  end
  return vb:row {spacing = renoise.ViewBuilder.DEFAULT_DIALOG_SPACING,
    vb:bitmap {bitmap = "images/dial-ranger.bmp", mode = "plain", tooltip = "Dial Ranger by nickcent"},
    vb:column {spacing = renoise.ViewBuilder.DEFAULT_CONTROL_SPACING,
      background.settings(vb),
      vb:row {spacing = renoise.ViewBuilder.DEFAULT_CONTROL_SPACING,
        vb:text(theme.text {text = "Skin", width = 94}),
        vb:popup {items = items, value = current, width = 172, tooltip = "Dial Ranger colour skin",
          notifier = function(index) on_skin(theme.skins[index].key) end},
      },
    },
  }
end

return M
