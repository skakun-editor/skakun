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

return utils
