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
local enchant    = require('core.enchant')
local stderr     = require('core.stderr')
local treesitter = require('core.treesitter')
local utils      = require('core.utils')

local SpellChecker = {
  broker = enchant.Broker.init(),
}
SpellChecker.__index = SpellChecker

function SpellChecker.of(buffer)
  if not buffer._spell_checker then
    buffer._spell_checker = SpellChecker.new(buffer)
  end
  return buffer._spell_checker
end

function SpellChecker.new(buffer)
  if not buffer.is_frozen then
    error('buffer is not frozen')
  end
  local self = setmetatable({
    buffer = buffer,
    is_correct = {},

    worker = nil,
    lock = thread.newlock(),
    is_stopping = false,
    parser = Parser.of(buffer),
    grammar = nil,
    tree = nil,
  }, SpellChecker)
  return self
end

function SpellChecker:refresh()
  self.parser:refresh()
  self.lock:acquire()
  if self.tree ~= self.parser.tree and not self.is_stopping then -- BUG: fails if no grammar
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

function SpellChecker:run()
  self.grammar = self.parser.grammar
  self.tree = self.parser.tree
  self.is_stopping = false

  -- The following sequence of environment variable accesses is apparently
  -- how gettext figures out what language to display system messages in.
  self.dict = self.broker:request_dict(self.buffer.doc.spell_checker_dict or os.getenv('LANGUAGE') or os.getenv('LC_ALL') or os.getenv('LC_MESSAGES') or os.getenv('LANG') or 'en')
  if not self.dict then return end

  local start = utils.timer()

  local idx = 1
  local iter = self.buffer:iter()
  local stack = {{ from = 1, to = #self.buffer, should_check = not self.tree }}

  local capture_iter = nil
  local next_capture = nil
  if self.tree then
    capture_iter = treesitter.Query.Runner.new(self.parser:get_predicates()):iter_captures(treesitter.Query.Cursor.new(self.grammar.spelling(), self.tree:root_node()))
    next_capture = capture_iter()
  end

  local word = ''
  local word_start
  local word_end
  local function flush_word()
    if #word > 0 and word_end then
      local is_correct = self.dict:check(word:sub(1, word_end - word_start + 1))
      for i = word_start, word_end do
        self.is_correct[i] = is_correct
      end
    end
    word = ''
  end

  while idx <= #self.buffer do
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
          if self.dict:is_word_character(codepoint, 2) then
            word_end = idx - 1
          end
          if self.dict:is_word_character(codepoint, 1) then
            word = word .. utf8.char(codepoint)
          else
            flush_word()
          end
        end

        if #word == 0 and self.dict:is_word_character(codepoint, 0) and word_end ~= idx - 1 then
          word = utf8.char(codepoint)
          word_start = idx - iter:last_advance()
          word_end = nil
        end
      end

    else
      flush_word()
      iter:skip(run_until + 1 - idx)
      idx = run_until + 1
    end
  end

  flush_word()

  stderr.info(here, 'spell checking done in ', math.floor(1e3 * (utils.timer() - start)), 'ms')
end

return SpellChecker
