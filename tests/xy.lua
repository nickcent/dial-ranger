-- Run from the repository root with luajit tests/xy.lua.
package.path = "com.cent.PinnedDevices.xrnx/?.lua;" .. package.path
local function param(value, quantum)
  return {value = value, value_min = -2, value_max = 2, value_quantum = quantum or 0,
    value_string = "original\t100%", is_automatable = true,
    record_value = function(self, n) self.value = n end}
end
local a, b, c, d = param(0), param(0, 1), param(0), param(0)
local song = {file_name = "xy.xrns", tracks = {
  {devices = {{name = "Filter", parameters = {a, b}}}},
  {devices = {{name = "Space", parameters = {c, d}}}},
}}
local tool = {}
renoise = {song = function() return song end, tool = function() return tool end,
  app = function() return {show_status = function() end} end,
  Document = {create = function() return function()
    return {pins = {value = "xy.xrns\t1\t1\tFilter\tdevice\t"}}
  end end}}
local pins, xy = require("pins"), require("xy")
pins.restore(song.file_name)
assert(#pins.list() == 1 and pins.list()[1].mode == "device")
local panel = pins.create_panel()
local first = pins.pin_param(1, 1, 1, panel)
pins.pin_param(1, 1, 2, panel)
local second = pins.pin_param(2, 1, 1, panel)
pins.pin_param(2, 1, 2, panel)
local function setup(source, index, axis, p, low, high)
  xy.assign(source, index, axis, p)
  local map = source.maps[index]
  assert(p.value == 0 and map.low == 0 and map.high == 0)
  p.value = low
  xy.capture(map, "low", p)
  p.value = high
  xy.capture(map, "high", p)
  assert(map.low == low and map.high == high and p.value == high)
end
setup(first, 1, "x", a, -2, 2)
setup(first, 2, "y", b, -2, 2)
setup(second, 1, "x", c, 2, -2)
setup(second, 2, "y", d, 1, 1)
-- Exercise the installed pad's event handler with two real mapping axes.
local envelopes = {}
local lane = {
  find_automation = function(_, p) return envelopes[p] end,
  create_automation = function(_, p)
    envelopes[p] = {add_point_at = function(self, line, value) self[line] = value end}
    return envelopes[p]
  end,
}
song.patterns = {{tracks = {lane, lane}}}
song.sequencer = {pattern_sequence = {1}}
song.transport = {playing = false, edit_pos = {sequence = 1, line = 2},
  playback_pos = {sequence = 1, line = 5}}
local handler
local vb = {bitmap = function() return {} end, stack = function(_, views) return views end,
  canvas = function(_, view) handler = view.mouse_handler; return {update = function() end} end}
local function event(kind, button, x, y)
  handler {type = kind, button = button, position = {x = x, y = y}}
end
require("pad_background").layer(vb, panel, function(x, y, recording)
  xy.move(panel, x, y, pins.list(), pins.resolve, recording)
end, function() end)
event("down", "left", 0, 0)
event("drag", "left", 399, 399)
event("up", "left", 399, 399)
assert(a.value == 2 and b.value == -2 and not next(envelopes))
event("down", "right", 399, 399)
assert(envelopes[a][2] == 1 and envelopes[b][2] == 0)
song.transport.playing = true
event("drag", "right", 0, 399)
assert(envelopes[a][5] == 0 and envelopes[b][5] == 0)
event("up", "right", 0, 399)
song.transport.playback_pos.line = 6
event("drag", "right", 399, 0)
assert(not envelopes[a][6] and not envelopes[b][6] and a.value == -2)
-- Restore the captured endpoint values for the original per-axis tests.
a.value, b.value, c.value, d.value = 2, 2, -2, 1
local function move(x, y) xy.move(panel, x, y, pins.list(), pins.resolve) end
-- Two parameters share X with opposing endpoint directions. A picker edit
-- changes only the transfer function used by the next X movement.
local midpoint = {0.9375, 0.75, 0.5, 0.25, 0.0625}
local scaling = require("scaling")
for _, y in ipairs({-1, 0, 0.02, 0.147, 0.5, 0.846, 0.98, 1, 2}) do
  local bend = scaling.from_midpoint(y)
  local expected = math.max(1/256, math.min(255/256, y))
  assert(math.abs(scaling.apply(bend, 0.5) - expected) < 1e-12)
  assert(scaling.apply(bend, 0) == 0 and scaling.apply(bend, 1) == 1)
end
for i, expected in ipairs(midpoint) do
  assert(scaling.apply(i, 0) == 0 and scaling.apply(i, 1) == 1)
  assert(scaling.apply(i, 0.5) == expected)
  first.maps[1].scaling = i
  move(0.5, nil)
  assert(a.value == -2 + 4 * expected and c.value == 0)
end
first.maps[1].scaling = 3
move(0.25, nil)
assert(a.value == -1 and c.value == 1 and b.value == 2 and d.value == 1)
d.value = 0 -- an external change must survive X-only movement
move(0.5, nil)
assert(a.value == 0 and c.value == 0 and d.value == 0)
move(nil, 0.7)
assert(b.value == 1 and d.value == 1 and a.value == 0 and c.value == 0)
move(0, 1)
assert(a.value == -2 and b.value == 2 and c.value == 2)
move(1, 0)
assert(a.value == 2 and b.value == -2 and c.value == -2)
xy.assign(first, 1, "y", a)
assert(first.maps[1].low == -2 and first.maps[1].high == 2 and a.value == 2)
local custom = scaling.from_midpoint(0.846)
first.maps[1].scaling = custom
first.maps[2].scaling = 5
local before = a.value
pins.save()
assert(a.value == before)
-- Simulate one legacy range at the same time as curved peers.
local legacy, replaced = tool.preferences.pins.value:gsub(
  "([^\n]*\txy%-range\t1\t2\t1\t1\t[^\n]*)\t3", "%1", 1)
assert(replaced == 1)
tool.preferences.pins.value = legacy
pins.reset()
a.value, b.value, c.value, d.value = 0.1, 0, 0.4, 0.5
pins.restore(song.file_name)
panel, first, second = pins.panels()[1], pins.list()[2], pins.list()[3]
assert(panel.x == 1 and panel.y == 0 and first.maps[1].axis == "y")
assert(second.maps[1].low == 2 and second.maps[1].high == -2)
assert(first.maps[1].scaling == custom and first.maps[2].scaling == 5 and second.maps[1].scaling == 3)
assert(first.maps[1].low_text == "original\t100%" and a.value == 0.1 and d.value == 0.5)
move(nil, 0.5)
assert(b.value == -2 and d.value == 1) -- curved interpolation then quantum; equal endpoints
a.value = 0.1
d.value = 0.5
xy.assign(first, 1, nil, a)
assert(not first.maps[1] and a.value == 0.1)
pins.unpin_param(second, 2)
assert(second.maps[2] == nil and d.value == 0.5)
table.remove(song.tracks[1].devices[1].parameters, 2)
assert(pins.prune() and first.maps[2] == nil)
song.tracks[2].devices = {}
move(0.5, 0.5)
assert(pins.prune() and #pins.list() == 2 and c.value == 0.4)
print("XY mapping, capture, per-axis writes, quantum, reversed/equal ranges, restore and source cleanup passed")
