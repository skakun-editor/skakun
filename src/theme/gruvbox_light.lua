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

local tty          = require('core.tty')
local DocView      = require('core.ui.doc_view')
local utils        = require('core.utils')
local gruvbox_dark = require('theme.gruvbox_dark')
local rgb = tty.Rgb.from_hex

local gruvbox_light = {
  themer = utils.Themer.new(),
}

function gruvbox_light.apply()
  local theme = tty.cap.foreground == 'true_color' and tty.cap.background == 'true_color' and gruvbox_light.true_color or gruvbox_light.ansi
  gruvbox_light.themer:apply(
    DocView.faces, 'normal', theme.faces.normal,
    DocView.faces, 'invalid', theme.faces.invalid,
    DocView.faces, 'syntax_highlights', theme.faces.syntax_highlights,
    DocView.colors, 'cursor', theme.colors.fg1,
    DocView.colors, 'cursor_foreground', theme.colors.bg2,
    DocView.colors, 'selection', theme.colors.bg1,
    DocView.colors, 'misspelling', theme.colors.red
  )
end

function gruvbox_light.unapply()
  gruvbox_light.themer:unapply()
end

-- The particular selection and configuration of colors used below is subject to
-- the following license:
--
-- Copyright (c) 2017 Pavel "morhetz" Pertsev
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

-- Reference: https://github.com/morhetz/gruvbox/blob/master/colors/gruvbox.vim

function gruvbox_light.regenerate(contrast)
  local bg0
  if contrast == 'hard' then
    bg0 = rgb'f9f5d7'
  elseif contrast == 'medium' or not contrast then
    bg0 = rgb'fbf1c7'
  elseif contrast == 'soft' then
    bg0 = rgb'f2e5bc'
  else
    error('unrecognized contrast value')
  end
  gruvbox_light.true_color = gruvbox_dark.from({
    bg0    = bg0,
    bg1    = rgb'ebdbb2',
    bg2    = rgb'd5c4a1',
    bg3    = rgb'bdae93',
    bg4    = rgb'a89984',

    gray   = rgb'928374',

    fg0    = rgb'282828',
    fg1    = rgb'3c3836',
    fg2    = rgb'504945',
    fg3    = rgb'665c54',
    fg4    = rgb'7c6f64',

    red    = rgb'9d0006',
    green  = rgb'79740e',
    yellow = rgb'b57614',
    blue   = rgb'076678',
    purple = rgb'8f3f71',
    aqua   = rgb'427b58',
    orange = rgb'af3a03',
  })
  gruvbox_light.ansi = gruvbox_dark.from({
    bg0    = 'bright_white',
    bg1    = 'white',
    bg2    = 'white',
    bg3    = 'white',
    bg4    = 'white',

    gray   = 'bright_black',

    fg0    = 'black',
    fg1    = 'black',
    fg2    = 'black',
    fg3    = 'black',
    fg4    = 'black',

    red    = 'red',
    green  = 'green',
    yellow = 'yellow',
    blue   = 'blue',
    purple = 'magenta',
    aqua   = 'cyan',
    orange = 'yellow',
  })
end

gruvbox_light.regenerate()

return gruvbox_light
