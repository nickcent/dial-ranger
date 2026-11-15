local background = require("pad_background")
local M = {}

function M.header(vb)
  return vb:row {spacing = renoise.ViewBuilder.DEFAULT_DIALOG_SPACING,
    vb:bitmap {bitmap = "images/dial-ranger.bmp", mode = "plain", tooltip = "Dial Ranger by nickcent"},
    background.settings(vb),
  }
end

return M
