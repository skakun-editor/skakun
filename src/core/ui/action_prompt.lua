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
local grapheme   = require('core.grapheme')
local stderr     = require('core.stderr')
local tty        = require('core.tty')
local ui         = require('core.ui')
local Action     = require('core.ui.action')
local TextField  = require('core.ui.text_field')
local Widget     = require('core.ui.widget')
local SortedSet  = require('core.utils.sorted_set')

-- HACK: fix the name collision of "actions" with Widget properly

local ActionPrompt = setmetatable({
  name = 'Action Prompt',

  scroll_speed = 3,

  faces = { -- HACK: are you sure about these?
    name = {},
    name_invalid = { foreground = 'red' },
    hint = { foreground = 'bright_black' },
    hint_invalid = { foreground = 'red' },
    selection = { foreground = 'black', background = 'white' },
    selection_invalid = { foreground = 'red', background = 'white' },
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
        self:activate_selected_action()
      end
    ),
    Action.new_simple(
      'select_prev',
      'Select previous action',
      'Selects the action directly above the current one, if one exists.',
      'up',
      function(action, event)
        self:move_action_selection_up(1)
        self:request_draw()
      end
    ),
    Action.new_simple(
      'select_next',
      'Select next action',
      'Selects the action directly below the current one, if one exists.',
      'down',
      function(action, event)
        self:move_action_selection_down(1)
        self:request_draw()
      end
    ),
    Action.new_simple(
      'select_prev_page',
      'Select action on previous page',
      'Moves the action selection up by one visible page or as far as it is possible.',
      'page_up',
      function(action, event)
        self:move_action_selection_up(self.height - 1)
        self:request_draw()
      end
    ),
    Action.new_simple(
      'select_next_page',
      'Select action on next page',
      'Moves the action selection down by one visible page or as far as it is possible.',
      'page_down',
      function(action, event)
        self:move_action_selection_down(self.height - 1)
        self:request_draw()
      end
    ),
    Action.new_simple(
      'select_prev_scroll',
      'Scroll action selection up',
      'Moves the action selection up by the distance appropriate for a mouse scroll.',
      'scroll_up',
      function(action, event)
        self:move_action_selection_up(self.scroll_speed)
        self:request_draw()
      end
    ),
    Action.new_simple(
      'select_next_scroll',
      'Scroll action selection down',
      'Moves the action selection down by the distance appropriate for a mouse scroll.',
      'scroll_down',
      function(action, event)
        self:move_action_selection_down(self.scroll_speed)
        self:request_draw()
      end
    ),
    Action.new_simple(
      'select_first',
      'Select the first action',
      nil,
      'ctrl+home',
      function(action, event)
        for i, action in ipairs(self.listed_actions) do
          if self:should_show_action(action) then
            self:set_selected_action_idx(i)
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
        for i = #self.listed_actions, 1, -1 do
          if self:should_show_action(self.listed_actions[i]) then
            self:set_selected_action_idx(i)
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

  self.listed_actions = {}
  self._selected_action_idx = nil

  return self
end

function ActionPrompt:draw()
  Widget.draw(self)
  if self.width <= 0 or self.height <= 0 then return end

  self.search_field:set_bounds(self.x, self.y, self.width, 1)
  self.search_field:draw()

  local selected_action_idx = self:selected_action_idx()

  local visible_actions_idxs = {}
  local i = (selected_action_idx or 1) - 1
  while self.listed_actions[i] and #visible_actions_idxs < (self.height - 2) // 2 do
    if self:should_show_action(self.listed_actions[i]) then
      table.insert(visible_actions_idxs, 1, i)
    end
    i = i - 1
  end
  i = selected_action_idx or 1
  while self.listed_actions[i] and #visible_actions_idxs < self.height - 1 do
    if self:should_show_action(self.listed_actions[i]) then
      table.insert(visible_actions_idxs, i)
    end
    i = i + 1
  end

  local y = self.y + 1

  for _, action_idx in ipairs(visible_actions_idxs) do
    local action = self.listed_actions[action_idx]

    local hint = action.activation_hint or ''
    local hint_width = math.min(self.width, self:width_of_text(hint))
    self:draw_text(
      action.widget.name .. ': ' .. action.name,
      self.x, y, self.width - hint_width,
      action_idx == selected_action_idx and self.faces.selection or self.faces.name,
      action_idx == selected_action_idx and self.faces.selection_invalid or self.faces.name_invalid
    )
    self:draw_text(
      hint,
      self.x + self.width - hint_width, y, hint_width,
      action_idx == selected_action_idx and self.faces.selection or self.faces.hint,
      action_idx == selected_action_idx and self.faces.selection_invalid or self.faces.hint_invalid
    )

    y = y + 1
  end

  tty.set_face(self.faces.name)
  while y < self.y + self.height do
    tty.move_to(self.x, y)
    tty.write((' '):rep(self.width))
    y = y + 1
  end
end

function ActionPrompt:draw_text(text, x, y, width, face, invalid_face)
  local written = 0
  tty.move_to(x, y)

  for _, grapheme in grapheme.characters(text) do
    if not utf8.len(grapheme) then
      grapheme = '�'
      tty.set_face(invalid_face)
    elseif ui.ctrl_pics[grapheme] then
      grapheme = ui.ctrl_pics[grapheme]
      tty.set_face(invalid_face)
    else
      tty.set_face(face)
    end

    local grapheme_width = tty.width_of(grapheme)
    if written > width then break end
    if written + grapheme_width > width then
      grapheme = (' '):rep(width - written)
    end
    tty.write(grapheme)
    written = written + grapheme_width
  end

  tty.set_face(face)
  tty.write((' '):rep(width - written))
  if written > width then
    tty.move_to(x + width - 1, y)
    tty.write('…')
  end
end

function ActionPrompt:width_of_text(text)
  local result = 0
  for _, grapheme in grapheme.characters(text) do
    result = result + tty.width_of(not utf8.len(grapheme) and '�' or ui.ctrl_pics[grapheme] or grapheme)
  end
  return result
end

function ActionPrompt:move_action_selection_up(rowc)
  local i = self:selected_action_idx()
  if not i then return end
  local new_idx = i
  while self.listed_actions[i - 1] and rowc > 0 do
    i = i - 1
    if self:should_show_action(self.listed_actions[i]) then
      new_idx = i
      rowc = rowc - 1
    end
  end
  self:set_selected_action_idx(new_idx)
end

function ActionPrompt:move_action_selection_down(rowc)
  local i = self:selected_action_idx()
  if not i then return end
  local new_idx = i
  while self.listed_actions[i + 1] and rowc > 0 do
    i = i + 1
    if self:should_show_action(self.listed_actions[i]) then
      new_idx = i
      rowc = rowc - 1
    end
  end
  self:set_selected_action_idx(new_idx)
end

function ActionPrompt:activate_selected_action()
  local action = self.listed_actions[self:selected_action_idx()]
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

function ActionPrompt:idle()
  self.search_field:idle()
end

function ActionPrompt:children()
  return coroutine.wrap(function()
    coroutine.yield(1, self.search_field)
  end)
end

function ActionPrompt:natural_size()
  local width = 0
  for _, action in ipairs(self.listed_actions) do
    width = math.max(width, self:width_of_text(self:action_text(action)))
  end
  return width, (width + 2) // 3
end

function ActionPrompt:add_actions_of(widget, should_recurse)
  for _, action in ipairs(widget.actions) do
    table.insert(self.listed_actions, action)
  end
  if not should_recurse then return end
  for _, child in widget:children() do
    self:add_actions_of(child, true)
  end
end

function ActionPrompt:should_show_action(action)
  local needle = grapheme.to_lowercase(self.search_field.text)
  if needle == '' then
    return true
  end
  local haystack = grapheme.to_lowercase(self:action_text(action))
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

function ActionPrompt:action_text(action)
  return action.widget.name .. ': ' .. action.name .. ' ' .. (action.activation_hint or '')
end

function ActionPrompt:selected_action_idx()
  local i = self._selected_action_idx
  if not self.listed_actions[i] or not self:should_show_action(self.listed_actions[i]) then
    i = 1
    while self.listed_actions[i] and not self:should_show_action(self.listed_actions[i]) do
      i = i + 1
    end
  end
  return i
end

function ActionPrompt:set_selected_action_idx(idx)
  self._selected_action_idx = idx
end

return ActionPrompt
