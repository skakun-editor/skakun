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

local tty    = require('core.tty')
local ui     = require('core.ui')
local Widget = require('core.ui.widget')

local Frame = setmetatable({
  name = 'Frame',
  faces = {
    content = {},
    border = { background = 'bright_black' },
    invalid = { foreground = 'black', background = 'red' },
  }
}, Widget)
Frame.__index = Frame

function Frame.new(content)
  local self = setmetatable(Widget.new(), Frame)
  self.faces = setmetatable({}, { __index = Frame.faces })
  self:set_content(content)
  return self
end

function Frame:draw()
  Widget.draw(self)
  if self.width <= 0 or self.height <= 0 then return end

  if self.content then
    self.content:set_bounds(self.x + 1, self.y + 1, self.width - 2, self.height - 2)
    self.content:draw()
  else
    tty.set_face(self.faces.content)
    for y = 1, self.height - 2 do
      tty.move_to(self.x + 1, self.y + y)
      tty.write((' '):rep(self.width - 2))
    end
  end

  tty.set_face(self.faces.border)
  tty.move_to(self.x, self.y)
  tty.write((' '):rep(self.width))
  for y = self.y + 1, self.y + self.height - 2 do
    tty.move_to(self.x, y)
    tty.write(' ')
    tty.move_to(self.x + self.width - 1, y)
    tty.write(' ')
  end
  if self.height >= 2 then
    tty.move_to(self.x, self.y + self.height - 1)
    tty.write((' '):rep(self.width))
  end

  local title = self:title()
  if title then
    local width = math.min(self.width, ui.text_width(title))
    ui.draw_text(
      title,
      self.x + (self.width - width) // 2, self.y,
      width,
      0,
      self.faces.border,
      self.faces.invalid
    )
  end
end

function Frame:natural_size()
  local w, h = 0, 0
  if self.content then
    w, h = self.content:natural_size()
  end
  local title = self:title()
  if title then
    w = math.max(w, ui.text_width(title))
  end
  return w + 2, h + 2
end

function Frame:children()
  return coroutine.wrap(function()
    coroutine.yield(self.content)
  end)
end

function Frame:set_content(widget)
  if self.content then
    self.content.parent = nil
  end
  self.content = widget
  if widget then
    assert(not widget.parent)
    widget.parent = self
  end
end

function Frame:title()
  return self.content and (self.content.frame_title or self.content.name)
end

return Frame
