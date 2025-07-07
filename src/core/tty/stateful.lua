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

local core        = require('core')
local InputParser = require('core.tty.input_parser')
local unix
if core.platform == 'linux' then
  unix            = require('core.tty.linux')
elseif core.platform == 'freebsd' then
  unix            = require('core.tty.freebsd')
end
local system      = require('core.tty.system')
local windows
if core.platform == 'windows' then
  windows         = require('core.tty.windows')
end
local utils       = require('core.utils')

-- BUG: fix arrow key repeats in Kitty
-- BUG: fix some perf issues and bugs in xterm and st

local tty = setmetatable({
  ansi_colors = {
    'black',
    'red',
    'green',
    'yellow',
    'blue',
    'magenta',
    'cyan',
    'white',
    'bright_black',
    'bright_red',
    'bright_green',
    'bright_yellow',
    'bright_blue',
    'bright_magenta',
    'bright_cyan',
    'bright_white',
  },

  underline_shapes = {
    'straight', -- ─────
    'double',   -- ═════
    'curly',    -- ﹏﹏﹏
    'dotted',   -- ┈┈┈┈┈
    'dashed',   -- ╌╌╌╌╌
  },

  cursor_shapes = {
    'block', -- █
    'slab',  -- ▁
    'bar',   -- ▎
  },

  -- You can preview these here: https://developer.mozilla.org/en-US/docs/Web/CSS/cursor#keyword
  mouse_shapes = {
    'default', -- Note that this means the system default, not the terminal default.
    'none',
    'context_menu',
    'help',
    'pointer',
    'progress',
    'wait',
    'cell',
    'crosshair',
    'text',
    'vertical_text',
    'alias',
    'copy',
    'move',
    'no_drop',
    'not_allowed',
    'grab',
    'grabbing',
    'e_resize',    -- →
    'n_resize',    -- ↑
    'ne_resize',   -- ↗
    'nw_resize',   -- ↖
    's_resize',    -- ↓
    'se_resize',   -- ↘
    'sw_resize',   -- ↙
    'w_resize',    -- ←
    'ew_resize',   -- ↔
    'ns_resize',   -- ↕
    'nesw_resize', -- ⤢
    'nwse_resize', -- ⤡
    'col_resize',
    'row_resize',
    'all_scroll',
    'zoom_in',
    'zoom_out',
  },

  face_attrs = {
    'foreground',
    'background',
    'bold',
    'italic',
    'underline',
    'underline_color',
    'underline_shape',
    'strikethrough',
  },

  -- All of the 104 keys of a standard US layout Windows keyboard
  buttons = {
    'escape', 'f1', 'f2', 'f3', 'f4', 'f5', 'f6', 'f7', 'f8', 'f9', 'f10', 'f11', 'f12', 'print_screen', 'scroll_lock', 'pause',
    'backtick', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', 'minus', 'equal', 'backspace', 'insert', 'home', 'page_up',
    'tab', 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', 'left_bracket', 'right_bracket', 'backslash', 'delete', 'end', 'page_down',
    'caps_lock', 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', 'semicolon', 'apostrophe', 'enter',
    'left_shift', 'z', 'x', 'c', 'v', 'b', 'n', 'm', 'comma', 'dot', 'slash', 'right_shift', 'up',
    'left_ctrl', 'left_super', 'left_alt', 'space', 'right_alt', 'right_super', 'menu', 'right_ctrl', 'left', 'down', 'right',
    'num_lock', 'kp_divide', 'kp_multiply', 'kp_subtract', 'kp_add', 'kp_enter', 'kp_1', 'kp_2', 'kp_3', 'kp_4', 'kp_5', 'kp_6', 'kp_7', 'kp_8', 'kp_9', 'kp_0', 'kp_decimal',
    'mouse_left', 'mouse_middle', 'mouse_right', 'scroll_up', 'scroll_down', 'scroll_left', 'scroll_right', 'mouse_prev', 'mouse_next',
  },

  -- Reminder: color caps must be one of: 'true_color', 'ansi', false.
  cap = {
    foreground = 'true_color',
    background = 'true_color',
    bold = true,
    italic = true,
    underline = true,
    underline_color = 'true_color',
    underline_shape = true,
    strikethrough = true,
    hyperlink = true,

    cursor = true,
    cursor_shape = true,
    mouse_shape = true,
    window_title = true,
    window_background = 'true_color',
    clipboard = 'remote', -- Must be one of: 'remote', 'local', false.
  },

  timeout = 0.05,
  input_buf = '',

  state = {},
}, { __index = system })

