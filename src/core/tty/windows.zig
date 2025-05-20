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
const c = @cImport({
  @cDefine("WIN32_LEAN_AND_MEAN", {});
  @cInclude("windows.h");
});

fn get_last_error() []const u8 {
  return @errorName(std.os.windows.kernel32.GetLastError());
}

fn set_clipboard(vm: *lua.Lua) i32 {
  const maybe_text = vm.optString(1);

  if(c.OpenClipboard(null) == 0) vm.raiseErrorStr("failed to open clipboard: %s", .{get_last_error()});
  defer _ = c.CloseClipboard();

  if(c.EmptyClipboard() == 0) {
    _ = c.CloseClipboard(); // defer doesn't work because of Lua's longjmp.
    vm.raiseErrorStr("failed to empty clipboard: %s", .{get_last_error()});
  }

  if(maybe_text == null) return 0;
  const text = maybe_text.?;

  // The UTF-8 encoding is always at least as long as the UTF-16 one, so we're
  // in the clear here. The memory must be allocated using GlobalAlloc with
  // GMEM_MOVEABLE as per: https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setclipboarddata
  const copy_len = text.len + 1 + std.mem.count(u8, text, "\n");
  const copy_handle = c.GlobalAlloc(c.GMEM_MOVEABLE, 2 * copy_len) orelse {
    _ = c.CloseClipboard();
    vm.raiseErrorStr("failed to allocate copy: %s", .{get_last_error()});
  };
  const copy = @as([*]u16, @alignCast(@ptrCast(c.GlobalLock(copy_handle))))[0 .. copy_len];
  var i: usize = 0;
  var j: usize = 0;
  while(i < text.len) {
    if(text[i] == '\n') {
      j += std.unicode.utf8ToUtf16Le(copy[j ..], "\r") catch unreachable;
    }
    const bytec = std.unicode.utf8ByteSequenceLength(text[i]) catch {
      _ = c.GlobalFree(copy_handle);
      _ = c.CloseClipboard();
      vm.raiseErrorStr("invalid UTF-8 code", .{});
    };
    j += std.unicode.utf8ToUtf16Le(copy[j ..], text[i .. i + bytec]) catch {
      _ = c.GlobalFree(copy_handle);
      _ = c.CloseClipboard();
      vm.raiseErrorStr("invalid UTF-8 code", .{});
    };
    i += bytec;
  }
  j += std.unicode.utf8ToUtf16Le(copy[j ..], "\x00") catch unreachable;
  _ = c.GlobalUnlock(copy_handle);

  if(c.SetClipboardData(c.CF_UNICODETEXT, copy_handle) == null) {
    _ = c.GlobalFree(copy_handle);
    _ = c.CloseClipboard();
    vm.raiseErrorStr("failed to set clipboard: %s", .{get_last_error()});
  }

  return 0;
}

const funcs = [_]lua.FnReg{
  .{ .name = "set_clipboard", .func = lua.wrap(set_clipboard) },
};

pub fn luaopen(vm: *lua.Lua) i32 {
  vm.newLib(&funcs);
  return 1;
}
