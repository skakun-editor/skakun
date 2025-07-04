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

local Editor = {}
Editor.__index = Editor

function Editor.new()
  local self = setmetatable({
    queue = {},
    clipboard = {},
  }, Editor)
  self.worker = thread.new(xpcall, function(err)
    stderr.info(here, debug.traceback(err))
  end, self.run, self)
  return self
end

function Editor:run()
  while true do
    self.queue_lock:acquire()
    local func = table.remove(1)
    self.queue_lock:release()
    xpcall(func, function(err)
      stderr.error(here, debug.traceback(err))
    end)
  end
end

function Editor:enqueue(func)
  self.queue_lock:acquire()
  table.insert(self.queue, func)
  self.queue_lock:release()
end

function Editor:queue_insert(doc, idx, idx_buffer, string)
  self:enqueue(function()
    local buffer = doc.buffer:thaw()
    idx = buffer:carry_idx_over(idx, idx_buffer)
    buffer:insert(idx, string)
    doc:set_buffer(buffer)
  end)
end

function Editor:queue_delete_backward(doc, idx, idx_buffer, cnt)
  self:enqueue(function()
    local buffer = doc.buffer:thaw()
    idx = buffer:carry_idx_over(idx, idx_buffer)
    buffer:delete(idx - cnt, idx - 1)
    doc:set_buffer(buffer)
  end)
end

function Editor:queue_delete_forward(doc, idx, idx_buffer, cnt)
  self:enqueue(function()
    local buffer = doc.buffer:thaw()
    idx = buffer:carry_idx_over(idx, idx_buffer)
    buffer:delete(idx, idx + cnt - 1)
    doc:set_buffer(buffer)
  end)
end

return Editor