function tty.setup()
  tty.open()
  if unix then
    local ok
    ok, tty.input_parser = pcall(unix.Kbd.new)
    if ok then
      unix.enable_raw_kbd()
    else
      tty.input_parser = InputParser.new()
    end
  else
    tty.input_parser = InputParser.new()
  end
  tty.enable_raw_mode()
  tty.detect_caps()
  tty.load_functions()
  tty.write('\27[?1049h') -- Switch to the alternate terminal screen
  tty.write('\27[?2004h') -- Enable bracketed paste
  tty.write('\27[>31u') -- Send key events in Kitty's format
  tty.write('\27=') -- Discriminate numpad keys
  tty.write('\27[?1000h') -- Enable mouse button events
  tty.write('\27[?1003h') -- Enable mouse movement events
  tty.write('\27[?1006h') -- Extend the range of mouse coordinates the terminal is able to report
  tty.write('\27]22;>default\27\\', '\27]22;\27\\') -- Push the terminal default onto the pointer shape stack
  tty.write('\27[22;0t') -- Save the window title on the stack
  if tty.cap.underline_color == 'true_color' or tty.cap.window_background then
    tty.load_ansi_color_palette()
  end
end

function tty.restore()
  tty.write('\27[0m')
  tty.set_cursor()
  tty.set_cursor_shape()
  tty.set_window_background()
  tty.write('\27[23;0t') -- Restore the window title from the stack
  tty.write('\27]22;<\27\\') -- Pop our pointer shape from the stack
  tty.write('\27[?1006l') -- Shrink the range of mouse coordinates to default
  tty.write('\27[?1003l') -- Disable mouse movement events
  tty.write('\27[?1000l') -- Disable mouse button events
  tty.write('\27>') -- Don't discriminate numpad keys
  tty.write('\27[<u') -- Pop the Kitty key event format from the stack
  tty.write('\27[?2004l') -- Disable bracketed paste
  tty.write('\27[?1049l') -- Switch back to the primary terminal screen
  tty.disable_raw_mode()
  if unix then
    pcall(unix.disable_raw_kbd)
  end
  tty.close()
end

