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

local here = ...
local stderr = require('core.stderr')
local tty    = require('core.tty')
local utils  = require('core.utils')

local Navigator = {
  tab_width = 8,
  global_cache_skip = 1e4,
  max_local_cache_size = 1e3,
  local_cache_prune_probability = 0.5,
}
Navigator.__index = Navigator

function Navigator.of(buffer)
  if not buffer._navigator then
    buffer._navigator = Navigator.new(buffer)
  end
  return buffer._navigator
end

function Navigator.new(buffer)
  if not buffer.is_frozen then
    error('buffer is not frozen')
  end
  local self = setmetatable({
    buffer = buffer,
    local_cache = Navigator.Cache.new(),
    global_cache = Navigator.Cache.new(),
  }, Navigator)
  self.global_cache:insert({ byte = 1, grapheme = 1, line = 1, col = 1, last_tab = nil })
  return self
end

function Navigator:locate_byte(byte)
  return self:locate(function(loc) return loc.byte > byte end)
end

function Navigator:locate_grapheme(grapheme)
  return self:locate(function(loc) return loc.grapheme > grapheme end)
end

function Navigator:locate_line_col(line, col)
  return self:locate(function(loc) return loc.line == line and loc.col > col or loc.line > line end)
end

function Navigator:locate_nearest_tab(byte)
  return self:locate(function(loc) return loc.last_tab and loc.last_tab >= byte end)
end

function Navigator:locate(is_too_far)
  local a = self.local_cache:search(is_too_far)
  local b = self.global_cache:search(is_too_far)

  local before = utils.copy(a and a.byte > b.byte and a or b)
  local iter = self.buffer:iter(before.byte)
  local after = utils.copy(before)
  local last_global_insert = b.byte

  while true do
    local ok, grapheme = pcall(iter.next_grapheme, iter)
    if not ok then
      grapheme = '�'
    elseif not grapheme then
      break
    end

    after.byte = before.byte + iter:last_advance()
    after.grapheme = before.grapheme + 1
    if grapheme == '\n' then
      after.line = before.line + 1
      after.col = 1
      after.last_tab = before.last_tab
    elseif grapheme == '\t' then
      after.line = before.line
      after.col = before.col + self.tab_width - (before.col - 1) % self.tab_width
      after.last_tab = before.byte
    else
      after.line = before.line
      after.col = before.col + tty.width_of(grapheme)
      after.last_tab = before.last_tab
    end

    if after.byte - last_global_insert >= self.global_cache_skip then
      self.global_cache:insert(after)
      last_global_insert = after.byte
    end

    if is_too_far(after) then
      break
    end
    local temp = before
    before = after
    after = temp
  end

  if self.local_cache.size + 1 > self.max_local_cache_size then
    local old_size = self.local_cache.size
    self.local_cache:prune(self.local_cache_prune_probability)
    stderr.info(here, 'pruned ', old_size - self.local_cache.size, ' nodes from local cache')
  end
  self.local_cache:insert(before)
  return before
end

-- I did try using a splay tree here but ultimately I had to abandon that idea
-- due to the shortcomings of its claimed advantages. To be precise, the cost of
-- rotations greatly outweighed the time savings of shorter search paths. So
-- much so that the randomized splay was always faster, even though its paper
-- said it shouldn't have been. On the other hand, the treap, which had to make
-- roughly 4x more descents, still outperformed the former and was simpler to
-- code. The one sure advantage of the splay, however, is the naturally arising
-- LRU quality of its levels, which could be exploited in pruning.
Navigator.Cache = {}
Navigator.Cache.__index = Navigator.Cache

function Navigator.Cache.new()
  return setmetatable({
    root = nil,
    size = 0,
  }, Navigator.Cache)
end

function Navigator.Cache:insert(loc)
  local path = {}
  local node = self.root
  while node do
    table.insert(path, node)
    if loc.byte < node.value.byte then
      node = node.left
    elseif node.value.byte < loc.byte then
      node = node.right
    else
      return false
    end
  end

  local node = {
    value = utils.copy(loc),
    priority = math.random(0),
    left = nil,
    right = nil,
    min = utils.copy(loc),
  }

  while #path > 0 and path[#path].priority <= node.priority do
    local child = table.remove(path)
    if child.value.byte < node.value.byte then
      child.right = node.left
      node.left = child
    else
      child.left = node.right
      child.min = utils.copy(child.left and child.left.min or child.value)
      node.right = child
    end
  end

  local parent = path[#path]
  if not parent then
    self.root = node
  elseif node.value.byte < parent.value.byte then
    parent.left = node
  else
    parent.right = node
  end

  if node.left then
    node.min = utils.copy(node.left.min)
  else
    table.insert(path, node)
    for i = #path - 1, 1, -1 do
      if path[i].min.byte < path[i + 1].min.byte then break end
      path[i].min = utils.copy(path[i + 1].min)
    end
  end

  self.size = self.size + 1
  return true
end

function Navigator.Cache:search(is_too_far)
  local node = self.root
  while node do
    if is_too_far(node.value) then
      node = node.left
    elseif node.right and not is_too_far(node.right.min) then
      node = node.right
    else
      return node.value
    end
  end
  return nil
end

function Navigator.Cache:prune(probability)
  local stack = {}
  self.size = 0

  local function dfs(node)
    if not node then return end
    dfs(node.left)

    if math.random() >= probability then
      if #stack > 0 and stack[#stack].priority < node.priority then
        stack[#stack].right = nil
        while #stack >= 2 and stack[#stack - 1].priority < node.priority do
          stack[#stack - 1].right = table.remove(stack)
        end
        node.left = table.remove(stack)
        node.min = utils.copy(node.left.min)
      else
        node.left = nil
        node.min = utils.copy(node.value)
      end
      table.insert(stack, node)
      self.size = self.size + 1
    end

    dfs(node.right)
  end
  dfs(self.root)

  for i = 1, #stack do
    stack[i].right = stack[i + 1]
  end
  self.root = stack[1]
end

return Navigator
