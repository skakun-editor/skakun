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

function Navigator.new(buffer)
  assert(buffer.is_frozen)

  local self = setmetatable({
    buffer = buffer,
  }, Navigator)

  if buffer.parent then
    local parent = buffer.parent.navigator
    self.local_cache = parent.local_cache:copy()
    self.global_cache = parent.global_cache:copy()

    for i, edit in ipairs(buffer.parent_diff) do
      local idx, len = edit.new_idx, edit.old_len
      local next_edit = buffer.parent_diff[i + 1]

      -- 1. Remove all cached locations with byte positions inside the edited
      --    region because even if some old and new grapheme boundaries match
      --    in some places, then the ones following them in the region don't
      --    necessarily have to. In other words, we have no guarantee which,
      --    if any, of the old cached locations are still valid.
      --    Example: 0x75 | 0x76 | 0x77 | 0x78 | 0x79 | 0x7a -> 0x75 0xcc 0x88 | 0x20 | 0xc3 0xbc = uvwxyz -> ü ü
      if len > 0 then
        self.local_cache:delete(idx, idx + len - 1)
        self.global_cache:delete(idx, idx + len - 1)
      end

      -- 2. We must update the byte positions of all cached locations to the
      --    right now, because the next steps depend on them.
      --    Example:
      --    | | *  * <- old cache elements
      --    |  \_____ <- edit
      --    |        | *  * <- updated old cache elements
      --    In the step below, we would have to locate the first old star in the
      --    new buffer and if we didn't update the byte positions of these old
      --    stars, then the locate method would pick the outdated second old
      --    star as the initial value for the linear search it does, which is
      --    wrong.
      local change = { byte = edit.new_len - edit.old_len, grapheme = 0, line = 0, col = 0, tab_col = 0 }
      self.local_cache:modify(idx + len, math.huge, change)
      self.global_cache:modify(idx + len, math.huge, change)
      len = edit.new_len

      if idx == 1 then
        self.global_cache:insert({ byte = 1, grapheme = 1, line = 1, col = 1, tab_col = 1 })
      end

      -- 3. Now we remove cached locations to the right of the edited region
      --    that are no longer valid grapheme boundaries.
      --    Example: 0xf0 0x9f 0x87 0xaa | 0x20 | 0xf0 0x9f 0x87 0xba -> 0xf0 0x9f 0x87 0xaa 0xf0 0x9f 0x87 0xba = 🇪 🇺 -> 🇪🇺
      --
      --    We assume here that when the grapheme boundary detection algorithm
      --    reports a grapheme boundary, then its state is reset to the initial
      --    value and previous inputs no longer have any effect on the output.
      --    Thus, it is sufficient to run this removal procedure only until we
      --    stop at a grapheme boundary that existed in the pre-edit buffer. The
      --    boundaries coming afterwards are all valid.
      --
      --    We also avoid entering the next edited region because potentially
      --    every edit might cause all cached locations to the right of it to be
      --    invalidated, which would mean iterating to the end of the buffer for
      --    every edit, resulting in quadratic time complexity.
      local closest_old, closest_new = nil, nil
      local a = self.local_cache:remove_greater_or_equal(idx + len)
      local b = self.global_cache:remove_greater_or_equal(idx + len)
      local ctx = nil
      while a or b do
        closest_old = (not b or a and a.byte < b.byte) and a or b
        if next_edit and next_edit.new_idx <= closest_old.byte then break end

        closest_new, ctx = self:locate_byte(closest_old.byte, ctx)
        if closest_new.byte == closest_old.byte then break end

        if closest_old == a then
          a = self.local_cache:remove_greater_or_equal(idx + len)
        else
          b = self.global_cache:remove_greater_or_equal(idx + len)
        end
      end
      if idx + len == 1 then
        self.global_cache:insert({ byte = 1, grapheme = 1, line = 1, col = 1, tab_col = 1 })
      end

      if closest_old and (not next_edit or closest_old.byte < next_edit.new_idx) then
        -- 4. Update the grapheme and line positions of all old cached locations
        --    to the right of the edited region. All of them were shifted by
        --    an equal amount with respect to these two coordinates, so it's
        --    enough to just calculate that shift based on the cached location
        --    we got from the previous step.
        local change = { byte = 0, grapheme = closest_new.grapheme - closest_old.grapheme, line = closest_new.line - closest_old.line, col = 0, tab_col = 0 }
        self.local_cache:modify(closest_old.byte, math.huge, change)
        self.global_cache:modify(closest_old.byte, math.huge, change)

        local first_after_edit = self:locate_byte(idx + len)
        if closest_new.line == first_after_edit.line then
          -- 5. Shift the column and tab column positions of all old cached
          --    locations in the same line as the first byte after the edited
          --    region.
          local function is_not_past_this_line(loc)
            return loc.line <= first_after_edit.line
          end
          local a = self.local_cache:find_last(is_not_past_this_line)
          local b = self.global_cache:find_last(is_not_past_this_line)
          local last_in_line = a and a.byte > b.byte and a or b
          local change = { byte = 0, grapheme = 0, line = 0, col = closest_new.col - closest_old.col, tab_col = closest_new.tab_col - closest_old.tab_col }
          self.local_cache:modify(closest_old.byte, last_in_line.byte, change)
          self.global_cache:modify(closest_old.byte, last_in_line.byte, change)

          -- 6. Fix the column positions of cached locations after tabs in the
          --    aforementioned line. Text after a tab can only shift by
          --    a multiple of the set tab width and if a tab character moves by
          --    such a multiple, then the text after it shifts by the same
          --    amount. So we can treat all subsequent tab columns in the line
          --    as one.
          --
          --    In the code below, we rely on the fact that the locate method
          --    does not fetch the cached location that would correspond exactly
          --    to the sought result, but rather limits its cache lookups to
          --    locations strictly before the range of acceptable answers.
          local function is_past_this_tab_col(loc)
            return loc.line > first_after_edit.line or loc.line == first_after_edit.line and loc.tab_col > first_after_edit.tab_col
          end
          local a = self.local_cache:find_first(is_past_this_tab_col)
          local b = self.global_cache:find_first(is_past_this_tab_col)
          local first_after_tab_old = (not b or a and a.byte < b.byte) and a or b
          if first_after_tab_old and first_after_tab_old.line == first_after_edit.line then
            local first_after_tab_new = self:locate_byte(first_after_tab_old.byte)
            local change = { byte = 0, grapheme = 0, line = 0, col = first_after_tab_new.col - first_after_tab_old.col, tab_col = 0 }
            self.local_cache:modify(first_after_tab_old.byte, last_in_line.byte, change)
            self.global_cache:modify(first_after_tab_old.byte, last_in_line.byte, change)
          end
        end
      end
    end

  else
    self.local_cache = Navigator.Cache.new()
    self.global_cache = Navigator.Cache.new()
    self.global_cache:insert({ byte = 1, grapheme = 1, line = 1, col = 1, tab_col = 1 })
  end

  return self
