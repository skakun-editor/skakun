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
local cjson  = require('cjson')
local core   = require('core')
local stderr = require('core.stderr')

local nerd_fonts = {
  version = '3.0.0',
  icons = {},
}

function nerd_fonts.init()
  local path = core.cache_dir .. '/' .. here .. '/' .. nerd_fonts.version .. '.json'

  if not os.rename(path, path) then
    local url = 'https://github.com/ryanoasis/nerd-fonts/raw/refs/tags/v' .. nerd_fonts.version .. '/glyphnames.json'
    stderr.info(here, 'downloading ', url)
    local temp_path = os.tmpname()
    local pipe = io.popen(('{ mkdir -p %q/%q && wget %q -O %q && mv %q %q; } 2>&1'):format(core.cache_dir, here, url, temp_path, temp_path, path), 'r')
    local log = pipe:read('a')
    if not pipe:close() then
      error(log, 0)
    end
  end

  local file <close> = io.open(path, 'r')
  local json = cjson.decode(file:read('a'))

  json.METADATA = nil
  for k, v in pairs(json) do
    nerd_fonts.icons[k] = v.char
  end
end

return nerd_fonts
