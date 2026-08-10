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

local grapheme  = require('core.grapheme')
local tty       = require('core.tty')
local ui        = require('core.ui')
local Action    = require('core.ui.action')
local TextField = require('core.ui.text_field')
local Widget    = require('core.ui.widget')

local List = setmetatable({
  name = 'List',
  frame_title = 'Select an Item',
  scroll_speed = 3,
  faces = {
    item = {},
    selection = { foreground = 'black', background = 'white' },
    invalid = { foreground = 'black', background = 'red' },
  },
}, Widget)
List.__index = List

function List.new(path)
  local self = setmetatable(Widget.new(), List)
  self.faces = setmetatable({}, { __index = List.faces })

  self:add_actions(
    Action.new_simple(
      'select_prev',
      'Select previous item',
      'Selects the item directly above the current one, if one exists.',
      'up',
      function(action, event)
        self:move_item_selection_up(1)
        self:request_draw()
      end
    ),
    Action.new_simple(
      'select_next',
      'Select next item',
      'Selects the item directly below the current one, if one exists.',
      'down',
      function(action, event)
        self:move_item_selection_down(1)
        self:request_draw()
      end
    ),
    Action.new_simple(
      'select_prev_page',
      'Select item on previous page',
      'Moves the item selection up by one visible page or as far as it is possible.',
      'page_up',
      function(action, event)
        self:move_item_selection_up(self.height - 1)
        self:request_draw()
      end
    ),
    Action.new_simple(
      'select_next_page',
      'Select item on next page',
      'Moves the item selection down by one visible page or as far as it is possible.',
      'page_down',
      function(action, event)
        self:move_item_selection_down(self.height - 1)
        self:request_draw()
      end
    ),
    Action.new_simple(
      'select_prev_scroll',
      'Scroll item selection up',
      'Moves the item selection up by the distance appropriate for a mouse scroll.',
      'scroll_up',
      function(action, event)
        self:move_item_selection_up(self.scroll_speed)
        self:request_draw()
      end
    ),
    Action.new_simple(
      'select_next_scroll',
      'Scroll item selection down',
      'Moves the item selection down by the distance appropriate for a mouse scroll.',
      'scroll_down',
      function(action, event)
        self:move_item_selection_down(self.scroll_speed)
        self:request_draw()
      end
    ),
    Action.new_simple(
      'select_first',
      'Select the first item',
      nil,
      'ctrl+home',
      function(action, event)
        for i, item in ipairs(self.items) do
          if self:should_show_item(item) then
            self:set_selected_item_idx(i)
            break
          end
        end
        self:request_draw()
      end
    ),
    Action.new_simple(
      'select_last',
      'Select the last item',
      nil,
      'ctrl+end',
      function(action, event)
        for i = #self.items, 1, -1 do
          if self:should_show_item(self.items[i]) then
            self:set_selected_item_idx(i)
            break
          end
        end
        self:request_draw()
      end
    )
  )

  self.search_field = TextField.new()
  self.search_field.parent = self
  self.search_field:set_name(self.name)
  self.search_field.text = path or ''

  self.items = {}
  self._selected_item_idx = nil

  return self
end

function List:draw()
  Widget.draw(self)
  if self.width <= 0 or self.height <= 0 then return end

  self.search_field:set_bounds(self.x, self.y, self.width, 1)
  self.search_field:draw()

  local selected_item_idx = self:selected_item_idx()

  local visible_items_idxs = {}
  local i = (selected_item_idx or 1) - 1
  while self.items[i] and #visible_items_idxs < (self.height - 2) // 2 do
    if self:should_show_item(self.items[i]) then
      table.insert(visible_items_idxs, 1, i)
    end
    i = i - 1
  end
  i = selected_item_idx or 1
  while self.items[i] and #visible_items_idxs < self.height - 1 do
    if self:should_show_item(self.items[i]) then
      table.insert(visible_items_idxs, i)
    end
    i = i + 1
  end

  local y = self.y + 1

  for _, i in ipairs(visible_items_idxs) do
    self:draw_item(self.items[i], self.x, y, self.width, i == selected_item_idx)
    y = y + 1
  end

  tty.set_face(self.faces.item)
  while y < self.y + self.height do
    tty.move_to(self.x, y)
    tty.write((' '):rep(self.width))
    y = y + 1
  end
end

function List:draw_item(item, x, y, width, is_selected)
  local curr_x = ui.draw_text(
    self:item_label(item),
    x, y,
    width,
    0,
    is_selected and self.faces.selection or self.faces.item,
    self.faces.invalid
  )
  tty.write((' '):rep(x + width - curr_x))
end

function List:natural_size()
  local width = 0
  for _, item in ipairs(self.items) do
    width = math.max(width, ui.text_width(self:item_label(item)))
  end
  return width, (width + 2) // 3
end

function List:should_show_item(item)
  local needle = grapheme.to_lowercase(self.search_field.text)
  if needle == '' then
    return true
  end
  local haystack = grapheme.to_lowercase(self:item_label(item))
  local j = 1
  for i = 1, #haystack do
    if haystack:byte(i) == needle:byte(j) then
      j = j + 1
      if j > #needle then
        return true
      end
    end
  end
  return false
end

function List:item_label(item)
  return tostring(item)
end

function List:move_item_selection_up(rowc)
  local i = self:selected_item_idx()
  if not i then return end
  local new_idx = i
  while self.items[i - 1] and rowc > 0 do
    i = i - 1
    if self:should_show_item(self.items[i]) then
      new_idx = i
      rowc = rowc - 1
    end
  end
  self:set_selected_item_idx(new_idx)
end

function List:move_item_selection_down(rowc)
  local i = self:selected_item_idx()
  if not i then return end
  local new_idx = i
  while self.items[i + 1] and rowc > 0 do
    i = i + 1
    if self:should_show_item(self.items[i]) then
      new_idx = i
      rowc = rowc - 1
    end
  end
  self:set_selected_item_idx(new_idx)
end

function List:children()
  return coroutine.wrap(function()
    coroutine.yield(self.search_field)
  end)
end

function List:selected_item_idx()
  local i = self._selected_item_idx
  if not self.items[i] or not self:should_show_item(self.items[i]) then
    i = 1
    while self.items[i] and not self:should_show_item(self.items[i]) do
      i = i + 1
    end
  end
  return i
end

function List:set_selected_item_idx(idx)
  self._selected_item_idx = idx
end

return List
