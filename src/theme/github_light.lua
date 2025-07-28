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

local tty         = require('core.tty')
local DocView     = require('core.ui.doc_view')
local utils       = require('core.utils')
local github_dark = require('theme.github_dark')
local rgb = tty.Rgb.from_hex

local github_light = {
  themer = utils.Themer.new(),
}

function github_light.apply()
  local theme = tty.cap.foreground == 'true_color' and tty.cap.background == 'true_color' and github_light.true_color or github_light.ansi
  github_light.themer:apply(
    DocView.faces, 'normal', theme.faces.normal,
    DocView.faces, 'invalid', theme.faces.invalid_illegal,
    DocView.faces, 'syntax_highlights', theme.faces.syntax_highlights,
    DocView.colors, 'cursor', theme.colors.cursor,
    DocView.colors, 'cursor_foreground', theme.colors.cursor_fg,
    DocView.colors, 'selection', theme.colors.selection_bg,
    DocView.colors, 'misspelling', theme.colors.step_error_text
  )
end

function github_light.unapply()
  github_light.themer:unapply()
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

-- Reference: https://www.npmjs.com/package/@primer/primitives/v/7.17.1?activeTab=code (dist/json/colors/light.json)

function github_light.regenerate()
  github_light.true_color = github_dark.from({
    text                 = rgb'1f2328',
    bg                   = rgb'ffffff',
    comment              = rgb'57606a',
    constant             = rgb'0550ae',
    entity               = rgb'6639ba',
    entity_tag           = rgb'116329',
    keyword              = rgb'cf222e',
    string               = rgb'0a3069',
    variable             = rgb'953800',
    invalid_illegal_text = rgb'f6f8fa',
    invalid_illegal_bg   = rgb'82071e',
    string_regexp        = rgb'116329',
    step_error_text      = rgb'ff8182',
    cursor               = rgb'1f2328',
    cursor_fg            = rgb'ffffff',
    selection_bg         = rgb'badeff',
  })
  github_light.ansi = github_dark.from({
    text                 = 'black',
    bg                   = 'bright_white',
    comment              = 'bright_black',
    constant             = 'bright_blue',
    entity               = 'magenta',
    entity_tag           = 'green',
    keyword              = 'red',
    string               = 'blue',
    variable             = 'yellow',
    invalid_illegal_text = 'bright_white',
    invalid_illegal_bg   = 'red',
    string_regexp        = 'green',
    step_error_text      = 'bright_red',
    cursor               = 'black',
    cursor_fb            = 'bright_white',
    selection_bg         = 'bright_cyan',
  })
end

github_light.regenerate()

return github_light
