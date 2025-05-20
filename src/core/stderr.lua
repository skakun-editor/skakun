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

local stderr = {
  time_color = '\27[90;2m',
  level_colors = {
    error = '\27[22;31;1m',
    warn = '\27[22;33;1m',
    info = '\27[22;34;1m',
  },
  place_color = '\27[39m',
  text_color = '\27[0m',
}

function stderr.color_log(level, place, ...)
  stderr.print_indented(table.concat({
    stderr.time_color, os.date('%T'), ' ',
    stderr.level_colors[level], level, ' ',
    stderr.place_color, tostring(place), ': ',
    stderr.text_color,
  }), ...)
end
function stderr.plain_log(level, place, ...)
  stderr.print_indented(('%s %s %s: '):format(os.date('%T'), level, place), ...)
end
stderr.log = stderr.color_log

stderr.lock = thread.newlock()
function stderr.print_indented(indent, ...)
  stderr.lock:acquire()
  io.stderr:write(indent)
  local args = table.pack(...)
  args[args.n] = tostring(args[args.n]):gsub('\n+$', '')
  for i = 1, args.n do
    io.stderr:write((tostring(args[i]):gsub('\n', '\n' .. indent)))
  end
  io.stderr:write('\n')
  stderr.lock:release()
end

function stderr.error(place, ...) stderr.log('error', place, ...) end
function stderr.warn(place, ...) stderr.log('warn', place, ...) end
function stderr.info(place, ...) stderr.log('info', place, ...) end

return stderr