end

function Navigator:locate_byte(byte, ctx)
  return self:locate(function(loc) return loc.byte - byte end, ctx)
end

function Navigator:locate_grapheme(grapheme, ctx)
  return self:locate(function(loc) return loc.grapheme - grapheme end, ctx)
end

function Navigator:locate_line_col(line, col, ctx)
  return self:locate(function(loc) return loc.line ~= line and loc.line - line or loc.col - col end, ctx)
end

function Navigator:locate_line_tab_col(line, tab_col, ctx)
  return self:locate(function(loc) return loc.line ~= line and loc.line - line or loc.tab_col - tab_col end, ctx)
end

function Navigator:locate(cmp, ctx)
  if ctx then
    assert(cmp(ctx.prev) < 0)
  else
    ctx = {}
    local a = self.local_cache:find_last(function(loc) return cmp(loc) < 0 end)
    local b = self.global_cache:find_last(function(loc) return cmp(loc) < 0 end)
    if not b then
      local first = { byte = 1, grapheme = 1, line = 1, col = 1, tab_col = 1 }
      return cmp(first) == 0 and first or nil, nil
    end
    ctx.curr = utils.copy(a and a.byte > b.byte and a or b)
    ctx.iter = self.buffer:iter(ctx.curr.byte)
    ctx.prev = {}
    ctx.last_global_insert = b.byte
  end

  local iter = ctx.iter
  local curr = ctx.curr
  local prev = ctx.prev
  local last_global_insert = ctx.last_global_insert

  while cmp(curr) < 0 do
    local ok, grapheme = pcall(iter.next_grapheme, iter)
    if not ok then
      grapheme = '�'
    elseif not grapheme then
      break
    end

    curr, prev = prev, curr
    curr.byte = prev.byte + iter:last_advance()
    curr.grapheme = prev.grapheme + 1
    if grapheme == '\n' then
      curr.line = prev.line + 1
      curr.col = 1
      curr.tab_col = 1
    elseif grapheme == '\t' then
      curr.line = prev.line
      curr.col = prev.col + self.tab_width - (prev.col - 1) % self.tab_width
      curr.tab_col = prev.tab_col + 1
    else
      curr.line = prev.line
      curr.col = prev.col + tty.width_of(grapheme)
      curr.tab_col = prev.tab_col
    end

    if curr.byte - last_global_insert >= self.global_cache_skip then
      self.global_cache:insert(curr)
      last_global_insert = curr.byte
    end
  end

  if self.local_cache.size + 1 > self.max_local_cache_size then
    local old_size = self.local_cache.size
    self.local_cache:prune(self.local_cache_prune_probability)
    stderr.info(here, 'pruned ', old_size - self.local_cache.size, ' nodes from local cache')
  end
  self.local_cache:insert(cmp(curr) < 0 and curr or prev)

  ctx.iter = iter
  ctx.curr = curr
  ctx.prev = prev
  ctx.last_global_insert = last_global_insert
  return cmp(curr) <= 0 and curr or prev, ctx
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

