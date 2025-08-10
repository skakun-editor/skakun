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

local Buffer    = require('core.buffer')
local Navigator = require('core.doc.navigator')
local utils     = require('core.utils')

local DocBuffer = {}
DocBuffer.__index = DocBuffer

function DocBuffer.new(doc, raw)
  local self = setmetatable({
    doc = doc,
    raw = raw or Buffer.new(),
    is_frozen = false,
    freeze_time = nil,
    navigator = nil,

    root = nil,
    depth = 0,
    parent = nil,
    parent_diff = {},
  }, DocBuffer)
  self.root = self
  return self
end

function DocBuffer.open(doc, path)
  return DocBuffer.new(doc, Buffer.open(path))
end

function DocBuffer:save(path)
  self.raw:save(path)
end

function DocBuffer:__len()
  return #self.raw
end

function DocBuffer:read(from, to)
  return self.raw:read(from, to)
end

function DocBuffer:iter(from)
  return self.raw:iter(from)
end

function DocBuffer:insert(idx, string)
  if self.is_frozen then
    error('buffer is frozen')
  end
  self.raw:insert(idx, string)
  self:record_edit(idx, 0, #string)
end

function DocBuffer:delete(from, to)
  if self.is_frozen then
    error('buffer is frozen')
  end
  self.raw:delete(from, to)
  self:record_edit(from, to - from + 1, 0)
end

function DocBuffer:copy(idx, src, from, to)
  if self.is_frozen then
    error('buffer is frozen')
  end
  self.raw:copy(idx, src.raw, from, to)
  self:record_edit(idx, 0, to - from + 1)
end

-- TODO: move idxs inside edits to their one-past-the-end

function DocBuffer:record_edit(idx, old_len, new_len)
  local diff = self.parent_diff
  if #diff == 0 then
    diff[1] = {
      old_idx = idx, old_len = old_len,
      new_idx = idx, new_len = new_len,
    }
    return
  end

  local i = 1
  while i <= #diff and diff[i].new_idx + diff[i].new_len < idx do
    i = i + 1
  end
  if i > #diff then
    local shift = diff[#diff].new_idx + diff[#diff].new_len - diff[#diff].old_idx - diff[#diff].old_len
    table.insert(diff, {
      old_idx = idx - shift, old_len = old_len,
      new_idx = idx, new_len = new_len,
    })
    return
  end
  local j = i - 1
  while j + 1 <= #diff and diff[j + 1].new_idx <= idx + old_len do
    j = j + 1
  end
  if j < 1 then
    table.insert(diff, 1, {
      old_idx = idx, old_len = old_len,
      new_idx = idx, new_len = new_len,
    })
    for k = 2, #diff do
      diff[k].new_idx = diff[k].new_idx + new_len - old_len
    end
    return
  end

  local edit = {}
  edit.new_idx = math.min(idx, diff[i].new_idx)
  edit.new_len = math.max(idx + old_len, diff[j].new_idx + diff[j].new_len) - edit.new_idx
  edit.old_idx = edit.new_idx - (diff[i].new_idx - diff[i].old_idx)
  edit.old_len = edit.new_idx + edit.new_len - (diff[j].new_idx + diff[j].new_len - diff[j].old_idx - diff[j].old_len) - edit.old_idx
  edit.new_len = edit.new_len + new_len - old_len
  for k = j + 1, #diff do
    diff[k].new_idx = diff[k].new_idx + new_len - old_len
  end
  table.move(diff, j + 1, #diff, i + 1)
  diff[i] = edit
end

function DocBuffer:freeze()
  if not self.is_frozen then
    self.is_frozen = true
    self.freeze_time = utils.timer()
    self.navigator = Navigator.new(self)
  end
end

function DocBuffer:thaw()
  if not self.is_frozen then
    return self
  end
  local copy = DocBuffer.new(self.doc)
  copy.raw:copy(1, self.raw, 1, #self.raw)
  copy.root = self.root
  copy.depth = self.depth + 1
  copy.parent = self
  return copy
end

function DocBuffer:walk_to(other, callback)
  if self.root ~= other.root then
    error('buffers belong to disjoint trees')
  end
  local a, b = self, other
  while a.depth > b.depth do
    callback(a)
    a = a.parent
  end
  local b_path = {}
  while b.depth > a.depth do
    table.insert(b_path, b)
    b = b.parent
  end
  while a ~= b do
    callback(a)
    a = a.parent
    table.insert(b_path, b)
    b = b.parent
  end
  callback(a)
  while #b_path > 0 do
    callback(table.remove(b_path))
  end
end

function DocBuffer:carry_idx_over(idx, idx_buffer)
  if self.root ~= idx_buffer.root then
    return 1
  end
  local prev
  idx_buffer:walk_to(self, function(buffer)
    if not prev then
      prev = buffer
      return
    end
    if prev == buffer.parent then
      local diff = buffer.parent_diff
      local edit = utils.binary_search_first(diff, function(edit)
        return idx < edit.old_idx + edit.old_len
      end)
      if edit then
        idx = math.min(idx, edit.old_idx) + (edit.new_idx - edit.old_idx)
      else
        idx = idx + (diff[#diff].new_idx + diff[#diff].new_len - diff[#diff].old_idx - diff[#diff].old_len)
      end
    else
      local diff = prev.parent_diff
      local edit = utils.binary_search_first(diff, function(edit)
        return idx < edit.new_idx + edit.new_len
      end)
      if edit then
        idx = math.min(idx, edit.new_idx) - (edit.new_idx - edit.old_idx)
      else
        idx = idx - (diff[#diff].new_idx + diff[#diff].new_len - diff[#diff].old_idx - diff[#diff].old_len)
      end
    end
    prev = buffer
  end)
  return idx
end

function DocBuffer:load()
  self.raw:load()
end

function DocBuffer:has_healthy_mmap()
  return self.raw:has_healthy_mmap()
end

function DocBuffer:has_corrupt_mmap()
  return self.raw:has_corrupt_mmap()
end

function DocBuffer.validate_mmaps()
  return Buffer.validate_mmaps()
end

return DocBuffer
