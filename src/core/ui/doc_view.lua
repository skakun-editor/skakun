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
local Parser            = require('core.doc.parser')
local SpellChecker      = require('core.doc.spell_checker')
local SyntaxHighlighter = require('core.doc.syntax_highlighter')
local stderr            = require('core.stderr')
local tty               = require('core.tty')
local Widget            = require('core.ui.widget')
local utils             = require('core.utils')

-- HACK: bring back soft wrapping
-- TODO: some nicer way of binding key shortcuts
-- TODO: line numbers
-- TODO: proper undo and redo
-- TODO: set native cursor and window title when widget focused

local DocView = setmetatable({
  should_soft_wrap = false,
  view_scroll_speed = 3,
  view_containment_margin = 2,
  faces = {
    normal = {},
    invalid = { foreground = 'red' },
    syntax_highlights = {},
  },
  colors = {
    cursor = 'white',
    cursor_foreground = 'black',
    selection = 'bright_black',
    misspelling = 'red',
  },
  ctrl_pics = (function()
    local result = {
      ['\127'] = '␡',
      ['\r\n'] = '␍␊',
    }
    for i = 0x00, 0x1f do
      result[string.char(i)] = utf8.char(0x2400 + i)
    end
    for i = 0x80, 0x9f do
      result[utf8.char(i)] = '�'
    end
    result['\u{85}'] = '␤'
    return result
  end)(),
}, Widget)
DocView.__index = DocView

function DocView.new(doc)
  local self = setmetatable(Widget.new(), DocView)
  self.faces     = setmetatable({}, { __index = DocView.faces     })
  self.colors    = setmetatable({}, { __index = DocView.colors    })
  self.ctrl_pics = setmetatable({}, { __index = DocView.ctrl_pics })

  self.doc = doc
  self.view_start = { line = 1, col = 1, buffer = doc.buffer }
  self.selections = utils.SortedSet.new(function(a, b)
    if a.idx ~= b.idx then
      return a.idx < b.idx
    else
      return a.len < b.len
    end
  end)
  self:clear_selections()
  self:add_selection(1, 0)

  self.parser = Parser.new()
  self.syntax_highlighter = SyntaxHighlighter.new()
  self.spell_checker = SpellChecker.new()

  return self
end

function DocView:draw()
  Widget.draw(self)
  self.drawn.buffer = self.doc.buffer
  self:start_background_tasks()
  self:sync_selections()
  self:layout_lines()
  self:draw_lines()
end

function DocView:start_background_tasks()
  local buffer = self.doc.buffer
  local function on_parsed(tree, grammar)
    if buffer ~= self.doc.buffer then return end
    if tree and grammar and self.syntax_highlighter:does_need_run(buffer, tree, grammar) then
      self.syntax_highlighter:stop()
      self.syntax_highlighter:run(buffer, tree, grammar, function()
        self:queue_draw()
      end)
    end
    if self.spell_checker:does_need_run(buffer, tree, grammar) then
      self.spell_checker:stop()
      self.spell_checker:run(buffer, tree, grammar, function()
        self:queue_draw()
      end)
    end
  end
  if self.parser:does_need_run(buffer) then
    self.parser:stop()
    self.parser:run(buffer, on_parsed)
  else
    local _, tree, grammar = self.parser:cached_parse_of(buffer)
    on_parsed(tree, grammar)
  end
end

function DocView:layout_lines()
  self.drawn.lines = {}
  self:sync_view_start()
  if self.should_soft_wrap then
    --[[
    local line, col = self.line, self.col
    for i = 1, self.height do
      self.drawn.lines[i] = { line = line, col = col }
      local loc =
      if ctx.navigator:locate_grapheme(ctx.navigator:locate_line_col(line, col + self.width).grapheme) ==  then

    end]]--
  else
    for i = 1, self.height do
      self.drawn.lines[i] = { line = self.view_start.line + i - 1, col = self.view_start.col }
    end
  end
end

