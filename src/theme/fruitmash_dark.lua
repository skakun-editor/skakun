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
local fruitmash_light = require('theme.fruitmash_light')
local rgb       = tty.Rgb.from_hex
local hsv       = tty.Rgb.from_hsv
local Fruitmash = getmetatable(fruitmash_light)

return Fruitmash.new(
  'Fruitmash Dark',
  {
    background             = rgb'222222',
    background_unfocused   = rgb'1a1a1a',
    background_raised      = rgb'2f2f2f',
    background_popup       = rgb'404040',
    background_popup_inset = rgb'303030',
    foreground             = rgb'ffffff',

    selection              = rgb'333333',
    comment                = rgb'777777',
    self                   = rgb'bbbbbb',

    red                    = hsv(  0, 0.6, 1.0),
    orange                 = hsv( 30, 0.6, 0.9),
    yellow                 = hsv( 45, 0.6, 1.0),
    green                  = hsv(110, 0.5, 0.9),
    cyan                   = hsv(190, 0.5, 0.9),
    blue                   = hsv(225, 0.5, 1.0),

    error                  = hsv( 0, 0.7, 0.8),
    warning                = hsv(60, 1.0, 0.5),
  },
  {
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
  }
)
