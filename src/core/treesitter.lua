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
local cjson   = require('cjson')
local core    = require('core')
local stderr  = require('core.stderr')
local utils   = require('core.utils')
local binding = require('lua_tree_sitter')

local treesitter = setmetatable({
  grammars = {},
}, { __index = binding })

function treesitter.on_grammars_change() end

function treesitter.load_pkgs(pkgs)
  local start = utils.timer()
  local leftovers = {}
  for _, url_or_path in ipairs(pkgs) do
    xpcall(
      treesitter.load_pkg,
      function(err)
        table.insert(leftovers, url_or_path)
        stderr.warn(here, err)
      end,
      url_or_path:find('^https?://') and core.cache_dir .. '/' .. here .. '/' .. utils.slugify(url_or_path) or url_or_path
    )
  end
  stderr.info(here, ('pkg preload done in %.2fs'):format(utils.timer() - start))
  treesitter.on_grammars_change()

  local success = false
  for _, url_or_path in ipairs(leftovers) do
    xpcall(
      function()
        local dir = url_or_path
        if url_or_path:find('^https?://') then
          dir = treesitter.download_pkg(url_or_path)
        end
        treesitter.build_pkg(dir)
        treesitter.load_pkg(dir)
        success = true
      end,
      function(err)
        if err then
          stderr.error(here, err)
        end
      end
    )
  end
  stderr.info(here, ('pkg load done in %.2fs'):format(utils.timer() - start))
  if success then
    treesitter.on_grammars_change()
  end
end

function treesitter.download_pkg(url)
  stderr.info(here, 'downloading pkg ', url)

  local slug = utils.slugify(url)
  local dest = core.cache_dir .. '/' .. here .. '/' .. slug

  if not os.rename(dest, dest) then
    if os.execute(('git ls-remote %q > /dev/null 2>&1'):format(url)) then
      assert(os.execute(('git clone --depth=1 -q %q %q'):format(url, dest)))
    else
      local temp = core.cache_dir .. '/' .. here .. '/.' .. slug
      local pipe = io.popen('{ ' .. table.concat({
        ('mkdir -p %q/%q'):format(core.cache_dir, here),
        ('wget %q -O %q'):format(url, temp),
        ('tar -xf %q --one-top-level=%q'):format(temp, dest),
        ('rm %q'):format(temp),
      }, ' && ') .. '; } 2>&1', 'r')
      local log = pipe:read('a')
      if not pipe:close() then
        error(log, 0)
      end
    end

  elseif os.execute(('git -C %q rev-parse 2> /dev/null'):format(dest)) then
    local pipe = io.popen(('git -C %q pull --depth=1 2>&1'):format(dest), 'r')
    local log = pipe:read('a')
    if not pipe:close() then
      error(log, 0)
    elseif not log:find('^Already up to date.\n') then
      stderr.info(here, log)
      assert(os.execute(('git -C %q clean -dfX'):format(dest)))
    end
  end

  return dest
end

function treesitter.build_pkg(dir)
  stderr.info(here, 'building pkg ', dir)

  local pipe = io.popen(('find %q -name tree-sitter.json -printf %%h\\\\0 2>&1'):format(dir), 'r')
  local roots = pipe:read('a')
  if not pipe:close() then
    error(roots, 0)
  end
  if roots == '' then
    stderr.warn(here, 'no tree-sitter.json in ', dir)
  end

  for root in utils.split(roots, '\0') do
    local pipe = io.popen(('make -C %q CFLAGS=-O3\\ -march=native -j 2>&1'):format(root), 'r')
    local log = pipe:read('a')
    if not pipe:close() then
      error(log, 0)
    end
  end
end

function treesitter.load_pkg(dir)
  stderr.info(here, 'loading pkg ', dir)

  local pipe = io.popen(('find %q -name tree-sitter.json -printf %%h\\\\0 2>&1'):format(dir), 'r')
  local roots = pipe:read('a')
  if not pipe:close() then
    error(roots, 0)
  end
  if #roots == 0 then
    stderr.warn(here, 'no tree-sitter.json in ', dir)
  end

  for root in utils.split(roots, '\0') do
    local file = io.open(root .. '/tree-sitter.json', 'r')
    local json = cjson.decode(file:read('a'))
    file:close()
    if #json.grammars == 0 then
      stderr.warn(here, 'no grammars in ', root)
    end

    for _, json in ipairs(json.grammars) do
      local id = json.scope .. '/' .. json.name
      stderr.info(here, 'loading grammar ', id)

      local ok, lang = pcall(
        treesitter.Language.load,
        root .. '/' .. (json.path or '.') .. '/libtree-sitter-' .. json.name .. (core.platform == 'macos' and '.dylib' or '.so'),
        json.name:gsub('-', '_')
      )
      if not ok then
        lang = treesitter.Language.load(
          root .. '/' .. (json.path or '.') .. '/libtree-sitter-' .. json.name:gsub('_', '-') .. (core.platform == 'macos' and '.dylib' or '.so'),
          json.name:gsub('-', '_')
        )
      end

      local function load_queries(paths)
        if type(paths) ~= 'table' then
          paths = {paths}
        end
        local result = {}
        for _, path in ipairs(paths) do
          local file, err = io.open(root .. '/' .. path, 'r')
          if file then
            table.insert(result, file:read('a'))
            file:close()
          else
            stderr.warn(here, err)
          end
        end
        return treesitter.Query.new(lang, table.concat(result)) -- Treesitter is the bottleneck here.
      end

      table.insert(treesitter.grammars, {
        id = id,
        file_types = json['file-types'] ~= cjson.null and json['file-types'] or {},
        injection_regex = json['injection-regex'],
        lang = lang,
        highlights = utils.once(load_queries, json.highlights or 'queries/highlights.scm'),
        locals = utils.once(load_queries, json.locals or 'queries/locals.scm'),
        injections = utils.once(load_queries, json.injections or 'queries/injections.scm'),
      })
    end
  end
end

function treesitter.grammar_for_path(path)
  for _, grammar in ipairs(treesitter.grammars) do
    for _, suffix in ipairs(grammar.file_types) do
      if path:sub(-#suffix) == suffix then
        return grammar
      end
    end
  end
end

return treesitter
