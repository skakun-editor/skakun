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
local grapheme   = require('core.grapheme')
local stderr     = require('core.stderr')
local tty        = require('core.tty')
local ui         = require('core.ui')
local nerd_fonts = require('core.ui.nerd_fonts')
local TextField  = require('core.ui.text_field')
local Widget     = require('core.ui.widget')
local SortedSet  = require('core.utils.sorted_set')
local Gio        = require('LuaGObject').Gio
local GLib       = require('LuaGObject').GLib

-- IDEA: ls colors
-- IDEA: file logo icon colors, with automatic saturation adjustment using oklch

local FileChooser = setmetatable({
  faces = { -- HACK: are you sure about these?
    completion = {},
    completion_invalid = { foreground = 'red' },
    selected_completion = { foreground = 'black', background = 'white' },
    selected_completion_invalid = { foreground = 'red', background = 'white' },
  },

  -- These icon names originate from: https://specifications.freedesktop.org/icon-naming/latest/#mimetypes
  file_xdg_generic_icons = {
    ['application-x-executable'] = 'fa-gear',
    ['audio-x-generic'] = 'fa-file_audio_o',
    ['font-x-generic'] = 'md-format_font',
    ['image-x-generic'] = 'fa-file_image_o',
    ['package-x-generic'] = 'fa-file_archive_o',
    ['text-html'] = 'fa-file_code_o',
    ['text-x-generic'] = 'fa-file_text_o',
    ['text-x-generic-template'] = 'fa-file_text_o',
    ['text-x-script'] = 'fa-file_code_o',
    ['video-x-generic'] = 'fa-file_video_o',
    ['x-office-address-book'] = 'fa-file_o',
    ['x-office-calendar'] = 'fa-file_o',
    ['x-office-document'] = 'fa-file_o',
    ['x-office-presentation'] = 'fa-file_o',
    ['x-office-spreadsheet'] = 'fa-file_o',
  },

  file_symbolic_icons = {
    ['inode/blockdevice'] = 'fa-hard_drive',
    ['inode/chardevice'] = 'fa-microchip',
    ['inode/directory'] = 'fa-folder',
    ['inode/fifo'] = 'md-pipe',
    ['inode/socket'] = 'md-power_socket_au',
    ['inode/symlink'] = 'fa-external_link',
  },

  file_logo_icons = {
    ['application/illustrator'] = 'dev-illustrator',
    ['application/java-archive'] = 'fa-java',
    ['application/json'] = 'dev-json',
    ['application/json-patch+json'] = 'dev-json',
    ['application/msaccess'] = 'md-microsoft_access',
    ['application/msexcel'] = 'md-microsoft_excel',
    ['application/mspowerpoint'] = 'md-microsoft_powerpoint',
    ['application/msword'] = 'md-microsoft_word',
    ['application/msword-template'] = 'md-microsoft_word',
    ['application/pdf'] = 'seti-pdf',
    ['application/rss+xml'] = 'md-rss',
    ['application/schema+json'] = 'dev-json',
    ['application/toml'] = 'custom-toml',
    ['application/vnd.amazon.mobi8-ebook'] = 'fa-amazon',
    ['application/vnd.android.package-archive'] = 'fa-android',
    ['application/vnd.coffeescript'] = 'seti-coffee',
    ['application/vnd.dart'] = 'seti-dart',
    ['application/vnd.debian.binary-package'] = 'dev-debian',
    ['application/vnd.google-earth.kml+xml'] = 'md-google_earth',
    ['application/vnd.google-earth.kmz'] = 'md-google_earth',
    ['application/vnd.mozilla.xul+xml'] = 'dev-mozilla',
    ['application/vnd.ms-access'] = 'md-microsoft_access',
    ['application/vnd.ms-excel'] = 'md-microsoft_excel',
    ['application/vnd.ms-excel.addin.macroEnabled.12'] = 'md-microsoft_excel',
    ['application/vnd.ms-excel.sheet.binary.macroEnabled.12'] = 'md-microsoft_excel',
    ['application/vnd.ms-excel.sheet.macroEnabled.12'] = 'md-microsoft_excel',
    ['application/vnd.ms-excel.template.macroEnabled.12'] = 'md-microsoft_excel',
    ['application/vnd.ms-officetheme'] = 'md-microsoft_office',
    ['application/vnd.ms-powerpoint'] = 'md-microsoft_powerpoint',
    ['application/vnd.ms-powerpoint.addin.macroEnabled.12'] = 'md-microsoft_powerpoint',
    ['application/vnd.ms-powerpoint.presentation.macroEnabled.12'] = 'md-microsoft_powerpoint',
    ['application/vnd.ms-powerpoint.slide.macroEnabled.12'] = 'md-microsoft_powerpoint',
    ['application/vnd.ms-powerpoint.slideshow.macroEnabled.12'] = 'md-microsoft_powerpoint',
    ['application/vnd.ms-powerpoint.template.macroEnabled.12'] = 'md-microsoft_powerpoint',
    ['application/vnd.ms-word'] = 'md-microsoft_word',
    ['application/vnd.ms-word.document.macroEnabled.12'] = 'md-microsoft_word',
    ['application/vnd.ms-word.template.macroEnabled.12'] = 'md-microsoft_word',
    ['application/vnd.oasis.opendocument.base'] = 'linux-libreofficebase',
    ['application/vnd.oasis.opendocument.chart'] = 'linux-libreofficecalc',
    ['application/vnd.oasis.opendocument.chart-template'] = 'linux-libreofficecalc',
    ['application/vnd.oasis.opendocument.database'] = 'linux-libreofficebase',
    ['application/vnd.oasis.opendocument.formula'] = 'linux-libreofficemath',
    ['application/vnd.oasis.opendocument.formula-template'] = 'linux-libreofficemath',
    ['application/vnd.oasis.opendocument.graphics'] = 'linux-libreofficedraw',
    ['application/vnd.oasis.opendocument.graphics-flat-xml'] = 'linux-libreofficedraw',
    ['application/vnd.oasis.opendocument.graphics-template'] = 'linux-libreofficedraw',
    ['application/vnd.oasis.opendocument.image'] = 'linux-libreoffice',
    ['application/vnd.oasis.opendocument.presentation'] = 'linux-libreofficeimpress',
    ['application/vnd.oasis.opendocument.presentation-flat-xml'] = 'linux-libreofficeimpress',
    ['application/vnd.oasis.opendocument.presentation-template'] = 'linux-libreofficeimpress',
    ['application/vnd.oasis.opendocument.spreadsheet'] = 'linux-libreofficecalc',
    ['application/vnd.oasis.opendocument.spreadsheet-flat-xml'] = 'linux-libreofficecalc',
    ['application/vnd.oasis.opendocument.spreadsheet-template'] = 'linux-libreofficecalc',
    ['application/vnd.oasis.opendocument.text'] = 'linux-libreofficewriter',
    ['application/vnd.oasis.opendocument.text-flat-xml'] = 'linux-libreofficewriter',
    ['application/vnd.oasis.opendocument.text-master'] = 'linux-libreofficewriter',
    ['application/vnd.oasis.opendocument.text-master-template'] = 'linux-libreofficewriter',
    ['application/vnd.oasis.opendocument.text-template'] = 'linux-libreofficewriter',
    ['application/vnd.oasis.opendocument.text-web'] = 'linux-libreofficewriter',
    ['application/vnd.openofficeorg.extension'] = 'linux-libreoffice',
    ['application/vnd.openxmlformats-officedocument.presentationml.presentation'] = 'md-microsoft_powerpoint',
    ['application/vnd.openxmlformats-officedocument.presentationml.slide'] = 'md-microsoft_powerpoint',
    ['application/vnd.openxmlformats-officedocument.presentationml.slideshow'] = 'md-microsoft_powerpoint',
    ['application/vnd.openxmlformats-officedocument.presentationml.template'] = 'md-microsoft_powerpoint',
    ['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'] = 'md-microsoft_excel',
    ['application/vnd.openxmlformats-officedocument.spreadsheetml.template'] = 'md-microsoft_excel',
    ['application/vnd.openxmlformats-officedocument.wordprocessingml.document'] = 'md-microsoft_word',
    ['application/vnd.openxmlformats-officedocument.wordprocessingml.template'] = 'md-microsoft_word',
    ['application/vnd.sqlite3'] = 'dev-sqlite',
    ['application/vnd.stardivision.calc'] = 'linux-libreofficecalc',
    ['application/vnd.stardivision.chart'] = 'linux-libreofficecalc',
    ['application/vnd.stardivision.draw'] = 'linux-libreofficedraw',
    ['application/vnd.stardivision.impress'] = 'linux-libreofficeimpress',
    ['application/vnd.stardivision.math'] = 'linux-libreofficemath',
    ['application/vnd.stardivision.writer'] = 'linux-libreofficewriter',
    ['application/vnd.stardivision.writer-global'] = 'linux-libreofficewriter',
    ['application/vnd.sun.xml.base'] = 'linux-libreofficebase',
    ['application/vnd.sun.xml.calc'] = 'linux-libreofficecalc',
    ['application/vnd.sun.xml.calc.template'] = 'linux-libreofficecalc',
    ['application/vnd.sun.xml.draw'] = 'linux-libreofficedraw',
    ['application/vnd.sun.xml.draw.template'] = 'linux-libreofficedraw',
    ['application/vnd.sun.xml.impress'] = 'linux-libreofficeimpress',
    ['application/vnd.sun.xml.impress.template'] = 'linux-libreofficeimpress',
    ['application/vnd.sun.xml.math'] = 'linux-libreofficemath',
    ['application/vnd.sun.xml.writer'] = 'linux-libreofficewriter',
    ['application/vnd.sun.xml.writer.global'] = 'linux-libreofficewriter',
    ['application/vnd.sun.xml.writer.template'] = 'linux-libreofficewriter',
    ['application/wasm'] = 'dev-wasm',
    ['application/x-asar'] = 'dev-electron',
    ['application/x-awk'] = 'dev-awk',
    ['application/x-bat'] = 'fa-windows',
    ['application/x-blender'] = 'dev-blender',
    ['application/x-codium-workspace'] = 'linux-vscodium',
    ['application/x-designer'] = 'dev-qt',
    ['application/x-desktop'] = 'linux-freedesktop',
    ['application/x-dosexec'] = 'custom-msdos',
    ['application/x-e-theme'] = 'linux-enlightenment',
    ['application/x-font-dos'] = 'custom-msdos',
    ['application/x-font-linux-psf'] = 'dev-linux',
    ['application/x-gdscript'] = 'dev-godot',
    ['application/x-godot-project'] = 'dev-godot',
    ['application/x-godot-resource'] = 'dev-godot',
    ['application/x-godot-scene'] = 'dev-godot',
    ['application/x-godot-shader'] = 'dev-godot',
    ['application/x-gtk-builder'] = 'linux-gtk',
    ['application/x-gz-font-linux-psf'] = 'dev-linux',
    ['application/x-gzpdf'] = 'seti-pdf',
    ['application/xhtml+xml'] = 'dev-html5',
    ['application/x-ipod-firmware'] = 'md-ipod',
    ['application/x-ipynb+json'] = 'dev-jupyter',
    ['application/x-java'] = 'fa-java',
    ['application/x-java-applet'] = 'fa-java',
    ['application/x-kcsrc'] = 'linux-kde',
    ['application/x-krita'] = 'linux-krita',
    ['application/x-ktheme'] = 'linux-kde',
    ['application/x-lzpdf'] = 'seti-pdf',
    ['application/xml'] = 'dev-xml',
    ['application/xml-dtd'] = 'dev-xml',
    ['application/x-mozilla-bookmarks'] = 'md-firefox',
    ['application/x-perl'] = 'seti-perl',
    ['application/x-php'] = 'dev-php',
    ['application/x-plasma'] = 'linux-kde_plasma',
    ['application/x-powershell'] = 'dev-powershell',
    ['application/x-python-bytecode'] = 'seti-python',
    ['application/x-ruby'] = 'seti-ruby',
    ['application/xsd'] = 'fae-w3c',
    ['application/x-spss-por'] = 'dev-spss',
    -- ['application/x-spss-sav'] = 'dev-spss',
    ['application/x-sqlite2'] = 'dev-sqlite',
    ['application/x-windows-themepack'] = 'fa-windows',
    ['application/x-xzpdf'] = 'seti-pdf',
    ['application/yaml'] = 'dev-yaml',
    ['audio/ac3'] = 'md-dolby',
    ['audio/midi'] = 'md-midi',
    ['audio/x-amzxml'] = 'fa-amazon',
    ['image/svg+xml-compressed'] = 'md-svg',
    ['image/svg+xml'] = 'md-svg',
    ['image/vnd.adobe.photoshop'] = 'dev-photoshop',
    ['image/x-compressed-xcf'] = 'linux-gimp',
    ['image/x-gimp-gbr'] = 'linux-gimp',
    ['image/x-gimp-gih'] = 'linux-gimp',
    ['image/x-gimp-pat'] = 'linux-gimp',
    ['image/x-kde-raw'] = 'linux-kde',
    ['image/x-win-bitmap'] = 'fa-windows',
    ['image/x-xcf'] = 'linux-gimp',
    ['image/x-xcursor'] = 'linux-xorg',
    ['image/x-xwindowdump'] = 'linux-xorg',
    ['text/css'] = 'dev-css3',
    ['text/html'] = 'dev-html5',
    ['text/javascript'] = 'dev-javascript',
    ['text/julia'] = 'seti-julia',
    ['text/markdown'] = 'fa-markdown',
    ['text/org'] = 'custom-orgmode',
    ['text/rust'] = 'seti-rust',
    ['text/vnd.kde.kcrash-report'] = 'linux-kde',
    ['text/vnd.trolltech.linguist'] = 'dev-qt',
    ['text/x-adasrc'] = 'custom-ada',
    ['text/x-chdr'] = 'custom-c',
    ['text/x-c++hdr'] = 'custom-cpp',
    ['text/x-cmake'] = 'dev-cmake',
    ['text/x-common-lisp'] = 'custom-common_lisp',
    ['text/x-crystal'] = 'seti-crystal',
    ['text/x-csharp'] = 'dev-csharp',
    ['text/x-csrc'] = 'custom-c',
    ['text/x-c++src'] = 'custom-cpp',
    ['text/x-devicetree-binary'] = 'dev-linux',
    ['text/x-devicetree-source'] = 'dev-linux',
    ['text/x-dsrc'] = 'dev-dlang',
    ['text/x-elixir'] = 'seti-elixir',
    ['text/x-emacs-lisp'] = 'custom-emacs',
    ['text/x-erlang'] = 'fa-erlang',
    ['text/x-fortran'] = 'dev-fortran',
    ['text/x-go'] = 'seti-go',
    ['text/x-gradle'] = 'seti-gradle',
    ['text/x-groovy'] = 'dev-groovy',
    ['text/x-haskell'] = 'seti-haskell',
    ['text/x-java'] = 'fa-java',
    ['text/x-kotlin'] = 'seti-kotlin',
    ['text/x-literate-haskell'] = 'seti-haskell',
    ['text/x-lua'] = 'seti-lua',
    ['text/x-matlab'] = 'dev-matlab',
    ['text/x-maven+xml'] = 'dev-maven',
    ['text/x-moc'] = 'dev-qt',
    ['text/x-ms-regedit'] = 'fa-windows',
    ['text/x-nimscript'] = 'seti-nim',
    ['text/x-nim'] = 'seti-nim',
    ['text/x-objcsrc'] = 'dev-objectivec',
    ['text/x-ocaml'] = 'dev-ocaml',
    ['text/x-opencl-src'] = 'dev-opencl',
    ['text/x-python3'] = 'seti-python',
    ['text/x-python'] = 'seti-python',
    ['text/x-qml'] = 'dev-qt',
    ['text/x-sass'] = 'seti-sass',
    ['text/x-scala'] = 'seti-scala',
    ['text/x-scheme'] = 'custom-scheme',
    ['text/x-tex'] = 'seti-tex',
    ['text/x-twig'] = 'seti-twig',
    ['text/x-typst'] = 'linux-typst',
    ['text/x-vala'] = 'dev-vala',
    ['text/x-vb'] = 'dev-visualbasic',
    ['text/x-zig'] = 'seti-zig',
    ['video/vnd.youtube.yt'] = 'fa-youtube',
  },
}, Widget)
FileChooser.__index = FileChooser

