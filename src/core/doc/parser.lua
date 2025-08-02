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
local stderr     = require('core.stderr')
local treesitter = require('core.treesitter')
local utils      = require('core.utils')

local grammars_version = 0
local continue = treesitter.on_grammars_change
function treesitter.on_grammars_change()
  grammars_version = grammars_version + 1
  continue()
end

local Parser = {
  predicates = {
    ['eq?'] = function(self, capture, other)
      if type(other) ~= 'string' then
        other = self:read_node(other:one_node())
      end
      for _, node in ipairs(capture:nodes()) do
        if self:read_node(node) ~= other then
          return false
        end
      end
      return true
    end,

    ['not-eq?'] = function(self, capture, other)
      if type(other) ~= 'string' then
        other = self:read_node(other:one_node())
      end
      for _, node in ipairs(capture:nodes()) do
        if self:read_node(node) == other then
          return false
        end
      end
      return true
    end,

    ['match?'] = function(self, capture, regex)
      for _, node in ipairs(capture:nodes()) do
        if not self:read_node(node):find(regex) then
          return false
        end
      end
      return true
    end,

    ['not-match?'] = function(self, capture, regex)
      for _, node in ipairs(capture:nodes()) do
        if self:read_node(node):find(regex) then
          return false
        end
      end
      return true
    end,

    ['any-of?'] = function(self, capture, ...)
      local str = self:read_node(capture:one_node())
      for i = 1, select('#', ...) do
        if str == select(i, ...) then
          return true
        end
      end
      return false
    end,
  },
}
Parser.__index = Parser

function Parser.of(buffer)
  if not buffer._parser then
    buffer._parser = Parser.new(buffer)
  end
  return buffer._parser
end

function Parser.new(buffer)
  if not buffer.is_frozen then
    error('buffer is not frozen')
  end
  local self = setmetatable({
    buffer = buffer,
    grammar = nil,
    tree = nil,

    worker = nil,
    lock = thread.newlock(),
    is_stopping = false,
    grammars_version = nil,
  }, Parser)
  return self
end

function Parser:refresh()
  self.lock:acquire()
  if self.grammars_version ~= grammars_version and not self.is_stopping then
    self.is_stopping = true
    if self.worker then
      self.worker:join()
    end
    self.worker = thread.new(xpcall, self.run, function(err)
      stderr.error(here, debug.traceback(err, 2))
    end, self)
  end
  self.lock:release()
end

function Parser:run()
  self.grammars_version = grammars_version
  self.is_stopping = false

  self.grammar = treesitter.grammar_for_path(self.buffer.doc.path or '')
  if not self.grammar then
    self.tree = nil
    return
  end

  local start = utils.timer()

  local tree = nil
  if self.buffer.parent then
    local parent = Parser.of(self.buffer.parent)
    parent:refresh()
    while not parent.tree do
      thread.sleep(0.01)
    end
    tree = parent.tree:copy()
    local dummy = treesitter.Point.new(0, 0)
    for i = #self.buffer.parent_diff, 1, -1 do
      local edit = self.buffer.parent_diff[i]
      local idx = edit.old_idx - 1
      tree:edit(idx, idx + edit.old_len, idx + edit.new_len, dummy, dummy, dummy)
    end
  end

  local parser = treesitter.Parser:new()
  parser:set_language(self.grammar.lang)
  self.tree = parser:parse(tree, function(idx)
    return self.buffer:read(idx + 1, math.min(idx + 1000000, #self.buffer))
  end)

  local millis = math.floor(1e3 * (utils.timer() - start))
  if millis > 20 then
    stderr.warn(here, 'slow parse took ', millis, 'ms')
  end
end

function Parser:get_predicates()
  local result = {}
  for name, func in pairs(self.predicates) do
    result[name] = function(...)
      return func(self, ...)
    end
  end
  return result
end

function Parser:read_node(node)
  return self.buffer:read(node:start_byte() + 1, node:end_byte())
end

return Parser
