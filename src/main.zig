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
const build = @import("build");
const lua = @import("zlua");
const c = @cImport({
  @cInclude("stdlib.h");
  @cInclude("time.h");
  @cInclude("unistd.h");
});
const assert = std.debug.assert;
const posix = std.posix;

var debug_allocator = std.heap.DebugAllocator(.{}).init;
const allocator = if(builtin.mode == .Debug) debug_allocator.allocator() else std.heap.smp_allocator;

var stderr_path: []const u8 = undefined;
var original_stderr: posix.fd_t = undefined;
var should_forward_stderr_on_exit = true;

var vm: *lua.Lua = undefined;

fn cleanup_stderr(_: i32) callconv(.C) void {
  if(should_forward_stderr_on_exit) {
    _ = posix.sendfile(original_stderr, posix.STDERR_FILENO, 0, 0, &.{}, &.{}, 0) catch unreachable;
  }
  posix.dup2(original_stderr, posix.STDERR_FILENO) catch unreachable;
  posix.close(original_stderr);
}

fn cleanup_stderr_with_leak_check() callconv(.C) void {
  allocator.free(stderr_path);
  _ = debug_allocator.deinit();
  cleanup_stderr(0);
}

fn cleanup_vm() callconv(.C) void {
  // The initial comments in doString's improve stack trace legibility.
  vm.loadString(
    \\-- main.zig cleanup_vm()
    \\local core = require('core')
    \\function os.exit()
    \\  error('os.exit is disabled during cleanup', 2)
    \\end
    \\for i = #core.cleanups, 1, -1 do
    \\  xpcall(core.cleanups[i], function(err)
    \\    io.stderr:write(debug.traceback(err, 2), '\n')
    \\    core.should_forward_stderr_on_exit = true
    \\  end)
    \\end
    \\return core.should_forward_stderr_on_exit
  ) catch unreachable;
  vm.call(.{ .args = 0, .results = 1 });
  should_forward_stderr_on_exit = vm.toBoolean(-1);
  vm.deinit();
}

