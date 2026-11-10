local M = {}

-- Renoise exposes this order on InstrumentMacroMapping, but has no public
-- transfer function for arbitrary track DSPs. These five laws are normalized.
M.names = {"Log fast", "Log slow", "Linear", "Exp slow", "Exp fast"}
M.linear = 3

function M.apply(index, t)
  if index == 1 then return 1 - (1 - t)^4 end
  if index == 2 then return 1 - (1 - t)^2 end
  if index == 4 then return t^2 end
  if index == 5 then return t^4 end
  return t
end

return M
