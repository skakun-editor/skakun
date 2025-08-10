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

local Parser = {}
Parser.__index = Parser

function Parser.new()
  return setmetatable({
    cache = setmetatable({}, { __mode = 'k' }),
    worker = nil,
    is_stopping = false,
    stopped_jobs = setmetatable({}, { __mode = 'k' }),
  }, Parser)
end

function Parser:does_need_run(buffer)
  local worker = self.worker
  if worker and not worker.thread:join(0) and worker.buffer == buffer and worker.job.grammar == self:grammar_for(buffer) then
    return false
  end
  -- Checking the cache after the running job should be less data-racey
  -- because the condition below is set before the condition above is unset.
  local cached = self.cache[buffer]
  if cached and cached.grammar == self:grammar_for(buffer) then
    return false
  end
  return true
end

function Parser:run(buffer, callback)
  local worker = self.worker
  assert(not worker or worker:join(0))

  local job = self.stopped_jobs[buffer]
  local grammar = self:grammar_for(buffer)
  if not job or job.grammar ~= grammar then
    job = {
      grammar = grammar,
      coroutine = coroutine.wrap(function()
        return self:parse(buffer, grammar, true)
      end),
    }
  end

  self.worker = {
    buffer = buffer,
    job = job,
    thread = thread.new(
      xpcall,
      function()
        local tree, grammar = job.coroutine()
        if self.is_stopping then
          self.stopped_jobs[buffer] = job
        else
          callback(tree, grammar)
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

function Parser:stop()
  local worker = self.worker
  if worker then
    worker.thread:join()
  end
end

function Parser:cached_parse_of(buffer)
  local cached = self.cache[buffer]
  if cached then
    return true, cached.tree, cached.grammar
  else
    return true, nil, nil
  end
end

function Parser:parse(buffer, grammar, is_async)
  assert(buffer.is_frozen)
  grammar = grammar or self:grammar_for(buffer)
  local start = utils.timer()

  local cached = self.cache[buffer]
  if cached and cached.grammar == grammar then
    return cached.tree, cached.grammar
  end

  if not grammar then
    self.cache[buffer] = nil
    return nil, nil
  end

  local tree = nil
  if buffer.parent then
    local parent_tree, parent_grammar = self:parse(buffer.parent)
    if parent_grammar == grammar then
      tree = parent_tree:copy()
      local dummy = treesitter.Point.new(0, 0)
      for i = #buffer.parent_diff, 1, -1 do
        local edit = buffer.parent_diff[i]
        local idx = edit.old_idx - 1
        tree:edit(idx, idx + edit.old_len, idx + edit.new_len, dummy, dummy, dummy)
        if is_async and self.is_stopping then
          coroutine.yield()
        end
      end
    end
  end

  local parser = treesitter.Parser:new()
  parser:set_language(grammar.lang)
  tree = parser:parse(tree, function(idx)
    return buffer:read(idx + 1, math.min(idx + 1000000, #buffer))
  end)

  local millis = math.floor(1e3 * (utils.timer() - start))
  if millis > 20 then
    stderr.warn(here, 'slow parse took ', millis, 'ms')
  end

  self.cache[buffer] = {
    tree = tree,
    grammar = grammar,
  }
  return tree, grammar
end

function Parser:grammar_for(buffer)
  return treesitter.grammar_for_path(buffer.doc.path or '')
end

return Parser
