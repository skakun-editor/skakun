local here = ...
local core       = require('core')
local Doc        = require('core.doc')
local stderr     = require('core.stderr')
local treesitter = require('core.treesitter')
local tty        = require('core.tty')
local DocView    = require('core.ui.doc_view')
local utils      = require('core.utils')
local rgb = utils.rgb

-- core.should_forward_stderr_on_exit = false
utils.lock_globals()
treesitter.start_pkg_loader()
table.insert(core.cleanups, tty.stop_pkg_loader)
table.insert(core.cleanups, tty.restore)
tty.setup()

local grammar
while not grammar do
  treesitter.grammars_lock:acquire()
  for _, i in ipairs(treesitter.grammars) do
    if i.file_suffixes then
      for _, suffix in ipairs(i.file_suffixes) do
        if core.args[2]:sub(-#suffix) == suffix then
          grammar = i
          break
        end
      end
      if grammar then break end
    end
  end
  treesitter.grammars_lock:release()
  os.execute('sleep 0.1')
end
local parser = treesitter.Parser.new()
parser:set_language(grammar.lang)
local src = io.open(core.args[2], 'r'):read('a')
local tree = parser:parse(nil, function(from)
  return src:sub(from + 1)
end)
local runner = treesitter.Query.Runner.new({
  ['eq?'] = function(capture, string)
    local node = capture:one_node()
    return src:sub(node:start_byte() + 1, node:end_byte()) == string
  end,
  ['match?'] = function(capture, regex)
    local node = capture:one_node()
    return src:sub(node:start_byte() + 1, node:end_byte()):match(regex)
  end,
  ['any-of?'] = function(capture, ...)
    local node = capture:one_node()
    local str = src:sub(node:start_byte() + 1, node:end_byte())
    for i = 1, select('#', ...) do
      if str == select(i, ...) then
        return true
      end
    end
    return false
  end,
})
local cursor = treesitter.Query.Cursor.new(grammar.highlights, tree:root_node())
stderr.info(here, 'witamy ', tree:root_node())
for i in runner:iter_captures(cursor) do
  local a = i:node():start_byte() + 1
  local b = i:node():end_byte()
  stderr.info(here, i:name(), ' ', a, ' ', b, ' \t', src:sub(a, b))
end
stderr.info(here, 'żegnamy')

--[[
local root = DocView.new(Doc.open(core.args[2]))

DocView.foreground = rgb'000000'
DocView.background = rgb'ffffff'
DocView.error_color = rgb'ff0000'

local old_width, old_height
while true do
  local width, height = tty.get_size()
  local should_redraw = width ~= old_width or height ~= old_height
  old_width = width
  old_height = height

  local margin = 1
  root.left = 1 + 2 * margin
  root.right = width - 2 * margin
  root.top = 1 + margin
  root.bottom = height - margin

  for _, event in ipairs(tty.read_events()) do
    if event.type == 'press' or event.type == 'repeat' then
      if event.button == 'escape' then
        os.exit(0)
      end
      should_redraw = true
    end
    root:handle_event(event)
  end

  if should_redraw then
    local start = utils.timer()

    tty.sync_begin()
    tty.set_background()
    tty.clear()

    root:draw()
    tty.set_cursor(false)

    tty.sync_end()
    tty.flush()

    stderr.info(here, 'redraw done in ', math.floor(1e6 * (utils.timer() - start)), 'µs')
  end
end
--]]
