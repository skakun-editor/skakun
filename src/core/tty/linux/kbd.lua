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
local system = require('core.tty.linux.system')
local K, KG, KT = system.K, system.KG, system.KT

-- Reference:
-- - https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/tty/vt/keyboard.c
-- - https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/include/uapi/linux/keyboard.h

local Kbd = {
  keycodes = system.keycodes,
}
Kbd.__index = Kbd

function Kbd.new()
  return setmetatable({
    keycodes = setmetatable({}, { __index = Kbd.keycodes }),

    keymap = system.get_keymap(),
    accentmap = system.get_accentmap(),

    buf = '',
    is_pressed = {},

    shift_state = 0,
    shift_pressedc = {},
    lock_state = 0,
    slock_state = 0,

    active_accent = nil,
    is_next_key_accent = false,

    active_codepoint = nil,
  }, Kbd)
end

function Kbd:feed(string)
  self.buf = self.buf .. string

  local result = {}

  local i = 1
  while i <= #self.buf do
    local keycode, is_release
    keycode, is_release, i = self:take_keycode(self.buf, i)
    if not keycode then break end

    local state = self.shift_state | self.slock_state
    local event = {
      type = is_release and 'release' or (self.is_pressed[keycode] and 'repeat' or 'press'),
      button = self.keycodes[keycode],
      alt = state & 1 << KG.ALT ~= 0,
      ctrl = state & 1 << KG.CTRL ~= 0,
      shift = state & 1 << KG.SHIFT ~= 0,
    }
    local ok, text = xpcall(self.handle_keycode, debug.traceback, self, keycode, is_release, event.type == 'repeat')
    if ok then
      event.text = text
    else
      stderr.error(here, 'keycode handler failed:\n', text)
    end
    self.is_pressed[keycode] = not is_release

    if event.button then
      table.insert(result, event)
    else
      stderr.warn(here, 'unknown keycode: ', keycode)
    end
  end
  self.buf = self.buf:sub(i)

  return result
end

function Kbd:take_keycode(buf, offset)
  local a, b, c = buf:byte(offset, offset + 2)
  if not a then
    return nil, nil, offset
  elseif a & 0x7f ~= 0 then
    return a & 0x7f, a >= 0x80, offset + 1
  elseif c then
    return (b & 0x7f) << 7 | c & 0x7f, a >= 0x80, offset + 3
  else
    return nil, nil, offset
  end
end

function Kbd:handle_keycode(keycode, is_release, is_repeat)
  local shift_final = (self.shift_state | self.slock_state) ~ self.lock_state
  local action = self.keymap[shift_final]
  if action then
    action = action[keycode]
  end
  if not action then
    self.slock_state = 0
    return
  end

  if action >= 0xf000 then
    return self:handle_codepoint(action & 0x0fff)
  end

  if action >> 8 == KT.LETTER then
    local caps_lock = system.get_kbd_locks()
    if caps_lock then
      local table = self.keymap[shift_final ~ 1 << KG.SHIFT]
      if table then
        action = table[keycode]
      end
    end
    action = KT.LATIN << 8 | action & 0xff
  end

  local result = self:handle_action(action, is_release, is_repeat)

  if action >> 8 ~= KT.SLOCK then
    self.slock_state = 0
  end

  return result
end

