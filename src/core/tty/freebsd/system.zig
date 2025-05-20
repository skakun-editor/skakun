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
  @cInclude("dev/evdev/input-event-codes.h");
  @cInclude("string.h");
  @cInclude("sys/consio.h");
  @cInclude("sys/kbio.h");
});
const tty = @import("../system.zig");

fn ioctl(request: anytype, arg: anytype) c_int {
  return std.c.ioctl(tty.file.handle, request, arg);
}
fn strerror() [*:0]const u8 {
  return c.strerror(std.c._errno().*);
}

// Ioctl reference:
// - https://cgit.freebsd.org/src/tree/sys/sys/kbio.h
// - https://cgit.freebsd.org/src/tree/sys/sys/consio.h
//
// Ioctl parameter type reference: https://cgit.freebsd.org/src/tree/sys/dev/vt/vt_core.c (vtterm_ioctl)
//
// Here is a more or less reasonable explanation of the terminology surrounding
// "virtual consoles" and "virtual terminals": https://unix.stackexchange.com/a/228052

var original_kbmode: ?c_int = null;

fn enable_raw_kbd(vm: *lua.Lua) i32 {
  if(!tty.is_open) vm.raiseErrorStr("tty is closed", .{});
  if(original_kbmode != null) return 0;
  var kbmode: c_int = undefined;
  if(ioctl(c.KDGKBMODE, &kbmode) < 0) vm.raiseErrorStr("failed to get original keyboard mode: %s", .{strerror()});
  if(ioctl(c.KDSKBMODE, c.K_CODE) < 0) vm.raiseErrorStr("failed to set raw keyboard mode: %s", .{strerror()});
  original_kbmode = kbmode;
  return 0;
}

fn disable_raw_kbd(vm: *lua.Lua) i32 {
  if(!tty.is_open) vm.raiseErrorStr("tty is closed", .{});
  if(original_kbmode) |x| {
    if(ioctl(c.KDSKBMODE, x) < 0) vm.raiseErrorStr("%s", .{strerror()});
    original_kbmode = null;
  }
  return 0;
}

fn get_keymap(vm: *lua.Lua) i32 {
  if(!tty.is_open) vm.raiseErrorStr("tty is closed", .{});

  var keymap: c.keymap = undefined;
  if(ioctl(c.GIO_KEYMAP, &keymap) < 0) vm.raiseErrorStr("%s", .{strerror()});

  vm.createTable(keymap.n_keys, 0);
  for(0 .. keymap.n_keys) |keycode| {
    vm.createTable(c.NUM_STATES, 2);
    for(0 .. c.NUM_STATES) |modifiers| {
      if(keymap.key[keycode].map[modifiers] == c.NOP) continue;
      vm.pushInteger(keymap.key[keycode].map[modifiers] | if(keymap.key[keycode].spcl & @as(u8, 0x80) >> @intCast(modifiers) != 0) c.SPCLKEY else 0);
      vm.setIndex(-2, @intCast(modifiers));
    }
    vm.pushInteger(keymap.key[keycode].flgs);
    vm.setField(-2, "flags");
    vm.setIndex(-2, @intCast(keycode));
  }
  return 1;
}

fn get_accentmap(vm: *lua.Lua) i32 {
  if(!tty.is_open) vm.raiseErrorStr("tty is closed", .{});

  var accentmap: c.accentmap = undefined;
  if(ioctl(c.GIO_DEADKEYMAP, &accentmap) < 0) vm.raiseErrorStr("%s", .{strerror()});

  vm.createTable(accentmap.n_accs, 0);
  for(0 .. accentmap.n_accs) |accent| {
    vm.newTable();
    for(0 .. c.NUM_ACCENTCHARS) |codepoint| {
      if(accentmap.acc[accent].map[codepoint][0] == 0) break;
      vm.pushInteger(accentmap.acc[accent].map[codepoint][1]);
      vm.setIndex(-2, accentmap.acc[accent].map[codepoint][0]);
    }
    if(accentmap.acc[accent].accchar != 0) {
      vm.pushInteger(accentmap.acc[accent].accchar);
      vm.setIndex(-2, ' ');
    }
    vm.setIndex(-2, @intCast(accent));
  }
  return 1;
}

