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
const c = @cImport(@cInclude("enchant.h"));
const assert = std.debug.assert;

fn get_version(vm: *lua.Lua) i32 {
  _ = vm.pushString(std.mem.span(c.enchant_get_version()));
  return 1;
}

fn set_prefix_dir(vm: *lua.Lua) i32 {
  c.enchant_set_prefix_dir(vm.checkString(1));
  return 0;
}

const funcs = [_]lua.FnReg{
  .{ .name = "get_version", .func = lua.wrap(get_version) },
  .{ .name = "set_prefix_dir", .func = lua.wrap(set_prefix_dir) },
};

fn broker_init(vm: *lua.Lua) i32 {
  vm.newUserdata(*c.EnchantBroker, 0).* = c.enchant_broker_init().?;
  vm.setMetatableRegistry("core.enchant.Broker");
  return 1;
}

fn broker_gc(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*c.EnchantBroker, 1, "core.enchant.Broker").*;
  c.enchant_broker_free(self);
  return 0;
}

fn broker_request_dict(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*c.EnchantBroker, 1, "core.enchant.Broker").*;
  const tag = vm.checkString(2);
  if(c.enchant_broker_request_dict(self, tag)) |dict| {
    vm.newUserdata(*c.EnchantDict, 1).* = dict;
    vm.setMetatableRegistry("core.enchant.Dict");
    vm.pushValue(1);
    vm.setUserValue(-2, 1) catch unreachable;
    return 1;
  } else {
    vm.pushFail();
    if(c.enchant_broker_get_error(self)) |err| {
      _ = vm.pushString(std.mem.span(err));
    } else {
      vm.pushNil();
    }
    return 2;
  }
}

fn broker_request_pwl_dict(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*c.EnchantBroker, 1, "core.enchant.Broker").*;
  const pwl = vm.checkString(2);
  if(c.enchant_broker_request_pwl_dict(self, pwl)) |dict| {
    vm.newUserdata(*c.EnchantDict, 1).* = dict;
    vm.setMetatableRegistry("core.enchant.Dict");
    vm.pushValue(1);
    vm.setUserValue(-2, 1) catch unreachable;
    return 1;
  } else {
    vm.pushFail();
    if(c.enchant_broker_get_error(self)) |err| {
      _ = vm.pushString(std.mem.span(err));
    } else {
      vm.pushNil();
    }
    return 2;
  }
}

fn broker_dict_exists(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*c.EnchantBroker, 1, "core.enchant.Broker").*;
  const tag = vm.checkString(2);
  vm.pushBoolean(c.enchant_broker_dict_exists(self, tag) != 0);
  return 1;
}

fn broker_set_ordering(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*c.EnchantBroker, 1, "core.enchant.Broker").*;
  const tag = vm.checkString(2);
  const ordering = vm.checkString(3);
  c.enchant_broker_set_ordering(self, tag, ordering);
  return 0;
}

fn broker_describe(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*c.EnchantBroker, 1, "core.enchant.Broker").*;
  vm.setTop(2);
  c.enchant_broker_describe(self, @ptrCast(&broker_describe_callback), vm);
  if(vm.getTop() > 2) {
    vm.raiseError();
  }
  return 0;
}

fn broker_describe_callback(provider_name: [*:0]const u8, provider_desc: [*:0]const u8,
                            provider_dll_file: [*:0]const u8, user_data: ?*anyopaque) callconv(.C) void
{
  const vm: *lua.Lua = @ptrCast(user_data.?);
  if(vm.getTop() > 2) return;
  vm.pushValue(2);
  _ = vm.pushString(std.mem.span(provider_name));
  _ = vm.pushString(std.mem.span(provider_desc));
  _ = vm.pushString(std.mem.span(provider_dll_file));
  vm.protectedCall(.{ .args = 3, .results = 0 }) catch {};
}

fn broker_list_dicts(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*c.EnchantBroker, 1, "core.enchant.Broker").*;
  vm.setTop(2);
  c.enchant_broker_list_dicts(self, @ptrCast(&broker_list_dicts_callback), vm);
  if(vm.getTop() > 2) {
    vm.raiseError();
  }
  return 0;
}

fn broker_list_dicts_callback(lang_tag: [*:0]const u8, provider_name: [*:0]const u8,
                              provider_desc: [*:0]const u8, provider_file: [*:0]const u8,
                              user_data: ?*anyopaque) callconv(.C) void
{
  const vm: *lua.Lua = @ptrCast(user_data.?);
  if(vm.getTop() > 2) return;
  vm.pushValue(2);
  _ = vm.pushString(std.mem.span(lang_tag));
  _ = vm.pushString(std.mem.span(provider_name));
  _ = vm.pushString(std.mem.span(provider_desc));
  _ = vm.pushString(std.mem.span(provider_file));
  vm.protectedCall(.{ .args = 4, .results = 0 }) catch {};
}

const broker_methods = [_]lua.FnReg{
  .{ .name = "init", .func = lua.wrap(broker_init) },
  .{ .name = "__gc", .func = lua.wrap(broker_gc) },
  .{ .name = "request_dict", .func = lua.wrap(broker_request_dict) },
  .{ .name = "request_pwl_dict", .func = lua.wrap(broker_request_pwl_dict) },
  .{ .name = "dict_exists", .func = lua.wrap(broker_dict_exists) },
  .{ .name = "set_ordering", .func = lua.wrap(broker_set_ordering) },
  .{ .name = "describe", .func = lua.wrap(broker_describe) },
  .{ .name = "list_dicts", .func = lua.wrap(broker_list_dicts) },
};

