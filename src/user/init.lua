local here = ...
local core              = require('core')
local Doc               = require('core.doc')
local SyntaxHighlighter = require('core.doc.syntax_highlighter')
local stderr            = require('core.stderr')
local treesitter        = require('core.treesitter')
local tty               = require('core.tty')
local ui                = require('core.ui')
local Action            = require('core.ui.action')
local ActionPrompt      = require('core.ui.action_prompt')
local DocView           = require('core.ui.doc_view')
local nerd_fonts        = require('core.ui.nerd_fonts')
local Widget            = require('core.ui.widget')
local utils             = require('core.utils')
local tty_test          = require('misc.tty_test')
local dracula           = require('theme.dracula')
local fruitmash_dark    = require('theme.fruitmash_dark')
local fruitmash_light   = require('theme.fruitmash_light')
local github_dark       = require('theme.github_dark')
local github_light      = require('theme.github_light')
local gruvbox_dark      = require('theme.gruvbox_dark')
local gruvbox_light     = require('theme.gruvbox_light')

-- TODO: update the rest of the themes to support the new ui eleements
-- TODO: logo
-- HACK: update docs when you're finished lol
-- TODO: autosave when idle
-- TODO: do we really need descriptions for all ui actions?

core.should_forward_stderr_on_exit = false
utils.lock_globals()
table.insert(core.cleanups, tty.restore)
tty.setup()
nerd_fonts.version = '3.4.0'
nerd_fonts.init()

-- local names = {'red', 'orange', 'yellow', 'green', 'cyan', 'blue'}
-- local width = 0
-- for _, name in ipairs(names) do
--   width = math.max(width, #name)
-- end
-- for _, name in ipairs(names) do
--   stderr.info(
--     here,
--     ('%-' .. width .. 's'):format(name),
--     ' ',
--     ('dark (%.3f %.3f %6.2f)'):format(fruitmash_dark.true_color.colors[name]:oklch()),
--     ' ',
--     ('light (%.3f %.3f %6.2f)'):format(fruitmash_light.true_color.colors[name]:oklch())
--   )
-- end

SyntaxHighlighter.is_debug = true

thread.new(xpcall, treesitter.load_pkgs, function(err)
  stderr.error(here, debug.traceback(err))
end, {
  core.exe_dir .. '/../../../tree-sitter-c',
  core.exe_dir .. '/../../../tree-sitter-lua',
  core.exe_dir .. '/../../../tree-sitter-python',
  core.exe_dir .. '/../../../tree-sitter-zig',
})

local root = Widget.new()
root.name = 'Root'

local doc_view = DocView.new(core.args[2] and Doc.open(core.args[2]) or Doc.new())
table.insert(core.cleanups, function() doc_view:stop_background_tasks() end)
doc_view.parent = root

local action_prompt = nil

local theme = dracula
theme.apply()

local mouse_x, mouse_y = 1, 1

function root:draw()
  Widget.draw(self)

  tty.set_cursor(false)
  tty.set_window_background(doc_view.faces.normal.background)

  doc_view:set_bounds(self:drawn_bounds())
  doc_view:draw()

  if action_prompt then
    local width, height = action_prompt:natural_size()
    if width > self.width then
      width = self.width
    elseif width % 2 ~= self.width % 2 then
      width = width + 1
    end
    if height > self.height then
      height = self.height
    elseif height % 2 ~= self.height % 2 then
      height = height + 1
    end
    action_prompt:set_bounds(1 + (self.width - width) // 2, 1 + (self.height - height) // 2, width, height)
    action_prompt:draw()
  end

  --[[
  local set = {}
  for _, face in pairs(DocView.faces.syntax_highlights) do
    if face.foreground then
      set[face.foreground] = true
    end
  end
  set[DocView.faces.normal.foreground or 'white'] = true
  local colors = {}
  for i in pairs(set) do
    table.insert(colors, i)
  end
  table.sort(colors, function(a, b)
    if type(a) == 'string' and type(b) == 'string' then
      return a < b
    elseif type(a) == 'string' then
      return true
    elseif type(b) == 'string' then
      return false
    else
      local ah, as, av = a:hsv()
      local bh, bs, bv = b:hsv()
      if ah ~= bh then return ah < bh end
      if as ~= bs then return as < bs end
      return av < bv
    end
  end)
  local y = 2
  for _, color in ipairs(colors) do
    tty.move_to(width - 4, y)
    tty.set_background(color)
    tty.write('    ')
    tty.move_to(width - 4, y + 1)
    tty.write('    ')
    y = y + 3
  end
  ]]

  local watermark = 'Skakun ' .. core.version
  tty.move_to(self.x + self.width - tty.width_of(watermark), self.y + self.height - 1)
  tty.set_face({ foreground = 'bright_black' })
  tty.write(watermark)

  -- local highlighter = SyntaxHighlighter.of(root.doc.buffer)
  -- local idx = root:buffer_idx_drawn_at(mouse_x, mouse_y)
  -- local highlight = '⬐' .. tostring(highlighter.highlight_at[idx])
  -- if highlighter.debug_info_at[idx] then
  --   highlight = highlight .. ' ' .. highlighter.debug_info_at[idx]
  -- end
  -- tty.move_to(mouse_x, mouse_y - 1)
  -- tty.set_face({ background = 'bright_black' })
  -- tty.write(highlight)
end

local themes = {dracula, fruitmash_dark, fruitmash_light, github_dark, github_light, gruvbox_dark, gruvbox_light}

root:add_actions(
  Action.new_simple(
    'quit',
    'Quit Skakun',
    nil,
    'ctrl+q',
    function(action, event)
      ui.stop()
    end
  ),
  Action.new(
    'set_theme',
    'Set UI theme',
    nil,
    Action.mod_symbols.ctrl .. '[F1-F' .. #themes .. ']',
    function(action, event)
      local num = event.button and tonumber(event.button:match('f(%d+)'))
      return event.type == 'press' and num and num <= #themes and not event.alt and event.ctrl and not event.shift
    end,
    function(action, event)
      if theme then
        theme.unapply()
        theme = nil
      end
      theme = themes[tonumber(event.button:match('f(%d+)'))]
      if theme then
        tty.cap.foreground = event.shift and 'ansi' or 'true_color'
        theme.apply()
      end
      root:request_draw()
    end
  ),
  Action.new_simple(
    'action_prompt',
    'Toggle action prompt',
    'Opens or closes a list of actions you can perform in the UI.',
    'f1',
    function(action, event)
      if action_prompt then
        action_prompt.parent = nil
        action_prompt = nil
      else
        action_prompt = ActionPrompt.new()
        action_prompt.parent = root
        action_prompt:add_actions_of(root, true)
      end
      root:request_draw()
    end
  ),
  Action.new(
    'tty_test',
    'Test terminal',
    'Runs a demo routine showcasing all the supported features of your terminal.',
    nil,
    nil,
    function(action, event)
      tty_test()
      root:request_draw()
    end
  )
)

function root:handle_event(event)
  if event.type == 'move' then
    mouse_x = event.x
    mouse_y = event.y
  end
  return Widget.handle_event(self, event)
end

function root:idle()
  doc_view:idle()
  if action_prompt then
    action_prompt:idle()
  end
end

function root:children()
  return coroutine.wrap(function()
    if action_prompt then
      coroutine.yield(1, action_prompt)
      coroutine.yield(2, doc_view)
    else
      coroutine.yield(1, doc_view)
    end
  end)
end

ui.run(root)
