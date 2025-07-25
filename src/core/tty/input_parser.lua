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
local stderr = require('core.stderr')

local InputParser = {
  dispatch_list = {
    'take_mouse',
    'take_kitty_key',
    'take_functional_key',
    'take_functional_key_with_mods',
    'take_shift_tab',
    'take_paste',
    'drop_kitty_functional_key',
    'take_key',
    'take_codepoint',
  },

  keymap = {
    [  0] = { button = 'space', ctrl = true },
    [  1] = { button = 'a', ctrl = true },
    [  2] = { button = 'b', ctrl = true },
    [  3] = { button = 'c', ctrl = true },
    [  4] = { button = 'd', ctrl = true },
    [  5] = { button = 'e', ctrl = true },
    [  6] = { button = 'f', ctrl = true },
    [  7] = { button = 'g', ctrl = true },
    [  8] = { button = 'backspace', ctrl = true },
    [  9] = { button = 'tab', text = '\t' },
    [ 10] = { button = 'j', ctrl = true },
    [ 11] = { button = 'k', ctrl = true },
    [ 12] = { button = 'l', ctrl = true },
    [ 13] = { button = 'enter', text = '\n' },
    [ 14] = { button = 'n', ctrl = true },
    [ 15] = { button = 'o', ctrl = true },
    [ 16] = { button = 'p', ctrl = true },
    [ 17] = { button = 'q', ctrl = true },
    [ 18] = { button = 'r', ctrl = true },
    [ 19] = { button = 's', ctrl = true },
    [ 20] = { button = 't', ctrl = true },
    [ 21] = { button = 'u', ctrl = true },
    [ 22] = { button = 'v', ctrl = true },
    [ 23] = { button = 'w', ctrl = true },
    [ 24] = { button = 'x', ctrl = true },
    [ 25] = { button = 'y', ctrl = true },
    [ 26] = { button = 'z', ctrl = true },
    [ 27] = { button = 'escape' },
    [ 28] = { button = 'backslash', ctrl = true },
    [ 29] = { button = 'right_bracket', ctrl = true },
    [ 30] = { button = 'backtick', ctrl = true, shift = true },
    [ 31] = { button = 'slash', ctrl = true },
    [ 32] = { button = 'space', text = ' ' },
    [127] = { button = 'backspace' },
    -- These depend on the system keyboard layout, unlike the ones above:
    [ 33] = { button = '1', shift = true, text = '!' },
    [ 34] = { button = 'apostrophe', shift = true, text = '"' },
    [ 35] = { button = '3', shift = true, text = '#' },
    [ 36] = { button = '4', shift = true, text = '$' },
    [ 37] = { button = '5', shift = true, text = '%' },
    [ 38] = { button = '7', shift = true, text = '&' },
    [ 39] = { button = 'apostrophe', text = "'" },
    [ 40] = { button = '9', shift = true, text = '(' },
    [ 41] = { button = '0', shift = true, text = ')' },
    [ 42] = { button = '8', shift = true, text = '*' },
    [ 43] = { button = 'equal', shift = true, text = '+' },
    [ 44] = { button = 'comma', text = ',' },
    [ 45] = { button = 'minus', text = '-' },
    [ 46] = { button = 'dot', text = '.' },
    [ 47] = { button = 'slash', text = '/' },
    [ 48] = { button = '0', text = '0' },
    [ 49] = { button = '1', text = '1' },
    [ 50] = { button = '2', text = '2' },
    [ 51] = { button = '3', text = '3' },
    [ 52] = { button = '4', text = '4' },
    [ 53] = { button = '5', text = '5' },
    [ 54] = { button = '6', text = '6' },
    [ 55] = { button = '7', text = '7' },
    [ 56] = { button = '8', text = '8' },
    [ 57] = { button = '9', text = '9' },
    [ 58] = { button = 'semicolon', shift = true, text = ':' },
    [ 59] = { button = 'semicolon', text = ';' },
    [ 60] = { button = 'comma', shift = true, text = '<' },
    [ 61] = { button = 'equal', text = '=' },
    [ 62] = { button = 'dot', shift = true, text = '>' },
    [ 63] = { button = 'slash', shift = true, text = '?' },
    [ 64] = { button = '2', shift = true, text = '@' },
    [ 65] = { button = 'a', shift = true, text = 'A' },
    [ 66] = { button = 'b', shift = true, text = 'B' },
    [ 67] = { button = 'c', shift = true, text = 'C' },
    [ 68] = { button = 'd', shift = true, text = 'D' },
    [ 69] = { button = 'e', shift = true, text = 'E' },
    [ 70] = { button = 'f', shift = true, text = 'F' },
    [ 71] = { button = 'g', shift = true, text = 'G' },
    [ 72] = { button = 'h', shift = true, text = 'H' },
    [ 73] = { button = 'i', shift = true, text = 'I' },
    [ 74] = { button = 'j', shift = true, text = 'J' },
    [ 75] = { button = 'k', shift = true, text = 'K' },
    [ 76] = { button = 'l', shift = true, text = 'L' },
    [ 77] = { button = 'm', shift = true, text = 'M' },
    [ 78] = { button = 'n', shift = true, text = 'N' },
    [ 79] = { button = 'o', shift = true, text = 'O' },
    [ 80] = { button = 'p', shift = true, text = 'P' },
    [ 81] = { button = 'q', shift = true, text = 'Q' },
    [ 82] = { button = 'r', shift = true, text = 'R' },
    [ 83] = { button = 's', shift = true, text = 'S' },
    [ 84] = { button = 't', shift = true, text = 'T' },
    [ 85] = { button = 'u', shift = true, text = 'U' },
    [ 86] = { button = 'v', shift = true, text = 'V' },
    [ 87] = { button = 'w', shift = true, text = 'W' },
    [ 88] = { button = 'x', shift = true, text = 'X' },
    [ 89] = { button = 'y', shift = true, text = 'Y' },
    [ 90] = { button = 'z', shift = true, text = 'Z' },
    [ 91] = { button = 'left_bracket', text = '[' },
    [ 92] = { button = 'backslash', text = '\\' },
    [ 93] = { button = 'right_bracket', text = ']' },
    [ 94] = { button = '6', shift = true, text = '^' },
    [ 95] = { button = 'minus', shift = true, text = '_' },
    [ 96] = { button = 'backtick', text = '`' },
    [ 97] = { button = 'a', text = 'a' },
    [ 98] = { button = 'b', text = 'b' },
    [ 99] = { button = 'c', text = 'c' },
    [100] = { button = 'd', text = 'd' },
    [101] = { button = 'e', text = 'e' },
    [102] = { button = 'f', text = 'f' },
    [103] = { button = 'g', text = 'g' },
    [104] = { button = 'h', text = 'h' },
    [105] = { button = 'i', text = 'i' },
    [106] = { button = 'j', text = 'j' },
    [107] = { button = 'k', text = 'k' },
    [108] = { button = 'l', text = 'l' },
    [109] = { button = 'm', text = 'm' },
    [110] = { button = 'n', text = 'n' },
    [111] = { button = 'o', text = 'o' },
    [112] = { button = 'p', text = 'p' },
    [113] = { button = 'q', text = 'q' },
    [114] = { button = 'r', text = 'r' },
    [115] = { button = 's', text = 's' },
    [116] = { button = 't', text = 't' },
    [117] = { button = 'u', text = 'u' },
    [118] = { button = 'v', text = 'v' },
    [119] = { button = 'w', text = 'w' },
    [120] = { button = 'x', text = 'x' },
    [121] = { button = 'y', text = 'y' },
    [122] = { button = 'z', text = 'z' },
    [123] = { button = 'left_bracket', shift = true, text = '{' },
    [124] = { button = 'backslash', shift = true, text = '|' },
    [125] = { button = 'right_bracket', shift = true, text = '}' },
    [126] = { button = 'backtick', shift = true, text = '~' },
  },

  kitty_keycodes = {
    [   27] = 'escape',
    [57361] = 'print_screen',
    [57359] = 'scroll_lock',
    [57362] = 'pause',

    [   96] = 'backtick',
    [   49] = '1',
    [   50] = '2',
    [   51] = '3',
    [   52] = '4',
    [   53] = '5',
    [   54] = '6',
    [   55] = '7',
    [   56] = '8',
    [   57] = '9',
    [   48] = '0',
    [   45] = 'minus',
    [   61] = 'equal',
    [  127] = 'backspace',

    [    9] = 'tab',
    [  113] = 'q',
    [  119] = 'w',
    [  101] = 'e',
    [  114] = 'r',
    [  116] = 't',
    [  121] = 'y',
    [  117] = 'u',
    [  105] = 'i',
    [  111] = 'o',
    [  112] = 'p',
    [   91] = 'left_bracket',
    [   93] = 'right_bracket',
    [   92] = 'backslash',

    [57358] = 'caps_lock',
    [   97] = 'a',
    [  115] = 's',
    [  100] = 'd',
    [  102] = 'f',
    [  103] = 'g',
    [  104] = 'h',
    [  106] = 'j',
    [  107] = 'k',
    [  108] = 'l',
    [   59] = 'semicolon',
    [   39] = 'apostrophe',
    [   13] = 'enter',

    [57441] = 'left_shift',
    [  122] = 'z',
    [  120] = 'x',
    [   99] = 'c',
    [  118] = 'v',
    [   98] = 'b',
    [  110] = 'n',
    [  109] = 'm',
    [   44] = 'comma',
    [   46] = 'dot',
    [   47] = 'slash',
    [57447] = 'right_shift',

    [57442] = 'left_ctrl',
    [57444] = 'left_super',
    [57443] = 'left_alt',
    [   32] = 'space',
    [57449] = 'right_alt',
    [57453] = 'right_alt',
    [57450] = 'right_super',
    [57363] = 'menu',
    [57448] = 'right_ctrl',

    [57360] = 'num_lock',
    [57410] = 'kp_divide',
    [57411] = 'kp_multiply',
    [57412] = 'kp_subtract',
    [57413] = 'kp_add',
    [57414] = 'kp_enter',
    [57400] = 'kp_1',
    [57424] = 'kp_1',
    [57401] = 'kp_2',
    [57420] = 'kp_2',
    [57402] = 'kp_3',
    [57422] = 'kp_3',
    [57403] = 'kp_4',
    [57417] = 'kp_4',
    [57404] = 'kp_5',
    [57405] = 'kp_6',
    [57418] = 'kp_6',
    [57406] = 'kp_7',
    [57423] = 'kp_7',
    [57407] = 'kp_8',
    [57419] = 'kp_8',
    [57408] = 'kp_9',
    [57421] = 'kp_9',
    [57399] = 'kp_0',
    [57425] = 'kp_0',
    [57416] = 'kp_decimal',
    [57426] = 'kp_decimal',
  },
}
InputParser.__index = InputParser

