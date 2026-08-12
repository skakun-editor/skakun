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

local tty     = require('core.tty')
local ui      = require('core.ui')
local Action  = require('core.ui.action')
local TabView = require('core.ui.tab_view')
local Widget  = require('core.ui.widget')
local utils   = require('core.utils')

local SplitView = setmetatable({
  name = 'Split View',
  faces = {
    content = {},
    content_unfocused = {},
    separator = { background = 'bright_black' },
    focused_separator = { foreground = 'black', background = 'bright_white' },
  },
}, Widget)
SplitView.__index = SplitView

function SplitView.new()
  local self = setmetatable(Widget.new(), SplitView)
  self.faces = setmetatable({}, { __index = SplitView.faces })

  local A = Action.Activator
  self:add_actions(
    Action.new(
      'focus_side_mouse',
      'Focus side under mouse pointer',
      nil,
      A.predicate(function(event)
        return (event.type == 'press' or event.type == 'repeat') and event.x and event.y
      end):with_hint('Any mouse button'),
      function(action, event)
        if utils.point_is_in_rect(event.x, event.y, self:first_bounds()) then
          self.focused_side = 'first'
        elseif utils.point_is_in_rect(event.x, event.y, self:second_bounds()) then
          self.focused_side = 'second'
        else
          self.focused_side = nil
        end
        self:request_draw()
      end
    ),
    Action.new(
      'unfocus_side',
      'Unfocus side',
      nil,
      A.click('ctrl+slash') & function(event)
        return self.focused_side
      end,
      function(action, event)
        self.focused_side = nil
        self:request_draw()
      end
    ),
    Action.new(
      'focus_leaf_num',
      'Focus nth pane',
      nil,
      A.click('ctrl+', function(button)
        return tonumber(button)
      end):with_hint(ui.modifier_syms.ctrl .. '[1-9,0]'),
      function(action, event)
        if self:focus_leaf_with_num(event.button == '0' and 10 or tonumber(event.button)) then
          self:request_draw()
        end
      end
    ),
    Action.new(
      'focus_leaf_prev',
      'Focus previous pane',
      nil,
      A.click('ctrl+page_up'),
      function(action, event)
        if self:focus_prev_leaf() then
          self:request_draw()
        end
      end
    ),
    Action.new(
      'focus_leaf_next',
      'Focus next pane',
      nil,
      A.click('ctrl+page_down'),
      function(action, event)
        if self:focus_next_leaf() then
          self:request_draw()
        end
      end
    ),
    Action.new(
      'tab_backward',
      'Move tab backward',
      nil,
      A.click('alt+shift+page_up'),
      function(action, event)
        if self:move_focused_leaf_tab_backward() then
          self:request_draw()
          action.consumes_event = true
        else
          action.consumes_event = false
        end
      end
    ),
    Action.new(
      'tab_forward',
      'Move tab forward',
      nil,
      A.click('alt+shift+page_down'),
      function(action, event)
        if self:move_focused_leaf_tab_forward() then
          self:request_draw()
          action.consumes_event = true
        else
          action.consumes_event = false
        end
      end
    ),
    Action.new(
      'leaf_backward',
      'Move pane backward',
      nil,
      A.click('ctrl+shift+page_up'),
      function(action, event)
        self:move_focused_leaf_backward()
        self:request_draw()
      end
    ),
    Action.new(
      'leaf_forward',
      'Move pane forward',
      nil,
      A.click('ctrl+shift+page_down'),
      function(action, event)
        self:move_focused_leaf_forward()
        self:request_draw()
      end
    ),
    Action.new(
      'resize_mouse',
      'Move split to mouse pointer',
      nil,
      (A.click('mouse_left') & function()
        return not self.focused_side
      end | function(event)
        return event.type == 'move' and self.mouse_is_resizing
      end):with_hint('Drag and hold ' .. ui.button_syms.mouse_left),
      function(action, event)
        self.mouse_is_resizing = true
        self.split_position = math.max(0.0, math.min(1.0, self:split_position_from_coord(self.is_vertical and event.x or event.y)))
        self:request_draw()
      end
    ),
    Action.new(
      'stop_drag',
      'Stop dragging split',
      nil,
      A.release('mouse_left') & function()
        return self.mouse_is_resizing
      end,
      function(action, event)
        self.mouse_is_resizing = false
      end
    ),
    Action.new(
      'resize_backward',
      'Move split backward',
      nil,
      A.click('ctrl+alt+left_bracket'),
      function(action, event)
        self.split_position = math.max(0.0, self:split_position_from_coord(self:split_coord() - 1))
        self:request_draw()
      end
    ),
    Action.new(
      'resize_forward',
      'Move split forward',
      nil,
      A.click('ctrl+alt+right_bracket'),
      function(action, event)
        self.split_position = math.min(1.0, self:split_position_from_coord(self:split_coord() + 1))
        self:request_draw()
      end
    ),
    Action.new(
      'split',
      'Split focused side',
      nil,
      A.click('ctrl+backslash'),
      function(action, event)
        self:split_focused_side()
        self:request_draw()
      end
    ),
    Action.new(
      'merge',
      'Merge focused side',
      nil,
      A.click('ctrl+w'),
      function(action, event)
        if self:merge_focused_side() then
          self:request_draw()
          action.consumes_event = true
        else
          action.consumes_event = false
        end
      end
    ),
    Action.new(
      'rotate_left',
      'Rotate left',
      nil,
      A.click('ctrl+left_bracket'),
      function(action, event)
        self:rotate_left()
        self:request_draw()
      end
    ),
    Action.new(
      'rotate_right',
      'Rotate right',
      nil,
      A.click('ctrl+right_bracket'),
      function(action, event)
        self:rotate_right()
        self:request_draw()
      end
    )
  )
  for _, i in ipairs({'unfocus_side', 'resize_backward', 'resize_forward', 'split', 'merge', 'rotate_left', 'rotate_right'}) do
    self.actions[i].has_precedence_over_children = false
  end
  self.actions.focus_side_mouse.consumes_event = false

  self.split_position = 0.5
  self.is_vertical = true
  self.first = nil
  self.second = nil

  self.focused_side = nil
  self.mouse_is_resizing = false

  return self
