-- Run from the repository root with luajit tests/xy.lua.
package.path = "com.cent.PinnedDevices.xrnx/?.lua;" .. package.path
local function param(value, quantum)
  return {value = value, value_min = -2, value_max = 2, value_quantum = quantum or 0,
    value_string = "original\t100%", is_automatable = true, value_observable = {},
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
    return {pins = {value = "xy.xrns\t1\t1\tFilter\tdevice\t"}, skin = {value = "terminal"}}
  end end}}
local pins, xy = require("pins"), require("xy")
local skins = {"terminal", "renoise", "hardware", "virus"}
pins.restore(song.file_name, skins)
assert(#pins.list() == 1 and pins.list()[1].mode == "device")
local panel = pins.create_panel("terminal")
local first = pins.pin_param(1, 1, 1, panel)
pins.pin_param(1, 1, 2, panel)
local second = pins.pin_param(2, 1, 1, panel)
pins.pin_param(2, 1, 2, panel)
local direct = {}
xy.assign(direct, 1, "x", a, true)
assert(direct.maps[1].low == -2 and direct.maps[1].high == 2 and a.value == 0)
direct.maps[1].low = -1
xy.assign(direct, 1, "y", a, true)
assert(direct.maps[1].axis == "y" and direct.maps[1].low == -1)
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
    envelopes[p] = {add_point_at = function(self, line, value) self[line] = value end,
      has_point_at = function(self, line) return self[line] ~= nil end}
    return envelopes[p]
  end,
}
song.patterns = {{tracks = {lane, lane}}}
song.sequencer = {pattern_sequence = {1}}
song.transport = {playing = false, edit_pos = {sequence = 1, line = 2},
  playback_pos = {sequence = 1, line = 5}}
local handler
local vb = {stack = function(_, views) return views end,
  canvas = function(_, view) handler = view.mouse_handler; return {update = function() end} end}
local function event(kind, button, x, y)
  handler {type = kind, button = button, position = {x = x, y = y}}
end
local _, pad = require("pad_background").layer(vb, panel, {}, function(x, y, recording, step)
  xy.move(panel, x, y, pins.list(), pins.resolve, recording, step)
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
-- Auto Reset: releasing a recording gesture returns the pad and records it.
panel.auto_reset, panel.reset_x, panel.reset_y = true, 0.75, 0.5
event("down", "right", 0, 399)
event("up", "right", 0, 399)
assert(panel.x == 0.75 and panel.y == 0.5 and a.value == 1 and b.value == 0)
assert(envelopes[a][6] == 0.75 and envelopes[b][6] == 0.5)
-- A changed reset position moves the resting pad without recording.
song.transport.playback_pos.line = 7
panel.reset_x = 0.25
pad.rest(false)
assert(panel.x == 0.25 and a.value == -1 and not envelopes[a][7])
-- A recorded jump holds the old value until just before its line, and a
-- second jump on that line keeps the hold.
song.transport.playback_pos.line = 8
local hold = 8 - 1 / 256
pad.jump(1, 0.5, true, true)
assert(envelopes[a][hold] == 0.25 and envelopes[a][8] == 1)
assert(envelopes[b][hold] == nil and envelopes[b][8] == 0.5)
pad.jump(0, 0.5, true, true)
assert(envelopes[a][hold] == 0.25 and envelopes[a][8] == 0 and a.value == -2)
-- Outside changes, as from automation playback, move the dot. The first
-- mapping with a range leads its axis and its curve is inverted.
local watchers = {}
xy.follow(panel, pins.list(), pins.resolve,
  function(observable, fn) watchers[observable] = fn end, pad.follow)
a.value = 1
watchers[a.value_observable]()
assert(panel.x == 0.75)
b.value, d.value = 1, 0.3
watchers[d.value_observable]()
assert(panel.y == 0.75)
first.maps[1].scaling = 5
a.value = -1.75
watchers[a.value_observable]()
assert(math.abs(panel.x - 0.5) < 1e-12)
first.maps[1].scaling = 3
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
panel.slots = {[3] = {x = 0.125, y = 1}}
pins.save()
assert(a.value == before)
-- Simulate one legacy range at the same time as curved peers, and a panel
-- saved with a colour and a name before skins chose the XY.
local legacy, replaced = tool.preferences.pins.value:gsub(
  "([^\n]*\txy%-range\t1\t2\t1\t1\t[^\n]*)\t3", "%1", 1)
assert(replaced == 1)
legacy, replaced = legacy:gsub("\tpanel\t1\tterminal", "\tpanel\t1\t557647\tPanel 1", 1)
assert(replaced == 1)
tool.preferences.pins.value = legacy
pins.reset()
a.value, b.value, c.value, d.value = 0.1, 0, 0.4, 0.5
pins.restore(song.file_name, {"hardware", "terminal", "renoise", "virus"})
panel, first, second = pins.panel("hardware"), pins.list()[2], pins.list()[3]
assert(panel and not pins.panel("terminal"))
assert(panel.auto_reset and panel.reset_x == 0.25 and panel.reset_y == 0.5)
assert(panel.slots[3].x == 0.125 and panel.slots[3].y == 1 and not panel.slots[1])
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
-- A saved skin sticks, whichever skin is current at the next load.
pins.save()
pins.reset()
pins.restore(song.file_name, skins)
assert(pins.panel("hardware") and not pins.panel("terminal"))
print("XY mapping, capture, per-axis writes, quantum, reversed/equal ranges, auto reset, jumps, "
  .. "follow, restore, skins and source cleanup passed")
