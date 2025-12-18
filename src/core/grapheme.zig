// Skakun - A robust and hackable hex and text editor
// Copyright (C) 2024-2025 Karol "digitcrusher" Łacina
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");
const lua = @import("zlua");
const c = @cImport(@cInclude("grapheme.h"));
const assert = std.debug.assert;

fn characters(vm: *lua.Lua) i32 {
  vm.pushInteger(0);
  vm.pushClosure(lua.wrap(characters_iter), 1);
  vm.pushValue(1);
  return 2;
}

fn characters_iter(vm: *lua.Lua) i32 {
  const from: usize = @intCast(vm.toInteger(lua.Lua.upvalueIndex(1)) catch unreachable);
  const tail = vm.checkString(1)[from ..];
  const len = c.grapheme_next_character_break_utf8(tail.ptr, tail.len);
  if(len == 0) {
    return 0;
  }
  vm.pushInteger(@intCast(from + 1));
  _ = vm.pushString(tail[0 .. len]);
  vm.pushInteger(@intCast(from + len));
  vm.replace(lua.Lua.upvalueIndex(1));
  return 2;
}

fn words(vm: *lua.Lua) i32 {
  vm.pushInteger(0);
  vm.pushClosure(lua.wrap(words_iter), 1);
  vm.pushValue(1);
  return 2;
}

fn words_iter(vm: *lua.Lua) i32 {
  const from: usize = @intCast(vm.toInteger(lua.Lua.upvalueIndex(1)) catch unreachable);
  const tail = vm.checkString(1)[from ..];
  const len = c.grapheme_next_word_break_utf8(tail.ptr, tail.len);
  if(len == 0) {
    return 0;
  }
  vm.pushInteger(@intCast(from + 1));
  _ = vm.pushString(tail[0 .. len]);
  vm.pushInteger(@intCast(from + len));
  vm.replace(lua.Lua.upvalueIndex(1));
  return 2;
}

fn sentences(vm: *lua.Lua) i32 {
  vm.pushInteger(0);
  vm.pushClosure(lua.wrap(sentences_iter), 1);
  vm.pushValue(1);
  return 2;
}

fn sentences_iter(vm: *lua.Lua) i32 {
  const from: usize = @intCast(vm.toInteger(lua.Lua.upvalueIndex(1)) catch unreachable);
  const tail = vm.checkString(1)[from ..];
  const len = c.grapheme_next_sentence_break_utf8(tail.ptr, tail.len);
  if(len == 0) {
    return 0;
  }
  vm.pushInteger(@intCast(from + 1));
  _ = vm.pushString(tail[0 .. len]);
  vm.pushInteger(@intCast(from + len));
  vm.replace(lua.Lua.upvalueIndex(1));
  return 2;
}

fn lines(vm: *lua.Lua) i32 {
  vm.pushInteger(0);
  vm.pushClosure(lua.wrap(lines_iter), 1);
  vm.pushValue(1);
  return 2;
}

fn lines_iter(vm: *lua.Lua) i32 {
  const from: usize = @intCast(vm.toInteger(lua.Lua.upvalueIndex(1)) catch unreachable);
  const tail = vm.checkString(1)[from ..];
  const len = c.grapheme_next_line_break_utf8(tail.ptr, tail.len);
  if(len == 0) {
    return 0;
  }
  vm.pushInteger(@intCast(from + 1));
  _ = vm.pushString(tail[0 .. len]);
  vm.pushInteger(@intCast(from + len));
  vm.replace(lua.Lua.upvalueIndex(1));
  return 2;
}

fn is_lowercase(vm: *lua.Lua) i32 {
  const string = vm.checkString(1);
  var prefix_len: usize = undefined;
  vm.pushBoolean(c.grapheme_is_lowercase_utf8(string.ptr, string.len, &prefix_len));
  vm.pushInteger(@intCast(prefix_len));
  return 2;
}

fn is_titlecase(vm: *lua.Lua) i32 {
  const string = vm.checkString(1);
  var prefix_len: usize = undefined;
  vm.pushBoolean(c.grapheme_is_titlecase_utf8(string.ptr, string.len, &prefix_len));
  vm.pushInteger(@intCast(prefix_len));
  return 2;
}

fn is_uppercase(vm: *lua.Lua) i32 {
  const string = vm.checkString(1);
  var prefix_len: usize = undefined;
  vm.pushBoolean(c.grapheme_is_uppercase_utf8(string.ptr, string.len, &prefix_len));
  vm.pushInteger(@intCast(prefix_len));
  return 2;
}

fn to_lowercase(vm: *lua.Lua) i32 {
  const src = vm.checkString(1);
  var result: lua.Buffer = undefined;
  var dest = result.initSize(vm, src.len + 1);
  var written = c.grapheme_to_lowercase_utf8(src.ptr, src.len, dest.ptr, dest.len);
  if(written >= dest.len) {
    dest = result.prepSize(written + 1);
    written = c.grapheme_to_lowercase_utf8(src.ptr, src.len, dest.ptr, dest.len);
    assert(written < dest.len);
  }
  result.pushResultSize(written);
  return 1;
}

fn to_titlecase(vm: *lua.Lua) i32 {
  const src = vm.checkString(1);
  var result: lua.Buffer = undefined;
  var dest = result.initSize(vm, src.len + 1);
  var written = c.grapheme_to_titlecase_utf8(src.ptr, src.len, dest.ptr, dest.len);
  if(written >= dest.len) {
    dest = result.prepSize(written + 1);
    written = c.grapheme_to_titlecase_utf8(src.ptr, src.len, dest.ptr, dest.len);
    assert(written < dest.len);
  }
  result.pushResultSize(written);
  return 1;
}

fn to_uppercase(vm: *lua.Lua) i32 {
  const src = vm.checkString(1);
  var result: lua.Buffer = undefined;
  var dest = result.initSize(vm, src.len + 1);
  var written = c.grapheme_to_uppercase_utf8(src.ptr, src.len, dest.ptr, dest.len);
  if(written >= dest.len) {
    dest = result.prepSize(written + 1);
    written = c.grapheme_to_uppercase_utf8(src.ptr, src.len, dest.ptr, dest.len);
    assert(written < dest.len);
  }
  result.pushResultSize(written);
  return 1;
}

const funcs = blk: {
  @setEvalBranchQuota(100_000);
  break :blk [_]lua.FnReg{
    .{ .name = "characters", .func = lua.wrap(characters) },
    .{ .name = "words", .func = lua.wrap(words) },
    .{ .name = "sentences", .func = lua.wrap(sentences) },
    .{ .name = "lines", .func = lua.wrap(lines) },
    .{ .name = "is_lowercase", .func = lua.wrap(is_lowercase) },
    .{ .name = "is_titlecase", .func = lua.wrap(is_titlecase) },
    .{ .name = "is_uppercase", .func = lua.wrap(is_uppercase) },
    .{ .name = "to_lowercase", .func = lua.wrap(to_lowercase) },
    .{ .name = "to_titlecase", .func = lua.wrap(to_titlecase) },
    .{ .name = "to_uppercase", .func = lua.wrap(to_uppercase) },
  };
};

export fn luaopen_core_grapheme(vm: *lua.Lua) i32 {
  vm.newLib(&funcs);
  return 1;
}
