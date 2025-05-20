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
  @cInclude("linux/input-event-codes.h");
  @cInclude("linux/kd.h");
  @cInclude("linux/keyboard.h");
  @cInclude("linux/tiocl.h");
  @cInclude("linux/vt.h");
  @cInclude("string.h");
});
const tty = @import("../system.zig");

fn ioctl(request: anytype, arg: anytype) c_int {
  return std.c.ioctl(tty.file.handle, request, arg);
}
fn strerror() [*:0]const u8 {
  return c.strerror(std.c._errno().*);
}

// Ioctl reference:
// - https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/include/uapi/linux/kd.h
// - https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/include/uapi/linux/vt.h
// - https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/include/uapi/linux/tiocl.h
//
// Ioctl parameter type reference:
// - https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/tty/vt/vt_ioctl.c
// - https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/tty/vt/keyboard.c
//
// Here is a more or less reasonable explanation of the terminology surrounding
// "virtual consoles" and "virtual terminals": https://unix.stackexchange.com/a/228052

var original_kbmode: ?c_int = null;

fn enable_raw_kbd(vm: *lua.Lua) i32 {
  if(!tty.is_open) vm.raiseErrorStr("tty is closed", .{});
  if(original_kbmode != null) return 0;
  var kbmode: c_int = undefined;
  if(ioctl(c.KDGKBMODE, &kbmode) < 0) vm.raiseErrorStr("failed to get original keyboard mode: %s", .{strerror()});
  if(ioctl(c.KDSKBMODE, c.K_MEDIUMRAW) < 0) vm.raiseErrorStr("failed to set raw keyboard mode: %s", .{strerror()});
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

// Reference: https://git.kernel.org/pub/scm/linux/kernel/git/legion/kbd.git/tree/src/libkeymap/kernel.c

fn get_keymap(vm: *lua.Lua) i32 {
  if(!tty.is_open) vm.raiseErrorStr("tty is closed", .{});
  // Unicode codepoints are deliberately turned to K_HOLE in any mode other than K_UNICODE.
  if(original_kbmode != null) vm.raiseErrorStr("raw keyboard mode is enabled", .{});

  vm.createTable(c.MAX_NR_KEYMAPS, 0);
  for(0 .. c.MAX_NR_KEYMAPS) |modifiers| {
    var intercom: c.kbentry = .{
      .kb_table = @intCast(modifiers),
      .kb_index = 0, // This has to be zero, otherwise Linux will return K_HOLE instead of K_NOSUCHMAP.
      .kb_value = undefined,
    };
    if(ioctl(c.KDGKBENT, &intercom) < 0) vm.raiseErrorStr("%s at table %d, index %d", .{strerror(), intercom.kb_table, intercom.kb_index});
    if(intercom.kb_value == c.K_NOSUCHMAP) continue;

    vm.createTable(c.NR_KEYS, 0);
    for(0 .. c.NR_KEYS) |keycode| {
      intercom.kb_index = @intCast(keycode);
      if(ioctl(c.KDGKBENT, &intercom) < 0) vm.raiseErrorStr("%s at table %d, index %d", .{strerror(), intercom.kb_table, intercom.kb_index});
      if(intercom.kb_value == c.K_HOLE) continue;
      vm.pushInteger(intercom.kb_value);
      vm.setIndex(-2, intercom.kb_index);
    }
    vm.setIndex(-2, intercom.kb_table);
  }
  return 1;
}

fn get_accentmap(vm: *lua.Lua) i32 {
  if(!tty.is_open) vm.raiseErrorStr("tty is closed", .{});

  var accentmap: c.kbdiacrsuc = undefined;
  if(ioctl(c.KDGKBDIACRUC, &accentmap) < 0) vm.raiseErrorStr("%s", .{strerror()});

  vm.newTable();
  for(0 .. accentmap.kb_cnt) |idx| {
    if(vm.getIndex(-1, accentmap.kbdiacruc[idx].diacr) != .table) {
      vm.pop(1);
      vm.newTable();
    }
    vm.pushInteger(accentmap.kbdiacruc[idx].result);
    vm.setIndex(-2, accentmap.kbdiacruc[idx].base);
    vm.setIndex(-2, accentmap.kbdiacruc[idx].diacr);
  }
  return 1;
}

fn set_kbd_locks(vm: *lua.Lua) i32 {
  if(!tty.is_open) vm.raiseErrorStr("tty is closed", .{});
  var state: c_ulong = 0;
  if(vm.toBoolean(1)) state |= c.LED_CAP;
  if(vm.toBoolean(2)) state |= c.LED_NUM;
  if(vm.toBoolean(3)) state |= c.LED_SCR;
  // KDSKBLED has more semantic meaning than KDSETLED.
  if(ioctl(c.KDSKBLED, state) < 0) vm.raiseErrorStr("%s", .{strerror()});
  return 0;
}

fn get_kbd_locks(vm: *lua.Lua) i32 {
  if(!tty.is_open) vm.raiseErrorStr("tty is closed", .{});
  var state: c_char = undefined;
  // KDGKBLED has more semantic meaning than KDGETLED.
  if(ioctl(c.KDGKBLED, &state) < 0) vm.raiseErrorStr("%s", .{strerror()});
  vm.pushBoolean(state & c.LED_CAP != 0);
  vm.pushBoolean(state & c.LED_NUM != 0);
  vm.pushBoolean(state & c.LED_SCR != 0);
  return 3;
}

fn set_active_vc(vm: *lua.Lua) i32 {
  if(!tty.is_open) vm.raiseErrorStr("tty is closed", .{});
  if(ioctl(c.VT_ACTIVATE, vm.checkInteger(1)) < 0) vm.raiseErrorStr("%s", .{strerror()});
  return 0;
}

fn get_active_vc(vm: *lua.Lua) i32 {
  if(!tty.is_open) vm.raiseErrorStr("tty is closed", .{});
  const linux_is_wack: c_char = c.TIOCL_GETFGCONSOLE;
  const result = ioctl(std.os.linux.T.IOCLINUX, &linux_is_wack);
  if(result < 0) vm.raiseErrorStr("%s", .{strerror()});
  vm.pushInteger(result + 1);
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
    .{c.KEY_SYSRQ, "print_screen"},
    .{c.KEY_SCROLLLOCK, "scroll_lock"},
    .{c.KEY_PAUSE, "pause"},

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
    .{c.KEY_LEFTMETA, "left_super"},
    .{c.KEY_LEFTALT, "left_alt"},
    .{c.KEY_SPACE, "space"},
    .{c.KEY_RIGHTALT, "right_alt"},
    .{c.KEY_RIGHTMETA, "right_super"},
    .{c.KEY_COMPOSE, "menu"},
    .{c.KEY_RIGHTCTRL, "right_ctrl"},

    .{c.KEY_INSERT, "insert"},
    .{c.KEY_DELETE, "delete"},
    .{c.KEY_HOME, "home"},
    .{c.KEY_END, "end"},
    .{c.KEY_PAGEUP, "page_up"},
    .{c.KEY_PAGEDOWN, "page_down"},

    .{c.KEY_UP, "up"},
    .{c.KEY_LEFT, "left"},
    .{c.KEY_DOWN, "down"},
    .{c.KEY_RIGHT, "right"},

    .{c.KEY_NUMLOCK, "num_lock"},
    .{c.KEY_KPSLASH, "kp_divide"},
    .{c.KEY_KPASTERISK, "kp_multiply"},
    .{c.KEY_KPMINUS, "kp_subtract"},
    .{c.KEY_KPPLUS, "kp_add"},
    .{c.KEY_KPENTER, "kp_enter"},
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

  const k = [_]struct {[:0]const u8, comptime_int}{
    .{"ENTER", c.K_ENTER},
    .{"CAPS", c.K_CAPS},
    .{"NUM", c.K_NUM},
    .{"CAPSON", c.K_CAPSON},
    .{"COMPOSE", c.K_COMPOSE},
    .{"DECRCONSOLE", c.K_DECRCONSOLE},
    .{"INCRCONSOLE", c.K_INCRCONSOLE},
    .{"BARENUMLOCK", c.K_BARENUMLOCK},

    .{"P0", c.K_P0},
    .{"P1", c.K_P1},
    .{"P2", c.K_P2},
    .{"P3", c.K_P3},
    .{"P4", c.K_P4},
    .{"P5", c.K_P5},
    .{"P6", c.K_P6},
    .{"P7", c.K_P7},
    .{"P8", c.K_P8},
    .{"P9", c.K_P9},
    .{"PPLUS", c.K_PPLUS},
    .{"PMINUS", c.K_PMINUS},
    .{"PSTAR", c.K_PSTAR},
    .{"PSLASH", c.K_PSLASH},
    .{"PENTER", c.K_PENTER},
    .{"PCOMMA", c.K_PCOMMA},
    .{"PDOT", c.K_PDOT},
    .{"PPLUSMINUS", c.K_PPLUSMINUS},
    .{"PPARENL", c.K_PPARENL},
    .{"PPARENR", c.K_PPARENR},

    .{"DGRAVE", c.K_DGRAVE},
    .{"DACUTE", c.K_DACUTE},
    .{"DCIRCM", c.K_DCIRCM},
    .{"DTILDE", c.K_DTILDE},
    .{"DDIERE", c.K_DDIERE},
    .{"DCEDIL", c.K_DCEDIL},
    .{"DMACRON", c.K_DMACRON},
    .{"DBREVE", c.K_DBREVE},
    .{"DABDOT", c.K_DABDOT},
    .{"DABRING", c.K_DABRING},
    .{"DDBACUTE", c.K_DDBACUTE},
    .{"DCARON", c.K_DCARON},
    .{"DOGONEK", c.K_DOGONEK},
    .{"DIOTA", c.K_DIOTA},
    .{"DVOICED", c.K_DVOICED},
    .{"DSEMVOICED", c.K_DSEMVOICED},
    .{"DBEDOT", c.K_DBEDOT},
    .{"DHOOK", c.K_DHOOK},
    .{"DHORN", c.K_DHORN},
    .{"DSTROKE", c.K_DSTROKE},
    .{"DABCOMMA", c.K_DABCOMMA},
    .{"DABREVCOMMA", c.K_DABREVCOMMA},
    .{"DDBGRAVE", c.K_DDBGRAVE},
    .{"DINVBREVE", c.K_DINVBREVE},
    .{"DBECOMMA", c.K_DBECOMMA},
    .{"DCURRENCY", c.K_DCURRENCY},
    .{"DGREEK", c.K_DGREEK},

    .{"SHIFT", c.K_SHIFT},
    .{"CAPSSHIFT", c.K_CAPSSHIFT},

    .{"ASC0", c.K_ASC0},
    .{"ASC9", c.K_ASC9},
    .{"HEX0", c.K_HEX0},
    .{"HEXf", c.K_HEXf},
  };
  vm.createTable(k.len, 0);
  inline for(k) |entry| {
    vm.pushInteger(entry[1]);
    vm.setField(-2, entry[0]);
  }
  vm.setField(-2, "K");

  const kg = [_]struct {[:0]const u8, comptime_int}{
    .{"CTRL", c.KG_CTRL},
    .{"SHIFT", c.KG_SHIFT},
    .{"ALT", c.KG_ALT},
  };
  vm.createTable(kg.len, 0);
  inline for(kg) |entry| {
    vm.pushInteger(entry[1]);
    vm.setField(-2, entry[0]);
  }
  vm.setField(-2, "KG");

  const kt = [_]struct {[:0]const u8, comptime_int}{
    .{"LATIN", c.KT_LATIN},
    .{"SPEC", c.KT_SPEC},
    .{"PAD", c.KT_PAD},
    .{"DEAD", c.KT_DEAD},
    .{"CONS", c.KT_CONS},
    .{"SHIFT", c.KT_SHIFT},
    .{"META", c.KT_META},
    .{"ASCII", c.KT_ASCII},
    .{"LOCK", c.KT_LOCK},
    .{"LETTER", c.KT_LETTER},
    .{"SLOCK", c.KT_SLOCK},
    .{"DEAD2", c.KT_DEAD2},
  };
  vm.createTable(kt.len, 0);
  inline for(kt) |entry| {
    vm.pushInteger(entry[1]);
    vm.setField(-2, entry[0]);
  }
  vm.setField(-2, "KT");

  return 1;
}
