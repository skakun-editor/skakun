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

local tty             = require('core.tty')
local DocView         = require('core.ui.doc_view')
local SplitView       = require('core.ui.split_view')
local TabView         = require('core.ui.tab_view')
local utils           = require('core.utils')
local fruitmash_light = require('theme.fruitmash_light')
local rgb = tty.Rgb.from_hex
local hsv = tty.Rgb.from_hsv

local fruitmash_dark = {
  themer = utils.Themer.new(),
}

function fruitmash_dark.apply()
  local theme = tty.cap.foreground == 'true_color' and tty.cap.background == 'true_color' and fruitmash_dark.true_color or fruitmash_dark.ansi
  fruitmash_dark.themer:apply(
    DocView.faces, 'invalid', theme.faces.invalid,
    DocView.faces, 'normal', theme.faces.normal,
    DocView.faces, 'syntax_highlights', theme.faces.syntax_highlights,
    DocView.colors, 'cursor', theme.colors.foreground,
    DocView.colors, 'cursor_foreground', theme.colors.background,
    DocView.colors, 'misspelling', theme.colors.error,
    DocView.colors, 'selection', theme.colors.selection,
    SplitView.faces, 'content', theme.faces.normal,
    SplitView.faces, 'content_unfocused', theme.faces.normal_unfocused,
    SplitView.faces, 'focused_separator', theme.faces.cursor,
    SplitView.faces, 'separator', theme.faces.raised,
    TabView.faces, 'content', theme.faces.normal,
    TabView.faces, 'content_unfocused', theme.faces.normal_unfocused,
    TabView.faces, 'invalid', theme.faces.invalid,
    TabView.faces, 'open_tab', theme.faces.cursor,
    TabView.faces, 'tab', theme.faces.raised
  )
end

function fruitmash_dark.unapply()
  fruitmash_dark.themer:unapply()
end

function fruitmash_dark.regenerate()
  fruitmash_dark.true_color = fruitmash_light.from({
    background           = rgb'222222',
    background_unfocused = rgb'1a1a1a',
    background_raised    = rgb'2f2f2f',
    foreground           = rgb'ffffff',

    selection            = rgb'333333',
    comment              = rgb'777777',
    self                 = rgb'bbbbbb',

    red                  = hsv(  0, 0.6, 1.0),
    orange               = hsv( 30, 0.6, 0.9),
    yellow               = hsv( 45, 0.6, 1.0),
    green                = hsv(110, 0.5, 0.9),
    cyan                 = hsv(190, 0.5, 0.9),
    blue                 = hsv(225, 0.5, 1.0),

    error                = hsv( 0, 0.7, 0.8),
    warning              = hsv(60, 1.0, 0.5),
  })
  fruitmash_dark.ansi = fruitmash_light.from({
    background = 'black',
    border     = 'bright_black',
    selection  = 'bright_black',
    comment    = 'white',
    self       = 'white',
    foreground = 'bright_white',

    red        = 'bright_red',
    orange     = 'yellow',
    yellow     = 'bright_yellow',
    green      = 'bright_green',
    cyan       = 'bright_cyan',
    blue       = 'bright_blue',

    error      = 'red',
    warning    = 'yellow',
  })
end

fruitmash_dark.regenerate()

return fruitmash_dark
