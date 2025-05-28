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

local SyntaxHighlighter = {
  predicates = {
    ['eq?'] = function(self) return function(capture, other)
      if type(other) ~= 'string' then
        other = self:read_node(other:one_node())
      end
      return self:read_node(capture:one_node()) == other
    end end,
    ['match?'] = function(self) return function(capture, regex)
      return self:read_node(capture:one_node()):match(regex)
    end end,
    ['any-of?'] = function(self) return function(capture, ...)
      local str = self:read_node(capture:one_node())
      for i = 1, select('#', ...) do
        if str == select(i, ...) then
          return true
        end
      end
      return false
    end end,
    ['set!'] = function(self) return function(key, value)
      self.capture_properties[key] = value
    end end,
    ['lua-match?'] = function(self) return function(capture, regex)
      return self:read_node(capture:one_node()):match(regex)
    end end,
  },
}
SyntaxHighlighter.__index = SyntaxHighlighter

function SyntaxHighlighter.of(buffer)
  if not buffer._syntax_highlighter then
    buffer._syntax_highlighter = SyntaxHighlighter.new(buffer)
  end
  return buffer._syntax_highlighter
end

function SyntaxHighlighter.new(buffer)
  if not buffer.is_frozen then
    error('buffer is not frozen')
  end
  local self = setmetatable({
    buffer = buffer,
    highlight_at = {},
    worker = nil,
    lock = thread.newlock(),
    grammars_version = nil,
    is_stopping = false,
  }, SyntaxHighlighter)
  return self
end

function SyntaxHighlighter:refresh()
  self.lock:acquire()
  if self.grammars_version ~= grammars_version and not self.is_stopping then
    self.is_stopping = true
    if self.worker then
      self.worker:join()
    end
    self.worker = thread.new(xpcall, self.run, function(err)
      stderr.error(here, debug.traceback(err))
    end, self)
  end
  self.lock:release()
end

function SyntaxHighlighter:run()
  self.grammars_version = grammars_version
  self.is_stopping = false

  local grammar = treesitter.grammar_for_path(self.buffer.doc.path or '')
  if not grammar then
    self.highlight_at = {}
    return
  end
  local predicates = {}
  for name, func in pairs(self.predicates) do
    predicates[name] = func(self)
  end
  local runner = treesitter.Query.Runner.new(predicates, function()
    self.capture_properties = {}
  end)

  local start = utils.timer()
  local parser = treesitter.Parser:new()
  parser:set_language(grammar.lang)
  local tree = parser:parse(nil, function(idx)
    return self.buffer:read(idx + 1, math.min(idx + 1000000, #self.buffer))
  end)
  if self.is_stopping then return end
  stderr.info(here, 'parse done in ', math.floor(1e3 * (utils.timer() - start)), 'ms')

  local start = utils.timer()
  local cursor = treesitter.Query.Cursor.new(grammar.highlights(), tree:root_node())
  for capture in runner:iter_captures(cursor) do
    for i = capture:node():start_byte() + 1, capture:node():end_byte() do
      self.highlight_at[i] = capture:name()
    end
    if self.is_stopping then return end
  end
  stderr.info(here, 'highlights done in ', math.floor(1e3 * (utils.timer() - start)), 'ms')

  local start = utils.timer()
  local cursor = treesitter.Query.Cursor.new(grammar.locals(), tree:root_node())
  local scopes = {
    {
      from = 1,
      to = math.maxinteger,
      highlight_for = {},
    },
  }
  for capture in runner:iter_captures(cursor) do
    local from = capture:node():start_byte() + 1
    local to = capture:node():end_byte()

    while from > scopes[#scopes].to do
      table.remove(scopes)
    end
    if capture:name() == 'local.scope' then
      table.insert(scopes, {
        from = from,
        to = to,
        highlight_for = setmetatable({}, { __index = scopes[#scopes].highlight_for }),
      })
    elseif capture:name() == 'local.definition' then
      scopes[#scopes].highlight_for[self:read_node(capture:node())] = self.highlight_at[from]
    elseif capture:name() == 'local.reference' then
      local name = scopes[#scopes].highlight_for[self:read_node(capture:node())]
      if name then
        for i = from, to do
          self.highlight_at[i] = name
        end
      end
    end

    if self.is_stopping then return end
  end
  stderr.info(here, 'locals done in ', math.floor(1e3 * (utils.timer() - start)), 'ms')
end

function SyntaxHighlighter:read_node(node)
  return self.buffer:read(node:start_byte() + 1, node:end_byte())
end

return SyntaxHighlighter
