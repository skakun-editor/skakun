-- Skakun - A robust and hackable hex and text editor
-- Copyright (C) 2024-2025 Karol "digitcrusher" Łacina
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.

local utils = {
  timer = require('core.utils.timer'),
}

function utils.lock_globals()
  setmetatable(_G, {
    __newindex = function(table, key, value)
      error('will not create new global variable: ' .. key, 2)
    end,
  })
end

function utils.unlock_globals()
  setmetatable(_G, nil)
end

function utils.hex_encode(string)
  local hex = ''
  for i = 1, #string do
    hex = hex .. ('%02x'):format(string:byte(i, i))
  end
  return hex
end

function utils.hex_decode(hex)
  local string = ''
  for i = 1, #hex, 2 do
    string = string .. string.char(tonumber(hex:sub(i, i + 1), 16))
  end
  return string
end

local alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local encode_map, decode_map = {}, {}
for i = 1, #alphabet do
  encode_map[i - 1] = alphabet:sub(i, i)
  decode_map[alphabet:byte(i, i)] = i - 1
end

function utils.base64_encode(string)
  local base64 = ''

  local i = 1
  while i + 2 <= #string do
    local a, b, c = string:byte(i, i + 2)
    base64 = base64 .. encode_map[a >> 2] .. encode_map[(a & 0x3) << 4 | b >> 4] .. encode_map[(b & 0xf) << 2 | c >> 6] .. encode_map[c & 0x3f]
    i = i + 3
  end

  local a, b = string:byte(i, i + 1)
  if b then
    base64 = base64 .. encode_map[a >> 2] .. encode_map[(a & 0x3) << 4 | b >> 4] .. encode_map[(b & 0xf) << 2] .. '='
  elseif a then
    base64 = base64 .. encode_map[a >> 2] .. encode_map[(a & 0x3) << 4] .. '=='
  end

  return base64
end

function utils.base64_decode(base64)
  local string = ''

  local len
  if base64:sub(-2, -2) == '=' then
    len = #base64 - 2
  elseif base64:sub(-1, -1) == '=' then
    len = #base64 - 1
  else
    len = #base64
  end

  local i = 1
  while i + 3 <= len do
    local a, b, c, d = base64:byte(i, i + 3)
    a, b, c, d = decode_map[a], decode_map[b], decode_map[c], decode_map[d]
    string = string .. string.char(a << 2 | b >> 4) .. string.char((b & 0xf) << 4 | c >> 2) .. string.char((c & 0x3) << 6 | d)
    i = i + 4
  end

  local a, b, c = base64:byte(i, i + 2)
  a, b, c = decode_map[a], decode_map[b], decode_map[c]
  if c then
    string = string .. string.char(a << 2 | b >> 4) .. string.char((b & 0xf) << 4 | c >> 2)
  elseif b then
    string = string .. string.char(a << 2 | b >> 4)
  end

  return string
end

function utils.tostring(value, visited)
  if type(value) == 'table' then
    visited = visited or {}
    if visited[value] then
      return tostring(value)
    end
    visited[value] = true

    local keys = {}
    for k in pairs(value) do
      table.insert(keys, k)
    end
    table.sort(keys)

    local result = '{\n'
    for _, k in ipairs(keys) do
      local v = utils.tostring(value[k], visited)
      if type(k) ~= 'string' or not k:match('^[%a_][%w_]*$') then
        k = '[' .. utils.tostring(k, visited) .. ']'
      end
      result = result .. '  ' .. k:gsub('\n', '\n  ') .. ' = ' .. v:gsub('\n', '\n  ') .. ',\n'
    end
    return result .. '}'

  elseif type(value) == 'string' then
    return ('%q'):format(value)
  else
    return tostring(value)
  end
end

function utils.copy(table)
  local result = {}
  for k, v in pairs(table) do
    result[k] = v
  end
  return result
end

function utils.split(string, sep)
  local i = 1
  return function()
    if i > #string then return end
    local j = string:find(sep, i) or #string + 1
    local result = string:sub(i, j - 1)
    i = j + 1
    return result
  end
end

function utils.slugify(string)
  return string:gsub('[^%w.-]', '_')
end

function utils.once(func, ...)
  local args = table.pack(...)
  local lock = thread.newlock()
  local results = nil
  return function()
    -- Depends heavily on the inner workings of the interpreter's
    -- multithreading and will most likely break, if they change.
    if not results then
      lock:acquire()
      if not results then
        results = table.pack(xpcall(func, debug.traceback, table.unpack(args, 1, args.n)))
      end
      lock:release()
    end
    if results[1] then
      return table.unpack(results, 2, results.n)
    else
      error(results[2], 0)
    end
  end
