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

local Action = {
  button_symbols = {
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

  mod_symbols = {
    alt = 'Alt+',
    ctrl = 'Ctrl+',
    shift = 'Shift+',
  },
}
Action.__index = Action

function Action.new(id, name, desc, activation_hint, is_activated_by_event, activate)
  return setmetatable({
    button_symbols = setmetatable({}, { __index = Action.button_symbols }),

    widget = nil,
    id = id,
    name = name,
    desc = desc,
    activation_hint = activation_hint,
    is_activated_by_event = is_activated_by_event,
    activate = activate,
  }, Action)
end

function Action.new_simple(id, name, desc, mod_button, activate)
  local self = Action.new(id, name, desc, nil, nil, activate)
  self:set_activation_button(mod_button)
  return self
end

function Action:set_activation_button(mod_button)
  local alt, ctrl, shift = false, false, false
  while true do
    local mod, button = mod_button:match('([^+]*)%+(.*)')
    if not mod then break end
    if mod == 'alt' then
      alt = true
    elseif mod == 'ctrl' then
      ctrl = true
    elseif mod == 'shift' then
      shift = true
    else
      error(('unknown modifier: %s'):format(mod))
    end
    mod_button = button
  end

  function self:activation_hint()
    return (ctrl and self.mod_symbols.ctrl or '') .. (shift and self.mod_symbols.shift or '') .. (alt and self.mod_symbols.alt or '') .. self.button_symbols[mod_button]
  end
  -- HACK: this functionality should be separated out into a method for events but I haven't figured out yet how to smoothly integrate that into the rest of the tty code
  function self:is_activated_by_event(event)
    return (event.type == 'press' or event.type == 'repeat') and event.button == mod_button and event.alt == alt and event.ctrl == ctrl and event.shift == shift
  end
end

function Action:activation_hint()
  return nil
end

function Action:is_activated_by_event(event)
  return false
end

function Action:activate(event) end

return Action
