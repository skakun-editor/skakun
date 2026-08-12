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

local ui = require('core.ui')

local Action = {}
Action.__index = Action

function Action.new(id, name, desc, activator, activate)
  local self = setmetatable({
    widget = nil,
    id = id,
    name = name,
    desc = desc,
    activator = nil,
    activation_hint = nil,
    activate = activate,
    has_precedence_over_children = true,
    consumes_event = true,
  }, Action)
  self:set_activator(activator)
  return self
end

function Action:set_activator(value)
  self.activator = value
  if value then
    self.activation_hint = value.hint
  end
end

function Action:is_activated_by_event(event)
  return self.activator and self.activator(event)
end

function Action:activate(event) end

Action.Activator = {}
Action.Activator.__index = Action.Activator

function Action.Activator.click(arg1, arg2)
  if type(arg1) == 'function' then
    assert(not arg2)
    return setmetatable({
      predicate = function(event)
        return (event.type == 'press' or event.type == 'repeat') and
               not event.alt and not event.ctrl and not event.shift and
               arg1(event.button)
      end,
      hint = nil,
    }, Action.Activator)

  else
    local alt, ctrl, shift = false, false, false
    while true do
      local mod, new_arg1 = arg1:match('([^+]*)%+(.*)')
      if not mod then break end
      if mod == 'alt' then
        alt = true
      elseif mod == 'ctrl' then
        ctrl = true
      elseif mod == 'shift' then
        shift = true
      else
        error(('unknown modifier: %s'):format(mod))
      end
      arg1 = new_arg1
    end

    if #arg1 == 0 then
      assert(type(arg2) == 'function')
      return setmetatable({
        predicate = function(event)
          return (event.type == 'press' or event.type == 'repeat') and
                 event.alt == alt and event.ctrl == ctrl and event.shift == shift and
                 arg2(event.button)
        end,
        hint = nil,
      }, Action.Activator)

    else
      assert(not arg2)
      return setmetatable({
        predicate = function(event)
          return (event.type == 'press' or event.type == 'repeat') and
                 event.alt == alt and event.ctrl == ctrl and event.shift == shift and
                 event.button == arg1
        end,
        hint = (alt and ui.modifier_syms.alt or '') ..
               (ctrl and ui.modifier_syms.ctrl or '') ..
               (shift and ui.modifier_syms.shift or '') ..
               ui.button_syms[arg1],
      }, Action.Activator)
    end
  end
end

function Action.Activator.release(arg)
  return setmetatable({
    predicate = type(arg) == 'function' and function(event)
      return event.type == 'release' and arg(event.button)
    end or function(event)
      return event.type == 'release' and event.button == arg
    end,
    hint = type(arg) ~= 'function' and 'Release' .. ui.button_syms[arg] or nil,
  }, Action.Activator)
end

function Action.Activator.predicate(func)
  return setmetatable({
    predicate = func,
    hint = nil,
  }, Action.Activator)
end

function Action.Activator:with_hint(text)
  return setmetatable({
    predicate = self.predicate,
    hint = text,
  }, Action.Activator)
end

function Action.Activator:__bor(other)
  if type(other) == 'function' then
    other = Action.Activator.predicate(other)
  end
  return setmetatable({
    predicate = function(event)
      return self(event) or other(event)
    end,
    hint = self.hint and other.hint and self.hint .. '/' .. other.hint or self.hint or other.hint,
  }, Action.Activator)
end

function Action.Activator:__band(other)
  if type(other) == 'function' then
    other = Action.Activator.predicate(other)
  end
  return setmetatable({
    predicate = function(event)
      return self(event) and other(event)
    end,
    hint = self.hint or other.hint,
  }, Action.Activator)
end

function Action.Activator:__call(event)
  return self.predicate(event)
end

return Action