function FileChooser.new(path)
  local self = setmetatable(Widget.new(), FileChooser)
  self.faces = setmetatable({}, { __index = FileChooser.faces })

  self.path_field = TextField.new()
  self.path_field.text = path or ''
  self.path_field.parent = self

  self._selected_completion = nil
  self.completions_dir = nil
  self.completions = SortedSet.new(function(a, b)
    local a_is_dir, b_is_dir = a:get_file_type() == 'DIRECTORY', b:get_file_type() == 'DIRECTORY'
    if a_is_dir ~= b_is_dir then
      return a_is_dir
    else
      return a:get_name() < b:get_name()
    end
  end)
  self.completions_lock = thread.newrelock()
  self.worker = nil
  self.worker_is_stopping = false

  return self
end

function FileChooser:draw()
  Widget.draw(self)
  if self.width == 0 or self.height == 0 then return end

  self:refresh_completions()

  self.path_field:set_bounds(self.x, self.y, self.width, 1)
  self.path_field:draw()

  local visible_completions = {}
  local center = self:selected_completion()
  if center then
    local node = self:prev_completion(center)
    while node and #visible_completions < (self.height - 2) // 2 do
      table.insert(visible_completions, 1, node.value)
      node = self:prev_completion(node)
    end
    node = center
    while node and #visible_completions < self.height - 1 do
      table.insert(visible_completions, node.value)
      node = self:next_completion(node)
    end
  end

  local y = self.y + 1

  for _, file_info in ipairs(visible_completions) do
    local x = self.x
    tty.move_to(x, y)

    local normal_face, invalid_face = self.faces.completion, self.faces.completion_invalid
    if file_info == self:selected_completion().value then
      normal_face = self.faces.selected_completion
      invalid_face = self.faces.selected_completion_invalid
    end

    for _, grapheme in grapheme.characters(self:label_for_completion(file_info)) do
      if not utf8.len(grapheme) then
        grapheme = '�'
        tty.set_face(invalid_face)
      elseif ui.ctrl_pics[grapheme] then
        grapheme = ui.ctrl_pics[grapheme]
        tty.set_face(invalid_face)
      else
        tty.set_face(normal_face)
      end

      local width = tty.width_of(grapheme)
      if x > self.x + self.width then break end
      if x + width > self.x + self.width then
        grapheme = (' '):rep(self.x + self.width - x)
      end
      tty.write(grapheme)
      x = x + width
    end

    tty.set_face(normal_face)
    tty.write((' '):rep(self.x + self.width - x))
    if x > self.x + self.width then
      tty.move_to(self.x + self.width - 1, y)
      tty.write('…')
    end

    y = y + 1
  end

  tty.set_face(self.faces.completion)
  while y < self.y + self.height do
    tty.move_to(self.x, y)
    tty.write((' '):rep(self.width))
    y = y + 1
  end
