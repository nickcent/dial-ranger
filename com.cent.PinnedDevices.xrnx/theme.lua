-- Skins. The window paints its own background and panels so it stands out
-- from the host Renoise theme; sliders, popups and value boxes are drawn by
-- Renoise and keep the host theme.
local M = {}

local looks = {
  renoise = {
    background = {30, 30, 30}, panel = {42, 42, 42}, border = {62, 62, 62},
    text = {205, 205, 205}, dim = {128, 128, 128},
    button = {56, 56, 56}, button_text = {220, 220, 220},
    accent = {232, 160, 42}, accent_text = {24, 24, 24},
    pad = {22, 22, 22}, grid = {255, 255, 255, 22}, ring = {232, 160, 42, 120},
    cross = {232, 160, 42, 200}, corner = {232, 160, 42}, cursor = {245, 245, 245},
  },
  terminal = {
    background = {4, 6, 5}, panel = {9, 13, 11}, border = {34, 78, 48},
    text = {150, 232, 162}, dim = {68, 128, 84},
    button = {12, 30, 19}, button_text = {150, 232, 162},
    accent = {118, 255, 140}, accent_text = {4, 6, 5},
    pad = {6, 10, 8}, grid = {118, 255, 140, 30}, ring = {118, 255, 140, 110},
    cross = {118, 255, 140, 200}, corner = {118, 255, 140}, cursor = {230, 255, 235},
  },
  hardware = {
    background = {44, 46, 48}, panel = {56, 59, 62}, border = {86, 90, 94},
    text = {228, 228, 222}, dim = {150, 152, 150},
    button = {28, 29, 31}, button_text = {228, 228, 222},
    accent = {255, 168, 48}, accent_text = {28, 29, 31},
    pad = {24, 25, 27}, grid = {255, 255, 255, 18}, ring = {255, 255, 255, 60},
    cross = {255, 168, 48, 190}, corner = {228, 228, 222}, cursor = {255, 168, 48},
  },
  virus = {
    background = {16, 9, 9}, panel = {34, 13, 13}, border = {112, 22, 24},
    text = {238, 228, 228}, dim = {168, 118, 118},
    button = {66, 16, 18}, button_text = {238, 228, 228},
    accent = {226, 30, 36}, accent_text = {255, 255, 255},
    pad = {10, 6, 6}, grid = {226, 30, 36, 34}, ring = {226, 30, 36, 120},
    cross = {226, 30, 36, 210}, corner = {238, 228, 228}, cursor = {255, 255, 255},
  },
}

-- Popup order and labels; keys match the `skin` preference.
M.skins = {
  {key = "terminal", label = "Terminal"},
  {key = "renoise", label = "Renoise"},
  {key = "hardware", label = "Hardware"},
  {key = "virus", label = "Virus"},
}

local palette

-- Selects the skin stored in the preferences; unknown keys fall back to the first skin.
function M.load()
  local pref = renoise.tool().preferences.skin
  if not looks[pref.value] then pref.value = M.skins[1].key end
  palette = looks[pref.value]
  M.palette = palette
end

function M.set(key)
  renoise.tool().preferences.skin.value = key
  M.load()
end

function M.current()
  return renoise.tool().preferences.skin.value
end

-- The palette of any skin, for views that show a skin other than the current.
function M.look(key)
  return looks[key]
end

-- Every skin key, the current skin first.
function M.keys()
  local keys = {M.current()}
  for _, skin in ipairs(M.skins) do
    if skin.key ~= keys[1] then keys[#keys + 1] = skin.key end
  end
  return keys
end

M.load()

-- Property helpers: fill in themed colours unless the caller set them.
function M.text(props)
  props.style, props.color = "custom", props.color or palette.text
  return props
end

function M.dim(props)
  props.style, props.color = "custom", props.color or palette.dim
  return props
end

function M.button(props)
  props.color = props.color or palette.button
  props.secondary_color = props.secondary_color or palette.button_text
  return props
end

function M.accent(props)
  props.color, props.secondary_color = palette.accent, palette.accent_text
  return props
end

-- A panel with a themed fill and a one-pixel border behind `views`. Returns
-- the panel and its inner column, which takes further add_view calls.
function M.panel(vb, views, width)
  local body = vb:column {margin = renoise.ViewBuilder.DEFAULT_CONTROL_MARGIN + 2,
    spacing = renoise.ViewBuilder.DEFAULT_CONTROL_SPACING, width = width, views = views}
  return vb:stack {
    vb:canvas {width = "100%", height = "100%", mode = "plain", render = function(ctx)
      local w, h = ctx.size.width, ctx.size.height
      ctx.fill_color = palette.panel
      ctx:fill_rect(0, 0, w, h)
      ctx.stroke_color, ctx.line_width = palette.border, 1
      ctx:stroke_rect(0.5, 0.5, w - 1, h - 1)
    end},
    body,
  }, body
end

return M
