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

local Action = require('core.ui.action')
local Frame  = require('core.ui.frame')
local List   = require('core.ui.list')

local ThemeSetter = {}
ThemeSetter.__index = ThemeSetter

function ThemeSetter.new(curr_theme)
  local self = setmetatable({
    themes = {},
    curr_theme = curr_theme,
  }, ThemeSetter)
  self.dialog = Frame.new(ThemeSetter.List.new(self))
  self.dialog:set_name('Theme Setter')
  return self
end

function ThemeSetter:add_theme(theme)
  for _, other in ipairs(self.themes) do
    if theme == other then return end
  end
  table.insert(self.themes, theme)
  table.sort(self.themes, function(a, b)
    return a.name < b.name
  end)
end

function ThemeSetter:require_themes(...)
  for i = 1, select('#', ...) do
    self:add_theme(require('theme.' .. select(i, ...)))
  end
end

function ThemeSetter:set_theme(theme)
  if self.curr_theme then
    self.curr_theme:unapply()
  end
  self.curr_theme = theme
  theme:apply()
  for i, other in ipairs(self.themes) do
    if theme == other then
      self.dialog.content:set_selected_item_idx(i)
      break
    end
  end
end

-- HACK: a nicer mechanism for this?

function ThemeSetter:show_dialog() end

function ThemeSetter:hide_dialog() end

ThemeSetter.List = setmetatable({
  name = 'Theme Setter',
  frame_title = 'Set the UI Theme',
  faces = {
    item = {},
    selection = { foreground = 'black', background = 'white' },
    invalid = { foreground = 'black', background = 'red' },
  },
}, List)
ThemeSetter.List.__index = ThemeSetter.List

function ThemeSetter.List.new(owner)
  local self = setmetatable(List.new(), ThemeSetter.List)
  self.faces = setmetatable({}, { __index = ThemeSetter.List.faces })

  local A = Action.Activator
  self:add_actions(
    Action.new(
      'apply',
      'Apply selected theme',
      'Activates the currently selected theme.',
      A.click('enter') | A.click('kp_enter'),
      function(action, event)
        self.owner:set_theme(self.items[self:selected_item_idx()])
        self.owner:hide_dialog()
        self:request_draw()
      end
    ),
    Action.new(
      'hide',
      'Hide',
      nil,
      A.click('escape'),
      function(action, event)
        self.owner:hide_dialog()
        self:request_draw()
      end
    )
  )

  self.owner = owner
  self.items = owner.themes

  return self
end

function ThemeSetter.List:item_label(theme)
  return theme.name
end

return ThemeSetter