function DocView:draw_lines()
  for y = self.y, self.y + self.height - 1 do
    local x = self.x
    tty.move_to(x, y)

    local line_start = self.drawn.lines[y - self.y + 1]
    local loc = self.doc.buffer.navigator:locate_line_col(line_start.line, line_start.col)
    local iter = self.doc.buffer:iter(loc.byte)

    if loc.col < line_start.col then
      local grapheme = self:next_grapheme(iter, loc)
      if not grapheme then
        iter:rewind(iter:last_advance())
      else
        loc.byte = loc.byte + iter:last_advance()
        loc.col = loc.col + tty.width_of(grapheme)
        local width = loc.col - self.col
        if x + width - 1 >= self.x + self.width then break end

        tty.write((' '):rep(width))
        x = x + width
      end
    end

    while true do
      local grapheme = self:next_grapheme(iter, loc)
      if not grapheme then break end

      local width = tty.width_of(grapheme)
      if x + width - 1 >= self.x + self.width then break end

      tty.write(grapheme)
      x = x + width
      loc.byte = loc.byte + iter:last_advance()
      loc.col = loc.col + width
    end

    tty.write((' '):rep(self.x + self.width - x))
  end
end

function DocView:next_grapheme(iter, loc)
  local ok, result = pcall(iter.next_grapheme, iter)
  local is_invalid = false
  if not ok then
    result = '�'
    is_invalid = true
  elseif not result or result == '\n' then
    result = nil
  elseif result == '\t' then
    local tab_width = self.doc.buffer.navigator.tab_width
    result = (' '):rep(tab_width - (loc.col - 1) % tab_width)
  elseif self.ctrl_pics[result] then
    result = self.ctrl_pics[result]
    is_invalid = true
  end

  local _, highlight_at = self.syntax_highlighter:cached_highlight_of(self.doc.buffer)
  local face = utils.copy(not is_invalid and (highlight_at and self.faces.syntax_highlights[highlight_at[loc.byte]] or self.faces.normal) or self.faces.invalid)

  local _, is_correct = self.spell_checker:cached_check_of(self.doc.buffer)
  if is_correct and is_correct[loc.byte] == false then
    face.underline = true
    face.underline_color = self.colors.misspelling
    face.underline_shape = 'curly'
  end

  local node = loc.next_selection or self.selections:find_first(function(sel)
    return loc.byte <= sel.idx + math.max(sel.len, 0)
  end)
  while node and node.value.idx + math.max(node.value.len, 0) < loc.byte do
    node = self.selections:next(node)
  end
  loc.next_selection = node
  if node then
    if loc.byte == node.value.idx + node.value.len then
      face.background = self.colors.cursor
      face.foreground = self.colors.cursor_foreground
    elseif node.value.idx + math.min(node.value.len, 0) <= loc.byte then
      face.background = self.colors.selection
    end
  end

  tty.set_face(face)
  return result
end

function DocView:buffer_idx_drawn_at(x, y)
  if not utils.is_point_in_rect(x, y, self:drawn_bounds()) then
    return nil
  end
  local drawn = self.drawn
  local line_start = drawn.lines[y - drawn.y + 1]
  local loc = drawn.buffer.navigator:locate_line_col(line_start.line, line_start.col + x - drawn.x)
  return self.doc.buffer:carry_idx_over(loc.byte, drawn.buffer)
end