end

function SplitView:draw()
  Widget.draw(self)
  if self.width <= 0 or self.height <= 0 then return end

  local x, y, w, h = self:first_bounds()
  if self.first then
    self.first:set_bounds(x, y, w, h)
    self.first:draw()
  else
    tty.set_face(self.focused_side == 'first' and self:is_focused() and self.faces.content or self.faces.content_unfocused)
    for i = 0, h - 1 do
      tty.move_to(x, y + i)
      tty.write((' '):rep(w))
    end
  end

  local x, y, w, h = self:second_bounds()
  if self.second then
    self.second:set_bounds(x, y, w, h)
    self.second:draw()
  else
    tty.set_face(self.focused_side == 'second' and self:is_focused() and self.faces.content or self.faces.content_unfocused)
    for i = 0, h - 1 do
      tty.move_to(x, y + i)
      tty.write((' '):rep(w))
    end
  end

  tty.set_face(not self.focused_side and self:is_focused() and self.faces.focused_separator or self.faces.separator)
  if self.is_vertical then
    local split_x = self:split_coord()
    for i = 0, self.height - 1 do
      tty.move_to(split_x, self.y + i)
      tty.write(' ')
    end
  else
    local split_y = self:split_coord()
    tty.move_to(self.x, split_y)
    tty.write((' '):rep(self.width))
  end
end

function SplitView:natural_size()
  local w1, h1, w2, h2 = 0, 0, 0, 0
  if self.first then
    w1, h1 = self.first:natural_size()
  end
  if self.second then
    w2, h2 = self.second:natural_size()
  end
  if self.is_vertical then
    return w1 + 1 + w2, math.max(h1, h2)
  else
    return math.max(w1, w2), h1 + 1 + h2
  end
end

function SplitView:first_bounds()
  if self.is_vertical then
    local split_x = self:split_coord()
    return self.x, self.y, split_x - self.x, self.height
  else
    local split_y = self:split_coord()
    return self.x, self.y, self.width, split_y - self.y
  end
end

function SplitView:second_bounds()
  if self.is_vertical then
    local split_x = self:split_coord()
    return split_x + 1, self.y, self.x + self.width - 1 - split_x, self.height
  else
    local split_y = self:split_coord()
    return self.x, split_y + 1, self.width, self.y + self.height - 1 - split_y
  end
end

function SplitView:split_coord()
  if self.is_vertical then
    return math.floor(0.5 + self.x + self.split_position * (self.width - 1))
  else
    return math.floor(0.5 + self.y + self.split_position * (self.height - 1))
  end
end

function SplitView:split_position_from_coord(value)
  if self.is_vertical then
    return (value - self.x) / (self.width - 1)
  else
    return (value - self.y) / (self.height - 1)
  end
end

function SplitView:children()
  return coroutine.wrap(function()
    if self.first then
      coroutine.yield(self.first)
    end
    if self.second then
      coroutine.yield(self.second)
    end
  end)