function InputParser.new()
  return setmetatable({
    dispatch_list = setmetatable({}, { __index = InputParser.dispatch_list }),
    keymap = setmetatable({}, { __index = InputParser.keymap }),
    kitty_keycodes = setmetatable({}, { __index = InputParser.kitty_keycodes }),

    buf = '',
    is_pressed = {},
  }, InputParser)
end

function InputParser:feed(string)
  self.buf = self.buf .. string

  local result = {}

  local i = 1
  while i <= #self.buf do
    local events
    for _, method_name in ipairs(self.dispatch_list) do
      events, i = self[method_name](self, self.buf, i)
      if events then break end
    end
    if not events then break end

    for _, event in ipairs(events) do
      if event.type == 'press' then
        if self.is_pressed[event.button] then
          event.type = 'repeat'
        else
          self.is_pressed[event.button] = true
        end
      elseif event.type == 'release' then
        self.is_pressed[event.button] = false
      end

      table.insert(result, event)
    end
  end
  self.buf = self.buf:sub(i)

  return result
end

function InputParser:take_mouse(buf, offset)
  -- Reference: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h2-Mouse-Tracking
  local bits, x, y, event, new_offset = buf:match('^\27%[<(%d+);(%d+);(%d+)([Mm])()', offset)
  if not event then
    return nil, offset
  end

  x = tonumber(x)
  y = tonumber(y)
  bits = tonumber(bits)
  if bits & 32 ~= 0 then
    return {{ type = 'move', x = x, y = y }}, new_offset
  end

  local shift = bits & 4 ~= 0
  local alt = bits & 8 ~= 0
  local ctrl = bits & 16 ~= 0
  local button = ({
    [0] = 'mouse_left',
    [1] = 'mouse_middle',
    [2] = 'mouse_right',
    [64] = 'scroll_up',
    [65] = 'scroll_down',
    [66] = 'scroll_left',
    [67] = 'scroll_right',
    [128] = 'mouse_prev',
    [129] = 'mouse_next',
  })[bits & ~28]
  if not button then
    stderr.warn(here, 'unknown mouse button: ', bits & ~28)
    return {}, new_offset
  end

  if button:find('scroll', 1, true) then
    return {
      { type = 'press',   button = button, alt = alt, ctrl = ctrl, shift = shift, x = x, y = y },
      { type = 'release', button = button, alt = alt, ctrl = ctrl, shift = shift, x = x, y = y },
    }, new_offset
  else
    return {{ type = event == 'M' and 'press' or 'release', button = button, alt = alt, ctrl = ctrl, shift = shift, x = x, y = y }}, new_offset
  end
