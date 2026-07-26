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

local here = ...
local grapheme  = require('core.grapheme')
local stderr    = require('core.stderr')
local tty       = require('core.tty')
local ui        = require('core.ui')
local Action    = require('core.ui.action')
local TextField = require('core.ui.text_field')
local Widget    = require('core.ui.widget')

local ActionPrompt = setmetatable({
  name = 'Action Prompt',
  scroll_speed = 3,
  faces = {
    name = {},
    hint = { foreground = 'bright_black' },
    selection = { foreground = 'black', background = 'white' },
    invalid = { foreground = 'black', background = 'red' },
  },
}, Widget)
ActionPrompt.__index = ActionPrompt

function ActionPrompt.new(path)
  local self = setmetatable(Widget.new(), ActionPrompt)
  self.faces = setmetatable({}, { __index = ActionPrompt.faces })

  self:add_actions(
    Action.new_simple(
      'activate',
      'Activate selected action',
      'Activates the currently selected action.',
      {'enter', 'kp_enter'},
      function(action, event)
        self:activate_selected_item()
      end
    ),
    Action.new_simple(
      'select_prev',
      'Select previous action',
      'Selects the action directly above the current one, if one exists.',
      'up',
      function(action, event)
        self:move_item_selection_up(1)
        self:request_draw()
      end
    ),
    Action.new_simple(
      'select_next',
      'Select next action',
      'Selects the action directly below the current one, if one exists.',
      'down',
      function(action, event)
        self:move_item_selection_down(1)
        self:request_draw()
      end
    ),
    Action.new_simple(
      'select_prev_page',
      'Select action on previous page',
      'Moves the action selection up by one visible page or as far as it is possible.',
      'page_up',
      function(action, event)
        self:move_item_selection_up(self.height - 1)
        self:request_draw()
      end
    ),
    Action.new_simple(
      'select_next_page',
      'Select action on next page',
      'Moves the action selection down by one visible page or as far as it is possible.',
      'page_down',
      function(action, event)
        self:move_item_selection_down(self.height - 1)
        self:request_draw()
      end
    ),
    Action.new_simple(
      'select_prev_scroll',
      'Scroll action selection up',
      'Moves the action selection up by the distance appropriate for a mouse scroll.',
      'scroll_up',
      function(action, event)
        self:move_item_selection_up(self.scroll_speed)
        self:request_draw()
      end
    ),
    Action.new_simple(
      'select_next_scroll',
      'Scroll action selection down',
      'Moves the action selection down by the distance appropriate for a mouse scroll.',
      'scroll_down',
      function(action, event)
        self:move_item_selection_down(self.scroll_speed)
        self:request_draw()
      end
    ),
    Action.new_simple(
      'select_first',
      'Select the first action',
      nil,
      'ctrl+home',
      function(action, event)
        for i, action in ipairs(self.items) do
          if self:should_show_item(action) then
            self:set_selected_item_idx(i)
            break
          end
        end
        self:request_draw()
      end
    ),
    Action.new_simple(
      'select_last',
      'Select the last action',
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
  self.search_field.name = self.name
  self.search_field.text = path or ''

  self.items = {}
  self._selected_item_idx = nil

  return self
end

function ActionPrompt:draw()
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

  for _, item_idx in ipairs(visible_items_idxs) do
    local action = self.items[item_idx]

    local hint = action.activation_hint or ''
    local hint_width = math.min(self.width, ui.text_width(hint))

    ui.draw_text(
      hint,
      self.x + self.width - hint_width, y,
      hint_width,
      0,
      item_idx == selected_item_idx and self.faces.selection or self.faces.hint,
      self.faces.invalid
    )

    local x = ui.draw_text(
      action.widget.name .. ': ' .. action.name,
      self.x, y,
      self.width - hint_width,
      0,
      item_idx == selected_item_idx and self.faces.selection or self.faces.name,
      self.faces.invalid
    )
    tty.move_to(x, y)
    tty.set_face(item_idx == selected_item_idx and self.faces.selection or self.faces.name)
    tty.write((' '):rep(self.x + self.width - hint_width - x))

    y = y + 1
  end

  tty.set_face(self.faces.name)
  while y < self.y + self.height do
    tty.move_to(self.x, y)
    tty.write((' '):rep(self.width))
    y = y + 1
  end
end

function ActionPrompt:move_item_selection_up(rowc)
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

function ActionPrompt:move_item_selection_down(rowc)
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

function ActionPrompt:activate_selected_item()
  local action = self.items[self:selected_item_idx()]
  if not action then
    return false
  end
  xpcall(
    action.activate,
    function(err)
      -- TODO: error pop up
      stderr.error(here, debug.traceback(err, 2))
    end,
    action
  )
  return true
end

function ActionPrompt:children()
  return coroutine.wrap(function()
    coroutine.yield(self.search_field)
  end)
end

function ActionPrompt:natural_size()
  local width = 0
  for _, action in ipairs(self.items) do
    width = math.max(width, ui.text_width(self:item_text(action)))
  end
  return width, (width + 2) // 3
end

function ActionPrompt:add_items_from_widget(widget, should_recurse)
  for _, action in ipairs(widget.actions) do
    table.insert(self.items, action)
  end
  if not should_recurse then return end
  for child in widget:focused_children() do
    self:add_items_from_widget(child, true)
  end
end

function ActionPrompt:should_show_item(action)
  local needle = grapheme.to_lowercase(self.search_field.text)
  if needle == '' then
    return true
  end
  local haystack = grapheme.to_lowercase(self:item_text(action))
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

function ActionPrompt:item_text(action)
  return action.widget.name .. ': ' .. action.name .. ' ' .. (action.activation_hint or '')
end

function ActionPrompt:selected_item_idx()
  local i = self._selected_item_idx
  if not self.items[i] or not self:should_show_item(self.items[i]) then
    i = 1
    while self.items[i] and not self:should_show_item(self.items[i]) do
      i = i + 1
    end
  end
  return i
end

function ActionPrompt:set_selected_item_idx(idx)
  self._selected_item_idx = idx
end

return ActionPrompt
