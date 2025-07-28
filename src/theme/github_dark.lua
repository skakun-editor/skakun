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

local github_dark = {
  themer = utils.Themer.new(),
}

function github_dark.apply()
  local theme = tty.cap.foreground == 'true_color' and tty.cap.background == 'true_color' and github_dark.true_color or github_dark.ansi
  github_dark.themer:apply(
    DocView.faces, 'normal', theme.faces.normal,
    DocView.faces, 'invalid', theme.faces.invalid_illegal,
    DocView.faces, 'syntax_highlights', theme.faces.syntax_highlights,
    DocView.colors, 'cursor', theme.colors.cursor,
    DocView.colors, 'cursor_foreground', theme.colors.cursor_fg,
    DocView.colors, 'selection', theme.colors.selection_bg,
    DocView.colors, 'misspelling', theme.colors.step_error_text
  )
end

function github_dark.unapply()
  github_dark.themer:unapply()
end

-- The particular selection and configuration of colors used below is subject to
-- the following license:
--
-- Copyright (c) 2018 GitHub Inc.
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

-- Reference: https://www.npmjs.com/package/@primer/primitives/v/7.17.1?activeTab=code (dist/json/colors/dark.json)

function github_dark.regenerate()
  github_dark.true_color = github_dark.from({
    text                 = rgb'e6edf3',
    bg                   = rgb'0d1117',
    comment              = rgb'8b949e',
    constant             = rgb'79c0ff',
    entity               = rgb'd2a8ff',
    entity_tag           = rgb'7ee787',
    keyword              = rgb'ff7b72',
    string               = rgb'a5d6ff',
    variable             = rgb'ffa657',
    invalid_illegal_text = rgb'f0f6fc',
    invalid_illegal_bg   = rgb'8e1519',
    step_error_text      = rgb'f85149',
    cursor               = rgb'e6edf3',
    cursor_fg            = rgb'0d1117',
    selection_bg         = rgb'1e4173',
  })
  github_dark.ansi = github_dark.from({
    text                 = 'white',
    bg                   = 'black',
    comment              = 'bright_black',
    constant             = 'bright_blue',
    entity               = 'bright_magenta',
    entity_tag           = 'bright_green',
    keyword              = 'bright_red',
    string               = 'bright_cyan',
    variable             = 'bright_yellow',
    invalid_illegal_text = 'bright_white',
    invalid_illegal_bg   = 'red',
    step_error_text      = 'bright_red',
    cursor               = 'white',
    cursor_fg            = 'black',
    selection_bg         = 'blue',
  })
end

function github_dark.from(colors)
  local faces = {
    normal          = { foreground = colors.text,                 background = colors.bg },
    comment         = { foreground = colors.comment,              background = colors.bg },
    constant        = { foreground = colors.constant,             background = colors.bg },
    entity          = { foreground = colors.entity,               background = colors.bg },
    entity_tag      = { foreground = colors.entity_tag,           background = colors.bg },
    keyword         = { foreground = colors.keyword,              background = colors.bg },
    string          = { foreground = colors.string,               background = colors.bg },
    variable        = { foreground = colors.variable,             background = colors.bg },
    invalid_illegal = { foreground = colors.invalid_illegal_text, background = colors.invalid_illegal_bg },
  }
  faces.syntax_highlights = SyntaxHighlighter.apply_fallbacks({
    comment                = faces.comment,
    literal                = faces.constant,
    string_literal         = faces.string,
    keyword                = faces.keyword,
    matchfix_operator      = faces.normal,
    member_access_operator = faces.normal,
    ['function']           = faces.entity,
    type                   = faces.variable,
    member_identifier      = faces.constant,
    member_function        = faces.entity,
    member_type            = faces.variable,
  }, SyntaxHighlighter.generate_fallbacks({ members = true }))
  return {
    colors = colors,
    faces = faces,
  }
end

github_dark.regenerate()

return github_dark