fn dict_gc(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*c.EnchantDict, 1, "core.enchant.Dict").*;
  assert(vm.getUserValue(1, 1) catch unreachable == .userdata);
  const dict = vm.checkUserdata(*c.EnchantBroker, -1, "core.enchant.Broker").*;
  c.enchant_broker_free_dict(dict, self);
  return 0;
}

fn dict_check(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*c.EnchantDict, 1, "core.enchant.Dict").*;
  const word = vm.checkString(2);
  const result = c.enchant_dict_check(self, word.ptr, @intCast(word.len));
  if(c.enchant_dict_get_error(self)) |err| {
    vm.raiseErrorStr("%s", .{err});
  } else {
    vm.pushBoolean(result == 0);
  }
  return 1;
}

fn dict_suggest(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*c.EnchantDict, 1, "core.enchant.Dict").*;
  const word = vm.checkString(2);
  var len: usize = undefined;
  if(c.enchant_dict_suggest(self, word.ptr, @intCast(word.len), &len)) |ptr| {
    defer c.enchant_dict_free_string_list(self, ptr);
    for(ptr[0 .. len]) |x| {
      _ = vm.pushString(std.mem.span(x));
    }
  } else if(c.enchant_dict_get_error(self)) |err| {
    vm.raiseErrorStr("%s", .{err});
  }
  return @intCast(len);
}

fn dict_add(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*c.EnchantDict, 1, "core.enchant.Dict").*;
  const word = vm.checkString(2);
  c.enchant_dict_add(self, word.ptr, @intCast(word.len));
  return 0;
}

fn dict_add_to_session(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*c.EnchantDict, 1, "core.enchant.Dict").*;
  const word = vm.checkString(2);
  c.enchant_dict_add_to_session(self, word.ptr, @intCast(word.len));
  return 0;
}

fn dict_remove(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*c.EnchantDict, 1, "core.enchant.Dict").*;
  const word = vm.checkString(2);
  c.enchant_dict_remove(self, word.ptr, @intCast(word.len));
  return 0;
}

fn dict_remove_from_session(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*c.EnchantDict, 1, "core.enchant.Dict").*;
  const word = vm.checkString(2);
  c.enchant_dict_remove_from_session(self, word.ptr, @intCast(word.len));
  return 0;
}

fn dict_is_added(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*c.EnchantDict, 1, "core.enchant.Dict").*;
  const word = vm.checkString(2);
  vm.pushBoolean(c.enchant_dict_is_added(self, word.ptr, @intCast(word.len)) != 0);
  return 1;
}

fn dict_is_removed(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*c.EnchantDict, 1, "core.enchant.Dict").*;
  const word = vm.checkString(2);
  vm.pushBoolean(c.enchant_dict_is_removed(self, word.ptr, @intCast(word.len)) != 0);
  return 1;
}

fn dict_get_extra_word_characters(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*c.EnchantDict, 1, "core.enchant.Dict").*;
  _ = vm.pushString(std.mem.span(c.enchant_dict_get_extra_word_characters(self)));
  return 1;
}

fn dict_is_word_character(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*c.EnchantDict, 1, "core.enchant.Dict").*;
  const uc = vm.checkInteger(2);
  const n = vm.checkInteger(3);
  vm.pushBoolean(c.enchant_dict_is_word_character(self, @intCast(uc), @intCast(n)) != 0);
  return 1;
}

fn dict_describe(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*c.EnchantDict, 1, "core.enchant.Dict").*;
  c.enchant_dict_describe(self, @ptrCast(&dict_describe_callback), vm);
  return 4;
}

fn dict_describe_callback(lang_tag: [*:0]const u8, provider_name: [*:0]const u8,
                          provider_desc: [*:0]const u8, provider_file: [*:0]const u8,
                          user_data: ?*anyopaque) callconv(.C) void
{
  const vm: *lua.Lua = @ptrCast(user_data.?);
  _ = vm.pushString(std.mem.span(lang_tag));
  _ = vm.pushString(std.mem.span(provider_name));
  _ = vm.pushString(std.mem.span(provider_desc));
  _ = vm.pushString(std.mem.span(provider_file));
}

const dict_methods = [_]lua.FnReg{
  .{ .name = "__gc", .func = lua.wrap(dict_gc) },
  .{ .name = "check", .func = lua.wrap(dict_check) },
  .{ .name = "suggest", .func = lua.wrap(dict_suggest) },
  .{ .name = "add", .func = lua.wrap(dict_add) },
  .{ .name = "add_to_session", .func = lua.wrap(dict_add_to_session) },
  .{ .name = "remove", .func = lua.wrap(dict_remove) },
  .{ .name = "remove_from_session", .func = lua.wrap(dict_remove_from_session) },
  .{ .name = "is_added", .func = lua.wrap(dict_is_added) },
  .{ .name = "is_removed", .func = lua.wrap(dict_is_removed) },
  .{ .name = "get_extra_word_characters", .func = lua.wrap(dict_get_extra_word_characters) },
  .{ .name = "is_word_character", .func = lua.wrap(dict_is_word_character) },
  .{ .name = "describe", .func = lua.wrap(dict_describe) },
};

export fn luaopen_core_enchant(vm: *lua.Lua) i32 {
  vm.newLib(&funcs);

  vm.newMetatable("core.enchant.Broker") catch unreachable;
  vm.setFuncs(&broker_methods, 0);
  vm.pushValue(-1);
  vm.setField(-2, "__index");
  vm.setField(-2, "Broker");

  vm.newMetatable("core.enchant.Dict") catch unreachable;
  vm.setFuncs(&dict_methods, 0);
  vm.pushValue(-1);
  vm.setField(-2, "__index");
  vm.setField(-2, "Dict");

  return 1;
}