end

function FileChooser:label_for_completion(file_info)
  return self:icon_for_file(file_info) .. ' ' .. file_info:get_name() .. (file_info:get_file_type() == 'DIRECTORY' and GLib.DIR_SEPARATOR_S or '')
end

function FileChooser:icon_for_file(file_info)
  local mime = file_info:get_content_type()
  local result = 'fa-file_o'
  if mime:find('^audio/') then
    result = 'fa-file_audio_o'
  elseif mime:find('^image/') then
    result = 'fa-file_image_o'
  elseif mime:find('^inode/') then
    result = 'fa-question'
  elseif mime:find('^text/') then
    result = 'fa-file_text_o'
  elseif mime:find('^video/') then
    result = 'fa-file_video_o'
  elseif mime:find('compress') then
    result = 'fa-file_archive_o'
  end
  result = self.file_xdg_generic_icons[Gio.content_type_get_generic_icon_name(mime)] or result
  result = self.file_symbolic_icons[mime] or result
  result = self.file_logo_icons[mime] or result
  return nerd_fonts.icons[result] or ' '
end

function FileChooser:handle_event(event)
  if (event.type == 'press' or event.type == 'repeat') and event.button == 'up' then
    self:move_completion_selection_up(1)
    self:request_draw()

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'down' then
    self:move_completion_selection_down(1)
    self:request_draw()

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'page_up' then
    self:move_completion_selection_up(self.height - 1)
    self:request_draw()

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'page_down' then
    self:move_completion_selection_down(self.height - 1)
    self:request_draw()

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'scroll_up' then
    self:move_completion_selection_up(3)
    self:request_draw()

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'scroll_down' then
    self:move_completion_selection_down(3)
    self:request_draw()

  elseif (event.type == 'press' or event.type == 'repeat') and event.button == 'tab' then
    if event.shift then
      self:ascend_dir()
      self:request_draw()
    elseif self:apply_selected_completion() then
      self:request_draw()
    end

  else
    self.path_field:handle_event(event)
  end