function tty.detect_caps()
  -- kitty's terminfo was used as a reference of the available capnames:
  -- https://github.com/kovidgoyal/kitty/blob/master/kitty/terminfo.py
  -- VTE's commit history: https://gitlab.gnome.org/GNOME/vte/-/commits/master
  -- Konsole's commit history: https://invent.kde.org/utilities/konsole/-/commits/master
  -- …which, geez, a pain to follow it was.
  -- xterm's changelog: https://invisible-island.net/xterm/xterm.log.html
  local vte = tonumber(os.getenv('VTE_VERSION')) or -1 -- VTE 0.34.5 (8bea17d1, 68046665)
  local konsole = tonumber(os.getenv('KONSOLE_VERSION')) or -1 -- Konsole 18.07.80 (b0d3d83e, 7e040b61)
  local xterm = os.getenv('XTERM_VERSION')
  if xterm then
    xterm = tonumber(xterm:match('%((%d+)%)'))
  else
    xterm = -1
  end

  -- This is an XTGETTCAP, which allows us to forget about the unreliable
  -- system-wide database and query the terminal's own terminfo entry. It's
  -- supported by… a *few* terminals. :/
  -- Reference: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-Device-Control-functions
  local has_xtgettcap = tty.query('\27P+q' .. utils.hex_encode('cr') .. '\27\\', '\27P[01]%+r=?%x*\27\\') -- An example query for "cr"
  tty.flush()
  if has_xtgettcap() then -- The terminal has replied with a well-formed answer.
    -- Flags don't work over XTGETTCAP, in kitty at least.
    function tty.getnum(capname, term)
      if term ~= nil then
        return function()
          return system.getnum(capname, term)
        end
      end

      capname = utils.hex_encode(capname)
      local reply = tty.query('\27P+q' .. capname .. '\27\\', '\27P([01])%+r' .. capname .. '=?(%x*)\27\\')
      return function()
        local has, value = reply()
        if has == '1' then
          return tonumber(utils.hex_decode(value))
        else
          return nil
        end
      end
    end

    function tty.getstr(capname, term)
      if term ~= nil then
        return function()
          return system.getstr(capname, term)
        end
      end

      capname = utils.hex_encode(capname)
      local reply = tty.query('\27P+q' .. capname .. '\27\\', '\27P([01])%+r' .. capname .. '=?(%x*)\27\\')
      return function()
        local has, value = reply()
        if has == '1' then
          return utils.hex_decode(value)
        else
          return nil
        end
      end
    end
  end

  local Tc = tty.getflag('Tc')
  local colors = tty.getnum('colors')
  local bold = tty.getstr('bold')
  local sitm = tty.getstr('sitm')
  local ritm = tty.getstr('ritm')
  local smul = tty.getstr('smul')
  local rmul = tty.getstr('rmul')
  local Su = tty.getflag('Su')
  local Setulc = tty.getstr('Setulc')
  local Smulx = tty.getstr('Smulx')
  local smxx = tty.getstr('smxx')
  local rmxx = tty.getstr('rmxx')
  local civis = tty.getstr('civis')
  local cnorm = tty.getstr('cnorm')
  local Ss = tty.getstr('Ss')
  local Se = tty.getstr('Se')
  local tsl = tty.getstr('tsl')
  local fsl = tty.getstr('fsl')
  local dsl = tty.getstr('dsl')
  local Ms = tty.getstr('Ms')
  -- Reference: https://sw.kovidgoyal.net/kitty/pointer-shapes/#querying-support
  -- Kitty sends out a colon, even though its own docs say there should be
  -- a semicolon there???
  local mouse_shape = tty.query('\27]22;?__current__\27\\', '\27]22:.*\27\\')
  -- Reference: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-Operating-System-Commands
  -- Konsole and st send BEL instead of ST at the end for some reason.
  local window_background = tty.query('\27]11;?\27\\', '\27]11;.*\27?\\?\a?')
  tty.flush()

  -- VTE 0.35.1 (c5a32b49), Konsole 3.5.4 (f34d8203)
  -- It would probably be better to follow: https://github.com/termstandard/colors#querying-the-terminal
  -- We could also assume that 256-color terminals are always true-color:
  -- tty.getflag('initc') or os.getenv('TERM'):find('256color')
  if vte >= 3501 or konsole >= 030504 or xterm >= 331 or Tc() or os.getenv('COLORTERM') == 'truecolor' or os.getenv('COLORTERM') == '24bit' then
    tty.cap.foreground = 'true_color'
    tty.cap.background = 'true_color'
  elseif colors() >= 8 then
    tty.cap.foreground = 'ansi'
    tty.cap.background = 'ansi'
  else
    -- I have yet to see a terminal in the 21st century that does not support
    -- any kind of text coloring.
    tty.cap.foreground = false
    tty.cap.background = false
  end

  -- The Linux console interprets "bold" in its own way.
  if vte >= 0 or konsole >= 0 or xterm >= 0 or os.getenv('TERM') ~= 'linux' and bold() then
    tty.cap.bold = true
  else
    tty.cap.bold = false
  end

  -- VTE 0.34.1 (ad68297c), Konsole 4.10.80 (68a98ed7)
  if vte >= 3401 or konsole >= 041080 or xterm >= 305 or sitm() and ritm() then
    tty.cap.italic = true
  else
    tty.cap.italic = false
  end

  -- Konsole 0.8.44 (https://invent.kde.org/utilities/konsole/-/blob/d8f74118/ChangeLog#L99)
  if vte >= 0 or konsole >= 000844 or xterm >= 0 or os.getenv('TERM') ~= 'linux' and smul() and rmul() then
    tty.cap.underline = true
  else
    tty.cap.underline = false
  end

  -- VTE 0.51.2 - color, double, curly (efaf8f3c, a8af47bc); VTE 0.75.90 - dotted, dashed (bec7e6a2); Konsole 22.11.80 (76f879cd)
  -- Smulx does not necessarily indicate color support.
  if vte >= 5102 or konsole >= 221180 or Su() or Setulc() or Smulx() then
    tty.cap.underline_color = 'true_color'
    tty.cap.underline_shape = true
  else
    tty.cap.underline_color = false
    tty.cap.underline_shape = false
  end

  -- VTE 0.10.2 (a175a436), Konsole 16.07.80 (84b43dfb)
  if vte >= 1002 or konsole >= 160780 or xterm >= 305 or smxx() and rmxx() then
    tty.cap.strikethrough = true
  else
    tty.cap.strikethrough = false
  end

  -- VTE 0.49.1 (c9e7cbab), Konsole 20.11.80 (faceafcc)
  -- There is currently no universal way to detect hyperlink support.
  -- Further reading: https://github.com/kovidgoyal/kitty/issues/68
  tty.cap.hyperlink = vte >= 4901 or konsole >= 201180 or true

  -- VTE 0.1.0 (81af00a6), Konsole 0.8.42 (https://invent.kde.org/utilities/konsole/-/blob/d8f74118/ChangeLog#L107)
  if vte >= 0100 or konsole >= 000842 or xterm >= 0 or civis() and cnorm() then
    tty.cap.cursor = true
  else
    tty.cap.cursor = false
  end

  -- VTE 0.39.0 (430965a0); Konsole 18.07.80 (7c2a1164); xterm 252 - block, slab; xterm 282 - bar
  if vte >= 3900 or konsole >= 180780 or xterm >= 282 or Ss() and Se() then
    tty.cap.cursor_shape = true
  else
    tty.cap.cursor_shape = false
  end

  if mouse_shape() then
    tty.cap.mouse_shape = true
  else
    tty.cap.mouse_shape = false
  end

  -- VTE 0.10.14 (38fb4802, f39e2815)
  if vte >= 1014 or xterm >= 0 or tsl() and fsl() and dsl() then
    tty.cap.window_title = true
  else
    tty.cap.window_title = false
  end

  -- VTE 0.35.2 (1b8c6b1a), Konsole 3.3.0 (c20973ec)
  -- This does not appear to have its own terminfo cap.
  if vte >= 3502 or konsole >= 030300 or xterm >= 0 then
    tty.cap.window_background = 'true_color'
  else
    -- …But we can ask the terminal to send us the current background color and
    -- see if it understands us.
    if window_background() then
      tty.cap.window_background = 'true_color'
    else
      tty.cap.window_background = false
    end
  end

  -- You may have to explicitly enable this: https://github.com/tmux/tmux/wiki/Clipboard
  if xterm >= 238 or Ms() then
    tty.cap.clipboard = 'remote'
  else
    tty.cap.clipboard = 'local'
  end

  -- Further reading: https://no-color.org/
  if os.getenv('NO_COLOR') and os.getenv('NO_COLOR') ~= '' then
    tty.cap.foreground = false
    tty.cap.background = false
    tty.cap.underline_color = false
    tty.cap.window_background = false
  end

  -- Discard any unprocessed query replies.
  tty.input_buf = ''
  tty.read()
end

function tty.load_ansi_color_palette()
  -- Reference: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-Operating-System-Commands
  local replies = {}
  for i, name in ipairs(tty.ansi_colors) do
    replies[name] = tty.query(
      '\27]4;' .. i - 1 .. ';?\27\\',
      -- Konsole and st send BEL instead of ST at the end for some reason.
      -- Fun fact: We can and may send RGB colors to the terminal in two
      -- different formats (#RRGGBB and rgb:RR/GG/BB) as part of the various
      -- sequences originating from xterm, but why do terminals always have to
      -- send back the second one? Well, xterm uses XParseColor for parsing
      -- our colors and it turns out that the former format (or in the words
      -- of X11 itself: "RGB Device") is actually deprecated by XParseColor!
      -- Source: man 3 XParseColor
      '\27]4;' .. i - 1 .. ';rgb:(%x%x)%x*/(%x%x)%x*/(%x%x)%x*\27?\\?\a?'
    )
  end
  tty.flush()

  tty.ansi_color_palette = {}
  for name, reply in pairs(replies) do
    local red, green, blue = reply()
    tty.ansi_color_palette[name] = tty.Rgb.new(
      tonumber(red, 16),
      tonumber(green, 16),
      tonumber(blue, 16)
    )
  end
end

function tty.read_events()
  local result = {}
  while true do
    tty.input_buf = tty.input_buf .. tty.read()
    local events = tty.input_parser:feed(tty.input_buf)
    tty.input_buf = ''
    if #events <= 0 then break end
    for _, event in ipairs(events) do
      table.insert(result, event)
    end
  end
  return result
end

function tty.query(question, answer_regex)
  tty.write(question)
  tty.query_clock = utils.timer()

  local answer = table.pack()
  return function()
    while not answer[1] do
      answer = table.pack(tty.input_buf:find(answer_regex))
      if answer[1] then
        tty.input_buf = tty.input_buf:sub(1, answer[1] - 1) .. tty.input_buf:sub(answer[2] + 1)
        break
      end

      local chunk = tty.read()
      if #chunk > 0 then
        tty.input_buf = tty.input_buf .. chunk
        tty.query_clock = utils.timer()
      elseif utils.timer() - tty.query_clock >= tty.timeout then
        answer[1] = true
        break
      end
    end
    return table.unpack(answer, 3, answer.n)
  end
end

-- These stubs are enhanced in tty.detect_caps.
function tty.getflag(capname, term)
  return function()
    return system.getflag(capname, term)
  end
end

function tty.getnum(capname, term)
  return function()
    return system.getnum(capname, term)
  end
end

function tty.getstr(capname, term)
  return function()
    return system.getstr(capname, term)
  end
end

-- Reference: https://gist.github.com/christianparpart/d8a62cc1ab659194337d73e399004036
function tty.sync_begin()
  tty.write('\27[?2026h')
end

function tty.sync_end()
  tty.write('\27[?2026l')
end

function tty.clear()
  tty.write('\27[2J')
end

function tty.reset()
  tty.write('\27[0m')
  tty.set_hyperlink()
  tty.set_cursor()
  tty.set_cursor_shape()
  tty.set_mouse_shape()
  tty.set_window_title()
  tty.set_window_background()
  tty.state = {}
end

function tty.move_to(x, y)
  if x and y then
    tty.write('\27[', y, ';', x, 'H')
  elseif x then
    tty.write('\27[', x, 'G')
  elseif y then
    tty.write('\27[', y, 'd')
  end
end

function tty.load_functions()
  -- Escape sequence references:
  -- - man 4 console_codes
  -- - https://wezfurlong.org/wezterm/escape-sequences.html
  -- Further reading: https://gpanders.com/blog/state-of-the-terminal/
  -- Terminals ignore unknown OSC sequences, so stubs for them improve
  -- performance only.

  local ansi_color_fg_codes = {}
  for i, name in ipairs(tty.ansi_colors) do
    ansi_color_fg_codes[name] = (name:match('^bright_') and 90 or 30) + (i - 1 & 7)
  end
  if tty.cap.foreground == 'true_color' then
    function tty.set_foreground(color)
      if ansi_color_fg_codes[color] then
        tty.write('\27[', ansi_color_fg_codes[color], 'm')
      elseif color then
        -- Reference: https://github.com/termstandard/colors
        -- According to the standards, the following syntax should use colons
        -- instead of semicolons but unfortunately the latter has become the
        -- predominant method due to misunderstandings and the passage of time.
        -- Further reading: https://chadaustin.me/2024/01/truecolor-terminal-emacs/
        tty.write('\27[38;2;', color.red, ';', color.green, ';', color.blue, 'm')
      else
        tty.write('\27[39m')
      end
      tty.state.foreground = color
    end
  elseif tty.cap.foreground == 'ansi' then
    function tty.set_foreground(color)
      if ansi_color_fg_codes[color] then
        -- The \27[22m here is important because in the Linux console the codes
        -- for the non-bright colors do not reset the brightness turned on by
        -- the bright colors.
        tty.write('\27[22;', ansi_color_fg_codes[color], 'm')
        tty.state.foreground = color
      else
        -- The above also applies to setting the default foreground color.
        tty.write('\27[22;39m')
        tty.state.foreground = nil
      end
    end
  else
    function tty.set_foreground() end
  end

  local ansi_color_bg_codes = {}
  for k, v in pairs(ansi_color_fg_codes) do
    ansi_color_bg_codes[k] = v + 10
  end
  if tty.cap.background == 'true_color' then
    function tty.set_background(color)
      if ansi_color_bg_codes[color] then
        tty.write('\27[', ansi_color_bg_codes[color], 'm')
      elseif color then
        -- Reference: https://github.com/termstandard/colors
        -- Same story with semicolons vs colons as before.
        tty.write('\27[48;2;', color.red, ';', color.green, ';', color.blue, 'm')
      else
        tty.write('\27[49m')
      end
      tty.state.background = color
    end
  elseif tty.cap.background == 'ansi' then
    function tty.set_background(color)
      if ansi_color_bg_codes[color] then
        -- The bright colors don't work for the background in the Linux console.
        tty.write('\27[', ansi_color_bg_codes[color], 'm')
        tty.state.background = color
      else
        tty.write('\27[49m')
        tty.state.background = nil
      end
    end
  else
    function tty.set_background() end
  end

  if tty.cap.bold then
    function tty.set_bold(is_enabled)
      if is_enabled then
        tty.write('\27[1m')
      else
        tty.write('\27[22m')
      end
      tty.state.bold = is_enabled
    end
  else
    -- Terminals without support simulate bold text by altering the foreground
    -- color, so it's important that we disable them.
    function tty.set_bold() end
  end

  if tty.cap.italic then
    -- Italics and boldness are mutually exclusive on xterm with italics taking
    -- precedence.
    function tty.set_italic(is_enabled)
      if is_enabled then
        tty.write('\27[3m')
      else
        tty.write('\27[23m')
      end
      tty.state.italic = is_enabled
    end
  else
    -- Terminals without support simulate italic text by altering the foreground
    -- color, so it's important that we disable them.
    function tty.set_italic() end
  end

  local underline_shape_codes = {
    straight = 1,
    double = 2,
    curly = 3,
    dotted = 4,
    dashed = 5,
  }
  if tty.cap.underline then
    function tty.set_underline(is_enabled)
      -- Reference: https://sw.kovidgoyal.net/kitty/underlines/
      if is_enabled then
        if tty.state.underline_shape then
          tty.write('\27[4:', underline_shape_codes[tty.state.underline_shape], 'm')
        else
          tty.write('\27[4m')
        end
      else
        tty.write('\27[24m')
      end
      tty.state.underline = is_enabled
    end
  else
    -- Terminals without support simulate underlined text by altering the
    -- foreground color, so it's important that we disable them.
    function tty.set_underline() end
  end

  if tty.cap.underline_color == 'true_color' then
    function tty.set_underline_color(color)
      -- Reference: https://sw.kovidgoyal.net/kitty/underlines/
      if tty.ansi_color_palette[color] then
        -- Sadly, there appears to be no escape sequence for ANSI underline
        -- colors. We have to fetch the RGB value from the terminal.
        tty.set_underline_color(tty.ansi_color_palette[color])
      elseif color then
        -- Same semicolon story as with foreground and background.
        tty.write('\27[58;2;', color.red, ';', color.green, ';', color.blue, 'm')
      else
        tty.write('\27[59m')
      end
      tty.state.underline_color = color
    end
  else
    function tty.set_underline_color() end
  end

  if tty.cap.underline_shape then
    function tty.set_underline_shape(name)
      tty.state.underline_shape = name
      tty.set_underline(tty.state.underline)
    end
  else
    -- Underline shapes turn the text black on xterm, so it's important that we
    -- disable them.
    function tty.set_underline_shape() end
  end

  if tty.cap.strikethrough then
    function tty.set_strikethrough(is_enabled)
      if is_enabled then
        tty.write('\27[9m')
      else
        tty.write('\27[29m')
      end
      tty.state.strikethrough = is_enabled
    end
  else
    function tty.set_strikethrough() end
  end

  if tty.cap.hyperlink then
    function tty.set_hyperlink(url)
      -- Reference: https://gist.github.com/egmontkob/eb114294efbcd5adb1944c9f3cb5feda
      -- ESCs and all other ASCII control characters are disallowed in valid URLs
      -- anyways. According to the specification in the link above we should also
      -- percent-encode all bytes outside of the 32-126 range but who cares?
      -- *It works on my machine.* ¯\_(ツ)_/¯
      tty.write('\27]8;;', (url or ''):gsub('\27', '%%1b'), '\27\\')
      tty.state.url = url
    end
  else
    function tty.set_hyperlink() end
  end

  if tty.cap.cursor then
    function tty.set_cursor(is_visible)
      -- There's no "reset cursor visibility to default" code, unless we query
      -- terminfo for "cnorm".
      if is_visible ~= false then
        tty.write('\27[?25h')
      else
        tty.write('\27[?25l')
      end
      tty.state.cursor = is_visible
    end
  else
    function tty.set_cursor() end
  end

  if tty.cap.cursor_shape then
    if os.getenv('TERM') == 'linux' then
      function tty.set_cursor_shape(name)
        -- Reference: https://www.kernel.org/doc/html/latest/admin-guide/vga-softcursor.html
        if name == 'block' then
          tty.write('\27[?8c')
        elseif name == 'slab' then
          tty.write('\27[?2c')
          -- No bar cursor available, sorry :(
        else
          tty.write('\27[?0c')
        end
        tty.state.cursor_shape = name
      end
    else
      function tty.set_cursor_shape(name)
        -- Reference: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-Functions-using-CSI-_-ordered-by-the-final-character_s_
        -- This utilizes only the blinking versions of the cursor shapes.
        if name == 'block' then
          tty.write('\27[1 q')
        elseif name == 'slab' then
          tty.write('\27[3 q')
        elseif name == 'bar' then
          tty.write('\27[5 q')
        else
          tty.write('\27[ q')
        end
        tty.state.cursor_shape = name
      end
    end
  else
    function tty.set_cursor_shape() end
  end

  if tty.cap.mouse_shape then
    function tty.set_mouse_shape(name)
      -- Reference: https://sw.kovidgoyal.net/kitty/pointer-shapes/
      -- The CSS names have hyphens, not underscores.
      tty.write('\27]22;', (name or ''):gsub('_', '-'), '\27\\')
      -- They don't work on xterm by the way, which has its own set of pointer
      -- shape names: https://invisible-island.net/xterm/manpage/xterm.html#VT100-Widget-Resources:pointerShape
      tty.state.mouse_shape = name
    end
  else
    function tty.set_mouse_shape() end
  end

  if tty.cap.window_title then
    function tty.set_window_title(text)
      -- Reference: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-Operating-System-Commands
      if text == '' then
        tty.write('\27]2; \27\\') -- Because '' should make the title empty, and not set it to terminal default.
      else
        tty.write('\27]2;', (text or ''):gsub('\27', ''), '\27\\')
      end
      tty.state.window_title = text
    end
  else
    function tty.set_window_title() end
  end

  if tty.cap.window_background then
    function tty.set_window_background(color)
      -- Reference: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-Operating-System-Commands
      if tty.ansi_color_palette[color] then
        -- We have to fetch the ANSI color's RGB value from the terminal because
        -- there's no other way.
        tty.set_window_background(tty.ansi_color_palette[color])
      elseif color then
        -- I don't know why, but this is ridiculously slow on kitty and st.
        -- Fun fact: xterm-compatibles accept X11 color names here, which you
        -- can find in /etc/X11/rgb.txt.
        tty.write(('\27]11;#%02x%02x%02x\27\\'):format(color.red, color.green, color.blue))
      else
        tty.write('\27]111;\27\\')
      end
      tty.state.window_background = color
    end
  else
    function tty.set_window_background() end
  end

  if tty.cap.clipboard == 'remote' then
    function tty.set_clipboard(text)
      -- Reference: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-Operating-System-Commands
      tty.write('\27]52;c;', utils.base64_encode(text or ''), '\27\\')
    end
  elseif tty.cap.clipboard == 'local' then
    function tty.set_clipboard(text)
      if core.platform == 'windows' then
        windows.set_clipboard(text)
      elseif core.platform == 'macos' then
        pipe = io.popen('pbcopy', 'w')
        pipe:write(text or '')
        pipe:close()
      else
        for _, cmd in ipairs({
          'xclip -selection clipboard',
          'xsel --clipboard',
          'wl-copy',
        }) do
          pipe = io.popen(cmd, 'w')
          pipe:write(text or '')
          if pipe:close() then break end
        end
      end
    end
  else
    function tty.set_clipboard() end
  end
end

tty.Rgb = {}
tty.Rgb.__index = tty.Rgb

function tty.Rgb.new(red, green, blue)
  return setmetatable({
    red = red,
    green = green,
    blue = blue,
  }, tty.Rgb)
end

function tty.Rgb.from(string)
  return tty.Rgb.new(
    tonumber(string:sub(1, 2), 16),
    tonumber(string:sub(3, 4), 16),
    tonumber(string:sub(5, 6), 16)
  )
end

function tty.Rgb:__eq(other)
  return self.red == other.red and self.green == other.green and self.blue == other.blue
end

function tty.set_face(face)
  for _, name in pairs(tty.face_attrs) do
    if tty.state[name] ~= face[name] then
      tty['set_' .. name](face[name])
    end
  end
end

return tty
