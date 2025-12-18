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
local grapheme  = require('core.grapheme')
local stderr    = require('core.stderr')
local tty       = require('core.tty')
local TextField = require('core.ui.text_field')
local Widget    = require('core.ui.widget')
local SortedSet = require('core.utils.sorted_set')
local Gio       = require('LuaGObject').Gio

local FileChooser = setmetatable({
  faces = {
  },
}, Widget)
FileChooser.__index = FileChooser

function FileChooser.new(path)
  local self = setmetatable(Widget.new(), FileChooser)
  self.faces = setmetatable({}, { __index = FileChooser.faces })

  self.path_field = TextField.new()
  self.path_field.text = path
  self.path_field.parent = self

  return self
end

function FileChooser:draw()
  Widget.draw(self)
  if self.width == 0 or self.height == 0 then return end

  self.path_field:set_bounds(self.x, self.y, self.width, 1)
  self.path_field:draw()

  local file = Gio.File.new_for_path(self.path .. 'x'):get_parent()
  stderr.info(here, file:get_path())
  local iter = file:enumerate_children('standard::display-name')
  local set = SortedSet.new(function(a, b)
    return a:get_display_name() < b:get_display_name()
  end)
  while true do
    local file = iter:next_file()
    if not file then break end
    set:insert(file)
  end
  for _, file in set:elems() do
    stderr.info(here, file:get_display_name())
  end
end

function FileChooser:handle_event(event)
  self.path_field:handle_event(event)
end

return FileChooser
