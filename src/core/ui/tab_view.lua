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
local Action = require('core.ui.action')
local Widget = require('core.ui.widget')

local TabView = setmetatable({
  name = 'Tab View',
  scroll_speed = 3,
  view_containment_margin = 2,
  faces = {
    tab = { background = 'bright_black' },
    open_tab = { foreground = 'black', background = 'bright_white' },
    content = {},
    content_unfocused = {},
    invalid = { foreground = 'black', background = 'red' },
  },
}, Widget)
TabView.__index = TabView

function TabView.new()
  local self = setmetatable(Widget.new(), TabView)
  self.faces = setmetatable({}, { __index = TabView.faces })

  local A = Action.Activator
  self:add_actions(
    Action.new(
      'open_mouse',
      'Open tab under mouse pointer',
      nil,
      A.click('mouse_left') & function(event)
        return self.x <= event.x and event.x < self.x + self.width and event.y == self.y
      end,
      function(action, event)
        local x = self.x - self.tab_bar_scroll
        for i, tab in ipairs(self.tabs) do
          local width = ui.text_width(self:tab_label(tab))
          if x <= event.x and event.x < x + width then
            self:set_open_tab_idx(i)
            self:request_draw()
            break
          end
          x = x + width
        end
      end
    ),
    Action.new(
      'open_num',
      'Open nth tab',
      nil,
      A.click('alt+', function(button)
        return tonumber(button)
      end):with_hint(ui.modifier_syms.alt .. '[1-9,0]'),
      function(action, event)
        local n = event.button == '0' and 10 or tonumber(event.button)
        if n <= #self.tabs then
          self:set_open_tab_idx(n)
        end
        self:request_draw()
      end
    ),
    Action.new(
      'open_prev',
      'Open previous tab',
      nil,
      A.click('alt+page_up'),
      function(action, event)
        if self.open_tab_idx then
          self:set_open_tab_idx(math.max(1, self.open_tab_idx - 1))
        elseif #self.tabs > 0 then
          self:set_open_tab_idx(#self.tabs)
        end
        self:request_draw()
      end
    ),
    Action.new(
      'open_next',
      'Open next tab',
      nil,
      A.click('alt+page_down'),
      function(action, event)
        if self.open_tab_idx then
          self:set_open_tab_idx(math.min(#self.tabs, self.open_tab_idx + 1))
        elseif #self.tabs > 0 then
          self:set_open_tab_idx(1)
        end
        self:request_draw()
      end
    ),
    Action.new(
      'remove',
      'Remove tab',
      nil,
      A.click('ctrl+w'),
      function(action, event)
        if self.open_tab_idx then
          self:remove_tab_at(self.open_tab_idx)
          self:request_draw()
          action.consumes_event = true
        else
          action.consumes_event = false
        end
      end
    ),
    Action.new(
      'move_backward',
      'Move tab left',
      nil,
      A.click('alt+shift+page_up'),
      function(action, event)
        if self:move_open_tab_backward() then
          self:request_draw()
        end
      end
    ),
    Action.new(
      'move_forward',
      'Move tab right',
      nil,
      A.click('alt+shift+page_down'),
      function(action, event)
        if self:move_open_tab_forward() then
          self:request_draw()
        end
      end
    ),
    Action.new(
      'scroll_backward',
      'Scroll left',
      nil,
      (A.click('scroll_up') | A.click('scroll_left')) & function(event)
        return self.x <= event.x and event.x < self.x + self.width and event.y == self.y
      end,
      function(action, event)
        self.tab_bar_scroll = math.max(0, self.tab_bar_scroll - self.scroll_speed)
        self:request_draw()
      end
    ),
    Action.new(
      'scroll_forward',
      'Scroll right',
      nil,
      (A.click('scroll_down') | A.click('scroll_right')) & function(event)
        return self.x <= event.x and event.x < self.x + self.width and event.y == self.y
      end,
      function(action, event)
        local width = 0
        for _, tab in ipairs(self.tabs) do
          width = width + ui.text_width(self:tab_label(tab))
        end
        self.tab_bar_scroll = math.max(0, math.min(width - self.width, self.tab_bar_scroll + self.scroll_speed))
        self:request_draw()
      end
    )
  )
  self.actions.remove.has_precedence_over_children = false

  self.tabs = {}
  self.open_tab_idx = nil
  self.tab_bar_scroll = 0

  return self
end

function TabView:draw()
  Widget.draw(self)
  if self.width <= 0 or self.height <= 0 then return end

  local tabs_are_drawn = #self.tabs >= 2

  local content = self.tabs[self.open_tab_idx]
  if content then
    content:set_bounds(self.x, self.y + (tabs_are_drawn and 1 or 0), self.width, self.height - (tabs_are_drawn and 1 or 0))
    content:draw()
  else
    tty.set_face(self:is_focused() and self.faces.content or self.faces.content_unfocused)
    for i = tabs_are_drawn and 1 or 0, self.height - 1 do
      tty.move_to(self.x, self.y + i)
      tty.write((' '):rep(self.width))
    end
  end

  if not tabs_are_drawn then return end

  -- BUG: ellipses are not drawn if the first/last tab fully fits
  local x, scroll = self.x, self.tab_bar_scroll
  for i, tab in ipairs(self.tabs) do
    x, scroll = ui.draw_text(
      self:tab_label(tab),
      x, self.y,
      self.width - (x - self.x),
      scroll,
      i == self.open_tab_idx and self.faces.open_tab or self.faces.tab,
      self.faces.invalid
    )
  end
  tty.move_to(x, self.y)
  tty.set_face(self.faces.tab)
  tty.write((' '):rep(self.x + self.width - x))
end

function TabView:natural_size()
  local tab = self.tabs[self.open_tab_idx]
  local w, h = 0, 0
  if tab then
    w, h = tab:natural_size()
  end
  return w, h + (#self.tabs > 1 and 1 or 0)
end

function TabView:children()
  return coroutine.wrap(function()
    for _, tab in ipairs(self.tabs) do
      coroutine.yield(tab)
    end
  end)
end

function TabView:child_is_focused(child)
  return child == self.tabs[self.open_tab_idx]
end

function TabView:insert_tab(idx, widget)
  assert(not widget.parent)
  widget.parent = self
  table.insert(self.tabs, idx, widget)
  if self.open_tab_idx and self.open_tab_idx >= idx then
    self:set_open_tab_idx(self.open_tab_idx + 1)
  end
end

function TabView:add_tab(widget)
  if self.open_tab_idx then
    self:insert_tab(self.open_tab_idx + 1, widget)
    return self.open_tab_idx + 1
  else
    self:insert_tab(#self.tabs + 1, widget)
    return #self.tabs
  end
end

function TabView:remove_tab_at(idx)
  local tab = table.remove(self.tabs, idx)
  tab.parent = nil
  if #self.tabs == 0 then
    self:set_open_tab_idx(nil)
  elseif self.open_tab_idx > #self.tabs then
    self:set_open_tab_idx(#self.tabs)
  end
  return tab
end

function TabView:set_open_tab_idx(idx)
  self.open_tab_idx = idx
  self:adjust_view_to_contain_open_tab()
end

function TabView:move_open_tab_backward()
  local i = self.open_tab_idx
  if not i or i <= 1 then
    return false
  end
  self.tabs[i - 1], self.tabs[i] = self.tabs[i], self.tabs[i - 1]
  self:set_open_tab_idx(i - 1)
  return true
end

function TabView:move_open_tab_forward()
  local i = self.open_tab_idx
  if not i or i >= #self.tabs then
    return false
  end
  self.tabs[i], self.tabs[i + 1] = self.tabs[i + 1], self.tabs[i]
  self:set_open_tab_idx(i + 1)
  return true
end

function TabView:adjust_view_to_contain_open_tab()
  if self.open_tab_idx then
    self:adjust_view_to_contain_tab_at(self.open_tab_idx)
  end
end

function TabView:adjust_view_to_contain_tab_at(idx)
  local offset = 0
  for i = 1, idx - 1 do
    offset = offset + ui.text_width(self:tab_label(self.tabs[i]))
  end
  local width = ui.text_width(self:tab_label(self.tabs[idx]))
  local all_width = offset + width
  for i = idx + 1, #self.tabs do
    all_width = all_width + ui.text_width(self:tab_label(self.tabs[i]))
  end
  if self.width then
    local margin = math.min(self.view_containment_margin, (self.width - width) // 2)
    self.tab_bar_scroll = math.max(math.min(self.tab_bar_scroll, offset - margin), offset + width + margin - self.width)
    self.tab_bar_scroll = math.max(math.min(self.tab_bar_scroll, all_width - self.width), 0)
  else
    self.tab_bar_scroll = math.max(offset - self.view_containment_margin, 0)
  end
end

function TabView:tab_label(widget)
  return ' ' .. (widget.tab_title or widget.name or tostring(widget)) .. ' '
end

return TabView