end

function SplitView:child_is_focused(child)
  return child == self[self.focused_side]
end

function SplitView:set_first(widget)
  if self.first then
    self.first.parent = nil
  end
  self.first = widget
  if widget then
    assert(not widget.parent)
    widget.parent = self
  end
end

function SplitView:set_second(widget)
  if self.second then
    self.second.parent = nil
  end
  self.second = widget
  if widget then
    assert(not widget.parent)
    widget.parent = self
  end
end

function SplitView:rotate_left()
  if self.is_vertical then
    self.first, self.second = self.second, self.first
    if self.focused_side then
      self.focused_side = self.focused_side == 'first' and 'second' or 'first'
    end
  end
  self.is_vertical = not self.is_vertical
end

function SplitView:rotate_right()
  if not self.is_vertical then
    self.first, self.second = self.second, self.first
    if self.focused_side then
      self.focused_side = self.focused_side == 'first' and 'second' or 'first'
    end
  end
  self.is_vertical = not self.is_vertical
end

function SplitView:split_focused_side()
  if not self.focused_side then return end
  local split = SplitView.new()
  if self.focused_side == 'first' then
    local child = self.first
    self:set_first(split)
    split:set_first(child)
    local _, _, width, height = self:first_bounds()
    split.is_vertical = width >= 2 * height
  else
    local child = self.second
    self:set_second(split)
    split:set_first(child)
    local _, _, width, height = self:second_bounds()
    split.is_vertical = width >= 2 * height
  end
end

-- BUG: merging a non-leaf split results in surprising behaviour
function SplitView:merge_focused_side()
  local child = self[self.focused_side]
  if getmetatable(child) ~= SplitView then
    return false
  end
  child = child:merge()
  self[self.focused_side] = child
  if child then
    child.parent = self
  end
  return true
end

