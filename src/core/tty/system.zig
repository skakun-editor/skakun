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
const builtin = @import("builtin");
const lua = @import("zlua");
const c = @cImport({
  @cInclude("string.h");
  @cInclude("sys/ioctl.h");
  @cInclude("termios.h");
  @cDefine("_XOPEN_SOURCE", {});
  @cInclude("wchar.h");
});
const curses = @cImport({
  @cInclude("curses.h");
  @cInclude("term.h");
});
const assert = std.debug.assert;
const File = std.fs.File;
const posix = std.posix;

pub var is_open = false;
pub var file: if(builtin.os.tag == .windows) struct { in: File, out: File } else File = undefined;
var reader_buf: [4096]u8 = undefined;
pub var reader: File.Reader = undefined;
// The buffer should be big enough to hold the entire screen in order to prevent
// flickering during redraws but we shouldn't care about redraws which are too
// slow anyways. The difference the buffer size makes is especially noticeable
// in xterm.
var writer_buf: [65536]u8 = undefined;
pub var writer: File.Writer = undefined;

fn open(vm: *lua.Lua) i32 {
  if(is_open) vm.raiseErrorStr("tty is already open", .{});
  // We get hold of the controlling terminal directly, because stdin and stdout
  // might have been redirected to pipes.
  if(builtin.os.tag == .windows) {
    // On Windows we have the special device files "CONIN$", "CONOUT$" and
    // "CON". "CON" combines both input from and output to the terminal, which
    // is what we want. Thanks to backwards compatibility with MS-DOS, such
    // special names are actually symbolic links into the "\\.\" directory.
    // Moreover, we wouldn't even be able to open "CON" in Zig because it calls
    // directly into the NT api, and not Win32, and doesn't handle these special
    // devices when converting DOS paths to NT paths. Thus, we are left with
    // "\\.\CON".
    //
    // Oh wait, you don't know what the difference between DOS and NT paths is?
    // Well. Thanks to backwards compatibility again (this time with
    // Windows 9x), Windows NT has evolved two different systems of paths:
    // everyday "DOS" paths from the Win32 API and internal NT kernel paths. The
    // full path translation process is very complex and very clever, but in the
    // case of "\\.\CON", its canonical NT path is "\??\CON".
    //
    // But… "canonical" isn't the best term here since "\??" is in fact,
    // a symlink to "\DosDevices", if you haven't noticed by now.
    //
    // If we take the time to dig into Windows' internals (or just stumble upon
    // an interesting article on the Internet), we'll learn that since
    // Windows 8, the console subsystem has been served by the condrv.sys
    // driver, which places its working files in the NT directory
    // "\Device\ConDrv". I hope you can already see what's going on here…
    //
    // We can open NT paths with std.os.windows.OpenFile but that's clearly
    // a verbose, internal, low-level facility that we'd certainly like to
    // avoid. Thankfully, there is a solution! Due to a programming oversight,
    // NT paths starting with the "\??" directory are directly accessible from
    // the DOS path system, and the whole NT root directory is also symlinked as
    // "GLOBALROOT" in NT "\??", and "\\?\" is a version of "\\.\" bypassing the
    // path normalization process just like "\??\", and…
    //
    // Uhh, I think I've had enough… In some cases we can also suffix the
    // special device files with a colon, but I am too scared to proceed
    // further.
    //
    // Microsoft® Windows™ is truly a wonderful piece of software.
    //
    // Reference:
    // - https://googleprojectzero.blogspot.com/2016/02/the-definitive-guide-on-win32-to-nt.html
    // - https://learn.microsoft.com/en-us/windows-hardware/drivers/kernel/introduction-to-ms-dos-device-names
    // - https://github.com/rprichard/win32-console-docs#console-handles-modern
    // - https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file
    // - https://learn.microsoft.com/en-us/sysinternals/downloads/winobj
    file.in  = std.fs.cwd().openFile("\\\\.\\CONIN$",  .{ .mode = .read_only  }) catch |err| vm.raiseErrorStr("failed to open CONIN$: %s", .{@errorName(err).ptr});
    file.out = std.fs.cwd().openFile("\\\\.\\CONOUT$", .{ .mode = .write_only }) catch |err| {
      file.in.close();
      vm.raiseErrorStr("failed to open CONOUT$: %s", .{@errorName(err).ptr});
    };
    // Yeah… uhh… it turns out CON can be opened with read or write access but not both…
    // Source: https://stackoverflow.com/questions/47534039/windows-console-handle-for-con-device#comment82036446_47534039
    reader = file.in.reader(&reader_buf);
    writer = file.out.writer(&writer_buf);
  } else {
    // Why "/dev/tty" exactly? Well, the answer is simple and well-documented
    // (unlike that other operating system):
    // - https://unix.stackexchange.com/q/60641
    // - https://tldp.org/HOWTO/Text-Terminal-HOWTO-7.html
    file = std.fs.cwd().openFile("/dev/tty", .{ .mode = .read_write }) catch |err| vm.raiseErrorStr("failed to open /dev/tty: %s", .{@errorName(err).ptr});
    reader = file.reader(&reader_buf);
    writer = file.writer(&writer_buf);
  }
  is_open = true;
  return 0;
}