end

function InputParser:take_kitty_key(buf, offset)
  -- Reference: https://sw.kovidgoyal.net/kitty/keyboard-protocol/
  -- Honestly, this protocol is so half-baked. How am I supposed to distinguish
  -- the "new" \27[A from the old \27[A and so on??? Oh, right. I have to send
  -- yet another terminal query across the Atlantic… And are we really going to
  -- ignore the monster dwelling below?

  local keycode, mods, event, codepoint, new_offset

  keycode, new_offset = buf:match('^\27%[(%d+)u()', offset)

  if not keycode then keycode, codepoint, new_offset = buf:match('^\27%[(%d+);;(%d+)u()', offset) end
  if not keycode then keycode, codepoint, new_offset = buf:match('^\27%[%d+::(%d+);;(%d+)u()', offset) end

  if not keycode then codepoint = nil end
  if not keycode then keycode, mods, new_offset = buf:match('^\27%[(%d+);(%d+)u()', offset) end
  if not keycode then keycode, mods, new_offset = buf:match('^\27%[(%d+):%d+;(%d+)u()', offset) end
  if not keycode then keycode, mods, new_offset = buf:match('^\27%[%d+::(%d+);(%d+)u()', offset) end

  if not keycode then keycode, mods, codepoint, new_offset = buf:match('^\27%[(%d+);(%d+);(%d+)u()', offset) end
  if not keycode then keycode, mods, codepoint, new_offset = buf:match('^\27%[(%d+):%d+;(%d+);(%d+)u()', offset) end
  if not keycode then keycode, mods, codepoint, new_offset = buf:match('^\27%[%d+::(%d+);(%d+);(%d+)u()', offset) end

  if not keycode then codepoint = nil end
  if not keycode then keycode, mods, event, new_offset = buf:match('^\27%[(%d+);(%d+):(%d)u()', offset) end
  if not keycode then keycode, mods, event, new_offset = buf:match('^\27%[(%d+):%d+;(%d+):(%d)u()', offset) end
  if not keycode then keycode, mods, event, new_offset = buf:match('^\27%[%d+::(%d+);(%d+):(%d)u()', offset) end

  if not keycode then keycode, mods, event, codepoint, new_offset = buf:match('^\27%[(%d+);(%d+):(%d);(%d+)u()', offset) end
  if not keycode then keycode, mods, event, codepoint, new_offset = buf:match('^\27%[(%d+):%d+;(%d+):(%d);(%d+)u()', offset) end
  if not keycode then keycode, mods, event, codepoint, new_offset = buf:match('^\27%[%d+::(%d+);(%d+):(%d);(%d+)u()', offset) end

  if not keycode then
    return nil, offset
  end

  local type
  if event == '1' or not event then
    type = 'press'
  elseif event == '2' then
    type = 'repeat'
  else
    type = 'release'
  end
  local button = self.kitty_keycodes[tonumber(keycode)]
  mods = mods and tonumber(mods) - 1 or 0

  if button then
    return {{
      type = type,
      button = button,
      alt = mods & 2 ~= 0,
      ctrl = mods & 4 ~= 0,
      shift = mods & 1 ~= 0,
      text = codepoint and utf8.char(codepoint),
    }}, new_offset
  elseif codepoint then
    stderr.warn(here, 'unknown kitty keycode: ', keycode)
    return {{ type = 'paste', text = utf8.char(codepoint) }}, new_offset
  else
    return {}, new_offset
  end
end

function InputParser:take_functional_key(buf, offset)
  local seq = buf:match('^\27[O%[]%d*.', offset)
  local button = ({
    ['\27OP'] = 'f1',
    ['\27OQ'] = 'f2',
    ['\27OR'] = 'f3',
    ['\27OS'] = 'f4',
    ['\27[15~'] = 'f5',
    ['\27[17~'] = 'f6',
    ['\27[18~'] = 'f7',
    ['\27[19~'] = 'f8',
    ['\27[20~'] = 'f9',
    ['\27[21~'] = 'f10',
    ['\27[23~'] = 'f11',
    ['\27[24~'] = 'f12',
    ['\27[29~'] = 'menu',
    ['\27[2~'] = 'insert',
    ['\27[3~'] = 'delete',
    ['\27[H'] = 'home',
    ['\27[F'] = 'end',
    ['\27[5~'] = 'page_up',
    ['\27[6~'] = 'page_down',
    ['\27[A'] = 'up',
    ['\27[D'] = 'left',
    ['\27[B'] = 'down',
    ['\27[C'] = 'right',
    ['\27Oo'] = 'kp_divide',
    ['\27Oj'] = 'kp_multiply',
    ['\27Om'] = 'kp_subtract',
    ['\27Ok'] = 'kp_add',
    ['\27OM'] = 'kp_enter',
    ['\27[E'] = 'kp_5',
    -- In Kitty's "enhanced" keyboard protocol mode:
    ['\27[P'] = 'f1',
    ['\27[Q'] = 'f2',
    ['\27[13~'] = 'f3',
    ['\27[S'] = 'f4',
  })[seq]

  if button then
    return {
      { type = 'press',   button = button, alt = false, ctrl = false, shift = false },
      { type = 'release', button = button, alt = false, ctrl = false, shift = false },
    }, offset + #seq
  else
    return nil, offset
  end
end

function InputParser:take_functional_key_with_mods(buf, offset)
  local keycode1, mods, keycode2, new_offset = buf:match('^\27(%[%d+;)(%d+)(.)()', offset)
  if not new_offset then
    keycode1, mods, keycode2, new_offset = buf:match('^\27(O)(%d+)(.)()', offset)
  end
  if not new_offset then
    return nil, offset
  end

  mods = tonumber(mods) - 1
  local shift = mods & 1 ~= 0
  local alt = mods & 2 ~= 0
  local ctrl = mods & 4 ~= 0
  local button = ({
    ['[1; P'] = 'f1',
    ['[1; Q'] = 'f2',
    ['[1; R'] = 'f3',
    ['[1; S'] = 'f4',
    ['[15; ~'] = 'f5',
    ['[17; ~'] = 'f6',
    ['[18; ~'] = 'f7',
    ['[19; ~'] = 'f8',
    ['[20; ~'] = 'f9',
    ['[21; ~'] = 'f10',
    ['[23; ~'] = 'f11',
    ['[24; ~'] = 'f12',
    ['[29; ~'] = 'menu',
    ['[2; ~'] = 'insert',
    ['[3; ~'] = 'delete',
    ['[1; H'] = 'home',
    ['[1; F'] = 'end',
    ['[5; ~'] = 'page_up',
    ['[6; ~'] = 'page_down',
    ['[1; A'] = 'up',
    ['[1; D'] = 'left',
    ['[1; B'] = 'down',
    ['[1; C'] = 'right',
    ['O o'] = 'kp_divide',
    ['O j'] = 'kp_multiply',
    ['O m'] = 'kp_subtract',
    ['O k'] = 'kp_add',
    ['O M'] = 'kp_enter',
    ['[1; E'] = 'kp_5',
    -- On Konsole:
    ['O P'] = 'f1',
    ['O Q'] = 'f2',
    ['O R'] = 'f3',
    ['O S'] = 'f4',
    -- On Kitty:
    ['[13; ~'] = 'f3',
  })[keycode1 .. ' ' .. keycode2]

  if button then
    return {
      { type = 'press',   button = button, alt = alt, ctrl = ctrl, shift = shift },
      { type = 'release', button = button, alt = alt, ctrl = ctrl, shift = shift },
    }, new_offset
  else
    return nil, offset
  end
end

function InputParser:take_shift_tab(buf, offset)
  if buf:find('^\27%[Z', offset) then
    return {
      { type = 'press',   button = 'tab', alt = false, ctrl = false, shift = true },
      { type = 'release', button = 'tab', alt = false, ctrl = false, shift = true },
    }, offset + 3
  else
    return nil, offset
  end
end

function InputParser:take_paste(buf, offset)
  -- Reference: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h2-Bracketed-Paste-Mode
  if not buf:find('^\27%[200~', offset) then
    return nil, offset
  end
  local end_offset = buf:find('\27[201~', offset, true)
  if not end_offset then
    return {}, offset
  end
  return {{ type = 'paste', text = buf:sub(offset + 6, end_offset - 1) }}, end_offset + 6
end

function InputParser:drop_kitty_functional_key(buf, offset)
  local new_offset = buf:match('^\27%[%d+;%d+:%d[ABCDEFHPQS~]()', offset)
  if new_offset then
    return {}, new_offset
  else
    return nil, offset
  end
end

function InputParser:take_key(buf, offset)
  local alt = buf:byte(offset) == 27 and #buf > 1
  local has_codepoint, new_offset = pcall(utf8.offset, buf, 2, offset + (alt and 1 or 0))
  if not has_codepoint then
    return nil, offset
  end
  local key = self.keymap[utf8.codepoint(buf, offset + (alt and 1 or 0), offset + (alt and 1 or 0), true)]
  if key then
    return {
      { type = 'press',   button = key.button, alt = alt, ctrl = key.ctrl or false, shift = key.shift or false, text = key.text },
      { type = 'release', button = key.button, alt = alt, ctrl = key.ctrl or false, shift = key.shift or false },
    }, new_offset
  else
    return nil, offset
  end
end

function InputParser:take_codepoint(buf, offset)
  local has_codepoint, new_offset = pcall(utf8.offset, buf, 2, offset)
  if has_codepoint then
    return {{ type = 'paste', text = buf:sub(offset, new_offset - 1) }}, new_offset
  else
    return nil, offset
  end
end

return InputParser
