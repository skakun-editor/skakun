local here = ...
local core       = require('core')
local Doc        = require('core.doc')
local stderr     = require('core.stderr')
local treesitter = require('core.treesitter')
local tty        = require('core.tty')
local DocView    = require('core.ui.doc_view')
local utils      = require('core.utils')
local dracula    = require('theme.dracula')

-- TODO: put ui thread into sleep instead of tirelessly polling tty input

-- core.should_forward_stderr_on_exit = false
utils.lock_globals()
table.insert(core.cleanups, tty.restore)
tty.setup()
dracula.apply()

thread.new(xpcall, treesitter.load_pkgs, function(err)
  stderr.error(here, debug.traceback(err))
end, {
  -- You can find more parsers here: https://github.com/tree-sitter/tree-sitter/wiki/List-of-parsers
  'https://github.com/tree-sitter/tree-sitter-agda',
  'https://github.com/tree-sitter/tree-sitter-bash',
  'https://github.com/tree-sitter/tree-sitter-c',
  'https://github.com/tree-sitter/tree-sitter-cpp',
  'https://github.com/tree-sitter/tree-sitter-c-sharp',
  'https://github.com/tree-sitter/tree-sitter-css',
  'https://github.com/tree-sitter/tree-sitter-embedded-template',
  'https://github.com/tree-sitter/tree-sitter-go',
  'https://github.com/tree-sitter/tree-sitter-haskell',
  'https://github.com/tree-sitter/tree-sitter-html',
  'https://github.com/tree-sitter/tree-sitter-java',
  'https://github.com/tree-sitter/tree-sitter-javascript',
  'https://github.com/tree-sitter/tree-sitter-jsdoc',
  'https://github.com/tree-sitter/tree-sitter-json',
  'https://github.com/tree-sitter/tree-sitter-julia',
  'https://github.com/tree-sitter/tree-sitter-ocaml',
  'https://github.com/tree-sitter/tree-sitter-php',
  'https://github.com/tree-sitter/tree-sitter-python',
  'https://github.com/tree-sitter/tree-sitter-ql',
  'https://github.com/tree-sitter/tree-sitter-ql-dbscheme',
  'https://github.com/tree-sitter/tree-sitter-regex',
  'https://github.com/tree-sitter/tree-sitter-ruby',
  'https://github.com/tree-sitter/tree-sitter-rust',
  'https://github.com/tree-sitter/tree-sitter-scala',
  'https://github.com/tree-sitter/tree-sitter-typescript',
  'https://github.com/tree-sitter/tree-sitter-verilog',
  'https://github.com/tree-sitter-grammars/tree-sitter-lua',
  'https://github.com/tree-sitter-grammars/tree-sitter-markdown',
  'https://github.com/tree-sitter-grammars/tree-sitter-zig',
})

local root = DocView.new(Doc.open(core.args[2]))

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
      elseif event.button == 't' then
        local ok, err = pcall(event.shift and dracula.apply or dracula.unapply)
        if not ok then
          stderr.error(here, err)
        end
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
    tty.set_window_background(root.faces.normal.background)

    tty.sync_end()
    tty.flush()

    stderr.info(here, 'redraw done in ', math.floor(1e6 * (utils.timer() - start)), 'µs')
    os.execute('sleep 0.01')
  end
end
