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
local SpellChecker      = require('core.doc.spell_checker')
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
  colors = {
    misspelling = 'red',
  },
}, Widget)
DocView.__index = DocView

function DocView.new(doc)
  local self = setmetatable(Widget.new(), DocView)
  self.faces = setmetatable({}, { __index = DocView.faces })
  self.doc = doc
  self.line = 1
  self.col = 1
  self:clear_selections()
  self:insert_selection(1, 0)
  return self
end

function DocView:draw()
  self.drawn_buffer = self.doc.buffer
  local ctx = {
    navigator = Navigator.of(self.drawn_buffer),
    syntax_highlighter = SyntaxHighlighter.of(self.drawn_buffer),
    spell_checker = SpellChecker.of(self.drawn_buffer),
  }
  ctx.syntax_highlighter:refresh()
  self:sync_selections()
  self:layout_lines(ctx)
  self:draw_lines(ctx)
end

function DocView:layout_lines(ctx)
  self.drawn_lines = {}
  if self.should_soft_wrap then
    --[[
    local line, col = self.line, self.col
    for i = 0, self.bottom - self.top do
      self.drawn_lines[i + 1] = { line = line, col = col }
      local loc =
      if ctx.navigator:locate_grapheme(ctx.navigator:locate_line_col(line, col + self:width()).grapheme) ==  then

    end]]--
  else
    for i = 1, self:height() do
      self.drawn_lines[i] = { line = self.line + i - 1, col = self.col }
    end
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

function DocView:draw_lines(ctx)
  for y = self.top, self.bottom do
    local x = self.left
    tty.move_to(x, y)

    local line_start = self.drawn_lines[y - self.top + 1]
    ctx.loc = ctx.navigator:locate_line_col(line_start.line, line_start.col)
    ctx.iter = self.drawn_buffer:iter(ctx.loc.byte)

    if ctx.loc.col < line_start.col then
      local grapheme = self:next_grapheme(ctx)
      if not grapheme then
        ctx.iter:rewind(ctx.iter:last_advance())
      else
        ctx.loc.byte = ctx.loc.byte + ctx.iter:last_advance()
        ctx.loc.col = ctx.loc.col + tty.width_of(grapheme)
        local width = ctx.loc.col - self.col
        if x + width - 1 > self.right then break end

        tty.write((' '):rep(width))
        x = x + width
      end
    end

    while true do
      local grapheme = self:next_grapheme(ctx)
      if not grapheme then break end

      local width = tty.width_of(grapheme)
      if x + width - 1 > self.right then break end

      tty.write(grapheme)
      x = x + width
      ctx.loc.byte = ctx.loc.byte + ctx.iter:last_advance()
      ctx.loc.col = ctx.loc.col + width
    end

    tty.write((' '):rep(self.right - x + 1))
  end
end

function DocView:next_grapheme(ctx)
  local ok, result = pcall(ctx.iter.next_grapheme, ctx.iter)
  local is_invalid = false
  if not ok then
    result = '�'
    is_invalid = true
  elseif not result or result == '\n' then
    result = nil
  elseif result == '\t' then
    result = (' '):rep(ctx.navigator.tab_width - (loc.col - 1) % ctx.navigator.tab_width)
  elseif ctrl_pics[result] then
    result = ctrl_pics[result]
    is_invalid = true
  end

  tty.set_face(is_invalid and self.faces.invalid or self:get_syntax_highlight_face(ctx.syntax_highlighter.highlight_at[ctx.loc.byte]))
  if ctx.spell_checker.is_correct[ctx.loc.byte] == false then
    tty.set_underline(true)
    tty.set_underline_color(self.colors.misspelling)
    tty.set_underline_shape('curly')
  end

  local sels, i = self.selections, ctx.curr_selection or 1
  while i <= #sels and sels[i].idx + math.max(sels[i].len, 0) < ctx.loc.byte do
    i = i + 1
  end
  ctx.curr_selection = i
  if i <= #sels then
    local sel = sels[i]
    if ctx.loc.byte == sel.idx + sel.len then
      tty.set_background(tty.Rgb.from('888888'))
    elseif sel.idx + math.min(sel.len, 0) <= ctx.loc.byte then
      tty.set_background(tty.Rgb.from('444444'))
    end
  end

  return result
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

function DocView:buffer_idx_at(x, y)
  if not utils.is_point_in_rect(x, y, self.left, self.top, self.right, self.bottom) then
    return nil
  end
  local line_start = self.drawn_lines[y - self.top + 1]
  return self.doc.buffer:carry_idx_over(Navigator.of(self.drawn_buffer):locate_line_col(line_start.line, line_start.col + x - self.left).byte, self.drawn_buffer)
end