fn close(_: *lua.Lua) i32 {
  if(!is_open) return 0;
  is_open = false;
  writer.interface.flush() catch {};
  if(builtin.os.tag == .windows) {
    file.in.close();
    file.out.close();
  } else {
    file.close();
  }
  return 0;
}

var original_termios: ?posix.termios = null;

fn enable_raw_mode(vm: *lua.Lua) i32 {
  if(!is_open) vm.raiseErrorStr("tty is closed", .{});
  if(original_termios != null) return 0;

  var termios = posix.tcgetattr(file.handle) catch |err| vm.raiseErrorStr("failed to get original termios: %s", .{@errorName(err).ptr});
  original_termios = termios;

  // Further reading:
  // - https://viewsourcecode.org/snaptoken/kilo/02.enteringRawMode.html
  // - man 3 cfmakeraw
  c.cfmakeraw(@ptrCast(&termios));
  termios.cc[@intFromEnum(posix.V.MIN)] = 0;
  termios.cc[@intFromEnum(posix.V.TIME)] = 0;
  posix.tcsetattr(file.handle, .FLUSH, termios) catch |err| vm.raiseErrorStr("failed to set raw termios: %s", .{@errorName(err).ptr});

  return 0;
}

fn disable_raw_mode(vm: *lua.Lua) i32 {
  if(!is_open) vm.raiseErrorStr("tty is closed", .{});
  if(original_termios) |x| {
    posix.tcsetattr(file.handle, .FLUSH, x) catch |err| vm.raiseErrorStr("%s", .{@errorName(err).ptr});
    original_termios = null;
  }
  return 0;
}

fn write(vm: *lua.Lua) i32 {
  if(!is_open) vm.raiseErrorStr("tty is closed", .{});
  for(1 .. @intCast(vm.getTop() + 1)) |arg_idx| {
    writer.interface.writeAll(vm.checkString(@intCast(arg_idx))) catch |err| vm.raiseErrorStr("%s", .{@errorName(err).ptr});
  }
  return 0;
}

fn flush(vm: *lua.Lua) i32 {
  if(!is_open) vm.raiseErrorStr("tty is closed", .{});
  writer.interface.flush() catch |err| vm.raiseErrorStr("%s", .{@errorName(err).ptr});
  return 0;
}

fn read(vm: *lua.Lua) i32 {
  if(!is_open) vm.raiseErrorStr("tty is closed", .{});
  var result: lua.Buffer = undefined;
  // A tight limit of 4KiB so as not to punish quadratic algorithms downstream.
  result.pushResultSize(reader.interface.readSliceShort(result.initSize(vm, 4096)) catch vm.raiseErrorStr("%s", .{@errorName(reader.err.?).ptr}));
  return 1;
}

fn wait_for_read(vm: *lua.Lua) i32 {
  if(!is_open) vm.raiseErrorStr("tty is closed", .{});
  const timeout = vm.optNumber(1);
  var fds = [_]posix.pollfd{.{
    .fd = (if(builtin.os.tag == .windows) file.in else file).handle,
    .events = posix.POLL.IN,
    .revents = 0,
  }};
  _ = posix.poll(&fds, @intFromFloat(1e3 * (timeout orelse -1))) catch |err| vm.raiseErrorStr("%s", .{@errorName(err).ptr});
  if(fds[0].revents == posix.POLL.IN) {
    vm.pushBoolean(true);
  } else {
    vm.pushFail();
  }
  return 1;
}