function Kbd:handle_action(action, is_release, is_repeat)
  if action >> 8 == KT.LATIN then
    return self:handle_codepoint(action & 0xff, is_release)

  elseif action >> 8 == KT.SPEC then
    if is_release then return end

    if action == K.ENTER then
      local result = '\n'
      if self.active_accent then
        result = utf8.char(self.active_accent) .. result
        self.active_accent = nil
      end
      return result

    elseif action == K.CAPS then
      if is_repeat then return end
      local caps, num, scroll = system.get_kbd_locks()
      system.set_kbd_locks(not caps, num, scroll)

    elseif action == K.NUM or action == K.BARENUMLOCK then
      if is_repeat then return end
      local caps, num, scroll = system.get_kbd_locks()
      system.set_kbd_locks(caps, not num, scroll)

    elseif action == K.CAPSON then
      if is_repeat then return end
      local _, num, scroll = system.get_kbd_locks()
      system.set_kbd_locks(true, num, scroll)

    elseif action == K.COMPOSE then
      self.is_next_key_accent = true

    -- When switching to the next or previous VC, Linux doesn't just choose
    -- active_vc ± 1, but rather selects the nearest "allocated" VC.
    -- Unfortunately, we ourselves cannot query whether a given VC fits the
    -- label. Linux does have VT_GETSTATE but it only works for the first 16
    -- VCs, which is kind of rubbish. Anyways, VCs are *usually* allocated
    -- sequentially, so who cares?
    elseif action == K.DECRCONSOLE then
      system.set_active_vc(system.get_active_vc() - 1)

    elseif action == K.INCRCONSOLE then
      system.set_active_vc(system.get_active_vc() + 1)

    else
      stderr.warn(here, 'unhandled special key action: ', action)
    end

  elseif action >> 8 == KT.PAD then
    if is_release then return end
    local _, num_lock = system.get_kbd_locks()
    if num_lock then
      local map = {
        [K.P0        ] = '0',
        [K.P1        ] = '1',
        [K.P2        ] = '2',
        [K.P3        ] = '3',
        [K.P4        ] = '4',
        [K.P5        ] = '5',
        [K.P6        ] = '6',
        [K.P7        ] = '7',
        [K.P8        ] = '8',
        [K.P9        ] = '9',
        [K.PPLUS     ] = '+',
        [K.PMINUS    ] = '-',
        [K.PSTAR     ] = '*',
        [K.PSLASH    ] = '/',
        [K.PENTER    ] = '\n',
        [K.PCOMMA    ] = ',',
        [K.PDOT      ] = '.',
        [K.PPLUSMINUS] = '?',
        [K.PPARENL   ] = '(',
        [K.PPARENR   ] = ')',
      }
      return map[action]
    else
      local map = {
        [K.PPLUS     ] = '+',
        [K.PMINUS    ] = '-',
        [K.PSTAR     ] = '*',
        [K.PSLASH    ] = '/',
        [K.PENTER    ] = '\n',
        [K.PPLUSMINUS] = '?',
        [K.PPARENL   ] = '(',
        [K.PPARENR   ] = ')',
      }
      return map[action]
    end

  elseif action >> 8 == KT.DEAD then
    local map = {
      [K.DGRAVE     ] = '`',
      [K.DACUTE     ] = '\'',
      [K.DCIRCM     ] = '^',
      [K.DTILDE     ] = '~',
      [K.DDIERE     ] = '"',
      [K.DCEDIL     ] = ',',
      [K.DMACRON    ] = '_',
      [K.DBREVE     ] = 'U',
      [K.DABDOT     ] = '.',
      [K.DABRING    ] = '*',
      [K.DDBACUTE   ] = '=',
      [K.DCARON     ] = 'c',
      [K.DOGONEK    ] = 'k',
      [K.DIOTA      ] = 'i',
      [K.DVOICED    ] = '#',
      [K.DSEMVOICED ] = 'o',
      [K.DBEDOT     ] = '!',
      [K.DHOOK      ] = '?',
      [K.DHORN      ] = '+',
      [K.DSTROKE    ] = '-',
      [K.DABCOMMA   ] = ')',
      [K.DABREVCOMMA] = '(',
      [K.DDBGRAVE   ] = ':',
      [K.DINVBREVE  ] = 'n',
      [K.DBECOMMA   ] = ';',
      [K.DCURRENCY  ] = '$',
      [K.DGREEK     ] = '@',
    }
    return self:handle_action(KT.DEAD2 << 8 | map[action]:byte(), is_release, is_repeat)

  elseif action >> 8 == KT.CONS then
    if is_release then return end
    system.set_active_vc((action & 0xff) + 1)

  elseif action >> 8 == KT.SHIFT then
    if is_repeat then return end

    if action == K.CAPSSHIFT then
      action = K.SHIFT
      if not is_release then
        local _, num, scroll = system.get_kbd_locks()
        system.set_kbd_locks(false, num, scroll)
      end
    end

    action = action & 0xff

    if is_release then
      self.shift_pressedc[action] = (self.shift_pressedc[action] or 0) - 1
    else
      self.shift_pressedc[action] = (self.shift_pressedc[action] or 0) + 1
    end
    self.shift_pressedc[action] = math.max(self.shift_pressedc[action], 0)

    local old_state = self.shift_state

    if self.shift_pressedc[action] > 0 then
      self.shift_state = self.shift_state | 1 << action
    else
      self.shift_state = self.shift_state & ~(1 << action)
    end

    if is_release and self.shift_state ~= old_state and self.active_codepoint then
      local result = utf8.char(self.active_codepoint)
      self.active_codepoint = nil
      return result
    end

  elseif action >> 8 == KT.META then
    if is_release then return end
    return string.char(action & 0xff)

  elseif action >> 8 == KT.ASCII then
    if is_release then return end
    if K.ASC0 <= action and action <= K.ASC9 then
      self.active_codepoint = (self.active_codepoint or 0) * 10 + action - K.ASC0
    elseif K.HEX0 <= action and action <= K.HEXf then
      self.active_codepoint = (self.active_codepoint or 0) * 16 + action - K.HEX0
    end

  elseif action >> 8 == KT.LOCK then
    if is_release or is_repeat then return end
    self.lock_state = self.lock_state ~ 1 << (action & 0xff)

  elseif action >> 8 == KT.SLOCK then
    self:handle_action(KT.SHIFT << 8 | action & 0xff, is_release, is_repeat)

    if is_release or is_repeat then return end
    self.slock_state = self.slock_state ~ 1 << (action & 0xff)

    if not self.keymap[self.lock_state ~ self.slock_state] then
      self.slock_state = 1 << (action & 0xff)
    end

  elseif action >> 8 == KT.DEAD2 then
    if is_release then return end

    if not self.active_accent then
      self.active_accent = action & 0xff
      return
    end

    local table = self.accentmap[self.active_accent]
    if table and table[action & 0xff] then
      self.active_accent = table[action & 0xff]
      return
    elseif action & 0xff == self.active_accent then return end

    local result = utf8.char(self.active_accent)
    self.active_accent = action & 0xff
    return result

  else
    stderr.warn(here, 'unhandled key action: ', action)
  end
end

function Kbd:handle_codepoint(codepoint, is_release)
  if is_release then return end

  local result = ''

  if self.active_accent then
    local table = self.accentmap[self.active_accent]
    if table and table[codepoint] then
      codepoint = table[codepoint]
    else
      result = utf8.char(self.active_accent)
    end
    self.active_accent = nil
  end

  if self.is_next_key_accent then
    self.is_next_key_accent = false
    self.active_accent = codepoint
  elseif result == '' or codepoint ~= utf8.codepoint(' ') then
    result = result .. utf8.char(codepoint)
  end

  return result
end

return Kbd