fn set_kbd_locks(vm: *lua.Lua) i32 {
  if(!tty.is_open) vm.raiseErrorStr("tty is closed", .{});
  if(ioctl(c.KDSKBSTATE, vm.checkInteger(1)) < 0) vm.raiseErrorStr("%s", .{strerror()});
  return 0;
}

fn get_kbd_locks(vm: *lua.Lua) i32 {
  if(!tty.is_open) vm.raiseErrorStr("tty is closed", .{});
  var result: c_int = undefined;
  if(ioctl(c.KDGKBSTATE, &result) < 0) vm.raiseErrorStr("%s", .{strerror()});
  vm.pushInteger(result);
  return 1;
}

fn set_active_vc(vm: *lua.Lua) i32 {
  if(!tty.is_open) vm.raiseErrorStr("tty is closed", .{});
  if(ioctl(c.VT_ACTIVATE, vm.checkInteger(1)) < 0) vm.raiseErrorStr("%s", .{strerror()});
  return 0;
}

fn get_active_vc(vm: *lua.Lua) i32 {
  if(!tty.is_open) vm.raiseErrorStr("tty is closed", .{});
  var result: c_int = undefined;
  // VT_GETINDEX returns the console of the file descriptor and not the active console.
  if(ioctl(c.VT_GETACTIVE, &result) < 0) vm.raiseErrorStr("%s", .{strerror()});
  vm.pushInteger(result);
  return 1;
}

const funcs = [_]lua.FnReg{
  .{ .name = "enable_raw_kbd", .func = lua.wrap(enable_raw_kbd) },
  .{ .name = "disable_raw_kbd", .func = lua.wrap(disable_raw_kbd) },
  .{ .name = "get_keymap", .func = lua.wrap(get_keymap) },
  .{ .name = "get_accentmap", .func = lua.wrap(get_accentmap) },
  .{ .name = "set_kbd_locks", .func = lua.wrap(set_kbd_locks) },
  .{ .name = "get_kbd_locks", .func = lua.wrap(get_kbd_locks) },
  .{ .name = "set_active_vc", .func = lua.wrap(set_active_vc) },
  .{ .name = "get_active_vc", .func = lua.wrap(get_active_vc) },
};

