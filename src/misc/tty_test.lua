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

local tty   = require('core.tty')
local utils = require('core.utils')
local rgb = tty.Rgb.from

tty.clear()

-- Everything
tty.move_to(40, 10)
tty.set_foreground('black')
tty.set_background(rgb'ff00bf')
tty.set_bold(true)
tty.set_italic(true)
tty.set_underline(true)
tty.set_underline_color('red')
tty.set_underline_shape('curly')
tty.set_strikethrough(true)
tty.set_hyperlink('https://example.com/')
tty.write('czesc okej!!!')
tty.reset()
tty.move_to(1, 1)

-- True colors
local function hue_color(hue)
  return {
    red   = math.floor(255 * math.min(math.max(2 - 4 * hue, 0), 1)),
    green = math.floor(255 * math.min(2 - math.abs(4 * hue - 2), 1)),
    blue  = math.floor(255 * math.min(math.max(4 * hue - 2, 0), 1)),
  }
end
local width = tty.getnum('cols')()
for i = 1, width do
  local progress = (i - 1) / (width - 1)
  tty.set_foreground(hue_color(progress))
  tty.set_background(hue_color(1 - progress))
  tty.write('▄')
end
tty.set_foreground()
tty.set_background()

-- List the terminal's capabilities
for key, value in pairs(tty.cap) do
  tty.set_bold(true)
  tty.write(key)
  tty.set_bold(false)
  tty.write('=', tostring(value), ' ')
end
tty.write('\r\n')

-- ANSI colors
for _, bg in ipairs(tty.ansi_colors) do
  tty.set_background(bg)
  for _, fg in ipairs(tty.ansi_colors) do
    tty.set_foreground(fg)
    tty.write('•')
  end
  tty.set_foreground()
  tty.set_background()
  tty.write(' ', bg, '\r\n')
end

-- Bold, italic, underline, strikethrough, hyperlink
tty.set_bold(true)
tty.write('bold')
tty.set_bold()
tty.write(' ')

tty.set_italic(true)
tty.write('italic')
tty.set_italic()
tty.write(' ')

tty.set_underline(true)
tty.write('un')
tty.set_underline_color('magenta')
tty.write('der')
tty.set_underline_color(rgb'ff00bf')
tty.write('line')
tty.set_underline()
tty.set_underline_color()
tty.write(' ')

tty.set_strikethrough(true)
tty.write('strikethrough')
tty.set_strikethrough()
tty.write(' ')

tty.set_hyperlink('https://example.com/')
tty.write('hyperlink')
tty.set_hyperlink()
tty.write(' ')

tty.write('\r\n')

-- Underline shapes
for _, name in pairs(tty.underline_shapes) do
  tty.set_underline_shape(name)
  tty.set_underline(true)
  tty.write(name)
  tty.set_underline()
  tty.write(' ')
end
tty.write('\r\n')

-- Mouse shapes part 1
tty.set_mouse_shape('wait')

-- ANSI-color window background
if tty.cap.window_background == 'true_color' or tty.cap.window_background == 'ansi' then
  for _, name in pairs(tty.ansi_colors) do
    tty.set_window_background(name)
    tty.flush()
    os.execute('sleep 0.4')
  end
  tty.set_window_background()
end

-- True-color window background
if tty.cap.window_background == 'true_color' then
  local start = utils.timer()
  while true do
    local progress = (utils.timer() - start) / 3
    if progress > 1 then break end
    tty.set_window_background(hue_color(progress))
    tty.flush()
  end
  tty.set_window_background()
end

-- Mouse shapes part 2
tty.set_mouse_shape('default')

-- Keyboard input
tty.write('Press ')
tty.set_italic(true)
tty.write('enter')
tty.set_italic(false)
tty.write(' to proceed to the next part of the experiment.')
tty.flush()
while (tty.read_events()[1] or {}).button ~= 'enter' do end
tty.write('\r\n')

-- All events, cursor shapes and window title
tty.write('Good job! Now you may press ')
tty.set_italic(true)
tty.write('escape')
tty.set_italic()
tty.write(' to quit.\r\n')

for i = 1, math.huge do
  local events = tty.read_events()
  for _, event in ipairs(events) do
    tty.write(event.type, '\t')

    if event.alt then tty.write('alt+') end
    if event.ctrl then tty.write('ctrl+') end
    if event.shift then tty.write('shift+') end
    if event.button then
      tty.write(event.button, '\t')
    end

    if event.text then
      tty.write('‘', event.text:gsub('\r\n', '\n'):gsub('\r', '\n'):gsub('\n', '\r\n'), '’')
    end

    if event.x or event.y then
      tty.write(tostring(event.x), ' ', tostring(event.y))
    end

    tty.write('\r\n')
  end
  if (events[1] or {}).button == 'escape' then break end

  tty.set_cursor_shape(tty.cursor_shapes[i % #tty.cursor_shapes + 1])
  tty.set_window_title('The time is: ' .. os.date())
  tty.flush()
end
