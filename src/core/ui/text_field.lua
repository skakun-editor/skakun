-- Skakun - A robust and hackable hex and text editor
-- Copyright (C) 2024-2025 Karol "digitcrusher" Łacina
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
local grapheme = require('core.grapheme')
local stderr   = require('core.stderr')
local tty      = require('core.tty')
local ui       = require('core.ui')
local Widget   = require('core.ui.widget')
local utils    = require('core.utils')

local TextField = setmetatable({
  history_commit_delay = 1,
  view_containment_margin = 2,
  faces = {
    normal = {},
    invalid = { foreground = 'red' },
    ellipsis = { foreground = 'white' },
  },
  colors = {
    cursor = 'white',
    cursor_foreground = 'black',
  },
}, Widget)
TextField.__index = TextField

function TextField.new()
  local self = setmetatable(Widget.new(), TextField)
  self.faces = setmetatable({}, { __index = TextField.faces })

  self.text = ''
  self.cursor = 1

  self.history = {}
  self.cursor_history = {}
  self.history_idx = nil
  self.last_edit_time = -math.huge
  self.cursor_after_edit = 1

  self.view_start = 1
  self.is_mouse_dragging_cursor = false

  return self
end

function TextField:draw()
  Widget.draw(self)
  if self.width == 0 or self.height == 0 then return end

  tty.move_to(self.x, self.y)
  local x = self.x - self.view_start + 1
  for i, grapheme in grapheme.characters(self.text) do
    local is_invalid = false
    if not utf8.len(grapheme) then
      grapheme = '�'
      is_invalid = true
    elseif ui.ctrl_pics[grapheme] then
      grapheme = ui.ctrl_pics[grapheme]
      is_invalid = true
    end

    local width = tty.width_of(grapheme)
    if x >= self.x + self.width then break end
    if x + width > self.x then
      if x < self.x or x + width > self.x + self.width then
        grapheme = (' '):rep(math.min(x + width - self.x, self.x + self.width - x))
      end
      tty.set_face(not is_invalid and self.faces.normal or self.faces.invalid)
      if i == self.cursor then
        tty.set_background(self.colors.cursor)
        tty.set_foreground(self.colors.cursor_foreground)
      end
      tty.write(grapheme)
    end
    x = x + width
  end

  if x >= self.x + self.width then
    tty.set_face(self.faces.ellipsis)
    tty.move_to(self.x + self.width - 1, self.y)
    tty.write('…')

  else
    tty.set_face(self.faces.normal)
    if self.cursor == #self.text + 1 and x < self.x + self.width then
      tty.set_background(self.colors.cursor)
      tty.set_foreground(self.colors.cursor_foreground)
      tty.write(' ')
      x = x + 1
      tty.set_face(self.faces.normal)
    end
    while x < self.x + self.width do
      tty.write(' ')
      x = x + 1
    end
  end

  if self.view_start > 1 then
    tty.set_face(self.faces.ellipsis)
    tty.move_to(self.x, self.y)
    tty.write('…')
  end
end

