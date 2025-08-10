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
local enchant    = require('core.enchant')
local stderr     = require('core.stderr')
local treesitter = require('core.treesitter')
local utils      = require('core.utils')

local SpellChecker = {
  broker = enchant.Broker.init(),
}
SpellChecker.__index = SpellChecker

function SpellChecker.new()
  return setmetatable({
    cache = setmetatable({}, { __mode = 'k' }),
    worker = nil,
    is_stopping = false,
    stopped_jobs = setmetatable({}, { __mode = 'k' }),
  }, SpellChecker)
end

function SpellChecker:does_need_run(buffer, tree, grammar)
  local worker = self.worker
  if worker and not worker.thread:join(0) and worker.buffer == buffer then
    local job = worker.job
    if job.tree == tree and job.grammar == grammar and job.dict == self:dict_for(buffer) then
      return false
    end
  end
  -- Checking the cache after the running job should be less data-racey
  -- because the condition below is set before the condition above is unset.
  local cached = self.cache[buffer]
  if cached and cached.is_complete and cached.tree == tree and cached.grammar == grammar and cached.dict == self:dict_for(buffer) then
    return false
  end
  return true
end

function SpellChecker:run(buffer, tree, grammar, callback)
  local worker = self.worker
  assert(not worker or worker.thread:join(0))

  local job = self.stopped_jobs[buffer]
  local dict = self:dict_for(buffer)
  if not job or job.tree ~= tree or job.grammar ~= grammar or job.dict ~= dict then
    job = {
      tree = tree,
      grammar = grammar,
      dict = dict,

      coroutine = coroutine.wrap(function()
        return self:check(buffer, tree, grammar, dict, true)
      end),
    }
  end

  self.worker = {
    buffer = buffer,
    job = job,
    thread = thread.new(
      xpcall,
      function()
        local is_correct = job.coroutine()
        if self.is_stopping then
          self.stopped_jobs[buffer] = job
        else
          callback(is_correct)
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

function SpellChecker:stop()
  local worker = self.worker
  if worker then
    self.is_stopping = true
    worker.thread:join()
    self.is_stopping = false
  end
end

function SpellChecker:cached_check_of(buffer)
  local cached = self.cache[buffer]
  if cached then
    return cached.is_complete, cached.is_correct
  else
    return true, nil
  end
end

function SpellChecker:check(buffer, tree, grammar, dict, is_async)
  assert(buffer.is_frozen)
  dict = dict or self:dict_for(buffer)
  local start = utils.timer()

  local cached = self.cache[buffer]
  if cached and cached.is_complete and cached.tree == tree and cached.grammar == grammar and cached.dict == dict then
    return cached.is_correct
  end

  local enchant_dict = self.broker:request_dict(dict)
  if not enchant_dict then
    self.cached[buffer] = nil
    return nil
  end

  local is_correct = {}
  self.cache[buffer] = {
    is_complete = false,
    is_correct = is_correct,

    tree = tree,
    grammar = grammar,
    dict = dict,
  }

  local idx = 1
  local iter = buffer:iter()
  local stack = {{ from = 1, to = #buffer, should_check = not tree }}

  local capture_iter = nil
  local next_capture = nil
  if tree then
    capture_iter = treesitter.Query.Runner.new(treesitter.predicates_with(function(node)
      return buffer:read(node:start_byte() + 1, node:end_byte())
    end)):iter_captures(treesitter.Query.Cursor.new(grammar.spelling(), tree:root_node()))
    next_capture = capture_iter()
  end

  local word = ''
  local word_start
  local word_end
  local function flush_word()
    if #word > 0 and word_end then
      local is_word_correct = enchant_dict:check(word:sub(1, word_end - word_start + 1))
      for i = word_start, word_end do
        is_correct[i] = is_word_correct
      end
    end
    word = ''
  end

  while idx <= #buffer do
    while idx > stack[#stack].to do
      table.remove(stack)
    end
    local run_until = math.maxinteger
    while next_capture do
      local from = next_capture:node():start_byte() + 1
      if idx < from then
        run_until = from - 1
        break
      end

      local to = next_capture:node():end_byte()
      if idx <= to then
        if next_capture:name() == 'check' then
          table.insert(stack, { from = from, to = to, should_check = true })
        elseif next_capture:name() == 'ignore' then
          table.insert(stack, { from = from, to = to, should_check = false })
        end
      end
      next_capture = capture_iter()
    end
    run_until = math.min(run_until, stack[#stack].to)

    if stack[#stack].should_check then
      while idx <= run_until do
        local ok, codepoint = pcall(iter.next_codepoint, iter)
        if not ok then
          codepoint = '�'
        end
        idx = idx + iter:last_advance()

        if #word > 0 then
          if enchant_dict:is_word_character(codepoint, 2) then
            word_end = idx - 1
          end
          if enchant_dict:is_word_character(codepoint, 1) then
            word = word .. utf8.char(codepoint)
          else
            flush_word()
          end
        end

        if #word == 0 and enchant_dict:is_word_character(codepoint, 0) and word_end ~= idx - 1 then
          word = utf8.char(codepoint)
          word_start = idx - iter:last_advance()
          word_end = nil
        end

        if is_async and self.is_stopping then
          coroutine.yield()
        end
      end

    else
      flush_word()
      iter:skip(run_until + 1 - idx)
      idx = run_until + 1
    end
  end

  flush_word()

  local millis = math.floor(1e3 * (utils.timer() - start))
  if millis > 100 then
    stderr.warn(here, 'slow check took ', millis, 'ms')
  end

  self.cache[buffer].is_complete = true
  return is_correct
end

function SpellChecker:dict_for(buffer)
  -- The following sequence of environment variable accesses is apparently
  -- how gettext figures out what language to display system messages in.
  return buffer.doc.spell_checker_dict or os.getenv('LANGUAGE') or os.getenv('LC_ALL') or os.getenv('LC_MESSAGES') or os.getenv('LANG') or 'en'
end

return SpellChecker
