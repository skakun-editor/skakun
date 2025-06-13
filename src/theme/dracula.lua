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

local tty     = require('core.tty')
local DocView = require('core.ui.doc_view')
local utils   = require('core.utils')
local rgb = tty.Rgb.from

local dracula = {
  themer = utils.Themer.new(),
}

function dracula.apply()
  local theme = tty.cap.foreground == 'true_color' and tty.cap.background == 'true_color' and dracula.true_color or dracula.ansi
  dracula.themer:apply(
    DocView.faces, 'normal', theme.faces.normal,
    DocView.faces, 'invalid', theme.faces.invalid,
    DocView.faces, 'syntax_highlights', theme.faces.syntax_highlights,
    DocView.colors, 'misspelling', theme.colors.red
  )
end

function dracula.unapply()
  dracula.themer:unapply()
end

-- The particular selection and configuration of colors used below is subject to
-- the following license:
--
-- Copyright (c) 2023 Dracula Theme
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

-- Reference: https://spec.draculatheme.com/

function dracula.regenerate()
  dracula.true_color = dracula.from({
    background = rgb'282A36',
    foreground = rgb'F8F8F2',
    selection  = rgb'44475A',
    comment    = rgb'6272A4',
    red        = rgb'FF5555',
    orange     = rgb'FFB86C',
    yellow     = rgb'F1FA8C',
    green      = rgb'50FA7B',
    purple     = rgb'BD93F9',
    cyan       = rgb'8BE9FD',
    pink       = rgb'FF79C6',
  })
  dracula.ansi = dracula.from({
    background = 'black',
    foreground = 'bright_white',
    selection  = 'bright_black',
    comment    = 'bright_black',
    red        = 'bright_red',
    orange     = 'yellow',
    yellow     = 'bright_yellow',
    green      = 'bright_green',
    purple     = 'magenta',
    cyan       = 'bright_cyan',
    pink       = 'bright_magenta',
  })
end