function DocView:handle_event(event)
  if (event.type == 'press' or event.type == 'repeat') and event.button == 'scroll_up' then
    self.view_start.line = math.max(self.view_start.line - self.view_scroll_speed, 1)

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'scroll_down' then
    self.view_start.line = self.view_start.line + self.view_scroll_speed

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'scroll_left' then
    self.view_start.col = math.max(self.view_start.col - self.view_scroll_speed, 1)

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'scroll_right' then
    self.view_start.col = self.view_start.col + self.view_scroll_speed

  elseif event.type == 'press' and event.button == 'mouse_left' then
    if utils.is_point_in_rect(event.x, event.y, self:drawn_bounds()) then
      local cursor = self:buffer_idx_drawn_at(event.x, event.y)
      if not event.shift then
        if event.alt then
          self:sync_selections()
        else
          self:clear_selections()
        end
        self:add_selection(cursor, 0)
      end
      local sel = self.latest_selection_node.value
      sel.len = cursor - sel.idx
      sel.col_hint = nil
      self:merge_selections_overlapping_with(self.latest_selection_node)
      self.is_mouse_dragging_selection = true
    end

  elseif event.type == 'move' then
    if self.is_mouse_dragging_selection and utils.is_point_in_rect(event.x, event.y, self:drawn_bounds()) then
      self:sync_selections()
      local sel = self.latest_selection_node.value
      sel.len = self:buffer_idx_drawn_at(event.x, event.y) - sel.idx
      sel.col_hint = false
      self:merge_selections_overlapping_with(self.latest_selection_node)
    end

  elseif event.type == 'release' and event.button == 'mouse_left' then
    self.is_mouse_dragging_selection = false

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'left' then
    self:sync_selections()
    self:move_cursors_left(not event.shift)
    self:adjust_view_to_contain_selection(self.selections:first().value)

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'right' then
    self:sync_selections()
    self:move_cursors_right(not event.shift)
    self:adjust_view_to_contain_selection(self.selections:last().value)

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'home' then
    self:sync_selections()
    if event.ctrl then
      self:move_cursors_to_buffer_start(not event.shift)
    else
      self:move_cursors_to_line_start(not event.shift)
    end
    self:adjust_view_to_contain_selection(self.selections:first().value)

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'end' then
    self:sync_selections()
    if event.ctrl then
      self:move_cursors_to_buffer_end(not event.shift)
    else
      self:move_cursors_to_line_end(not event.shift)
    end
    self:adjust_view_to_contain_selection(self.selections:last().value)

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'up' then
    self:sync_selections()
    self:move_cursors_up(1, not event.shift)
    self:adjust_view_to_contain_selection(self.selections:first().value)

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'down' then
    self:sync_selections()
    self:move_cursors_down(1, not event.shift)
    self:adjust_view_to_contain_selection(self.selections:last().value)

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'page_up' then
    self:sync_selections()
    self:move_cursors_up(#self.drawn.lines, not event.shift)
    self:adjust_view_to_contain_selection(self.selections:first().value)

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'page_down' then
    self:sync_selections()
    self:move_cursors_down(#self.drawn.lines, not event.shift)
    self:adjust_view_to_contain_selection(self.selections:last().value)

  elseif (event.type == 'press' or event.type == 'repeat') and event.ctrl and event.button == 'a' then
    self:clear_selections()
    self:add_selection(1, #self.doc.buffer)

  elseif (event.type == 'press' or event.type == 'repeat') and event.ctrl and event.button == 'z' then
    if self.doc.buffer.parent then
      self.doc:set_buffer(self.doc.buffer.parent)
    end

  elseif event.type == 'press' and event.ctrl and event.button == 's' then
    self.doc:save()

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'backspace' then
    self:sync_selections()
    local buffer = self.doc.buffer:thaw()
    local nav = self.doc.buffer.navigator
    local shift = 0
    for _, sel in self.selections:elems() do
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
    self:adjust_view_to_contain_selection(self.selections:first().value)

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'delete' then
    self:sync_selections()
    local buffer = self.doc.buffer:thaw()
    local nav = self.doc.buffer.navigator
    local shift = 0
    for _, sel in self.selections:elems() do
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
      else
        local to = nav:locate_grapheme(nav:locate_byte(sel.idx).grapheme + 1).byte
        buffer:delete(sel.idx, to - 1)
        shift = shift - (to - sel.idx)
      end
      sel.col_hint = nil
    end
    self:merge_overlapping_selections()
    self.doc:set_buffer(buffer)
    self.selections_set_buffer_log_idx = #self.doc.set_buffer_log
    self:adjust_view_to_contain_selection(self.selections:first().value)

  elseif event.text then
    event.text = event.text:gsub('\r\n', '\n'):gsub('\r', '\n')
    self:sync_selections()
    local buffer = self.doc.buffer:thaw()
    local shift = 0
    for _, sel in self.selections:elems() do
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
    self:adjust_view_to_contain_selection(self.selections:first().value)
  end
end

function DocView:sync_view_start()
  local start = self.view_start
  if start.buffer ~= self.doc.buffer then
    local loc = start.buffer.navigator:locate_line_col(start.line, start.col)
    start.line = self.doc.buffer.navigator:locate_byte(self.doc.buffer:carry_idx_over(loc.byte, start.buffer)).line
    start.buffer = self.doc.buffer
  end
end

function DocView:adjust_view_to_contain_idx(idx)
  self:sync_view_start()
  local loc = self.doc.buffer.navigator:locate_byte(idx)
  local start = self.view_start
  local margin = 2 * self.view_containment_margin + 1 <= self.height and self.view_containment_margin or 0
  start.line = math.max(math.min(start.line, loc.line - margin), loc.line + margin - self.height + 1, 1)
  local margin = 2 * self.view_containment_margin + 1 <= self.width and self.view_containment_margin or 0
  start.col = math.max(math.min(start.col, loc.col - margin), loc.col + margin - self.width + 1, 1)
end

function DocView:adjust_view_to_contain_selection(sel)
  self:adjust_view_to_contain_idx(sel.idx)
  self:adjust_view_to_contain_idx(sel.idx + sel.len)
end

function DocView:add_selection(idx, len)
  local is_new, node = self.selections:insert({ idx = idx, len = len })
  self.latest_selection_node = node
  if not is_new then return end
  self:merge_selections_overlapping_with(node)
end

function DocView:sync_selections()
  for k = self.selections_set_buffer_log_idx + 1, #self.doc.set_buffer_log do
    local buffer = self.doc.set_buffer_log[k]
    for _, sel in self.selections:elems() do
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

function DocView:move_cursors_left(should_curtail_selections)
  assert(self.selections_set_buffer_log_idx == #self.doc.set_buffer_log)
  local nav = self.doc.buffer.navigator
  for _, sel in self.selections:elems() do
    local cursor
    if should_curtail_selections and sel.len ~= 0 then
      cursor = sel.idx + math.min(sel.len, 0)
    else
      cursor = nav:locate_grapheme(nav:locate_byte(sel.idx + sel.len).grapheme - 1)
      cursor = cursor and cursor.byte or 1
    end
    if should_curtail_selections then
      sel.idx = cursor
      sel.len = 0
    else
      sel.len = cursor - sel.idx
    end
    sel.col_hint = nil
  end
  self:merge_overlapping_selections(-1)
end

function DocView:move_cursors_right(should_curtail_selections)
  assert(self.selections_set_buffer_log_idx == #self.doc.set_buffer_log)
  local nav = self.doc.buffer.navigator
  for _, sel in self.selections:elems() do
    local cursor
    if should_curtail_selections and sel.len ~= 0 then
      cursor = sel.idx + math.max(sel.len, 0)
    else
      cursor = nav:locate_grapheme(nav:locate_byte(sel.idx + sel.len).grapheme + 1).byte
    end
    if should_curtail_selections then
      sel.idx = cursor
      sel.len = 0
    else
      sel.len = cursor - sel.idx
    end
    sel.col_hint = nil
  end
  self:merge_overlapping_selections(1)
end

function DocView:move_cursors_to_line_start(should_curtail_selections)
  assert(self.selections_set_buffer_log_idx == #self.doc.set_buffer_log)
  local nav = self.doc.buffer.navigator
  for _, sel in self.selections:elems() do
    local cursor = nav:locate_line_col(nav:locate_byte(sel.idx + sel.len).line, 1).byte
    if should_curtail_selections then
      sel.idx = cursor
      sel.len = 0
    else
      sel.len = cursor - sel.idx
    end
    sel.col_hint = nil
  end
  self:merge_overlapping_selections(-1)
end

function DocView:move_cursors_to_line_end(should_curtail_selections)
  assert(self.selections_set_buffer_log_idx == #self.doc.set_buffer_log)
  local nav = self.doc.buffer.navigator
  for _, sel in self.selections:elems() do
    local cursor = nav:locate_line_col(nav:locate_byte(sel.idx + sel.len).line, math.huge).byte
    if should_curtail_selections then
      sel.idx = cursor
      sel.len = 0
    else
      sel.len = cursor - sel.idx
    end
    sel.col_hint = nil
  end
  self:merge_overlapping_selections(1)
end

function DocView:move_cursors_to_buffer_start(should_curtail_selections)
  assert(self.selections_set_buffer_log_idx == #self.doc.set_buffer_log)
  local cursor = 1
  for _, sel in self.selections:elems() do
    if should_curtail_selections then
      sel.idx = cursor
      sel.len = 0
    else
      sel.len = cursor - sel.idx
    end
    sel.col_hint = nil
  end
  self:merge_overlapping_selections(-1)
end

function DocView:move_cursors_to_buffer_end(should_curtail_selections)
  assert(self.selections_set_buffer_log_idx == #self.doc.set_buffer_log)
  local cursor = #self.doc.buffer + 1
  for _, sel in self.selections:elems() do
    if should_curtail_selections then
      sel.idx = cursor
      sel.len = 0
    else
      sel.len = cursor - sel.idx
    end
    sel.col_hint = nil
  end
  self:merge_overlapping_selections(1)
end

function DocView:move_cursors_up(count, should_curtail_selections)
  assert(self.selections_set_buffer_log_idx == #self.doc.set_buffer_log)
  if count <= 0 then return end
  local nav = self.doc.buffer.navigator
  for _, sel in self.selections:elems() do
    local loc = nav:locate_byte(sel.idx + sel.len)
    sel.col_hint = sel.col_hint or loc.col
    local cursor = nav:locate_line_col(loc.line - count, sel.col_hint)
    cursor = cursor and cursor.byte or 1
    if should_curtail_selections then
      sel.idx = cursor
      sel.len = 0
    else
      sel.len = cursor - sel.idx
    end
  end
  self:merge_overlapping_selections(-1)
end

function DocView:move_cursors_down(count, should_curtail_selections)
  assert(self.selections_set_buffer_log_idx == #self.doc.set_buffer_log)
  if count <= 0 then return end
  local nav = self.doc.buffer.navigator
  for _, sel in self.selections:elems() do
    local loc = nav:locate_byte(sel.idx + sel.len)
    sel.col_hint = sel.col_hint or loc.col
    local cursor = nav:locate_line_col(loc.line + count, sel.col_hint).byte
    if should_curtail_selections then
      sel.idx = cursor
      sel.len = 0
    else
      sel.len = cursor - sel.idx
    end
  end
  self:merge_overlapping_selections(1)
end

function DocView:merge_overlapping_selections(preferred_len_sign)
  local node = self.selections:first()
  while node do
    self:merge_selections_overlapping_with(node, preferred_len_sign)
    node = self.selections:next(node)
  end
end

function DocView:merge_selections_overlapping_with(node, preferred_len_sign)
  preferred_len_sign = preferred_len_sign or node.value.len
  while true do
    local neighbor = self.selections:prev(node)
    if not neighbor then break end
    local merged = self:merge_selections_if_overlapping(node.value, neighbor.value, preferred_len_sign)
    if not merged then break end
    node.value = merged
    self.selections:remove(neighbor)
    if self.latest_selection_node == neighbor then
      self.latest_selection_node = node
    end
  end
  while true do
    local neighbor = self.selections:next(node)
    if not neighbor then break end
    local merged = self:merge_selections_if_overlapping(node.value, neighbor.value, preferred_len_sign)
    if not merged then break end
    node.value = merged
    self.selections:remove(neighbor)
    if self.latest_selection_node == neighbor then
      self.latest_selection_node = node
    end
  end
end

function DocView:clear_selections()
  self.selections:clear()
  self.selections_set_buffer_log_idx = #self.doc.set_buffer_log
  self.latest_selection_node = nil
  self.is_mouse_dragging_selection = false
end

function DocView:merge_selections_if_overlapping(a, b, preferred_len_sign)
  if a.idx + math.max(a.len, 0) < b.idx + math.min(b.len, 0) or b.idx + math.max(b.len, 0) < a.idx + math.min(a.len, 0) then
    return nil
  elseif a.len == 0 then
    return utils.copy(b)
  elseif b.len == 0 then
    return utils.copy(a)
  end
  local from = math.min(a.idx, a.idx + a.len + 1, b.idx, b.idx + b.len + 1)
  local to   = math.max(a.idx, a.idx + a.len - 1, b.idx, b.idx + b.len - 1)
  local result
  if a.len > 0 and b.len > 0 or (not preferred_len_sign or preferred_len_sign >= 0) and (a.len > 0 or b.len > 0) then
    result = { idx = from, len = to - from + 1 }
  else
    result = { idx = to, len = -(to - from + 1) }
  end
  if result.idx + result.len == a.idx + a.len then
    result.col_hint = a.col_hint
  elseif result.idx + result.len == b.idx + b.len then
    result.col_hint = b.col_hint
  end
  return result
end

return DocView

-- Every grapheme, once added, must have a constant width over its entire lifetime. In particular, it can't depend on its position in the text. The only hard-coded exception to this rule are tabs.
