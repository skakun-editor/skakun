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

var timer: ?std.time.Timer = null;

fn read(vm: *lua.Lua) i32 {
  vm.pushNumber(@as(f64, @floatFromInt(timer.?.read())) / 1e9);
  return 1;
}

export fn luaopen_core_utils_timer(vm: *lua.Lua) i32 {
  if(timer == null) {
    timer = @TypeOf(timer.?).start() catch unreachable;
  }
  vm.pushFunction(lua.wrap(read));
  return 1;
}
