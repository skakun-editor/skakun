local here = ...
local core          = require('core')
local Buffer        = require('core.buffer')
local Doc           = require('core.doc')
local stderr        = require('core.stderr')
local treesitter    = require('core.treesitter')
local tty           = require('core.tty')
local DocView       = require('core.ui.doc_view')
local utils         = require('core.utils')
local dracula       = require('theme.dracula')
local github_dark   = require('theme.github_dark')
local github_light  = require('theme.github_light')
local gruvbox_dark  = require('theme.gruvbox_dark')
local gruvbox_light = require('theme.gruvbox_light')

-- TODO: display syntax group under cursor
-- TODO: commands under F1

core.should_forward_stderr_on_exit = false
utils.lock_globals()
table.insert(core.cleanups, tty.restore)
tty.setup()

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

local root = DocView.new(core.args[2] and Doc.open(core.args[2]) or Doc.new())
local theme = dracula
theme.apply()

local should_redraw = true
local old_width, old_height
while true do
  local width, height = tty.get_size()
  if width ~= old_width or height ~= old_height then
    should_redraw = true
  end
  old_width = width
  old_height = height

  root.x = 1
  root.y = 1
  root.width = width
  root.height = height

  if should_redraw then
    should_redraw = false

    local start = utils.timer()
    tty.sync_begin()
    tty.set_background()
    tty.clear()

    root:draw()
    tty.set_cursor(false)
    tty.set_window_background(root.faces.normal.background)

    local watermark = 'Skakun ' .. core.version
    tty.move_to(width - #watermark + 1, height)
    tty.set_face({ foreground = 'bright_black' })
    tty.write(watermark)

    tty.sync_end()
    tty.flush()

    local micros = math.floor(1e6 * (utils.timer() - start))
    if micros >= 16000 then
      stderr.warn(here, 'slow redraw took ', micros, 'µs')
    end
  end

  if not Buffer.validate_mmaps() then
    should_redraw = true
  end

  tty.wait_for_read(1)
  for _, event in ipairs(tty.read_events()) do
    local start = utils.timer()
    if event.type == 'press' or event.type == 'repeat' then
      if event.button == 'escape' then
        os.exit(0)
      elseif tonumber(event.button:match('f(%d+)')) then
        if theme then
          theme.unapply()
          theme = nil
        end
        theme = ({dracula, github_dark, github_light, gruvbox_dark, gruvbox_light})[tonumber(event.button:match('f(%d+)'))]
        if theme then
          tty.cap.foreground = event.shift and 'ansi' or 'true_color'
          theme.apply()
        end
      end
    end
    should_redraw = true
    root:handle_event(event)
    local micros = math.floor(1e6 * (utils.timer() - start))
    if micros >= 1000 then
      stderr.warn(here, 'slow event took ', micros, 'µs')
    end
  end
end