pub fn luaopen(vm: *lua.Lua) i32 {
  vm.newLib(&funcs);

  // The FreeBSD peculiarities were picked out with the help of misc/kbdscan.
  // Unfortunately, FreeBSD didn't care enough to put their keycodes in a header
  // file.
  const keycodes = [_]struct {comptime_int, []const u8}{
    .{c.KEY_ESC, "escape"},
    .{c.KEY_F1, "f1"},
    .{c.KEY_F2, "f2"},
    .{c.KEY_F3, "f3"},
    .{c.KEY_F4, "f4"},
    .{c.KEY_F5, "f5"},
    .{c.KEY_F6, "f6"},
    .{c.KEY_F7, "f7"},
    .{c.KEY_F8, "f8"},
    .{c.KEY_F9, "f9"},
    .{c.KEY_F10, "f10"},
    .{c.KEY_F11, "f11"},
    .{c.KEY_F12, "f12"},
    .{92, "print_screen"},
    .{c.KEY_SCROLLLOCK, "scroll_lock"},
    .{104, "pause"},

    .{c.KEY_GRAVE, "backtick"},
    .{c.KEY_1, "1"},
    .{c.KEY_2, "2"},
    .{c.KEY_3, "3"},
    .{c.KEY_4, "4"},
    .{c.KEY_5, "5"},
    .{c.KEY_6, "6"},
    .{c.KEY_7, "7"},
    .{c.KEY_8, "8"},
    .{c.KEY_9, "9"},
    .{c.KEY_0, "0"},
    .{c.KEY_MINUS, "minus"},
    .{c.KEY_EQUAL, "equal"},
    .{c.KEY_BACKSPACE, "backspace"},

    .{c.KEY_TAB, "tab"},
    .{c.KEY_Q, "q"},
    .{c.KEY_W, "w"},
    .{c.KEY_E, "e"},
    .{c.KEY_R, "r"},
    .{c.KEY_T, "t"},
    .{c.KEY_Y, "y"},
    .{c.KEY_U, "u"},
    .{c.KEY_I, "i"},
    .{c.KEY_O, "o"},
    .{c.KEY_P, "p"},
    .{c.KEY_LEFTBRACE, "left_bracket"},
    .{c.KEY_RIGHTBRACE, "right_bracket"},
    .{c.KEY_BACKSLASH, "backslash"},

    .{c.KEY_CAPSLOCK, "caps_lock"},
    .{c.KEY_A, "a"},
    .{c.KEY_S, "s"},
    .{c.KEY_D, "d"},
    .{c.KEY_F, "f"},
    .{c.KEY_G, "g"},
    .{c.KEY_H, "h"},
    .{c.KEY_J, "j"},
    .{c.KEY_K, "k"},
    .{c.KEY_L, "l"},
    .{c.KEY_SEMICOLON, "semicolon"},
    .{c.KEY_APOSTROPHE, "apostrophe"},
    .{c.KEY_ENTER, "enter"},

    .{c.KEY_LEFTSHIFT, "left_shift"},
    .{c.KEY_Z, "z"},
    .{c.KEY_X, "x"},
    .{c.KEY_C, "c"},
    .{c.KEY_V, "v"},
    .{c.KEY_B, "b"},
    .{c.KEY_N, "n"},
    .{c.KEY_M, "m"},
    .{c.KEY_COMMA, "comma"},
    .{c.KEY_DOT, "dot"},
    .{c.KEY_SLASH, "slash"},
    .{c.KEY_RIGHTSHIFT, "right_shift"},

    .{c.KEY_LEFTCTRL, "left_ctrl"},
    .{105, "left_super"},
    .{c.KEY_LEFTALT, "left_alt"},
    .{c.KEY_SPACE, "space"},
    .{93, "right_alt"},
    .{106, "right_super"},
    .{107, "menu"},
    .{90, "right_ctrl"},

    .{102, "insert"},
    .{103, "delete"},
    .{94, "home"},
    .{99, "end"},
    .{96, "page_up"},
    .{101, "page_down"},

    .{95, "up"},
    .{97, "left"},
    .{100, "down"},
    .{98, "right"},

    .{c.KEY_NUMLOCK, "num_lock"},
    .{91, "kp_divide"},
    .{c.KEY_KPASTERISK, "kp_multiply"},
    .{c.KEY_KPMINUS, "kp_subtract"},
    .{c.KEY_KPPLUS, "kp_add"},
    .{89, "kp_enter"},
    .{c.KEY_KP1, "kp_1"},
    .{c.KEY_KP2, "kp_2"},
    .{c.KEY_KP3, "kp_3"},
    .{c.KEY_KP4, "kp_4"},
    .{c.KEY_KP5, "kp_5"},
    .{c.KEY_KP6, "kp_6"},
    .{c.KEY_KP7, "kp_7"},
    .{c.KEY_KP8, "kp_8"},
    .{c.KEY_KP9, "kp_9"},
    .{c.KEY_KP0, "kp_0"},
    .{c.KEY_KPDOT, "kp_decimal"},
  };
  vm.createTable(keycodes.len, 0);
  inline for(keycodes) |entry| {
    _ = vm.pushString(entry[1]);
    vm.setIndex(-2, entry[0]);
  }
  vm.setField(-2, "keycodes");

  const constants = [_]struct {[:0]const u8, comptime_int}{
    .{"CLKED", c.CLKED},
    .{"NLKED", c.NLKED},
    .{"SLKED", c.SLKED},
    .{"ALKED", c.ALKED},
    .{"LOCK_MASK", c.LOCK_MASK},

    .{"ALTGR_OFFSET", c.ALTGR_OFFSET},
    .{"FLAG_LOCK_C", c.FLAG_LOCK_C},
    .{"FLAG_LOCK_N", c.FLAG_LOCK_N},

    .{"LSH", @as(u32, c.LSH) | @as(u32, c.SPCLKEY)},
    .{"RSH", @as(u32, c.RSH) | @as(u32, c.SPCLKEY)},
    .{"CLK", @as(u32, c.CLK) | @as(u32, c.SPCLKEY)},
    .{"NLK", @as(u32, c.NLK) | @as(u32, c.SPCLKEY)},
    .{"SLK", @as(u32, c.SLK) | @as(u32, c.SPCLKEY)},
    .{"LALT", @as(u32, c.LALT) | @as(u32, c.SPCLKEY)},
    .{"LCTR", @as(u32, c.LCTR) | @as(u32, c.SPCLKEY)},
    .{"NEXT", @as(u32, c.NEXT) | @as(u32, c.SPCLKEY)},
    .{"F_SCR", @as(u32, c.F_SCR) | @as(u32, c.SPCLKEY)},
    .{"L_SCR", @as(u32, c.L_SCR) | @as(u32, c.SPCLKEY)},
    .{"RCTR", @as(u32, c.RCTR) | @as(u32, c.SPCLKEY)},
    .{"RALT", @as(u32, c.RALT) | @as(u32, c.SPCLKEY)},
    .{"ALK", @as(u32, c.ALK) | @as(u32, c.SPCLKEY)},
    .{"ASH", @as(u32, c.ASH) | @as(u32, c.SPCLKEY)},
    .{"META", @as(u32, c.META) | @as(u32, c.SPCLKEY)},

    .{"F_ACC", @as(u32, c.F_ACC) | @as(u32, c.SPCLKEY)},
    .{"L_ACC", @as(u32, c.L_ACC) | @as(u32, c.SPCLKEY)},

    .{"PREV", @as(u32, c.PREV) | @as(u32, c.SPCLKEY)},
    .{"LSHA", @as(u32, c.LSHA) | @as(u32, c.SPCLKEY)},
    .{"RSHA", @as(u32, c.RSHA) | @as(u32, c.SPCLKEY)},
    .{"LCTRA", @as(u32, c.LCTRA) | @as(u32, c.SPCLKEY)},
    .{"RCTRA", @as(u32, c.RCTRA) | @as(u32, c.SPCLKEY)},
    .{"LALTA", @as(u32, c.LALTA) | @as(u32, c.SPCLKEY)},
    .{"RALTA", @as(u32, c.RALTA) | @as(u32, c.SPCLKEY)},

    .{"SPCLKEY", c.SPCLKEY},

    // Taken from https://cgit.freebsd.org/src/tree/sys/dev/kbd/kbdreg.h
    .{"SHIFTS1", 1 << 16},
    .{"SHIFTS2", 1 << 17},
    .{"SHIFTS", 1 << 16 | 1 << 17},
    .{"CTLS1", 1 << 18},
    .{"CTLS2", 1 << 19},
    .{"CTLS", 1 << 18 | 1 << 19},
    .{"ALTS1", 1 << 20},
    .{"ALTS2", 1 << 21},
    .{"ALTS", 1 << 20 | 1 << 21},
    .{"AGRS1", 1 << 22},
    .{"AGRS2", 1 << 23},
    .{"AGRS", 1 << 22 | 1 << 23},
    .{"METAS1", 1 << 24},
    .{"NLKDOWN", 1 << 26},
    .{"SLKDOWN", 1 << 27},
    .{"CLKDOWN", 1 << 28},
    .{"ALKDOWN", 1 << 29},
    .{"SHIFTAON", 1 << 30},
  };
  inline for(constants) |entry| {
    vm.pushInteger(entry[1]);
    vm.setField(-2, entry[0]);
  }

  return 1;
}
