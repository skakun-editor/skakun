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

local SyntaxHighlighter = require('core.doc.syntax_highlighter')
local tty               = require('core.tty')
local DocView           = require('core.ui.doc_view')
local utils             = require('core.utils')
local rgb = tty.Rgb.from

local gruvbox_dark = {
  themer = utils.Themer.new(),
}

function gruvbox_dark.apply()
  local theme = tty.cap.foreground == 'true_color' and tty.cap.background == 'true_color' and gruvbox_dark.true_color or gruvbox_dark.ansi
  gruvbox_dark.themer:apply(
    DocView.faces, 'normal', theme.faces.normal,
    DocView.faces, 'invalid', theme.faces.invalid,
    DocView.faces, 'syntax_highlights', theme.faces.syntax_highlights,
    DocView.colors, 'cursor', theme.colors.fg1,
    DocView.colors, 'cursor_foreground', theme.colors.bg2,
    DocView.colors, 'selection', theme.colors.bg1,
    DocView.colors, 'misspelling', theme.colors.red
  )
end

function gruvbox_dark.unapply()
  gruvbox_dark.themer:unapply()
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

function gruvbox_dark.regenerate(contrast)
  local bg0
  if contrast == 'hard' then
    bg0 = rgb'1d2021'
  elseif contrast == 'medium' or not contrast then
    bg0 = rgb'282828'
  elseif contrast == 'soft' then
    bg0 = rgb'32302f'
  else
    error('unrecognized contrast value')
  end
  gruvbox_dark.true_color = gruvbox_dark.from({
    bg0    = bg0,
    bg1    = rgb'3c3836',
    bg2    = rgb'504945',
    bg3    = rgb'665c54',
    bg4    = rgb'7c6f64',

    gray   = rgb'928374',

    fg0    = rgb'fbf1c7',
    fg1    = rgb'ebdbb2',
    fg2    = rgb'd5c4a1',
    fg3    = rgb'bdae93',
    fg4    = rgb'a89984',

    red    = rgb'fb4934',
    green  = rgb'b8bb26',
    yellow = rgb'fabd2f',
    blue   = rgb'83a598',
    purple = rgb'd3869b',
    aqua   = rgb'8ec07c',
    orange = rgb'fe8019',
  })
  gruvbox_dark.ansi = gruvbox_dark.from({
    bg0    = 'black',
    bg1    = 'black',
    bg2    = 'bright_black',
    bg3    = 'bright_black',
    bg4    = 'bright_black',

    gray   = 'bright_black',

    fg0    = 'white',
    fg1    = 'white',
    fg2    = 'white',
    fg3    = 'white',
    fg4    = 'white',

    red    = 'bright_red',
    green  = 'bright_green',
    yellow = 'bright_yellow',
    blue   = 'bright_blue',
    purple = 'bright_magenta',
    aqua   = 'bright_cyan',
    orange = 'yellow',
  })
end

function gruvbox_dark.from(colors)
  -- I had to infer the syntax groups on my own because the declared groups
  -- in the Neovim colorscheme file match the displayed ones only partially.
  local faces = {
    normal             = { foreground = colors.fg1,    background = colors.bg0 },
    invalid            = { foreground = colors.bg0,    background = colors.red },

    comment            = { foreground = colors.gray,   background = colors.bg0, italic = true },
    todo               = { foreground = colors.fg1,    background = colors.bg0, bold = true, italic = true },
    error              = { foreground = colors.red,    background = colors.bg0, bold = true },

    operator           = { foreground = colors.fg1,    background = colors.bg0 },
    keyword            = { foreground = colors.red,    background = colors.bg0 },
    preproc            = { foreground = colors.aqua,   background = colors.bg0 },

    identifier         = { foreground = colors.fg1,    background = colors.bg0 },
    function_          = { foreground = colors.blue,   background = colors.bg0 },

    constant           = { foreground = colors.purple, background = colors.bg0 },
    escape             = { foreground = colors.orange, background = colors.bg0 },
    string             = { foreground = colors.green,  background = colors.bg0 },

    type               = { foreground = colors.yellow, background = colors.bg0 },
    modifier           = { foreground = colors.orange, background = colors.bg0 },
    storage            = { foreground = colors.aqua,   background = colors.bg0 },

    html_tag           = { foreground = colors.aqua,   background = colors.bg0, bold = true },
    html_attr          = { foreground = colors.aqua,   background = colors.bg0 },

    punctuation        = { foreground = colors.fg3,    background = colors.bg0 },
    special_identifier = { foreground = colors.fg1,    background = colors.bg0, bold = true },
    special_constant   = { foreground = colors.purple, background = colors.bg0, bold = true },
    special_function   = { foreground = colors.blue,   background = colors.bg0, bold = true },
    special_type       = { foreground = colors.yellow, background = colors.bg0, bold = true },
    builtin_identifier = { foreground = colors.fg1,    background = colors.bg0, italic = true },
    builtin_constant   = { foreground = colors.purple, background = colors.bg0, italic = true },
    builtin_function   = { foreground = colors.blue,   background = colors.bg0, italic = true },
    builtin_type       = { foreground = colors.yellow, background = colors.bg0, italic = true },
  }
  faces.syntax_highlights = SyntaxHighlighter.apply_fallbacks({
    comment              = faces.comment,

    punctuation          = faces.punctuation,

    escape_sequence      = faces.escape,

    literal              = faces.constant,
    string_literal       = faces.string,

    keyword              = faces.keyword,
    operator             = faces.operator,
    type_keyword         = faces.modifier,
    declaration          = faces.storage,
    pragma               = faces.preproc,

    constant             = faces.constant,
    ['function']         = faces.function_,
    type                 = faces.type,
    special_identifier   = faces.special_identifier,
    special_constant     = faces.special_constant,
    special_function     = faces.special_function,
    special_type         = faces.special_type,
    builtin_identifier   = faces.builtin_identifier,
    builtin_constant     = faces.builtin_constant,
    builtin_function     = faces.builtin_function,
    builtin_type         = faces.builtin_type,
  }, SyntaxHighlighter.generate_fallbacks({ builtins = true, escape_sequences = true, specials = true }))
  return {
    colors = colors,
    faces = faces,
  }
end

gruvbox_dark.regenerate()

return gruvbox_dark