fn get_size(vm: *lua.Lua) i32 {
  if(!is_open) vm.raiseErrorStr("tty is closed", .{});
  var result: c.winsize = undefined;
  if(std.c.ioctl(if(builtin.os.tag == .windows) file.out.handle else file.handle, c.TIOCGWINSZ, &result) < 0) vm.raiseErrorStr("%s", .{c.strerror(std.c._errno().*)});
  vm.pushInteger(result.ws_col);
  vm.pushInteger(result.ws_row);
  return 2;
}

fn width_of(vm: *lua.Lua) i32 {
  var result: usize = 0;
  var iter = (std.unicode.Utf8View.init(vm.checkString(1)) catch vm.raiseErrorStr("invalid UTF-8 code", .{})).iterator();
  // Open sesame! (This was tricky to find.)
  _ = std.c.setlocale(std.c.LC.CTYPE, "");
  while(iter.nextCodepoint()) |x| {
    const addend = c.wcwidth(x);
    if(addend < 0) {
      result += 1;
    } else {
      result += @intCast(addend);
    }
  }
  vm.pushInteger(@intCast(result));
  return 1;
}

fn getflag(vm: *lua.Lua) i32 {
  const capname = vm.checkString(1);
  const term = if(vm.optString(2)) |x| x.ptr else null;

  const old = curses.cur_term;
  assert(curses.setupterm(term, 0, null) == curses.OK);
  defer {
    assert(curses.del_curterm(curses.cur_term) == curses.OK);
    _ = curses.set_curterm(old);
  }

  switch(curses.tigetflag(capname)) {
    -1 => vm.pushNil(),
    0 => vm.pushBoolean(false),
    else => vm.pushBoolean(true),
  }
  return 1;
}

fn getnum(vm: *lua.Lua) i32 {
  const capname = vm.checkString(1);
  const term = if(vm.optString(2)) |x| x.ptr else null;

  const old = curses.cur_term;
  assert(curses.setupterm(term, 0, null) == curses.OK);
  defer {
    assert(curses.del_curterm(curses.cur_term) == curses.OK);
    _ = curses.set_curterm(old);
  }

  switch(curses.tigetnum(capname)) {
    -2 => vm.pushNil(),
    -1 => vm.pushBoolean(false),
    else => |x| vm.pushInteger(x),
  }
  return 1;
}

fn getstr(vm: *lua.Lua) i32 {
  const capname = vm.checkString(1);
  const term = if(vm.optString(2)) |x| x.ptr else null;

  const old = curses.cur_term;
  assert(curses.setupterm(term, 0, null) == curses.OK);
  defer {
    assert(curses.del_curterm(curses.cur_term) == curses.OK);
    _ = curses.set_curterm(old);
  }

  const result = curses.tigetstr(capname);
  switch(@as(isize, @bitCast(@intFromPtr(result)))) {
    -1 => vm.pushNil(),
    0 => vm.pushBoolean(false),
    else => _ = vm.pushString(std.mem.span(result)),
  }
  return 1;
}

const funcs = blk: {
  @setEvalBranchQuota(100_000);
  break :blk [_]lua.FnReg{
    .{ .name = "open", .func = lua.wrap(open) },
    .{ .name = "close", .func = lua.wrap(close) },
    .{ .name = "enable_raw_mode", .func = lua.wrap(enable_raw_mode) },
    .{ .name = "disable_raw_mode", .func = lua.wrap(disable_raw_mode) },

    .{ .name = "write", .func = lua.wrap(write) },
    .{ .name = "flush", .func = lua.wrap(flush) },
    .{ .name = "read", .func = lua.wrap(read) },
    .{ .name = "wait_for_read", .func = lua.wrap(wait_for_read) },
    .{ .name = "get_size", .func = lua.wrap(get_size) },
    .{ .name = "width_of", .func = lua.wrap(width_of) },

    .{ .name = "getflag", .func = lua.wrap(getflag) },
    .{ .name = "getnum", .func = lua.wrap(getnum) },
    .{ .name = "getstr", .func = lua.wrap(getstr) },
  };
};

pub fn luaopen(vm: *lua.Lua) i32 {
  vm.newLib(&funcs);
  return 1;
}
