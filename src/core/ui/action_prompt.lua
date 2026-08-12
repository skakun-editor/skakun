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
local stderr = require('core.stderr')
local tty    = require('core.tty')
local ui     = require('core.ui')
local Action = require('core.ui.action')
local List   = require('core.ui.list')

local ActionPrompt = setmetatable({
  name = 'Action Prompt',
  frame_title = 'Choose an Action to Run',
  faces = {
    item = {},
    hint = { foreground = 'bright_black' },
    selection = { foreground = 'black', background = 'white' },
    invalid = { foreground = 'black', background = 'red' },
  },
}, List)
ActionPrompt.__index = ActionPrompt

function ActionPrompt.new(path)
  local self = setmetatable(List.new(), ActionPrompt)
  self.faces = setmetatable({}, { __index = ActionPrompt.faces })

  local A = Action.Activator
  self:add_actions(
    Action.new(
      'activate',
      'Activate selected action',
      'Activates the currently selected action.',
      A.click('enter') | A.click('kp_enter'),
      function(action, event)
        self:activate_selected_item()
        self:close()
      end
    ),
    Action.new(
      'activate_keep_open',
      'Activate selected action and keep open',
      nil,
      A.click('ctrl+enter') | A.click('ctrl+kp_enter'),
      function(action, event)
        self:activate_selected_item()
      end
    )
  )

  self.search_field:set_name('Action Prompt')

  return self
end

function ActionPrompt:draw_item(action, x, y, width, is_selected)
  local hint = action.activation_hint or ''
  local hint_width = math.min(self.width, ui.text_width(hint))

  ui.draw_text(
    hint,
    x + width - hint_width, y,
    hint_width,
    0,
    is_selected and self.faces.selection or self.faces.hint,
    self.faces.invalid
  )

  local curr_x = ui.draw_text(
    action.widget.name .. ': ' .. action.name,
    x, y,
    width - hint_width,
    0,
    is_selected and self.faces.selection or self.faces.item,
    self.faces.invalid
  )
  tty.move_to(curr_x, y)
  tty.set_face(is_selected and self.faces.selection or self.faces.item)
  tty.write((' '):rep(x + width - hint_width - curr_x))
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

function ActionPrompt:close() end

function ActionPrompt:add_items_from_widget(widget, should_recurse)
  for _, action in ipairs(widget.actions) do
    table.insert(self.items, action)
  end
  if not should_recurse then return end
  for child in widget:focused_children() do
    self:add_items_from_widget(child, true)
  end
end

function ActionPrompt:item_label(action)
  return action.widget.name .. ': ' .. action.name .. ' ' .. (action.activation_hint or '')
end

return ActionPrompt
