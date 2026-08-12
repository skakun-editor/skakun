-- Skakun - A robust and hackable hex and text editor
-- Copyright (C) 2024-2026 Karol "digitcrusher" Łacina
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
local grapheme = require('core.grapheme')
local stderr   = require('core.stderr')
local tty      = require('core.tty')
local utils    = require('core.utils')

-- IDEA: styling as code, which would solve the issues of:
--       1. how to dim the interface when a popup is overlaid on top of it
--       2. generic style attributes removing the need to set them in every single widget's prototype
--       3. assigning different styles to a widget depending on whether it's in a popup or somewhere else
-- TODO: proper focus state signalling for all widgets

local ui = {
  is_running = true,
  idle_interval = 0.1,

  ctrl_pics = (function()
    local result = {
      ['\127'] = '␡',
      ['\r\n'] = '␍␊',
    }
    for i = 0x00, 0x1f do
      result[string.char(i)] = utf8.char(0x2400 + i)
    end
    for i = 0x80, 0x9f do
      result[utf8.char(i)] = '�'
    end
    result['\u{85}'] = '␤'
    return result
  end)(),

  button_syms = {
    ['escape'] = 'Esc',
    ['f1'] = 'F1',
    ['f2'] = 'F2',
    ['f3'] = 'F3',
    ['f4'] = 'F4',
    ['f5'] = 'F5',
    ['f6'] = 'F6',
    ['f7'] = 'F7',
    ['f8'] = 'F8',
    ['f9'] = 'F9',
    ['f10'] = 'F10',
    ['f11'] = 'F11',
    ['f12'] = 'F12',
    ['print_screen'] = 'PrtSc',
    ['scroll_lock'] = 'ScrlLock',
    ['pause'] = 'Pause',

    ['backtick'] = '`',
    ['1'] = '1',
    ['2'] = '2',
    ['3'] = '3',
    ['4'] = '4',
    ['5'] = '5',
    ['6'] = '6',
    ['7'] = '7',
    ['8'] = '8',
    ['9'] = '9',
    ['0'] = '0',
    ['minus'] = '-',
    ['equal'] = '=',
    ['backspace'] = 'Backspc',
    ['insert'] = 'Ins',
    ['home'] = 'Home',
    ['page_up'] = 'PgUp',

    ['tab'] = 'Tab',
    ['q'] = 'Q',
    ['w'] = 'W',
    ['e'] = 'E',
    ['r'] = 'R',
    ['t'] = 'T',
    ['y'] = 'Y',
    ['u'] = 'U',
    ['i'] = 'I',
    ['o'] = 'O',
    ['p'] = 'P',
    ['left_bracket'] = '[',
    ['right_bracket'] = ']',
    ['backslash'] = '\\',
    ['delete'] = 'Del',
    ['end'] = 'End',
    ['page_down'] = 'PgDn',

    ['caps_lock'] = 'CapsLock',
    ['a'] = 'A',
    ['s'] = 'S',
    ['d'] = 'D',
    ['f'] = 'F',
    ['g'] = 'G',
    ['h'] = 'H',
    ['j'] = 'J',
    ['k'] = 'K',
    ['l'] = 'L',
    ['semicolon'] = ';',
    ['apostrophe'] = '\'',
    ['enter'] = 'Enter',

    ['left_shift'] = 'LShift',
    ['z'] = 'Z',
    ['x'] = 'X',
    ['c'] = 'C',
    ['v'] = 'V',
    ['b'] = 'B',
    ['n'] = 'N',
    ['m'] = 'M',
    ['comma'] = ',',
    ['dot'] = '.',
    ['slash'] = '/',
    ['right_shift'] = 'RShift',
    ['up'] = 'Up',

    ['left_ctrl'] = 'LCtrl',
    ['left_super'] = 'LSuper',
    ['left_alt'] = 'LAlt',
    ['space'] = 'Space',
    ['right_alt'] = 'RAlt',
    ['right_super'] = 'RSuper',
    ['menu'] = 'Menu',
    ['right_ctrl'] = 'RCtrl',
    ['left'] = 'Left',
    ['down'] = 'Down',
    ['right'] = 'Right',

    ['num_lock'] = 'NumLock',
    ['kp_divide'] = 'KP/',
    ['kp_multiply'] = 'KP*',
    ['kp_subtract'] = 'KP-',
    ['kp_add'] = 'KP+',
    ['kp_enter'] = 'KPEnter',
    ['kp_1'] = 'KP1',
    ['kp_2'] = 'KP2',
    ['kp_3'] = 'KP3',
    ['kp_4'] = 'KP4',
    ['kp_5'] = 'KP5',
    ['kp_6'] = 'KP6',
    ['kp_7'] = 'KP7',
    ['kp_8'] = 'KP8',
    ['kp_9'] = 'KP9',
    ['kp_0'] = 'KP0',
    ['kp_decimal'] = 'KP.',

    ['mouse_left'] = 'LMB',
    ['mouse_middle'] = 'MMB',
    ['mouse_right'] = 'RMB',
    ['scroll_up'] = 'ScrlUp',
    ['scroll_down'] = 'ScrlDown',
    ['scroll_left'] = 'ScrlLeft',
    ['scroll_right'] = 'ScrlRght',
    ['mouse_prev'] = 'Back',
    ['mouse_next'] = 'Fwd',
  },

  modifier_syms = {
    alt = 'Alt+',
    ctrl = 'Ctrl+',
    shift = 'Shift+',
  },
}

