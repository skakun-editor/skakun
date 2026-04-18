// Skakun - A robust and hackable hex and text editor
// Copyright (C) 2024-2026 Karol "digitcrusher" Łacina
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
const Buffer = @import("core.buffer").Buffer;
const tty = @import("core.tty.system");
const assert = std.debug.assert;

const Loc = struct {
  byte: usize,
  grapheme: usize,
  line: usize,
  col: usize,
  tab_col: usize,

  fn cmp_to_byte(self: Loc, byte: usize) std.math.Order {
    return std.math.order(self.byte, byte);
  }

  fn cmp_to_grapheme(self: Loc, grapheme: usize) std.math.Order {
    return std.math.order(self.grapheme, grapheme);
  }

  fn cmp_to_line_col(self: Loc, line: usize, col: usize) std.math.Order {
    return switch(std.math.order(self.line, line)) {
      .eq => std.math.order(self.col, col),
      else => |x| x,
    };
  }

  fn cmp_to_line_tab_col(self: Loc, line: usize, tab_col: usize) std.math.Order {
    return switch(std.math.order(self.line, line)) {
      .eq => std.math.order(self.tab_col, tab_col),
      else => |x| x,
    };
  }
};

fn locate_byte(vm: *lua.Lua) !i32 {
  const byte = @max(0, vm.checkInteger(2));
  vm.remove(2);
  return locate(vm, Loc.cmp_to_byte, .{@as(usize, @intCast(byte))});
}

fn locate_grapheme(vm: *lua.Lua) !i32 {
  const grapheme = @max(0, vm.checkInteger(2));
  vm.remove(2);
  return locate(vm, Loc.cmp_to_grapheme, .{@as(usize, @intCast(grapheme))});
}

fn locate_line_col(vm: *lua.Lua) !i32 {
  const line = @max(0, vm.checkInteger(2));
  const col = @max(0, vm.checkInteger(3));
  vm.rotate(2, -2);
  vm.pop(2);
  return locate(vm, Loc.cmp_to_line_col, .{@as(usize, @intCast(line)), @as(usize, @intCast(col))});
}

fn locate_line_tab_col(vm: *lua.Lua) !i32 {
  const line = @max(0, vm.checkInteger(2));
  const tab_col = @max(0, vm.checkInteger(3));
  vm.rotate(2, -2);
  vm.pop(2);
  return locate(vm, Loc.cmp_to_line_tab_col, .{@as(usize, @intCast(line)), @as(usize, @intCast(tab_col))});
}

const LocateCtx = struct {
  curr: Loc,
  prev: Loc,
  last_global_insert: usize,
};

