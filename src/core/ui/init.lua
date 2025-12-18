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
local stderr = require('core.stderr')
local tty    = require('core.tty')
local utils  = require('core.utils')

local ui = {
  is_running = true,
  idle_interval = 0.1,
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
}

function ui.run(root)
  local should_redraw = true
  local old_width, old_height

  ui.is_running = true
  while ui.is_running do
    local width, height = tty.get_size()
    if width ~= old_width or height ~= old_height then
      should_redraw = true
    end
    old_width = width
    old_height = height

    root:set_bounds(1, 1, width, height)

    if root.is_queued_for_draw then
      should_redraw = true
    end

    if should_redraw then
      should_redraw = false

      local start = utils.timer()
      tty.sync_begin()
      tty.set_background()
      tty.clear()

      root:draw()

      tty.sync_end()
      tty.flush()

      local micros = math.floor(1e6 * (utils.timer() - start))
      if micros >= 16000 then
        stderr.warn(here, 'slow redraw took ', micros, 'µs')
      end
    end

    root:idle()

    tty.wait_for_read(ui.idle_interval)
    for _, event in ipairs(tty.read_events()) do
      local start = utils.timer()
      root:handle_event(event)
      local micros = math.floor(1e6 * (utils.timer() - start))
      if micros >= 1000 then
        stderr.warn(here, 'slow event took ', micros, 'µs')
      end
    end
  end
end

function ui.stop()
  ui.is_running = false
end

return ui
