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

-- IDEA: split bounds into logical and visual bounds (clip rects) to make scrolled content possible

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

function Widget:set_bounds(x, y, width, height)
  self.x = x
  self.y = y
  self.width = width
  self.height = height
end

function Widget:drawn_bounds()
  return self.drawn.x, self.drawn.y, self.drawn.width, self.drawn.height
end

function Widget:request_draw()
  if self.has_requested_draw then return end
  self.has_requested_draw = true
  if self.parent then
    self.parent:request_draw()
  end
end

function Widget:natural_size()
  return 0, 0
end

function Widget:handle_event(event)
  for _, action in ipairs(self.actions) do
    if action.has_precedence_over_children and action:is_activated_by_event(event) then
      action:activate(event)
      if action.consumes_event then
        return true
      end
    end
  end
  for child in self:focused_children() do
    if child:handle_event(event) then
      return true
    end
  end
  for _, action in ipairs(self.actions) do
    if not action.has_precedence_over_children and action:is_activated_by_event(event) then
      action:activate(event)
      if action.consumes_event then
        return true
      end
    end
  end
  return false
end

function Widget:idle()
  for child in self:children() do
    child:idle()
  end
end

function Widget:children()
  return coroutine.wrap(function() end)
end

function Widget:child_is_focused(child)
  return true
end

function Widget:focused_children()
  return coroutine.wrap(function()
    local iter = self:children()
    while true do
      local child = iter()
      if not child or self:child_is_focused(child) then
        coroutine.yield(child)
      end
    end
  end)
end

function Widget:is_focused()
  return not self.parent or self.parent:child_is_focused(self) and self.parent:is_focused()
end

function Widget:add_action(action)
  assert(not action.widget and not self.actions[action.id])
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
      self.actions[action.id] = nil
      action.widget = nil
      return
    end
  end
  assert(false)
end

function Widget:set_name(string)
  self.name = string
  for child in self:children() do
    child:set_name(string)
  end
end

return Widget