function dracula.from(colors)
  local faces = {
    normal                                    = { foreground = colors.foreground, background = colors.background },
    invalid                                   = { foreground = colors.foreground, background = colors.red },
    deprecated                                = { foreground = colors.foreground, background = colors.purple },
    error                                     = { foreground = colors.red,        background = colors.background },

    diff_text                                 = { foreground = colors.comment,    background = colors.background },
    diff_header                               = { foreground = colors.comment,    background = colors.background },
    diff_inserted                             = { foreground = colors.green,      background = colors.background },
    diff_deleted                              = { foreground = colors.red,        background = colors.background },
    diff_changed                              = { foreground = colors.orange,     background = colors.background },

    markup_bold                               = { foreground = colors.orange,     background = colors.background, bold = true },
    markup_heading                            = { foreground = colors.purple,     background = colors.background, bold = true },
    markup_italic                             = { foreground = colors.yellow,     background = colors.background, italic = true },
    markup_list_bullet_or_number              = { foreground = colors.cyan,       background = colors.background },
    markup_inline_code                        = { foreground = colors.green,      background = colors.background },
    markup_link_url                           = { foreground = colors.cyan,       background = colors.background },
    markup_link_text                          = { foreground = colors.pink,       background = colors.background },
    markup_blockquote                         = { foreground = colors.yellow,     background = colors.background, italic = true },
    markup_horizontal_rule                    = { foreground = colors.comment,    background = colors.background },
    markup_code_block_without_syntax          = { foreground = colors.orange,     background = colors.background },
    markup_rst_constants                      = { foreground = colors.purple,     background = colors.background },

    class_name                                = { foreground = colors.cyan,       background = colors.background },
    instance_reserved_words                   = { foreground = colors.purple,     background = colors.background, italic = true },
    inherited_class_name                      = { foreground = colors.cyan,       background = colors.background, italic = true },

    comment                                   = { foreground = colors.comment,    background = colors.background },
    doc_comment_keywords                      = { foreground = colors.pink,       background = colors.background },
    doc_comment_types                         = { foreground = colors.cyan,       background = colors.background, italic = true },
    doc_comment_parameters                    = { foreground = colors.orange,     background = colors.background, italic = true },

    constant                                  = { foreground = colors.purple,     background = colors.background },
    constant_escape_sequences                 = { foreground = colors.pink,       background = colors.background },

    html_tags                                 = { foreground = colors.pink,       background = colors.background },
    css_parent_selectors                      = { foreground = colors.pink,       background = colors.background },
    html_css_attribute_names                  = { foreground = colors.green,      background = colors.background },

    function_names                            = { foreground = colors.green,      background = colors.background },
    function_parameters                       = { foreground = colors.orange,     background = colors.background, italic = true },
    decorators                                = { foreground = colors.green,      background = colors.background, italic = true },

    keyword                                   = { foreground = colors.pink,       background = colors.background },
    keyword_new                               = { foreground = colors.pink,       background = colors.background, bold = true },
    keyword_generic_css_selector              = { foreground = colors.pink,       background = colors.background },

    support                                   = { foreground = colors.cyan,       background = colors.background, italic = true },
    builtin_magic_methods_or_constants        = { foreground = colors.purple,     background = colors.background },
    builtin_functions                         = { foreground = colors.cyan,       background = colors.background },

    separators_references_or_accessors        = { foreground = colors.pink,       background = colors.background },
    brackets_parens_braces                    = { foreground = colors.foreground, background = colors.background },
    string_interpolation_operators            = { foreground = colors.pink,       background = colors.background },

    keys                                      = { foreground = colors.cyan,       background = colors.background },
    date_time                                 = { foreground = colors.orange,     background = colors.background },
    yaml_aliases                              = { foreground = colors.green,      background = colors.background, italic = true, underline = true },

    storage                                   = { foreground = colors.pink,       background = colors.background },
    types                                     = { foreground = colors.cyan,       background = colors.background, italic = true },
    modifiers                                 = { foreground = colors.pink,       background = colors.background },
    generic_templates_and_mapped_declarations = { foreground = colors.orange,     background = colors.background, italic = true },

    string                                    = { foreground = colors.yellow,     background = colors.background },
    string_regexp                             = { foreground = colors.red,        background = colors.background },

    variable                                  = { foreground = colors.foreground, background = colors.background },
    object_keys                               = { foreground = colors.foreground, background = colors.background },
    destructuring_alias_lhs                   = { foreground = colors.orange,     background = colors.background, italic = true },
    destructuring_alias_rhs                   = { foreground = colors.foreground, background = colors.background },
  }
  faces.syntax_highlights = {
    ['attribute']                   = faces.decorators,
    ['boolean']                     = faces.builtin_magic_methods_or_constants,
    ['character']                   = faces.constant,
    ['character.special']           = faces.keyword,
    ['comment']                     = faces.comment,
    ['comment.documentation']       = faces.comment,
    ['conditional']                 = faces.keyword,
    ['constant']                    = faces.constant,
    ['constant.builtin']            = faces.builtin_magic_methods_or_constants,
    ['constant.character']          = faces.constant,
    ['constant.macro']              = faces.keyword,
    ['constructor']                 = faces.class_name,
    ['delimiter']                   = faces.normal,
    ['escape']                      = faces.constant_escape_sequences,
    ['exception']                   = faces.keyword,
    ['float']                       = faces.constant,
    ['function']                    = faces.function_names,
    ['function.builtin']            = faces.builtin_functions,
    ['function.call']               = faces.function_names,
    ['function.macro']              = faces.function_names,
    ['function.method']             = faces.function_names,
    ['function.method.builtin']     = faces.builtin_magic_methods_or_constants,
    ['function.special']            = faces.function_names,
    ['include']                     = faces.keyword,
    ['keyword']                     = faces.keyword,
    ['keyword.conditional']         = faces.keyword,
    ['keyword.conditional.ternary'] = faces.keyword,
    ['keyword.debug']               = faces.keyword,
    ['keyword.directive']           = faces.keyword,
    ['keyword.exception']           = faces.keyword,
    ['keyword.function']            = faces.keyword,
    ['keyword.import']              = faces.keyword,
    ['keyword.operator']            = faces.keyword,
    ['keyword.repeat']              = faces.keyword,
    ['keyword.return']              = faces.keyword,
    ['keyword.type']                = faces.keyword,
    ['label']                       = faces.yaml_aliases,
    ['method']                      = faces.function_names,
    ['method.call']                 = faces.function_names,
    ['module']                      = faces.normal,
    ['module.builtin']              = faces.normal,
    ['namespace']                   = faces.normal,
    ['number']                      = faces.constant,
    ['number.float']                = faces.constant,
    ['operator']                    = faces.keyword,
    ['parameter']                   = faces.function_parameters,
    ['property']                    = faces.object_keys,
    ['property.definition']         = faces.object_keys,
    ['punctuation']                 = faces.normal,
    ['punctuation.bracket']         = faces.brackets_parens_braces,
    ['punctuation.delimiter']       = faces.normal,
    ['punctuation.special']         = faces.string_interpolation_operators,
    ['repeat']                      = faces.keyword,
    ['storageclass']                = faces.modifiers,
    ['string']                      = faces.string,
    ['string.documentation']        = faces.comment,
    ['string.escape']               = faces.constant_escape_sequences,
    ['string.special']              = faces.string_regexp,
    ['string.special.key']          = faces.keys,
    ['string.special.regex']        = faces.string_regexp,
    ['string.special.symbol']       = faces.constant,
    ['tag']                         = faces.html_tags,
    ['tag.error']                   = faces.error,
    ['type']                        = faces.class_name,
    ['type.builtin']                = faces.types,
    ['type.definition']             = faces.class_name,
    ['type.qualifier']              = faces.modifiers,
    ['variable']                    = faces.variable,
    ['variable.builtin']            = faces.instance_reserved_words,
    ['variable.member']             = faces.object_keys,
    ['variable.parameter']          = faces.function_parameters,
  }
  return {
    colors = colors,
    faces = faces,
  }
end

dracula.regenerate()

return dracula
