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

local SortedSet = {}
SortedSet.__index = SortedSet

function SortedSet.new(cmp)
  return setmetatable({
    cmp = cmp or function(a, b) return a < b end,
    root = nil,
  }, SortedSet)
end

function SortedSet:insert(value)
  local node = {
    value = value,
    parent = nil,
    left = nil,
    right = nil,
    size = 1,
  }
  if not self.root then
    self.root = node
    return true, node
  end

  local parent = self.root
  while parent do
    node.parent = parent
    if self.cmp(value, parent.value) then
      parent = parent.left
    elseif self.cmp(parent.value, value) then
      parent = parent.right
    else
      return false, parent
    end
  end

  local parent = node.parent
  if self.cmp(value, parent.value) then
    self:set_left(parent, node)
  else
    self:set_right(parent, node)
  end
  self:fix_path_to_root(parent)

  return true, node
end

function SortedSet:__len()
  return self.root and self.root.size or 0
end

function SortedSet:elems()
  local node = self:first()
  return function()
    if node then
      local result = node
      node = self:next(node)
      return result, result.value
    end
  end
end

function SortedSet:find(value)
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

function SortedSet:find_first(is_far_enough)
  local result, node = nil, self.root
  while node do
    if is_far_enough(node.value) then
      result = node
      node = node.left
    else
      node = node.right
    end
  end
  return result
end

function SortedSet:find_last(is_near_enough)
  local result, node = nil, self.root
  while node do
    if is_near_enough(node.value) then
      result = node
      node = node.right
    else
      node = node.left
    end
  end
  return result
end

function SortedSet:first()
  local node = self.root
  if node then
    while node.left do
      node = node.left
    end
  end
  return node
end

function SortedSet:last()
  local node = self.root
  if node then
    while node.right do
      node = node.right
    end
  end
  return node
end

function SortedSet:next(node)
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

function SortedSet:prev(node)
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

function SortedSet:remove(node)
  local sub, lowest_broken = nil, node.parent
  if not node.left then
    sub = node.right
  elseif not node.right then
    sub = node.left
  else
    sub = node.right
    while sub.left do
      sub = sub.left
    end
    local parent = sub.parent
    if parent ~= node then
      self:set_left(parent, sub.right)
      lowest_broken = parent
      self:set_right(sub, node.right)
    end
    self:set_left(sub, node.left)
  end

  local parent = node.parent
  if node == self.root then
    self.root = sub
    sub.parent = nil
  elseif node == parent.left then
    self:set_left(parent, sub)
  else
    self:set_right(parent, sub)
  end

  if lowest_broken then
    self:fix_path_to_root(lowest_broken)
  end
  node.parent = nil
  node.left = nil
  node.right = nil

  return node.value
end

function SortedSet:clear()
  self.root = nil
end

-- Reference: Hirai, Y. & Yamamoto, K. (2011) "Balancing weight-balanced trees", Journal of Functional Programming

function SortedSet:fix_path_to_root(node)
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
    else
      node.size = 1 + (node.left and node.left.size or 0) + (node.right and node.right.size or 0)
    end
    node = node.parent
  end
end

function SortedSet:rotate_left(node)
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

function SortedSet:rotate_right(node)
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

function SortedSet:set_left(node, child)
  node.left = child
  if node.left then
    node.left.parent = node
    node.size = 1 + node.left.size + (node.right and node.right.size or 0)
  else
    node.size = 1 + (node.right and node.right.size or 0)
  end
end

function SortedSet:set_right(node, child)
  node.right = child
  if node.right then
    node.right.parent = node
    node.size = 1 + (node.left and node.left.size or 0) + node.right.size
  else
    node.size = 1 + (node.left and node.left.size or 0)
  end
end

return SortedSet
