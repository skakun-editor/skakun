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