end

function utils.binary_search_first(table, is_far_enough)
  local left, right = 1, #table
  while left <= right do
    local mid = left + (right - left) // 2
    if is_far_enough(table[mid]) then
      right = mid
      if left == right then
        return table[left], left
      end
    else
      left = mid + 1
    end
  end
end

function utils.binary_search_last(table, is_near_enough)
  local left, right = 1, #table
  while left <= right do
    local mid = left + (right - left + 1) // 2
    if is_near_enough(table[mid]) then
      left = mid
      if left == right then
        return table[left], left
      end
    else
      right = mid - 1
    end
  end
end

function utils.is_point_in_rect(x, y, left, top, right, bottom)
  return left <= x and x <= right and top <= y and y <= bottom
end

utils.Themer = {}
utils.Themer.__index = utils.Themer

function utils.Themer.new()
  return setmetatable({
    saved = nil,
  }, utils.Themer)
end

function utils.Themer:apply(...)
  local count = select('#', ...)
  assert(count % 3 == 0)
  if self.saved then
    error('theme already applied')
  end
  self.saved = {}
  for i = 1, count, 3 do
    local object, key, value = select(i, ...), select(i + 1, ...), select(i + 2, ...)
    local old_value = object[key]
    object[key] = value
    table.insert(self.saved, object)
    table.insert(self.saved, key)
    table.insert(self.saved, old_value)
  end
end

function utils.Themer:unapply(...)
  if not self.saved then
    error('theme not applied')
  end
  for i = 1, #self.saved, 3 do
    local object, key, old_value = self.saved[i], self.saved[i + 1], self.saved[i + 2]
    object[key] = old_value
  end
  self.saved = nil
end

-- Reference: Hirai, Y. & Yamamoto, K. (2011) "Balancing weight-balanced trees", Journal of Functional Programming

utils.Set = {}
utils.Set.__index = utils.Set

function utils.Set.new(cmp)
  return setmetatable({
    cmp = cmp or function(a, b) return a < b end,
    root = nil,
  }, utils.Set)
end

function utils.Set:insert(value)
  local node = {
    value = value,
    parent = nil,
    left = nil,
    right = nil,
    size = 1,
  }
  if not self.root then
    self.root = node
    return node
  end

  local parent = self.root
  while parent do
    node.parent = parent
    if self.cmp(value, parent.value) then
      parent = parent.left
    elseif self.cmp(parent.value, value) then
      parent = parent.right
    else
      return nil
    end
  end

  local parent = node.parent
  if self.cmp(value, parent.value) then
    self:set_left(parent, node)
  else
    self:set_right(parent, node)
  end
  self:balance_path_to_root(parent)

  return node
end

function utils.Set:find(value)
  local node = self.root
  while node do
    if self.cmp(value, node.value) then
      node = node.left
    elseif self.cmp(node.value, value) then
      node = node.right
    else
      return node
    end
  end
  return nil
end

function utils.Set:first()
  local node = self.root
  if node then
    while node.left do
      node = node.left
    end
  end
  return node
end

function utils.Set:last()
  local node = self.root
  if node then
    while node.right do
      node = node.right
    end
  end
  return node
end

function utils.Set:__len()
  return self.root and self.root.size or 0
end

function utils.Set:next(node)
  if node.right then
    node = node.right
    while node.left do
      node = node.left
    end
  else
    while node.parent and node == node.parent.right do
      node = node.parent
    end
    node = node.parent
  end
  return node
end

function utils.Set:prev(node)
  if node.left then
    node = node.left
    while node.right do
      node = node.right
    end
  else
    while node.parent and node == node.parent.left do
      node = node.parent
    end
    node = node.parent
  end
  return node
end

function utils.Set:remove(node)
  local parent = node.parent
  if not parent then
    self.root = nil
  elseif node == parent.left then
    self:set_left(parent, nil)
  else
    self:set_right(parent, nil)
  end
  self:balance_path_to_root(parent)
  return node.value
end

