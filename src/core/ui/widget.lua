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

local Widget = {}
Widget.__index = Widget

function Widget.new()
  return setmetatable({
    parent = nil,
    x = nil,
    y = nil,
    width = nil,
    height = nil,
    drawn = nil,
    is_queued_for_draw = false,
  }, Widget)
end

function Widget:draw()
  self.drawn = {
    x = self.x,
    y = self.y,
    width = self.width,
    height = self.height,
  }
  self.is_queued_for_draw = false
end

function Widget:handle_event() end

function Widget:idle() end

function Widget:set_bounds(x, y, width, height)
  self.x = x
  self.y = y
  self.width = width
  self.height = height
end

function Widget:drawn_bounds()
  local drawn = self.drawn
  return drawn.x, drawn.y, drawn.x + drawn.width - 1, drawn.y + drawn.height - 1
end

function Widget:queue_draw()
  self.is_queued_for_draw = true
  if self.parent then
    self.parent:queue_draw()
  end
end

return Widget