function Navigator.Cache:copy()
  self.root.is_frozen = true
  return setmetatable({
    root = self.root,
    size = self.size,
  }, Navigator.Cache)
end

function Navigator.Cache:insert(loc)
  local path = {}
  local node = self.root
  while node do
    self:hello(node)
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
    is_frozen = false,
    value = utils.copy(loc),
    latent_change = nil,
    priority = math.random(0),
    left = nil,
    right = nil,
    size = 1,
    min = utils.copy(loc),
  }

  while #path > 0 and path[#path].priority <= node.priority do
    local child = self:thaw(table.remove(path))
    if child.value.byte < node.value.byte then
      child.right = node.left
      child.size = 1 + (child.left and child.left.size or 0) + (child.right and child.right.size or 0)
      node.left = child
    else
      child.left = node.right
      child.size = 1 + (child.left and child.left.size or 0) + (child.right and child.right.size or 0)
      child.min = utils.copy(child.left and child.left.min or child.value)
      node.right = child
    end
  end
  node.size = 1 + (node.left and node.left.size or 0) + (node.right and node.right.size or 0)

  table.insert(path, node)
  for i = #path - 1, 1, -1 do
    local parent, child = self:thaw(path[i]), path[i + 1]
    if child.value.byte < parent.value.byte then
      parent.left = child
    else
      parent.right = child
    end
    if parent == path[i] then break end
    path[i] = parent
  end
  self.root = path[1]

  for i = 1, #path - 1 do
    path[i].size = path[i].size + 1
  end
  if node.left then
    node.min = utils.copy(node.left.min)
  else
    for i = #path - 1, 1, -1 do
      if path[i].left ~= path[i + 1] then break end
      path[i].min = utils.copy(path[i + 1].min)
    end
  end

  self.size = self.size + 1
  return true
end

function Navigator.Cache:find_first(is_far_enough)
  local result, node = nil, self.root
  while node do
    self:hello(node)
    if is_far_enough(node.value) then
      result = node.value
      node = node.left
    else
      node = node.right
    end
  end
  return result
end

function Navigator.Cache:find_last(is_near_enough)
  local node = self.root
  while node do
    self:hello(node)
    if not is_near_enough(node.value) then
      node = node.left
    elseif node.right and is_near_enough(node.right.min) then
      node = node.right
    else
      return node.value
    end
  end
  return nil
end