fn locate(vm: *lua.Lua, cmp: anytype, cmp_args: anytype) !i32 {
  var ctx: *LocateCtx = undefined;
  var ctx_is_ok = false;
  if(vm.isNoneOrNil(2)) {
    vm.setTop(1);
    ctx = vm.newUserdata(LocateCtx, 1);
    vm.setMetatableRegistry("core.doc._navigator.LocateCtx");
  } else {
    ctx = vm.checkUserdata(LocateCtx, 2, "core.doc._navigator.LocateCtx");
    ctx_is_ok = @call(.auto, cmp, .{ctx.prev} ++ cmp_args) == .lt;
  }

  if(!ctx_is_ok) {
    var is_near_enough_args: std.meta.ArgsTuple(@TypeOf(cmp)) = .{undefined} ++ cmp_args;
    vm.pushLightUserdata(&is_near_enough_args);
    vm.pushClosure(lua.wrap(struct {
      fn is_near_enough(vm2: *lua.Lua) !i32 {
        var args = (vm2.toUserdata(std.meta.ArgsTuple(@TypeOf(cmp)), lua.Lua.upvalueIndex(1)) catch unreachable).*;
        args[0] = try vm2.toAny(Loc, 1);
        vm2.pushBoolean(@call(.auto, cmp, args) == .lt);
        return 1;
      }
    }.is_near_enough), 1);
    const is_near_enough_idx = vm.getTop();

    _ = vm.getField(1, "local_cache");
    _ = vm.getField(-1, "find_last");
    vm.rotate(-2, 1);
    vm.pushValue(is_near_enough_idx);
    vm.call(.{ .args = 2, .results = 1 });
    const a = try vm.toAny(?Loc, -1);

    _ = vm.getField(1, "global_cache");
    _ = vm.getField(-1, "find_last");
    vm.rotate(-2, 1);
    vm.pushValue(is_near_enough_idx);
    vm.call(.{ .args = 2, .results = 1 });
    const b: Loc = try vm.toAny(?Loc, -1) orelse .{ .byte = 1, .grapheme = 1, .line = 1, .col = 1, .tab_col = 1 };
    if(@call(.auto, cmp, .{b} ++ cmp_args) == .gt) {
      return 0;
    }

    ctx.curr = if(a != null and a.?.byte > b.byte) a.? else b;
    ctx.prev = .{ .byte = 1, .grapheme = 1, .line = 1, .col = 1, .tab_col = 1 };
    ctx.last_global_insert = b.byte;
  }

  var curr = ctx.curr;
  var prev = ctx.prev;

  var grapheme_buf = std.array_list.Managed(u8).init(vm.allocator());
  defer grapheme_buf.deinit();

  _ = vm.getField(1, "buffer");
  _ = vm.getField(-1, "iter");
  vm.rotate(-2, 1);
  vm.pushAny(curr.byte) catch unreachable;
  vm.call(.{ .args = 2, .results = 1 });
  const iter = vm.checkUserdata(Buffer.Iterator, -1, "core.buffer.iter");

  _ = vm.getField(1, "tab_width");
  const tab_width = try vm.toNumeric(usize, -1);

  _ = vm.getGlobal("require") catch {};
  _ = vm.pushString("core.tty.system");
  vm.call(.{ .args = 1, .results = 1 });
  _ = vm.getField(-1, "width_of_ptr");
  const tty_width_of = vm.checkUserdata(tty.WidthOfFn, -1, "core.tty.system.WidthOfFn").*;

  _ = vm.getField(1, "global_cache_skip");
  const global_cache_skip = try vm.toNumeric(usize, -1);

  while(@call(.auto, cmp, .{curr} ++ cmp_args) == .lt) {
    grapheme_buf.clearRetainingCapacity();
    const grapheme = iter.next_grapheme(&grapheme_buf) catch "�" orelse break;

    std.mem.swap(Loc, &curr, &prev);
    curr.byte = prev.byte + iter.last_advance;
    curr.grapheme = prev.grapheme + 1;
    if(std.mem.eql(u8, grapheme, "\n")) {
      curr.line = prev.line + 1;
      curr.col = 1;
      curr.tab_col = 1;
    } else if(std.mem.eql(u8, grapheme, "\t")) {
      curr.line = prev.line;
      curr.col = prev.col + tab_width - (prev.col - 1) % tab_width;
      curr.tab_col = prev.tab_col + 1;
    } else {
      curr.line = prev.line;
      curr.col = prev.col + try tty_width_of(grapheme);
      curr.tab_col = prev.tab_col;
    }

    if(curr.byte - ctx.last_global_insert >= global_cache_skip) {
      _ = vm.getField(1, "global_cache");
      _ = vm.getField(-1, "insert");
      vm.rotate(-2, 1);
      vm.pushAny(curr) catch unreachable;
      vm.call(.{ .args = 2, .results = 0 });
      ctx.last_global_insert = curr.byte;
    }
  }

  _ = vm.getField(1, "local_cache");
  const local_cache_idx = vm.getTop();
  _ = vm.getField(local_cache_idx, "size");
  const old_size = vm.checkInteger(-1);
  _ = vm.getField(1, "max_local_cache_size");
  const max_local_cache_size = vm.checkInteger(-1);

  if(old_size + 1 > max_local_cache_size) {
    _ = vm.getField(local_cache_idx, "prune");
    vm.pushValue(local_cache_idx);
    _ = vm.getField(1, "local_cache_prune_probability");
    vm.call(.{ .args = 2, .results = 0 });

    _ = vm.getGlobal("require") catch {};
    _ = vm.pushString("core.stderr");
    vm.call(.{ .args = 1, .results = 1 });
    _ = vm.getField(-1, "info");
    _ = vm.pushString("core.doc._navigator");
    _ = vm.pushString("pruned ");
    vm.pushInteger(old_size);
    _ = vm.getField(local_cache_idx, "size");
    vm.arith(.sub);
    _ = vm.pushString(" nodes from local cache");
    vm.call(.{ .args = 4, .results = 0 });
  }

  _ = vm.getField(local_cache_idx, "insert");
  vm.pushValue(local_cache_idx);
  vm.pushAny(if(@call(.auto, cmp, .{curr} ++ cmp_args) == .lt) curr else prev) catch unreachable;
  vm.call(.{ .args = 2, .results = 0 });

  ctx.curr = curr;
  ctx.prev = prev;

  vm.pushAny(if(@call(.auto, cmp, .{curr} ++ cmp_args) != .gt) curr else prev) catch unreachable;
  vm.pushValue(2);
  return 2;
}

const funcs = [_]lua.FnReg{
  .{ .name = "locate_byte", .func = lua.wrap(locate_byte) },
  .{ .name = "locate_grapheme", .func = lua.wrap(locate_grapheme) },
  .{ .name = "locate_line_col", .func = lua.wrap(locate_line_col) },
  .{ .name = "locate_line_tab_col", .func = lua.wrap(locate_line_tab_col) },
};

fn luaopen(vm: *lua.Lua) i32 {
  vm.newLib(&funcs);
  vm.newMetatable("core.doc._navigator.LocateCtx") catch unreachable;
  vm.pop(1);
  return 1;
}

comptime {
  _ = lua.exportFn("core_doc__navigator", luaopen);
}
