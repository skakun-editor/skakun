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
local Parser     = require('core.doc.parser')
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
  is_debug = false,
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
    debug_info_at = {},

    worker = nil,
    lock = thread.newlock(),
    is_stopping = false,
    parser = Parser.of(buffer),
    grammar = nil,
    tree = nil,
  }, SyntaxHighlighter)
  return self
end

function SyntaxHighlighter:refresh()
  self.parser:refresh()
  self.lock:acquire()
  if self.tree ~= self.parser.tree and not self.is_stopping then
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

function SyntaxHighlighter:run()
  self.grammar = self.parser.grammar
  self.tree = self.parser.tree
  self.is_stopping = false

  if not self.tree then
    self.highlight_at = {}
    self.debug_info_at = {}
    return
  end

  local runner = treesitter.Query.Runner.new(self.parser:get_predicates())

  local start = utils.timer()
  local cursor = treesitter.Query.Cursor.new(self.grammar.highlights(), self.tree:root_node())
  for capture in runner:iter_captures(cursor) do
    if capture:name():sub(1, 1) ~= '_' then
      for i = capture:node():start_byte() + 1, capture:node():end_byte() do
        self.highlight_at[i] = capture:name()
      end
    end
    if self.is_stopping then return end
  end
  stderr.info(here, 'highlights done in ', math.floor(1e3 * (utils.timer() - start)), 'ms')

  local start = utils.timer()
  local cursor = treesitter.Query.Cursor.new(self.grammar.locals(), self.tree:root_node())
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
      scopes[#scopes].highlight_for[self.parser:read_node(capture:node())] = self.highlight_at[from]
      if self.is_debug then
        for i = from, to do
          self.debug_info_at[i] = self.debug_info_at[i] or capture:name()
        end
      end
    elseif capture:name() == 'local.reference' then
      local name = scopes[#scopes].highlight_for[self.parser:read_node(capture:node())]
      if name then
        for i = from, to do
          self.highlight_at[i] = name
        end
        if self.is_debug then
          for i = from, to do
            self.debug_info_at[i] = self.debug_info_at[i] or capture:name()
          end
        end
      end
    end

    if self.is_stopping then return end
  end
  stderr.info(here, 'locals done in ', math.floor(1e3 * (utils.timer() - start)), 'ms')
end

-- IDEA: type parameters

SyntaxHighlighter.base_fallbacks = {
  comment                = false,

  punctuation            = false,

  escape_sequence        = false,

  literal                = false,
  boolean_literal        = 'literal',
  character_literal      = 'literal',
  null_literal           = 'literal',
  number_literal         = 'literal',
  string_literal         = 'literal',
  symbol_literal         = 'literal',

  keyword                = false,
  operator               = 'keyword',
  matchfix_operator      = 'operator',
  member_access_operator = 'operator',
  type_keyword           = 'keyword',
  evaluation_branch      = 'keyword',
  evaluation_loop        = 'keyword',
  evaluation_end         = 'keyword',
  declaration            = 'keyword',
  declaration_modifier   = 'declaration',
  pragma                 = 'keyword',

  identifier             = false,
  variable               = 'identifier',
  constant               = 'variable',
  function_parameter     = 'variable',
  ['function']           = 'identifier',
  type                   = 'identifier',
  goto_label             = 'identifier',
}

function SyntaxHighlighter.generate_fallbacks(opts)
  local result = utils.copy(SyntaxHighlighter.base_fallbacks)

  local mem = { identifier = true }
  local function is_identifier(name)
    if mem[name] == nil and name then
      mem[name] = is_identifier(result[name])
    end
    return mem[name] or false
  end

  for name, _ in pairs(SyntaxHighlighter.base_fallbacks) do
    if is_identifier(name) then
      if opts.members and result[name] then
        result['member_' .. name] = 'member_' .. result[name]
      else
        result['member_' .. name] = name
      end
    end
  end

  local names = {}
  for name, _ in pairs(result) do
    table.insert(names, name)
  end

  for _, name in ipairs(names) do
    if is_identifier(name) then
      if opts.specials and result[name] then
        result['special_' .. name] = 'special_' .. result[name]
      else
        result['special_' .. name] = name
      end
    end
  end

  for _, name in ipairs(names) do
    if is_identifier(name) then
      if opts.builtins and result[name] then
        result['builtin_' .. name] = 'builtin_' .. result[name]
      else
        result['builtin_' .. name] = name
      end
    end
  end

  local names = {}
  for name, _ in pairs(result) do
    table.insert(names, name)
  end

  for _, name in ipairs(names) do
    if name ~= 'comment' and name ~= 'punctuation' then
      if opts.delimiters then
        result[name .. '_delimiter'] = result[name] and result[name] .. '_delimiter' or 'punctuation'
      else
        result[name .. '_delimiter'] = name
      end
    end
  end

  for _, name in ipairs(names) do
    if name ~= 'escape_sequence' then
      if opts.escape_sequences then
        result[name .. '_escape_sequence'] = result[name] and result[name] .. '_escape_sequence' or 'escape_sequence'
      else
        result[name .. '_escape_sequence'] = name
      end
    end
  end

  return result
end

function SyntaxHighlighter.apply_fallbacks(syntax_highlights, fallbacks)
  local function apply(name)
    if not syntax_highlights[name] and fallbacks[name] then
      apply(fallbacks[name])
      syntax_highlights[name] = syntax_highlights[fallbacks[name]]
    end
  end
  for name, _ in pairs(fallbacks) do
    apply(name)
  end
  return syntax_highlights
end

return SyntaxHighlighter