pub fn main() !void {
  // By putting defer statements in code blocks, we ensure that they really run
  // and aren't bypassed by a call to os.exit, so that the allocator doesn't
  // spew out unnecessary memory leak warnings in cleanup.
  {
    const base_dir = try std.process.getEnvVarOwned(
      allocator,
      if(builtin.os.tag == .windows)
        "TEMP" // %TEMP%, unlike %LOCALAPPDATA%, is periodically cleaned by the system.
      else if(builtin.os.tag.isDarwin())
        "HOME"
      else
        "XDG_RUNTIME_DIR", // I'm not even sure, if this is the right place.
    );
    defer allocator.free(base_dir);

    stderr_path = try std.fmt.allocPrint(
      allocator,
      if(builtin.os.tag == .windows)
        "{s}\\Skakun\\{}.log"
      else if(builtin.os.tag.isDarwin())
        "{s}/Library/Logs/Skakun/{}.log" // I absolutely adore this.
      else
        "{s}/skakun/{}.log",
      .{base_dir, c.getpid()},
    );
    errdefer allocator.free(stderr_path);

    try std.fs.cwd().makePath(std.fs.path.dirname(stderr_path) orelse ".");
    const new_stderr = try posix.open(stderr_path, .{ .ACCMODE = .RDWR, .APPEND = true, .CREAT = true, .TRUNC = true }, std.fs.File.default_mode);
    defer posix.close(new_stderr);
    original_stderr = try posix.dup(posix.STDERR_FILENO);
    errdefer posix.close(original_stderr);
    try posix.dup2(new_stderr, posix.STDERR_FILENO);
    errdefer posix.dup2(original_stderr, posix.STDERR_FILENO) catch unreachable;

    // This innocent little log header has a double purpose of checking whether
    // our new setup works, and restoring the original if not. We wouldn't be
    // able to do that later and any attempts to write anything to stderr
    // (including errors caused by writing to stderr) would silently fail.
    try std.io.getStdErr().writer().print("Skakun {s} on {s} {s}, {s}", .{build.version, @tagName(builtin.cpu.arch), @tagName(builtin.os.tag), c.ctime(&c.time(null))});

    if(c.atexit(cleanup_stderr_with_leak_check) != 0) return error.OutOfMemory;
    // If any errors were to occur in this code block past the registration of
    // this SIGABRT handler, then both the errdefer's and the handler would be
    // executed, which is obviously undesirable.
    posix.sigaction(posix.SIG.ABRT, &.{ .handler = .{ .handler = cleanup_stderr }, .mask = posix.sigemptyset(), .flags = 0 }, null);
    // posix.sigaction(posix.SIG.ABRT, &.{ .handler = .{ .handler = cleanup_stderr }, .mask = posix.empty_sigset, .flags = 0 }, null);
  }

  vm = try .init(allocator);
  vm.openLibs();

  assert(vm.getSubtable(lua.registry_index, "_LOADED"));
  assert(!vm.getSubtable(-1, "core"));

  if(builtin.os.tag == .linux) {
    _ = vm.pushString("linux");
  } else if(builtin.os.tag == .windows) {
    _ = vm.pushString("windows");
  } else if(builtin.os.tag.isDarwin()) {
    _ = vm.pushString("macos");
  } else if(builtin.os.tag.isBSD()) {
    _ = vm.pushString("freebsd");
  } else {
    vm.pushNil();
  }
  vm.setField(-2, "platform");

  {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if(args.len >= 2 and std.mem.eql(u8, args[1], "--version")) {
      try std.io.getStdOut().writeAll(std.fmt.comptimePrint(
        \\Skakun {s}
        \\Copyright (C) 2024-2025 Karol "digitcrusher" Łacina
        \\This program comes with ABSOLUTELY NO WARRANTY.
        \\This is free software, and you are welcome to redistribute it
        \\under certain conditions; see the source for copying conditions.
        \\
      , .{build.version}));
      should_forward_stderr_on_exit = false;
      return;
    }

    vm.createTable(@intCast(args.len), 0);
    for(args, 1 ..) |arg, i| {
      _ = vm.pushString(arg);
      vm.setIndex(-2, @intCast(i));
    }
    vm.setField(-2, "args");
  }

  _ = vm.pushBoolean(should_forward_stderr_on_exit);
  vm.setField(-2, "should_forward_stderr_on_exit");

  _ = vm.pushString(stderr_path);
  vm.setField(-2, "stderr_path");

  _ = vm.pushString(build.version);
  vm.setField(-2, "version");

  {
    const exe_dir = try std.fs.selfExeDirPathAlloc(allocator);
    defer allocator.free(exe_dir);
    _ = vm.pushString(exe_dir);
    vm.setField(-2, "exe_dir");
  }

  try vm.doString(
    \\-- main.zig main() #1
    \\xpcall(
    \\  function()
    \\    local core = require('core')
    \\    core.cleanups = {}
    \\    if core.platform == 'windows' then
    \\      -- %APPDATA% differs from %LOCALAPPDATA% in that it is synced
    \\      -- across devices.
    \\      core.config_dir = os.getenv('APPDATA') .. '\\Skakun'
    \\    elseif core.platform == 'macos' then
    \\      -- There's also $HOME/Library/Preferences for Apple's proprietary
    \\      -- configuration file format ".plist".
    \\      core.config_dir = os.getenv('HOME') .. '/Library/Application Support/Skakun'
    \\    else
    \\      core.config_dir = (os.getenv('XDG_CONFIG_HOME') or os.getenv('HOME') .. '/.config') .. '/skakun'
    \\    end
    \\    package.path = core.exe_dir .. '/../lib/skakun/?/init.lua;' .. package.path
    \\    package.path = core.exe_dir .. '/../lib/skakun/?.lua;' .. package.path
    \\    package.cpath = core.exe_dir .. '/../lib/skakun/?.so;' .. package.cpath
    \\    package.path = core.config_dir .. '/?/init.lua;' .. package.path
    \\    package.path = core.config_dir .. '/?.lua;' .. package.path
    \\    package.cpath = core.config_dir .. '/?.so;' .. package.cpath
    \\
    \\    if core.platform == 'windows' then
    \\      core.cache_dir = os.getenv('LOCALAPPDATA') .. '\\Skakun\\Cache'
    \\    elseif core.platform == 'macos' then
    \\      core.cache_dir = os.getenv('HOME') .. '/Library/Caches/Skakun'
    \\    else
    \\      core.cache_dir = (os.getenv('XDG_CACHE_HOME') or os.getenv('HOME') .. '/.cache') .. '/skakun'
    \\    end
    \\  end,
    \\
    \\  function(err)
    \\    -- The depth has to be 1 here for some reason.
    \\    io.stderr:write(debug.traceback(err), '\n')
    \\    os.exit(1)
    \\  end
    \\)
  );

  vm.requireF("core.buffer", lua.wrap(@import("core/buffer.zig").luaopen), false);
  vm.requireF("core.tty.system", lua.wrap(@import("core/tty/system.zig").luaopen), false);
  if(builtin.os.tag == .linux) {
    vm.requireF("core.tty.linux.system", lua.wrap(@import("core/tty/linux/system.zig").luaopen), false);
  } else if(builtin.os.tag == .windows) {
    vm.requireF("core.tty.windows", lua.wrap(@import("core/tty/windows.zig").luaopen), false);
  } else if(builtin.os.tag.isBSD()) {
    vm.requireF("core.tty.freebsd.system", lua.wrap(@import("core/tty/freebsd/system.zig").luaopen), false);
  }

  // We let Zig modules do their cleanup after Lua's turn.
  if(c.atexit(cleanup_vm) != 0) return error.OutOfMemory;

  try vm.doString(
    \\-- main.zig main() #2
    \\local core = require('core')
    \\xpcall(require, function(err)
    \\  io.stderr:write(debug.traceback(err, 2), '\n')
    \\  core.should_forward_stderr_on_exit = true
    \\  os.exit(1)
    \\end, 'user')
  );
}
