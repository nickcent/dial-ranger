local M = {}

-- Integer positions retain the original five responses exactly.
M.names = {"Log fast", "Log slow", "Linear", "Exp slow", "Exp fast"}
M.linear = 3

function M.apply(index, t)
  local bend = (index or M.linear) - M.linear
  if bend == 0 then return t end
  local power = 2 ^ math.abs(bend)
  if bend > 0 then return t ^ power end
  return 1 - (1 - t) ^ power
end

-- Inverse of apply: the position that yields `value`.
function M.invert(index, value)
  local bend = (index or M.linear) - M.linear
  if bend == 0 then return value end
  local root = 1 / 2 ^ math.abs(bend)
  if bend > 0 then return value ^ root end
  return 1 - (1 - value) ^ root
end

-- Invert the same transfer function at x = 0.5. The handle tracks the
-- pointer vertically while the curve remains monotonic with fixed endpoints.
function M.from_midpoint(y)
  local tail = math.max(1/256, math.min(y, 1 - y))
  local bend = math.log(-math.log(tail) / math.log(2)) / math.log(2)
  return M.linear + (y < 0.5 and bend or -bend)
end

return M
