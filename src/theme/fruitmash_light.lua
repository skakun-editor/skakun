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

local SyntaxHighlighter = require('core.doc.syntax_highlighter')
local tty               = require('core.tty')
local ActionPrompt      = require('core.ui.action_prompt')
local DocView           = require('core.ui.doc_view')
local Frame             = require('core.ui.frame')
local List              = require('core.ui.list')
local SplitView         = require('core.ui.split_view')
local TabView           = require('core.ui.tab_view')
local TextField         = require('core.ui.text_field')
local ThemeSetter       = require('core.ui.theme_setter')
local utils             = require('core.utils')
local rgb = tty.Rgb.from_hex
local hsv = tty.Rgb.from_hsv

local Fruitmash = {}
Fruitmash.__index = Fruitmash

function Fruitmash.new(name, true_color_palette, ansi_palette)
  local self = setmetatable({}, Fruitmash)
  self.name = name
  self.true_color = { colors = true_color_palette }
  self.ansi = { colors = ansi_palette }
  self:regenerate()
  self.themer = utils.Themer.new()
  return self
end

function Fruitmash:apply()
  local theme = tty.cap.foreground == 'true_color' and tty.cap.background == 'true_color' and self.true_color or self.ansi
  self.themer:apply(
    ActionPrompt.faces, 'hint', theme.faces.popup_inset_hint,
    ActionPrompt.faces, 'invalid', theme.faces.invalid,
    ActionPrompt.faces, 'item', theme.faces.popup_inset,
    ActionPrompt.faces, 'selection', theme.faces.cursor,
    DocView.colors, 'cursor', theme.colors.foreground,
    DocView.colors, 'cursor_foreground', theme.colors.background,
    DocView.colors, 'misspelling', theme.colors.error,
    DocView.colors, 'selection', theme.colors.selection,
    DocView.faces, 'invalid', theme.faces.invalid,
    DocView.faces, 'normal', theme.faces.normal,
    DocView.faces, 'syntax_highlights', theme.faces.syntax_highlights,
    Frame.faces, 'border', theme.faces.popup,
    Frame.faces, 'content', theme.faces.popup_inset,
    Frame.faces, 'invalid', theme.faces.invalid,
    List.faces, 'invalid', theme.faces.invalid,
    List.faces, 'item', theme.faces.raised,
    List.faces, 'selection', theme.cursor,
    SplitView.faces, 'content', theme.faces.normal,
    SplitView.faces, 'content_unfocused', theme.faces.normal_unfocused,
    SplitView.faces, 'focused_separator', theme.faces.cursor,
    SplitView.faces, 'separator', theme.faces.raised,
    TabView.faces, 'content', theme.faces.normal,
    TabView.faces, 'content_unfocused', theme.faces.normal_unfocused,
    TabView.faces, 'invalid', theme.faces.invalid,
    TabView.faces, 'open_tab', theme.faces.cursor,
    TabView.faces, 'tab', theme.faces.raised,
    TextField.colors, 'cursor', theme.colors.foreground,
    TextField.colors, 'color_foreground', theme.colors.background,
    TextField.faces, 'ellipsis', theme.faces.popup_inset_hint,
    TextField.faces, 'invalid', theme.faces.invalid,
    TextField.faces, 'text', theme.faces.popup_inset,
    ThemeSetter.List.faces, 'invalid', theme.faces.invalid,
    ThemeSetter.List.faces, 'item', theme.faces.popup_inset,
    ThemeSetter.List.faces, 'selection', theme.faces.cursor
  )
end

function Fruitmash:unapply()
  self.themer:unapply()
end

function Fruitmash:regenerate()
  for _, theme in ipairs({self.true_color, self.ansi}) do
    local colors = theme.colors
    local faces = {
      normal             = { foreground = colors.foreground, background = colors.background             },
      normal_unfocused   = { foreground = colors.foreground, background = colors.background_unfocused   },
      raised             = { foreground = colors.foreground, background = colors.background_raised      },
      popup              = { foreground = colors.foreground, background = colors.background_popup       },
      popup_inset        = { foreground = colors.foreground, background = colors.background_popup_inset },
      popup_inset_hint   = { foreground = colors.comment,    background = colors.background_popup_inset },
      cursor             = { foreground = colors.background, background = colors.foreground             },
      invalid            = { foreground = colors.background, background = colors.error                  },

      comment            = { foreground = colors.comment,    background = colors.background,            italic = true },
      punctuation        = { foreground = colors.comment,    background = colors.background             },
      constant           = { foreground = colors.blue,       background = colors.background             },
      string             = { foreground = colors.yellow,     background = colors.background             },
      keyword            = { foreground = colors.red,        background = colors.background             },
      declaration        = { foreground = colors.blue,       background = colors.background             },
      function_parameter = { foreground = colors.orange,     background = colors.background,            italic = true },
      function_          = { foreground = colors.green,      background = colors.background             },
      type               = { foreground = colors.cyan,       background = colors.background             },
      builtin_variable   = { foreground = colors.self,       background = colors.background,            italic = true },
    }
    faces.syntax_highlights = SyntaxHighlighter.apply_fallbacks({
      comment                = faces.comment,

      punctuation            = faces.punctuation,

      escape_sequence        = faces.constant,

      literal                = faces.constant,
      string_literal         = faces.string,

      keyword                = faces.keyword,
      matchfix_operator      = faces.punctuation,
      member_access_operator = faces.punctuation,
      declaration            = faces.declaration,
      declaration_modifier   = faces.keyword,

      constant               = faces.constant,
      function_parameter     = faces.function_parameter,
      ['function']           = faces.function_,
      type                   = faces.type,
      builtin_variable       = faces.builtin_variable,
      builtin_constant       = faces.constant,
      builtin_function       = faces.function_,
      builtin_type           = faces.type,
    }, SyntaxHighlighter.generate_fallbacks({ builtins = true, delimiters = true, escape_sequences = true }))
    theme.faces = faces
  end
end

return Fruitmash.new(
  'Fruitmash Light',
  {
    background             = rgb'ffffff',
    background_unfocused   = rgb'eeeeee',
    background_raised      = rgb'dddddd',
    background_popup       = rgb'd0d0d0',
    background_popup_inset = rgb'e0e0e0',
    foreground             = rgb'444444',

    selection              = rgb'eeeeee',
    comment                = rgb'999999',
    self                   = rgb'666666',

    red                    = hsv(  0, 0.8,  0.8),
    orange                 = hsv( 30, 1.0,  0.8),
    yellow                 = hsv( 45, 1.0,  0.8),
    green                  = hsv(110, 1.0,  0.5),
    cyan                   = hsv(190, 1.0,  0.65),
    blue                   = hsv(225, 0.64, 0.7),

    error                  = hsv( 0, 0.5, 1.0),
    warning                = hsv(60, 0.8, 0.7),
  },
  {
    background = 'bright_white',
    border     = 'white',
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
  }
)
