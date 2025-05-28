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

local Buffer = require('core.buffer')
local utils  = require('core.utils')

local DocBuffer = {}
DocBuffer.__index = DocBuffer

function DocBuffer.new(doc)
  return setmetatable({
    doc = doc,
    buffer = Buffer.new(),
    is_frozen = false,
    freeze_time = nil,
  }, DocBuffer)
end

function DocBuffer.open(path, doc)
  return setmetatable({
    doc = doc,
    buffer = Buffer.open(path),
    is_frozen = false,
    freeze_time = nil,
  }, DocBuffer)
end

function DocBuffer:save(path)
  self.buffer:save(path)
end

function DocBuffer:__len()
  return #self.buffer
end

function DocBuffer:read(from, to)
  return self.buffer:read(from, to)
end

function DocBuffer:iter(from)
  return self.buffer:iter(from)
end

function DocBuffer:insert(idx, string)
  if self.is_frozen then
    error('buffer is frozen')
  end
  self.buffer:insert(idx, string)
end

function DocBuffer:delete(from, to)
  if self.is_frozen then
    error('buffer is frozen')
  end
  self.buffer:delete(from, to)
end

function DocBuffer:copy(idx, src, from, to)
  if self.is_frozen then
    error('buffer is frozen')
  end
  self.buffer:copy(idx, src.buffer, from, to)
end

function DocBuffer:freeze()
  if not self.is_frozen then
    self.is_frozen = true
    self.freeze_time = utils.timer()
  end
end

function DocBuffer:thaw()
  if self.is_frozen then
    local copy = DocBuffer.new(self.doc)
    copy:insert(1, self, 1, #self)
    return copy
  else
    return self
  end
end

function DocBuffer:load()
  self.buffer:load()
end

function DocBuffer:has_healthy_mmap()
  return self.buffer:has_healthy_mmap()
end

function DocBuffer:has_corrupt_mmap()
  return self.buffer:has_corrupt_mmap()
end

function DocBuffer.validate_mmaps()
  return Buffer.validate_mmaps()
end

return DocBuffer
