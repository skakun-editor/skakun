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

local SyntaxHighlighter = {
  is_debug = false,
}
SyntaxHighlighter.__index = SyntaxHighlighter

function SyntaxHighlighter.new()
  return setmetatable({
    cache = setmetatable({}, { __mode = 'k' }),
    worker = nil,
    is_stopping = false,
    stopped_jobs = setmetatable({}, { __mode = 'k' }),
  }, SyntaxHighlighter)
end


function SyntaxHighlighter:does_need_run(buffer, tree, grammar)
  local worker = self.worker
  if worker and not worker.thread:join(0) and worker.buffer == buffer then
    local job = worker.job
    if job.tree == tree and job.grammar == grammar then
      return false
    end
  end
  -- Checking the cache after the running job should be less data-racey
  -- because the condition below is set before the condition above is unset.
  local cached = self.cache[buffer]
  if cached and cached.is_complete and cached.tree == tree and cached.grammar == grammar then
    return false
  end
  return true
end

function SyntaxHighlighter:run(buffer, tree, grammar, callback)
  local worker = self.worker
  assert(not worker or worker.thread:join(0))

  local job = self.stopped_jobs[buffer]
  if not job or job.tree ~= tree or job.grammar ~= grammar then
    job = {
      tree = tree,
      grammar = grammar,

      coroutine = coroutine.wrap(function()
        return self:highlight(buffer, tree, grammar, true)
      end),
    }
  end

  self.worker = {
    buffer = buffer,
    job = job,
    thread = thread.new(
      xpcall,
      function()
        local highlight_at, debug_info_at = job.coroutine()
        if self.is_stopping then
          self.stopped_jobs[buffer] = job
        else
          callback(highlight_at, debug_info_at)
        end
        self.worker = nil
      end,
      function(err)
        stderr.error(here, debug.traceback(err, 2))
        self.worker = nil
      end
    ),
  }
end

function SyntaxHighlighter:stop()
  local worker = self.worker
  if worker then
    self.is_stopping = true
    worker.thread:join()
    self.is_stopping = false
  end
end

function SyntaxHighlighter:cached_highlight_of(buffer)
  local cached = self.cache[buffer]
  if cached then
    return cached.is_complete, cached.highlight_at, cached.debug_info_at
  else
    return true, nil, nil
  end
end

function SyntaxHighlighter:highlight(buffer, tree, grammar, is_async)
  assert(buffer.is_frozen)

  local cached = self.cache[buffer]
  if cached and cached.is_complete and cached.tree == tree and cached.grammar == grammar then
    return cached.highlight_at, cached.debug_info_at
  end

  local highlight_at = {}
  local debug_info_at = self.is_debug and {} or nil
  self.cache[buffer] = {
    is_complete = false,
    highlight_at = highlight_at,
    debug_info_at = debug_info_at,

    tree = tree,
    grammar = grammar,
  }

  local parent = buffer.parent
  while parent do
    local cached = self.cache[parent]
    if self.cache[parent] then
      highlight_at = setmetatable(highlight_at, { __index = self.cache[parent].highlight_at })
      break
    end
    parent = parent.parent
  end

  local function read_node(node)
    return buffer:read(node:start_byte() + 1, node:end_byte())
  end
  local runner = treesitter.Query.Runner.new(treesitter.predicates_with(read_node))

  local start = utils.timer()
  for capture in runner:iter_captures(treesitter.Query.Cursor.new(grammar.highlights(), tree:root_node())) do
    if capture:name():sub(1, 1) ~= '_' then
      for i = capture:node():start_byte() + 1, capture:node():end_byte() do
        highlight_at[i] = capture:name()
      end
    end

    if is_async and self.is_stopping then
      coroutine.yield()
    end
  end
  local millis = math.floor(1e3 * (utils.timer() - start))
  if millis > 200 then
    stderr.warn(here, 'slow highlights took ', millis, 'ms')
  end

  local start = utils.timer()
  local scopes = {
    {
      from = 1,
      to = math.maxinteger,
      highlight_for = {},
    },
  }
  for capture in runner:iter_captures(treesitter.Query.Cursor.new(grammar.locals(), tree:root_node())) do
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
      scopes[#scopes].highlight_for[read_node(capture:node())] = highlight_at[from]
      if debug_info_at then
        for i = from, to do
          debug_info_at[i] = debug_info_at[i] or capture:name()
        end
      end
    elseif capture:name() == 'local.reference' then
      local name = scopes[#scopes].highlight_for[read_node(capture:node())]
      if name then
        for i = from, to do
          highlight_at[i] = name
        end
        if debug_info_at then
          for i = from, to do
            debug_info_at[i] = debug_info_at[i] or capture:name()
          end
        end
      end
    end

    if is_async and self.is_stopping then
      coroutine.yield()
    end
  end
  local millis = math.floor(1e3 * (utils.timer() - start))
  if millis > 50 then
    stderr.warn(here, 'slow locals took ', millis, 'ms')
  end

  local metatable = getmetatable(highlight_at)
  if metatable then
    metatable.__index = nil
  end
  self.cache[buffer].is_complete = true
  return highlight_at, debug_info_at
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
  evaluation_yield       = 'keyword',
  evaluation_delay       = 'keyword',
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