function ui.run(root)
  local should_redraw = true
  local old_width, old_height

  ui.is_running = true
  while ui.is_running do
    local width, height = tty.get_size()
    if width ~= old_width or height ~= old_height then
      should_redraw = true
    end
    old_width = width
    old_height = height

    xpcall(
      root.set_bounds,
      function(err)
        stderr.error(here, debug.traceback(err, 2))
      end,
      root, 1, 1, width, height
    )

    if root.has_requested_draw then
      should_redraw = true
    end

    if should_redraw then
      should_redraw = false

      local start = utils.timer()
      tty.sync_begin()

      xpcall(
        root.draw,
        function(err)
          stderr.error(here, debug.traceback(err, 2))
        end,
        root
      )

      tty.sync_end()
      tty.flush()

      local micros = math.floor(1e6 * (utils.timer() - start))
      if micros >= 16000 then
        stderr.warn(here, 'slow redraw took ', micros, 'µs')
      end
    end

    xpcall(
      root.idle,
      function(err)
        stderr.error(here, debug.traceback(err, 2))
      end,
      root
    )

    tty.wait_for_read(ui.idle_interval)
    for _, event in ipairs(tty.read_events()) do
      local start = utils.timer()
      xpcall(
        root.handle_event,
        function(err)
          stderr.error(here, debug.traceback(err, 2))
        end,
        root, event
      )
      local micros = math.floor(1e6 * (utils.timer() - start))
      if micros >= 1000 then
        stderr.warn(here, 'slow event took ', micros, 'µs')
      end
    end
  end
end

function ui.stop()
  ui.is_running = false
end

function ui.draw_text(text, x, y, max_width, scroll, face, invalid_face)
  if max_width <= 0 or #text == 0 then
    return x, scroll
  end

  local written = 0
  tty.move_to(x, y)

  if scroll < 0 then
    written = math.min(max_width, -scroll)
    tty.set_face(face)
    tty.write((' '):rep(written))
  end

  local has_underflow, has_overflow = scroll > 0, false

  for _, grapheme in grapheme.characters(text) do
    local is_invalid = false
    if not utf8.len(grapheme) then
      grapheme = '�'
      is_invalid = true
    elseif ui.ctrl_pics[grapheme] then
      grapheme = ui.ctrl_pics[grapheme]
      is_invalid = true
    end

    local grapheme_width = tty.width_of(grapheme)
    scroll = scroll - grapheme_width
    if written >= max_width then
      has_overflow = true
    elseif scroll < 0 then
      if -scroll > max_width then
        grapheme = (' '):rep(max_width + scroll)
        written = written + max_width + scroll
        has_overflow = true
      elseif -scroll < grapheme_width then
        grapheme = (' '):rep(-scroll)
        written = written - scroll
      else
        written = written + grapheme_width
      end
      tty.set_face(is_invalid and invalid_face or face)
      tty.write(grapheme)
    end
  end

  if has_underflow or has_overflow then
    tty.set_face(face)
end

  if has_underflow then
    tty.move_to(x, y)
    tty.write('…')
  end

  if has_overflow then
    tty.move_to(x + max_width - 1, y)
    tty.write('…')
  elseif has_underflow then
    tty.move_to(x + written, y)
  end

  return x + written, scroll + written
end

function ui.text_width(text)
  local result = 0
  for _, grapheme in grapheme.characters(text) do
    result = result + tty.width_of(not utf8.len(grapheme) and '�' or ui.ctrl_pics[grapheme] or grapheme)
  end
  return result
end

return ui
