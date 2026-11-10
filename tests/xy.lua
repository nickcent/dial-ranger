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
local function move(x, y) xy.move(panel, x, y, pins.list(), pins.resolve) end
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
pins.save()
pins.reset()
a.value, b.value, c.value, d.value = 0.1, 0, 0.4, 0.5
pins.restore(song.file_name)
panel, first, second = pins.panels()[1], pins.list()[2], pins.list()[3]
assert(panel.x == 1 and panel.y == 0 and first.maps[1].axis == "y")
assert(second.maps[1].low == 2 and second.maps[1].high == -2)
assert(first.maps[1].low_text == "original\t100%" and a.value == 0.1 and d.value == 0.5)
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