end

function FileChooser:move_completion_selection_up(rowc)
  local node = self:selected_completion()
  while rowc > 0 and node do
    node = self:prev_completion(node)
    rowc = rowc - 1
  end
  self:set_selected_completion(node or self:first_completion())
end

function FileChooser:move_completion_selection_down(rowc)
  local node = self:selected_completion()
  while rowc > 0 and node do
    node = self:next_completion(node)
    rowc = rowc - 1
  end
  self:set_selected_completion(node or self:last_completion())
end

function FileChooser:apply_selected_completion()
  local node = self:selected_completion()
  if not node then
    return false
  end
  self.path_field:update_history_before_edit()
  self.path_field.text = GLib.build_pathv(GLib.DIR_SEPARATOR_S, {
    GLib.path_get_dirname(self.path_field.text),
    node.value:get_name() .. (node.value:get_file_type() == 'DIRECTORY' and GLib.DIR_SEPARATOR_S or ''),
  })
  self.path_field.cursor = #self.path_field.text + 1
  self.path_field:update_history_after_edit()
  self.path_field:adjust_view_to_contain_idx(self.path_field.cursor)
  return true
end

function FileChooser:ascend_dir() -- HACK: rename!
  self.path_field:update_history_before_edit()
  local dir = GLib.path_get_dirname(self.path_field.text .. 'x')
  if GLib.path_get_basename(dir) == '..' or GLib.path_get_dirname(dir) == dir then
    self.path_field.text = GLib.build_pathv(GLib.DIR_SEPARATOR_S, {dir, '..' .. GLib.DIR_SEPARATOR_S})
  else
    self.path_field.text = GLib.path_get_dirname(dir) .. GLib.DIR_SEPARATOR_S
  end
  self.path_field.cursor = #self.path_field.text + 1
  self.path_field:update_history_after_edit()
  self.path_field:adjust_view_to_contain_idx(self.path_field.cursor)