function utils.Set:balance_path_to_root(node)
  local function weight(node)
    return (node and node.size or 0) + 1
  end
  while node do
    if 5 * weight(node.left) < 2 * weight(node.right) then
      if 2 * weight(node.right.left) < 3 * weight(node.right.right) then
        self:rotate_right(node)
      else
        self:rotate_left(node.right)
        self:rotate_right(node)
      end
      node = node.parent
    elseif 2 * weight(node.left) > 5 * weight(node.right) then
      if 3 * weight(node.left.left) > 2 * weight(node.left.right) then
        self:rotate_left(node)
      else
        self:rotate_right(node.left)
        self:rotate_left(node)
      end
      node = node.parent
    end
    node.size = 1 + (node.left and node.left.size or 0) + (node.right and node.right.size or 0)
    node = node.parent
  end
end

function utils.Set:rotate_left(node)
  local child, parent = node.left, node.parent
  self:set_left(node, child.right)
  self:set_right(child, node)
  if not parent then
    self.root = child
    child.parent = nil
  elseif node == parent.left then
    self:set_left(parent, child)
  else
    self:set_right(parent, child)
  end
end

function utils.Set:rotate_right(node)
  local child, parent = node.right, node.parent
  self:set_right(node, child.left)
  self:set_left(child, node)
  if not parent then
    self.root = child
    child.parent = nil
  elseif node == parent.left then
    self:set_left(parent, child)
  else
    self:set_right(parent, child)
  end
end

function utils.Set:set_left(node, child)
  node.left = child
  if node.left then
    node.left.parent = node
    node.size = 1 + node.left.size + (node.right and node.right.size or 0)
  else
    node.size = 1 + (node.right and node.right.size or 0)
  end
end

function utils.Set:set_right(node, child)
  node.right = child
  if node.right then
    node.right.parent = node
    node.size = 1 + (node.left and node.left.size or 0) + node.right.size
  else
    node.size = 1 + (node.left and node.left.size or 0)
  end
end



utils.Treap = {}
utils.Treap.__index = utils.Treap

function utils.Treap.new(cmp)
  return setmetatable({
    cmp = cmp or function(a, b) return a < b end,
    root = nil,
  }, utils.Treap)
end

function utils.Treap:insert(value)
  local node, parent = self.root, nil
  while node do
    parent = node
    if self.cmp(value, node.value) then
      node = node.left
    elseif self.cmp(node.value, value) then
      node = node.right
    else
      return nil
    end
  end

  local node = {
    value = value,
    priority = math.random(0),
    parent = nil,
    left = nil,
    right = nil,
    size = 1,
  }

  while parent and parent.priority <= node.priority do
    local child = parent
    parent = child.parent
    if self.cmp(child.value, value) then
      self:set_right(child, node.left)
      self:set_left(node, child)
    else
      self:set_left(child, node.right)
      self:set_right(node, child)
    end
  end

  if not parent then
    self.root = node
  elseif self.cmp(value, parent.value) then
    self:set_left(parent, node)
  else
    self:set_right(parent, node)
  end

  while parent do
    parent.size = 1 + (parent.left and parent.left.size or 0) + (parent.right and parent.right.size or 0)
    parent = parent.parent
  end

  return node
end

function utils.Treap:find(value)
  local node = self.root
  while node do
    if self.cmp(value, node.value) then
      node = node.left
    elseif self.cmp(node.value, value) then
      node = node.right
    else
      return node
    end
  end
  return nil
end

function utils.Treap:first()
  local node = self.root
  if node then
    while node.left do
      node = node.left
    end
  end
  return node
end

function utils.Treap:last()
  local node = self.root
  if node then
    while node.right do
      node = node.right
    end
  end
  return node
end

function utils.Treap:__len()
  return self.root and self.root.size or 0
end

function utils.Treap:next(node)
  if node.right then
    node = node.right
    while node.left do
      node = node.left
    end
  else
    while node.parent and node == node.parent.right do
      node = node.parent
    end
    node = node.parent
  end
  return node
end

function utils.Treap:prev(node)
  if node.left then
    node = node.left
    while node.right do
      node = node.right
    end
  else
    while node.parent and node == node.parent.left do
      node = node.parent
    end
    node = node.parent
  end
  return node
end

function utils.Treap:remove(node)
end

function utils.Treap:set_left(node, child)
  node.left = child
  if node.left then
    node.left.parent = node
    node.size = 1 + node.left.size + (node.right and node.right.size or 0)
  else
    node.size = 1 + (node.right and node.right.size or 0)
  end
end

function utils.Treap:set_right(node, child)
  node.right = child
  if node.right then
    node.right.parent = node
    node.size = 1 + (node.left and node.left.size or 0) + node.right.size
  else
    node.size = 1 + (node.left and node.left.size or 0)
  end
end

return utils
