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

local Widget = {
  name = 'Widget',
}
Widget.__index = Widget

function Widget.new()
  return setmetatable({
    parent = nil,
    x = nil,
    y = nil,
    width = nil,
    height = nil,
    drawn = nil,
    has_requested_draw = false,
    actions = {},
  }, Widget)
end

function Widget:draw()
  self.drawn = {
    x = self.x,
    y = self.y,
    width = self.width,
    height = self.height,
  }
  self.has_requested_draw = false
end

function Widget:handle_event(event)
  for _, action in ipairs(self.actions) do
    if action:is_activated_by_event(event) then
      action:activate(event)
      return true
    end
  end
  for _, child in self:children() do
    if child:handle_event(event) then
      return true
    end
  end
  return false
end

function Widget:idle() end

function Widget:children()
  return coroutine.wrap(function() end)
end

function Widget:natural_size()
  return 0, 0
end

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

function Widget:request_draw()
  self.has_requested_draw = true
  if self.parent then
    self.parent:request_draw()
  end
end

function Widget:add_action(action)
  assert(not action.widget)
  action.widget = self
  self.actions[action.id] = action
  table.insert(self.actions, action)
end

function Widget:add_actions(...)
  for i = 1, select('#', ...) do
    self:add_action(select(i, ...))
  end
end

function Widget:remove_action(action)
  for i = 1, #self.actions do
    if self.actions[i] == action then
      table.remove(self.actions, i)
      self.actions[action.id] = false
      action.widget = nil
      return
    end
  end
  assert(false)
end

return Widget
