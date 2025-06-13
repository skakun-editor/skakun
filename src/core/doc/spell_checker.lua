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
local enchant = require('core.enchant')
local stderr  = require('core.stderr')
local utils   = require('core.utils')

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
  }, SpellChecker)
  self.worker = thread.new(xpcall, self.run, function(err)
    stderr.error(here, debug.traceback(err))
  end, self)
  return self
end

function SpellChecker:run()
  -- The following sequence of environment variable accesses is apparently
  -- how gettext figures out what language to display system messages in.
  self.dict = self.broker:request_dict(self.buffer.doc.spell_checker_dict or os.getenv('LANGUAGE') or os.getenv('LC_ALL') or os.getenv('LC_MESSAGES') or os.getenv('LANG') or 'en')
  if not self.dict then return end

  local start = utils.timer()
  local word = ''
  local word_start = 1
  local word_end = 1
  local iter = self.buffer:iter(word_start)
  while true do
    local ok, codepoint = pcall(iter.next_codepoint, iter)
    if not ok or not codepoint then break end

    if self.dict:is_word_character(codepoint, #word == 0 and 0 or 1) then
      word = word .. utf8.char(codepoint)
      if self.dict:is_word_character(codepoint, 2) then
        word_end = word_start + #word - 1
      end
    elseif #word > 0 then
      local is_correct = self.dict:check(word:sub(1, word_end - word_start + 1))
      for i = word_start, word_end do
        self.is_correct[i] = is_correct
      end
      iter:rewind(word_start + #word + iter:last_advance() - word_end - 1)
      word = ''
      word_start = word_end + 1
      word_end = word_start
    else
      word_start = word_start + iter:last_advance()
      word_end = word_start
    end
  end
  stderr.info(here, 'spell checking done in ', math.floor(1e3 * (utils.timer() - start)), 'ms')
end

return SpellChecker