function DocView:handle_event(event)
  if event.type == 'press' and event.button == 'mouse_left' then
    if utils.is_point_in_rect(event.x, event.y, self.left, self.top, self.right, self.bottom) then
      local cursor = self:buffer_idx_at(event.x, event.y)
      if not event.shift then
        if event.alt then
          self:sync_selections()
        else
          self:clear_selections()
        end
        self:insert_selection(cursor, 0)
      end
      local sel = self.selections[self.latest_selection_idx]
      sel.len = cursor - sel.idx
      self:merge_overlapping_selections(sel.len)
      self.is_mouse_dragging_selection = true
    end

  elseif event.type == 'move' then
    if self.is_mouse_dragging_selection and utils.is_point_in_rect(event.x, event.y, self.left, self.top, self.right, self.bottom) then
      local sel = self.selections[self.latest_selection_idx]
      sel.len = self:buffer_idx_at(event.x, event.y) - sel.idx
      self:merge_overlapping_selections(sel.len)
    end

  elseif event.type == 'release' and event.button == 'mouse_left' then
    self.is_mouse_dragging_selection = false

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'left' then
    self:sync_selections()
    local nav = Navigator.of(self.doc.buffer)
    for _, sel in ipairs(self.selections) do
      if not event.shift and sel.len ~= 0 then
        sel.idx = sel.idx + math.min(sel.len, 0)
        sel.len = 0
      else
        local cursor = nav:locate_grapheme(nav:locate_byte(sel.idx + sel.len).grapheme - 1).byte
        if event.shift then
          sel.len = cursor - sel.idx
        else
          sel.idx = cursor
        end
      end
      sel.col_hint = nil
    end
    self:merge_overlapping_selections(-1)

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'right' then
    self:sync_selections()
    local nav = Navigator.of(self.doc.buffer)
    for _, sel in ipairs(self.selections) do
      if not event.shift and sel.len ~= 0 then
        sel.idx = sel.idx + math.max(sel.len, 0)
        sel.len = 0
      else
        local cursor = nav:locate_grapheme(nav:locate_byte(sel.idx + sel.len).grapheme + 1).byte
        if event.shift then
          sel.len = cursor - sel.idx
        else
          sel.idx = cursor
        end
      end
      sel.col_hint = nil
    end
    self:merge_overlapping_selections(1)

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'up' then
    self:sync_selections()
    local nav = Navigator.of(self.doc.buffer)
    for _, sel in ipairs(self.selections) do
      local loc = nav:locate_byte(sel.idx + sel.len)
      sel.col_hint = sel.col_hint or loc.col
      local cursor = nav:locate_line_col(loc.line - 1, sel.col_hint).byte
      if event.shift then
        sel.len = cursor - sel.idx
      else
        sel.idx = cursor
        sel.len = 0
      end
    end
    self:merge_overlapping_selections(-1)

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'down' then
    self:sync_selections()
    local nav = Navigator.of(self.doc.buffer)
    for _, sel in ipairs(self.selections) do
      local loc = nav:locate_byte(sel.idx + sel.len)
      sel.col_hint = sel.col_hint or loc.col
      local cursor = nav:locate_line_col(loc.line + 1, sel.col_hint).byte
      if event.shift then
        sel.len = cursor - sel.idx
      else
        sel.idx = cursor
        sel.len = 0
      end
    end
    self:merge_overlapping_selections(1)

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'home' then
    self:sync_selections()
    local nav = Navigator.of(self.doc.buffer)
    for _, sel in ipairs(self.selections) do
      local cursor = nav:locate_line_col(nav:locate_byte(sel.idx + sel.len).line, 1).byte
      if event.shift then
        sel.len = cursor - sel.idx
      else
        sel.idx = cursor
        sel.len = 0
      end
      sel.col_hint = nil
    end
    self:merge_overlapping_selections(-1)

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'end' then
    self:sync_selections()
    local nav = Navigator.of(self.doc.buffer)
    for _, sel in ipairs(self.selections) do
      local cursor = nav:locate_line_col(nav:locate_byte(sel.idx + sel.len).line, math.huge).byte
      if event.shift then
        sel.len = cursor - sel.idx
      else
        sel.idx = cursor
        sel.len = 0
      end
      sel.col_hint = nil
    end
    self:merge_overlapping_selections(1)

  elseif (event.type == 'press' or event.type == 'repeat') and event.ctrl and event.button == 'z' then
    if self.doc.buffer.parent then
      self.doc:set_buffer(self.doc.buffer.parent)
    end

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'backspace' then
    self:sync_selections()
    local buffer = self.doc.buffer:thaw()
    local nav = Navigator.of(self.doc.buffer)
    local shift = 0
    for _, sel in ipairs(self.selections) do
      sel.idx = sel.idx + shift
      if sel.len > 0 then
        buffer:delete(sel.idx, sel.idx + sel.len - 1)
        shift = shift - sel.len
        sel.len = 0
      elseif sel.len < 0 then
        buffer:delete(sel.idx + sel.len + 1, sel.idx)
        shift = shift + sel.len
        sel.idx = sel.idx + sel.len + 1
        sel.len = 0
      elseif sel.idx > 1 then
        local from = nav:locate_grapheme(nav:locate_byte(sel.idx).grapheme - 1).byte
        buffer:delete(from, sel.idx - 1)
        shift = shift - (sel.idx - from)
        sel.idx = from
      end
      sel.col_hint = nil
    end
    self:merge_overlapping_selections()
    self.doc:set_buffer(buffer)
    self.selections_set_buffer_log_idx = #self.doc.set_buffer_log

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'delete' then
    self:sync_selections()
    local buffer = self.doc.buffer:thaw()
    local nav = Navigator.of(self.doc.buffer)
    local shift = 0
    for _, sel in ipairs(self.selections) do
      sel.idx = sel.idx + shift
      if sel.len > 0 then
        buffer:delete(sel.idx, sel.idx + sel.len - 1)
        shift = shift - sel.len
        sel.len = 0
      elseif sel.len < 0 then
        buffer:delete(sel.idx + sel.len + 1, sel.idx)
        shift = shift + sel.len
        sel.idx = sel.idx + sel.len + 1
        sel.len = 0
      elseif sel.idx > 1 then
        local to = nav:locate_grapheme(nav:locate_byte(sel.idx).grapheme + 1).byte
        buffer:delete(sel.idx, to - 1)
        shift = shift - (to - sel.idx)
      end
      sel.col_hint = nil
    end
    self:merge_overlapping_selections()
    self.doc:set_buffer(buffer)
    self.selections_set_buffer_log_idx = #self.doc.set_buffer_log

  elseif event.text then
    self:sync_selections()
    local buffer = self.doc.buffer:thaw()
    local shift = 0
    for _, sel in ipairs(self.selections) do
      sel.idx = sel.idx + shift
      if sel.len > 0 then
        buffer:delete(sel.idx, sel.idx + sel.len - 1)
        shift = shift - sel.len
        sel.len = 0
      elseif sel.len < 0 then
        buffer:delete(sel.idx + sel.len + 1, sel.idx)
        shift = shift + sel.len
        sel.idx = sel.idx + sel.len + 1
        sel.len = 0
      end
      buffer:insert(sel.idx, event.text)
      shift = shift + #event.text
      sel.idx = sel.idx + #event.text
      sel.col_hint = nil
    end
    self:merge_overlapping_selections()
    self.doc:set_buffer(buffer)
    self.selections_set_buffer_log_idx = #self.doc.set_buffer_log
  end
