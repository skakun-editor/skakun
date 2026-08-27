-- Skakun - A robust and hackable hex and text editor
-- Copyright (C) 2024-2026 Karol "digitcrusher" Łacina
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

local DocBuffer = require('core.doc.buffer')
local GLib      = require('LuaGObject').GLib

local Doc = {
  history_commit_delay = 1.0,
}
Doc.__index = Doc

function Doc.new()
  local self = setmetatable({
    history_idx = 1,
    path = nil,
  }, Doc)
  local buffer = DocBuffer.new(self)
  buffer:freeze()
  self.buffer = buffer
  self.history = {buffer}
  self.set_buffer_log = {buffer}
  return self
end

function Doc.open(path)
  local self = setmetatable({
    history_idx = 1,
    path = nil,
  }, Doc)
  local buffer = DocBuffer.open(self, path)
  buffer:freeze()
  self:set_path(path)
  self.buffer = buffer
  self.history = {buffer}
  self.set_buffer_log = {buffer}
  return self
end

function Doc:save(path)
  if path then
    self.buffer:save(path)
  elseif not self.path then
    error('path not set')
  else
    self.buffer:save(self.path)
  end
end

function Doc:set_path(value)
  self.path = GLib.canonicalize_filename(value, nil)
end

function Doc:set_buffer(buffer)
  assert(buffer.doc == self)
  buffer:freeze()
  if self.history_idx < #self.history or buffer.freeze_time - self.buffer.freeze_time >= self.history_commit_delay then
    for i = self.history_idx + 1, #self.history do
      self.history[i] = nil
    end
    self.history_idx = self.history_idx + 1
  end
  self.history[self.history_idx] = buffer
  self.buffer = buffer
  table.insert(self.set_buffer_log, buffer)
end

function Doc:undo()
  self.history_idx = math.max(1, self.history_idx - 1)
  self.buffer = self.history[self.history_idx]
  table.insert(self.set_buffer_log, self.buffer)
end

function Doc:redo()
  self.history_idx = math.min(#self.history, self.history_idx + 1)
  self.buffer = self.history[self.history_idx]
  table.insert(self.set_buffer_log, self.buffer)
end

return Doc