function Navigator.Cache:remove_greater_or_equal(idx)
  local node = self.root
  local path = {}
  while node do
    self:hello(node)
    table.insert(path, node)
    if idx <= node.value.byte then
      node = node.left
    elseif node.value.byte < idx then
      node = node.right
    end
  end
  while #path > 0 and path[#path].value.byte < idx do
    table.remove(path)
  end

  local node = path[#path]
  if not node then
    return nil
  end

  local path_len = #path
  path[path_len] = self:merge(node.left, node.right)
  if path_len > 1 then
    local parent = self:thaw(path[path_len - 1])
    if node == parent.left then
      parent.left = path[path_len]
    else
      parent.right = path[path_len]
    end
    path[path_len - 1] = parent
    for i = path_len - 2, 1, -1 do
      local parent, child = self:thaw(path[i]), path[i + 1]
      if child.value.byte < parent.value.byte then
        parent.left = child
      else
        parent.right = child
      end
      if parent == path[i] then break end
      path[i] = parent
    end
  end
  self.root = path[1]

  for i = 1, path_len - 1 do
    path[i].size = path[i].size - 1
  end
  if not node.left and path_len > 1 and node.value.byte < path[path_len - 1].value.byte then
    path[path_len - 1].min = utils.copy(path[path_len] and path[path_len].min or path[path_len - 1].value)
    for i = path_len - 2, 1, -1 do
      if path[i].left ~= path[i + 1] then break end
      path[i].min = utils.copy(path[i + 1].min)
    end
  end

  self.size = self.size - 1
  return node.value
end

function Navigator.Cache:modify(from, to, change)
  local function descend(node, node_max_byte)
    if from <= node.min.byte and node_max_byte <= to then
      return self:modify_subtree(node, change)
    end

    self:hello(node)
    node = self:thaw(node)

    if node.left and from <= node.value.byte - 1 then
      node.left = descend(node.left, node.value.byte - 1)
      node.min = utils.copy(node.left.min)
    end

    if node.right and node.right.min.byte <= to then
      node.right = descend(node.right, node_max_byte)
    end

    if from <= node.value.byte and node.value.byte <= to then
      self:modify_value(node.value, change)
    end

    return node
  end
  if self.root then
    self.root = descend(self.root, math.huge)
  end
end

function Navigator.Cache:delete(from, to)
  local function descend(node, node_max_byte)
    if not node or from <= node.min.byte and node_max_byte <= to then
      return nil
    end

    self:hello(node)

    if from <= node.value.byte and node.value.byte <= to then
      return self:merge(
        descend(node.left, node.value.byte - 1),
        descend(node.right, node_max_byte)
      )
    end

    node = self:thaw(node)

    if to < node.value.byte then
      node.left = descend(node.left, node.value.byte - 1)
      node.size = 1 + (node.left and node.left.size or 0) + (node.right and node.right.size or 0)
      node.min = utils.copy(node.left and node.left.min or node.value)

    else
      node.right = descend(node.right, node_max_byte)
      node.size = 1 + (node.left and node.left.size or 0) + (node.right and node.right.size or 0)
    end

    return node
  end
  self.root = descend(self.root, math.huge)
  self.size = self.root and self.root.size or 0
end

function Navigator.Cache:prune(probability)
  local stack = {}

  local function dfs(node)
    if not node then return end
    self:hello(node)
    dfs(node.left)

    if math.random() >= probability then
      node = self:thaw(node)
      if #stack > 0 and stack[#stack].priority < node.priority then
        stack[#stack].right = nil
        while #stack >= 2 and stack[#stack - 1].priority < node.priority do
          local parent = stack[#stack - 1]
          parent.right = table.remove(stack)
          parent.size = parent.size + parent.right.size
        end
        node.left = table.remove(stack)
        node.size = 1 + node.left.size
        node.min = utils.copy(node.left.min)
      else
        node.left = nil
        node.size = 1
        node.min = utils.copy(node.value)
      end
      table.insert(stack, node)
    end

    dfs(node.right)
  end
  dfs(self.root)

  stack[#stack].right = nil
  for i = #stack - 1, 1, -1 do
    local parent = stack[i]
    parent.right = stack[i + 1]
    parent.size = parent.size + parent.right.size
  end

  self.root = stack[1]
  self.size = self.root and self.root.size or 0
end

function Navigator.Cache:hello(node)
  if node.latent_change then
    if node.left then
      node.left = self:modify_subtree(node.left, node.latent_change)
    end
    if node.right then
      node.right = self:modify_subtree(node.right, node.latent_change)
    end
    node.latent_change = nil
  end
  if node.is_frozen then
    if node.left then
      node.left.is_frozen = true
    end
    if node.right then
      node.right.is_frozen = true
    end
  end
end

function Navigator.Cache:thaw(node)
  if not node.is_frozen then
    return node
  end
  self:hello(node)
  return {
    is_frozen = false,
    value = utils.copy(node.value),
    latent_change = nil,
    priority = node.priority,
    left = node.left,
    right = node.right,
    size = node.size,
    min = utils.copy(node.min),
  }
end

function Navigator.Cache:merge(a, b)
  if not a then return b end
  if not b then return a end
  if a.priority > b.priority then
    self:hello(a)
    a = self:thaw(a)
    a.right = self:merge(a.right, b)
    if b then
      a.size = a.size + b.size
    end
    return a
  else
    self:hello(b)
    b = self:thaw(b)
    b.left = self:merge(a, b.left)
    b.min = utils.copy(b.left.min)
    if a then
      b.size = b.size + a.size
    end
    return b
  end
end

function Navigator.Cache:modify_subtree(node, change)
  node = self:thaw(node)
  self:modify_value(node.value, change)
  self:modify_value(node.min, change)
  if node.latent_change then
    self:modify_value(node.latent_change, change)
  else
    node.latent_change = utils.copy(change)
  end
  return node
end

function Navigator.Cache:modify_value(value, change)
  value.byte     = value.byte     + change.byte
  value.grapheme = value.grapheme + change.grapheme
  value.line     = value.line     + change.line
  value.col      = value.col      + change.col
  value.tab_col  = value.tab_col  + change.tab_col
end

return Navigator
