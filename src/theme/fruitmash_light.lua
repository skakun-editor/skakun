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
local rgb = tty.Rgb.from_hex
local hsv = tty.Rgb.from_hsv

local fruitmash_light = {
  themer = utils.Themer.new(),
}

function fruitmash_light.apply()
  local theme = tty.cap.foreground == 'true_color' and tty.cap.background == 'true_color' and fruitmash_light.true_color or fruitmash_light.ansi
  fruitmash_light.themer:apply(
    DocView.faces, 'normal', theme.faces.normal,
    DocView.faces, 'invalid', theme.faces.invalid,
    DocView.faces, 'syntax_highlights', theme.faces.syntax_highlights,
    DocView.colors, 'cursor', theme.colors.foreground,
    DocView.colors, 'cursor_foreground', theme.colors.background,
    DocView.colors, 'selection', theme.colors.selection,
    DocView.colors, 'misspelling', theme.colors.error
  )
end

function fruitmash_light.unapply()
  fruitmash_light.themer:unapply()
end

function fruitmash_light.regenerate()
  fruitmash_light.true_color = fruitmash_light.from({
    background = rgb'ffffff',
    selection  = rgb'eeeeee',
    comment    = rgb'999999',
    self       = rgb'666666',
    foreground = rgb'444444',

    red        = hsv(  0, 0.8, 0.8),
    orange     = hsv( 30, 1.0, 0.8),
    yellow     = hsv( 45, 1.0, 0.8),
    green      = hsv(120, 1.0, 0.5),
    cyan       = hsv(190, 1.0, 0.6),
    blue       = hsv(240, 0.5, 0.7),

    error      = hsv( 0, 0.5, 1.0),
    warning    = hsv(60, 0.8, 0.7),
  })
  fruitmash_light.ansi = fruitmash_light.from({
    background = 'bright_white',
    selection  = 'white',
    comment    = 'bright_black',
    self       = 'bright_black',
    foreground = 'black',

    red        = 'red',
    orange     = 'yellow',
    yellow     = 'bright_yellow',
    green      = 'green',
    cyan       = 'cyan',
    blue       = 'blue',

    error      = 'bright_red',
    warning    = 'bright_yellow',
  })
end

function fruitmash_light.from(colors)
  local faces = {
    normal             = { foreground = colors.foreground,  background = colors.background },
    invalid            = { foreground = colors.background,  background = colors.error      },
    comment            = { foreground = colors.comment,     background = colors.background, italic = true },
    punctuation        = { foreground = colors.comment,     background = colors.background },
    constant           = { foreground = colors.blue,        background = colors.background },
    string             = { foreground = colors.yellow,      background = colors.background },
    keyword            = { foreground = colors.red,         background = colors.background },
    declaration        = { foreground = colors.blue,        background = colors.background },
    function_parameter = { foreground = colors.orange,      background = colors.background, italic = true },
    function_          = { foreground = colors.green,       background = colors.background },
    type               = { foreground = colors.cyan,        background = colors.background },
    builtin_variable   = { foreground = colors.self,        background = colors.background, italic = true },
  }
  faces.syntax_highlights = SyntaxHighlighter.apply_fallbacks({
    comment                    = faces.comment,

    punctuation                = faces.punctuation,

    escape_sequence            = faces.constant,

    literal                    = faces.constant,
    string_literal             = faces.string,

    keyword                    = faces.keyword,
    matchfix_operator          = faces.punctuation,
    member_access_operator     = faces.punctuation,
    declaration                = faces.declaration,
    declaration_modifier       = faces.keyword,

    constant                   = faces.constant,
    function_parameter         = faces.function_parameter,
    ['function']               = faces.function_,
    type                       = faces.type,
    builtin_variable           = faces.builtin_variable,
    builtin_constant           = faces.constant,
    builtin_function           = faces.function_,
    builtin_type               = faces.type,
  }, SyntaxHighlighter.generate_fallbacks({ builtins = true, delimiters = true, escape_sequences = true }))
  return {
    colors = colors,
    faces = faces,
  }
end

fruitmash_light.regenerate()

return fruitmash_light