end

function FileChooser:idle()
  self.path_field:idle()
end

function FileChooser:refresh_completions()
  local completions_dir = Gio.File.new_for_path(self.path_field.text .. 'x'):get_parent()
  if self.completions_dir and self.completions_dir:equal(completions_dir) then return end
  if self.worker then
    self.worker_is_stopping = true
    self.worker:join()
    self.worker_is_stopping = false
  end
  self.completions_dir = completions_dir
  self.completions:clear()
  self.worker = thread.new(xpcall, self.generate_completions, function(err)
    stderr.error(here, debug.traceback(err, 2))
  end, self)
end

function FileChooser:generate_completions()
  do
    local lock <close> = self.completions_lock:acquire()
    self.completions:clear()
  end
  local iter = self.completions_dir:enumerate_children('standard::*')
  while true do
    local lock <close> = self.completions_lock:acquire()
    local file_info = nil
    for i = 1, 100 do
      file_info = iter:next_file()
      if not file_info or self.worker_is_stopping then break end
      self.completions:insert(file_info)
    end
    if not file_info or self.worker_is_stopping then break end
  end
  self:request_draw()
end

function FileChooser:selected_completion()
  local lock <close> = self.completions_lock:acquire()
  local prefix = self:completions_prefix()
  local node = self._selected_completion and self.completions:find(self._selected_completion.value)
  return node and node.value:get_name():sub(1, #prefix) == prefix and node or self:first_completion()
end

function FileChooser:set_selected_completion(node)
  self._selected_completion = node
end

function FileChooser:first_completion()
  local lock <close> = self.completions_lock:acquire()
  local prefix = self:completions_prefix()
  local node = self.completions:find_first(function(value)
    return value:get_name() >= prefix or value:get_file_type() ~= 'DIRECTORY'
  end)
  node = node and node.value:get_name():sub(1, #prefix) == prefix and node or self.completions:find_first(function(value)
    return value:get_file_type() ~= 'DIRECTORY' and value:get_name() >= prefix
  end)
  return node and node.value:get_name():sub(1, #prefix) == prefix and node or nil
end

function FileChooser:last_completion()
  local lock <close> = self.completions_lock:acquire()
  local prefix = self:completions_prefix()
  local node = self.completions:find_last(function(value)
    return value:get_name():sub(1, #prefix) <= prefix or value:get_file_type() == 'DIRECTORY'
  end)
  node = node and node.value:get_name():sub(1, #prefix) == prefix and node or self.completions:find_last(function(value)
    return value:get_file_type() == 'DIRECTORY' and value:get_name():sub(1, #prefix) <= prefix
  end)
  return node and node.value:get_name():sub(1, #prefix) == prefix and node or nil
end

function FileChooser:next_completion(node)
  local lock <close> = self.completions_lock:acquire()
  local prefix = self:completions_prefix()
  node = self.completions:next(node)
  if not node or node.value:get_name():sub(1, #prefix) == prefix then
    return node
  elseif node.value:get_file_type() ~= 'DIRECTORY' and node.value:get_name() >= prefix then
    return nil
  else
    node = self.completions:find_first(function(value)
      return value:get_file_type() ~= 'DIRECTORY' and value:get_name() >= prefix
    end)
    return node and node.value:get_name():sub(1, #prefix) == prefix and node or nil
  end
end

function FileChooser:prev_completion(node)
  local lock <close> = self.completions_lock:acquire()
  local prefix = self:completions_prefix()
  node = self.completions:prev(node)
  if not node or node.value:get_name():sub(1, #prefix) == prefix then
    return node
  elseif node.value:get_file_type() == 'DIRECTORY' and node.value:get_name():sub(1, #prefix) <= prefix then
    return nil
  else
    node = self.completions:find_last(function(value)
      return value:get_file_type() == 'DIRECTORY' and value:get_name():sub(1, #prefix) <= prefix
    end)
    return node and node.value:get_name():sub(1, #prefix) == prefix and node or nil
  end
end

function FileChooser:completions_prefix() -- HACK: rename?
  return GLib.path_get_basename(self.path_field.text .. 'x'):sub(1, -2)
end

return FileChooser