end

function DocView:sync_selections()
  for k = self.selections_set_buffer_log_idx + 1, #self.doc.set_buffer_log do
    local buffer = self.doc.set_buffer_log[k]
    for _, sel in ipairs(self.selections) do
      local old_cursor = sel.idx + sel.len
      sel.len = buffer:carry_idx_over(old_cursor, self.doc.set_buffer_log[self.selections_set_buffer_log_idx])
      if sel.len ~= old_cursor then
        sel.col_hint = nil
      end
      sel.idx = buffer:carry_idx_over(sel.idx, self.doc.set_buffer_log[self.selections_set_buffer_log_idx])
      sel.len = sel.len - sel.idx
    end
    self:merge_overlapping_selections()
    self.selections_set_buffer_log_idx = k
  end
end

function DocView:merge_overlapping_selections(preferred_len_sign)
  preferred_len_sign = preferred_len_sign or 1
  if not (preferred_len_sign > 0 or preferred_len_sign < 0) then
    preferred_len_sign = 1
  end

  local dest = 2
  for src = 2, #self.selections do
    local a, b = self.selections[dest - 1], self.selections[src]
    self.selections[src] = nil

    if a.idx + math.max(a.len, 0) < b.idx + math.min(b.len, 0) then
      self.selections[dest] = b
      if self.latest_selection_idx == src then
        self.latest_selection_idx = dest
      end
      dest = dest + 1

    else
      if a.len == 0 then
        self.selections[dest - 1] = b
      elseif b.len ~= 0 then
        local from = math.min(a.idx, a.idx + a.len + 1, b.idx, b.idx + b.len + 1)
        local to   = math.max(a.idx, a.idx + a.len - 1, b.idx, b.idx + b.len - 1)
        local old_a_cursor = a.idx + a.len
        if (a.len * preferred_len_sign > 0 or b.len * preferred_len_sign > 0) == (preferred_len_sign > 0) then
          a.idx = from
          a.len = to - from + 1
        else
          a.idx = to
          a.len = -(to - from + 1)
        end
        if a.idx + a.len == b.idx + b.len then
          a.col_hint = b.col_hint
        elseif a.idx + a.len ~= old_a_cursor then
          a.col_hint = nil
        end
      end
      if self.latest_selection_idx == src then
        self.latest_selection_idx = dest - 1
      end
    end

  end
end

function DocView:insert_selection(idx, len)
  local _, i = utils.binary_search_first(self.selections, function(sel)
    return idx + math.min(len, 0) < sel.idx + math.min(sel.len, 0)
  end)
  i = i or #self.selections + 1
  table.insert(self.selections, i, { idx = idx, len = len, col_hint = nil })
  self.latest_selection_idx = i
  self:merge_overlapping_selections()
end

function DocView:clear_selections()
  self.selections = {}
  self.selections_set_buffer_log_idx = #self.doc.set_buffer_log
  self.latest_selection_idx = nil
  self.is_mouse_dragging_selection = false
end

return DocView

-- Every grapheme, once added, must have a constant width over its entire lifetime. In particular, it can't depend on its position in the text. The only hard-coded exception to this rule are tabs.