function TextField:handle_event(event)
  if event.type == 'press' and event.button == 'mouse_left' or event.type == 'move' then
    if event.type == 'press' then
      self.is_mouse_dragging_cursor = true
    end
    if self.is_mouse_dragging_cursor and utils.is_point_in_rect(event.x, event.y, self:drawn_bounds()) then
      -- We can't process these events as though the user were interacting with
      -- the state actually visible on their screen because, in contrast to
      -- DocView, we have no way to send cursor positions across time. So we
      -- just give up completely and don't go through the hastle of trying to
      -- achieve a partial result.
      self.cursor = #self.text + 1
      local x = self.drawn.x - self.view_start + 1
      for i, grapheme in grapheme.characters(self.text) do
        x = x + tty.width_of(utf8.len(grapheme) and grapheme or '�')
        if event.x < x then
          self.cursor = i
          break
        end
      end
      self:adjust_view_to_contain_idx(self.cursor)
      self:queue_draw()
    end

  elseif event.type == 'release' and event.button == 'mouse_left' then
    self.is_mouse_dragging_cursor = false

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'left' then
    local old_cursor = self.cursor
    for i in (event.ctrl and grapheme.words or grapheme.characters)(self.text) do
      if i >= old_cursor then break end
      self.cursor = i
    end
    self:adjust_view_to_contain_idx(self.cursor)
    self:queue_draw()

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'right' then
    local old_cursor = self.cursor
    for i in (event.ctrl and grapheme.words or grapheme.characters)(self.text) do
      if i > self.cursor then
        self.cursor = i
        break
      end
    end
    if self.cursor == old_cursor then
      self.cursor = #self.text + 1
    end
    self:adjust_view_to_contain_idx(self.cursor)
    self:queue_draw()

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'home' then
    self.cursor = 1
    self:adjust_view_to_contain_idx(self.cursor)
    self:queue_draw()

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'end' then
    self.cursor = #self.text + 1
    self:adjust_view_to_contain_idx(self.cursor)
    self:queue_draw()

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'z' and event.ctrl then
    if not self.history_idx then
      if self.history[#self.history] ~= self.text then
        table.insert(self.history, self.text)
        table.insert(self.cursor_history, self.cursor_after_edit)
      end
      self.history_idx = #self.history
    end
    self.history_idx = math.max(self.history_idx - 1, 1)
    self.text = self.history[self.history_idx]
    self.cursor = self.cursor_history[self.history_idx]
    self:adjust_view_to_contain_idx(self.cursor)
    self:queue_draw()

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'y' and event.ctrl then
    if not self.history_idx then
      if self.history[#self.history] ~= self.text then
        table.insert(self.history, self.text)
        table.insert(self.cursor_history, self.cursor_after_edit)
      end
      self.history_idx = #self.history
    end
    self.history_idx = math.min(self.history_idx + 1, #self.history)
    self.text = self.history[self.history_idx]
    self.cursor = self.cursor_history[self.history_idx]
    self:adjust_view_to_contain_idx(self.cursor)
    self:queue_draw()

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'backspace' then
    self:update_history_before_edit()
    local from = 1
    for i in (event.ctrl and grapheme.words or grapheme.characters)(self.text) do
      if i >= self.cursor then break end
      from = i
    end
    self.text = self.text:sub(1, from - 1) .. self.text:sub(self.cursor)
    self.cursor = from
    self:update_history_after_edit()
    self:adjust_view_to_contain_idx(self.cursor)
    self:queue_draw()

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'delete' then
    self:update_history_before_edit()
    local to = #self.text + 1
    for i in (event.ctrl and grapheme.words or grapheme.characters)(self.text) do
      if i > self.cursor then
        to = i
        break
      end
    end
    self.text = self.text:sub(1, self.cursor - 1) .. self.text:sub(to)
    self:update_history_after_edit()
    self:queue_draw()

  elseif event.text then
    self:update_history_before_edit()
    self.text = self.text:sub(1, self.cursor - 1) .. event.text .. self.text:sub(self.cursor)
    self.cursor = self.cursor + #event.text
    self:update_history_after_edit()
    self:adjust_view_to_contain_idx(self.cursor)
    self:queue_draw()
  end
end

function TextField:adjust_view_to_contain_idx(idx)
  local col = 1
  for i, grapheme in grapheme.characters(self.text) do
    if idx < i + #grapheme then break end
    col = col + tty.width_of(utf8.len(grapheme) and grapheme or '�')
  end
  local margin = math.min(self.view_containment_margin, (self.width - 1) // 2)
  self.view_start = math.max(math.min(self.view_start, col - margin), col + margin - self.width + 1, 1)
end

function TextField:update_history_before_edit()
  local now = utils.timer()
  if self.history_idx then
    for i = self.history_idx + 1, #self.history do
      self.history[i] = nil
      self.cursor_history[i] = nil
    end
    self.history_idx = nil
  elseif now - self.last_edit_time >= self.history_commit_delay and self.history[#self.history] ~= self.text then
    table.insert(self.history, self.text)
    table.insert(self.cursor_history, self.cursor_after_edit)
  end
  self.last_edit_time = now
end

function TextField:update_history_after_edit()
  self.cursor_after_edit = self.cursor
end

return TextField