function SplitView:merge()
  local result
  if not self.first or not self.second then
    result = self.first or self.second
  else
    if getmetatable(self.first) == TabView then
      result = self.first
    else
      result = TabView.new()
      result:set_open_tab_idx(result:add_tab(self.first))
    end
    if getmetatable(self.second) == TabView then
      for _, tab in ipairs(self.second.tabs) do
        tab.parent = nil
        result:insert_tab(#result.tabs + 1, tab)
      end
    else
      self.second.parent = nil
      result:insert_tab(#result.tabs + 1, self.second)
    end
  end
  if result then
    result.parent = nil
  end
  return result
end

function SplitView:move_focused_leaf_backward()
  local curr_parent, curr_side = self:focused_leaf()
  if not curr_parent then
    return false
  end
  local prev_parent, prev_side = self:prev_leaf(curr_parent, curr_side)
  if not prev_parent then
    return false
  end
  local curr = curr_parent[curr_side]
  local prev = prev_parent[prev_side]
  curr_parent[curr_side] = prev
  prev_parent[prev_side] = curr
  if prev then
    prev.parent = curr_parent
  end
  curr.parent = prev_parent
  self:focus_leaf(prev_parent, prev_side)
  return true
end

function SplitView:move_focused_leaf_forward()
  local curr_parent, curr_side = self:focused_leaf()
  if not curr_parent then
    return false
  end
  local next_parent, next_side = self:next_leaf(curr_parent, curr_side)
  if not next_parent then
    return false
  end
  local curr = curr_parent[curr_side]
  local next = next_parent[next_side]
  curr_parent[curr_side] = next
  next_parent[next_side] = curr
  if next then
    next.parent = curr_parent
  end
  curr.parent = next_parent
  self:focus_leaf(next_parent, next_side)
  return true
end

function SplitView:move_focused_leaf_tab_backward()
  local curr_parent, curr_side = self:focused_leaf()
  if not curr_parent then
    return false
  end
  local curr = curr_parent[curr_side]
  if getmetatable(curr) ~= TabView then
    return false
  end
  if not curr:move_open_tab_backward() and curr.open_tab_idx and #curr.tabs > 0 then
    local prev_parent, prev_side = self:prev_leaf(curr_parent, curr_side)
    if not prev_parent then
      return true
    end
    local prev = prev_parent[prev_side]
    if getmetatable(prev) ~= TabView then
      local tab_view = TabView.new()
      if prev then
        prev.parent = nil
        tab_view:add_tab(prev)
      end
      prev_parent[prev_side] = tab_view
      tab_view.parent = prev_parent
      prev = tab_view
    end
    local tab = curr:remove_tab_at(curr.open_tab_idx)
    prev:insert_tab(#prev.tabs + 1, tab)
    prev:set_open_tab_idx(#prev.tabs)
    self:focus_leaf(prev_parent, prev_side)
  end
  return true
end

function SplitView:move_focused_leaf_tab_forward()
  local curr_parent, curr_side = self:focused_leaf()
  if not curr_parent then
    return false
  end
  local curr = curr_parent[curr_side]
  if getmetatable(curr) ~= TabView then
    return false
  end
  if not curr:move_open_tab_forward() and curr.open_tab_idx and #curr.tabs > 0 then
    local next_parent, next_side = self:next_leaf(curr_parent, curr_side)
    if not next_parent then
      return true
    end
    local next = next_parent[next_side]
    if getmetatable(next) ~= TabView then
      local tab_view = TabView.new()
      if next then
        next.parent = nil
        tab_view:add_tab(next)
      end
      next_parent[next_side] = tab_view
      tab_view.parent = next_parent
      next = tab_view
    end
    local tab = curr:remove_tab_at(curr.open_tab_idx)
    next:insert_tab(1, tab)
    next:set_open_tab_idx(1)
    self:focus_leaf(next_parent, next_side)
  end
  return true
end

function SplitView:focus_leaf_with_num(num)
  local function walk(node)
    if getmetatable(node.first) == SplitView then
      if walk(node.first) then
        node.focused_side = 'first'
        return true
      end
    else
      if num == 1 then
        node.focused_side = 'first'
        return true
      end
      num = num - 1
    end
    if getmetatable(node.second) == SplitView then
      if walk(node.second) then
        node.focused_side = 'second'
        return true
      end
    else
      if num == 1 then
        node.focused_side = 'second'
        return true
      end
      num = num - 1
    end
    return false
  end
  return walk(self)
end

function SplitView:focus_prev_leaf()
  local branch = self:lowest_focused_split()
  if branch.focused_side then
    local parent, side = self:prev_leaf(branch, branch.focused_side)
    if not parent then
      return false
    end
    self:focus_leaf(parent, side)
  elseif getmetatable(branch.first) == SplitView then
    self:focus_leaf(branch.first:last_leaf())
  else
    self:focus_leaf(branch, 'first')
  end
  return true
end

function SplitView:focus_next_leaf()
  local branch = self:lowest_focused_split()
  if branch.focused_side then
    local parent, side = self:next_leaf(branch, branch.focused_side)
    if not parent then
      return false
    end
    self:focus_leaf(parent, side)
  else
    if getmetatable(branch.second) == SplitView then
      self:focus_leaf(branch.second:first_leaf())
    else
      self:focus_leaf(branch, 'second')
    end
  end
  return true
end

function SplitView:focus_leaf(parent, side)
  while true do
    parent.focused_side = side
    if parent == self then break end
    parent, side = self:node_parent(parent, side)
  end
end

function SplitView:focused_leaf()
  if not self.focused_side then
    return nil, nil
  end
  local child = self[self.focused_side]
  if getmetatable(child) ~= SplitView then
    return self, self.focused_side
  else
    return child:focused_leaf()
  end
end

function SplitView:lowest_focused_split()
  local child = self[self.focused_side]
  if getmetatable(child) ~= SplitView then
    return self
  else
    return child:lowest_focused_split()
  end
end

function SplitView:first_leaf()
  if getmetatable(self.first) ~= SplitView then
    return self, 'first'
  else
    return self.first:first_leaf()
  end
end

function SplitView:last_leaf()
  if getmetatable(self.second) ~= SplitView then
    return self, 'second'
  else
    return self.second:last_leaf()
  end
end

function SplitView:prev_leaf(parent, side)
  while side == 'first' and parent ~= self do
    parent, side = self:node_parent(parent, side)
  end
  if side == 'first' then
    return nil, nil
  end
  side = 'first'
  while true do
    local child = parent[side]
    if getmetatable(child) ~= SplitView then break end
    parent, side = child, 'second'
  end
  return parent, side
end

function SplitView:next_leaf(parent, side)
  while side == 'second' and parent ~= self do
    parent, side = self:node_parent(parent, side)
  end
  if side == 'second' then
    return nil, nil
  end
  side = 'second'
  while true do
    local child = parent[side]
    if getmetatable(child) ~= SplitView then break end
    parent, side = child, 'first'
  end
  return parent, side
end

function SplitView:node_parent(parent, side)
  assert(parent ~= self)
  local grandparent = parent.parent
  return grandparent, parent == grandparent.first and 'first' or 'second'
end

return SplitView
