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
local Navigator         = require('core.doc.navigator')
local SyntaxHighlighter = require('core.doc.syntax_highlighter')
local stderr            = require('core.stderr')
local tty               = require('core.tty')
local Widget            = require('core.ui.widget')
local utils             = require('core.utils')

local DocView = setmetatable({
  should_soft_wrap = false,
  faces = {
    normal = {},
    invalid = { foreground = 'red' },
    syntax_highlights = {},
  },
}, Widget)
DocView.__index = DocView

function DocView.new(doc)
  local self = setmetatable(Widget.new(), DocView)
  self.faces = setmetatable({}, { __index = DocView.faces })
  self.doc = doc
  self.line = 1
  self.col = 1
  return self
end

function DocView:draw()
  if self.should_soft_wrap then
    self:draw_soft_wrap()
  else
    self:draw_cut_off()
  end
end

local ctrl_pics = {
  ['\127'] = '␡',
  ['\r\n'] = '␍␊',
}
for i, ctrl_pic in ipairs({
  '␀', '␁', '␂', '␃', '␄', '␅', '␆', '␇', '␈', '␉', '␊', '␋', '␌', '␍', '␎', '␏',
  '␐', '␑', '␒', '␓', '␔', '␕', '␖', '␗', '␘', '␙', '␚', '␛', '␜', '␝', '␞', '␟',
}) do
  ctrl_pics[string.char(i - 1)] = ctrl_pic
end
for i = 0x80, 0x9f do
  ctrl_pics[utf8.char(i)] = '�'
end
ctrl_pics['\u{85}'] = '␤'

function DocView:draw_soft_wrap()
  self.doc.buffer:freeze()
  local nav = Navigator.of(self.doc.buffer)
  local highlighter = SyntaxHighlighter.of(self.doc.buffer)
  highlighter:refresh()

  local loc = nav:locate_line_col(self.line, self.col)
  local iter = self.doc.buffer:iter(loc.byte)

  for y = self.top, self.bottom do
    local x = self.left
    tty.move_to(x, y)

    while true do
      local grapheme, face = self:next_grapheme(iter, loc, nav, highlighter)
      tty.set_face(face)
      if not grapheme then
        loc.byte = loc.byte + iter:last_advance()
        loc.line = loc.line + 1
        loc.col = 1
        break
      end

      local width = tty.width_of(grapheme)
      if x + width - 1 > self.right then
        iter:rewind(iter:last_advance())
        break
      end

      tty.write(grapheme)
      x = x + width
      loc.byte = loc.byte + iter:last_advance()
      loc.col = loc.col + width
    end

    tty.write((' '):rep(self.right - x + 1))
  end
end

function DocView:draw_cut_off()
  self.doc.buffer:freeze()
  local nav = Navigator.of(self.doc.buffer)
  local highlighter = SyntaxHighlighter.of(self.doc.buffer)
  highlighter:refresh()

  for y = self.top, self.bottom do
    local x = self.left
    tty.move_to(x, y)

    local loc = nav:locate_line_col(self.line + y - self.top, self.col)
    local iter = self.doc.buffer:iter(loc.byte)

    if loc.col < self.col then
      local grapheme, face = self:next_grapheme(iter, loc, nav, highlighter)
      if not grapheme then
        iter:rewind(iter:last_advance())
      else
        tty.set_face(face)
        loc.byte = loc.byte + iter:last_advance()
        loc.col = loc.col + tty.width_of(grapheme)
        local width = loc.col - self.col
        if x + width - 1 > self.right then break end

        tty.write((' '):rep(width))
        x = x + width
      end
    end

    while true do
      local grapheme, face = self:next_grapheme(iter, loc, nav, highlighter)
      tty.set_face(face)
      if not grapheme then break end

      local width = tty.width_of(grapheme)
      if x + width - 1 > self.right then break end

      tty.write(grapheme)
      x = x + width
      loc.byte = loc.byte + iter:last_advance()
      loc.col = loc.col + width
    end

    tty.write((' '):rep(self.right - x + 1))
  end
end

function DocView:next_grapheme(iter, loc, nav, highlighter)
  local ok, grapheme = pcall(iter.next_grapheme, iter)
  if not ok then
    return '�', self.faces.invalid
  elseif not grapheme or grapheme == '\n' then
    return nil, self:get_syntax_highlight_face(highlighter.highlight_at[loc.byte])
  elseif grapheme == '\t' then
    return (' '):rep(nav.tab_width - (loc.col - 1) % nav.tab_width), self:get_syntax_highlight_face(highlighter.highlight_at[loc.byte])
  elseif ctrl_pics[grapheme] then
    return ctrl_pics[grapheme], self.faces.invalid
  else
    return grapheme, self:get_syntax_highlight_face(highlighter.highlight_at[loc.byte])
  end
end

function DocView:get_syntax_highlight_face(name)
  if not name then
    return self.faces.normal
  end

  local result = self.faces.syntax_highlights[name]
  if result then
    return result
  end

  local group = name
  while not result do
    group = group:match('(.*)%.')
    if not group then
      result = self.faces.normal
    else
      result = self.faces.syntax_highlights[group]
    end
  end
  self.faces.syntax_highlights[name] = result
  stderr.warn(here, ('inheriting syntax highlight face for %q from %q'):format(name, group))
  return result
end

function DocView:handle_event(event)
  if event.type == 'press' or event.type == 'repeat' then
    if event.button == 'up' then
      self.line = math.max(self.line - 1, 1)
    elseif event.button == 'scroll_up' then
      self.line = math.max(self.line - 3, 1)
    elseif event.button == 'page_up' then
      self.line = math.max(self.line - self:height(), 1)
    elseif event.button == 'left' then
      self.col = math.max(self.col - 1, 1)
    elseif event.button == 'down' then
      self.line = self.line + 1
    elseif event.button == 'scroll_down' then
      self.line = self.line + 3
    elseif event.button == 'page_down' then
      self.line = self.line + self:height()
    elseif event.button == 'right' then
      self.col = self.col + 1
    elseif event.button == 'w' then
      self.should_soft_wrap = not self.should_soft_wrap
    end
  end
end

return DocView

-- Every grapheme, once added, must have a constant width over its entire lifetime. In particular, it can't depend on its position in the text. The only hard-coded exception to this rule are tabs.
