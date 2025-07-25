local here = ...
local core              = require('core')
local Buffer            = require('core.buffer')
local Doc               = require('core.doc')
local SyntaxHighlighter = require('core.doc.syntax_highlighter')
local stderr            = require('core.stderr')
local treesitter        = require('core.treesitter')
local tty               = require('core.tty')
local DocView           = require('core.ui.doc_view')
local utils             = require('core.utils')
local dracula           = require('theme.dracula')
local github_dark       = require('theme.github_dark')
local github_light      = require('theme.github_light')
local gruvbox_dark      = require('theme.gruvbox_dark')
local gruvbox_light     = require('theme.gruvbox_light')

-- TODO: display syntax group under cursor
-- TODO: commands under F1
-- TODO: logo
-- HACK: update docs when you're finished lol
-- TODO: autosave when idle

core.should_forward_stderr_on_exit = false
utils.lock_globals()
table.insert(core.cleanups, tty.restore)
tty.setup()

SyntaxHighlighter.is_debug = true

thread.new(xpcall, treesitter.load_pkgs, function(err)
  stderr.error(here, debug.traceback(err))
end, {
  'https://github.com/skakun-editor/tree-sitter-c',
  'https://github.com/skakun-editor/tree-sitter-lua',
  'https://github.com/skakun-editor/tree-sitter-python',
  'https://github.com/skakun-editor/tree-sitter-zig',
})

local root = DocView.new(core.args[2] and Doc.open(core.args[2]) or Doc.new())
local theme = dracula
theme.apply()

local should_redraw = true
local old_width, old_height
local mouse_x, mouse_y = 1, 1
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

    local highlighter = SyntaxHighlighter.of(root.doc.buffer)
    local idx = root:buffer_idx_drawn_at(mouse_x, mouse_y)
    local highlight = '⬐' .. tostring(highlighter.highlight_at[idx])
    if highlighter.debug_info_at[idx] then
      highlight = highlight .. ' ' .. highlighter.debug_info_at[idx]
    end
    tty.move_to(mouse_x, mouse_y - 1)
    tty.set_face({ background = 'bright_black' })
    tty.write(highlight)

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
    elseif event.type == 'move' then
      mouse_x = event.x
      mouse_y = event.y
    end
    should_redraw = true
    root:handle_event(event)
    local micros = math.floor(1e6 * (utils.timer() - start))
    if micros >= 1000 then
      stderr.warn(here, 'slow event took ', micros, 'µs')
    end
  end
end
