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
const gio = @cImport({
  @cInclude("gio/gio.h");
  @cInclude("gio/gunixoutputstream.h");
});
const grapheme = @cImport(@cInclude("grapheme.h"));
const libc = @cImport(@cInclude("stdlib.h"));
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const posix = std.posix;

// Some methods have an optional "err_msg" parameter, which on failure, may be
// set to an error message from GIO. The caller is responsible for freeing
// err_msg with the Editor's allocator afterwards.

pub const Error = Allocator.Error || error {MultipleHardLinks, NegativeRange, OutOfBounds} || GioError || posix.OpenError || posix.ReadError || posix.MMapError || posix.RealPathError || posix.RenameError || posix.TruncateError;

threadlocal var rng: ?std.Random.DefaultPrng = null;
fn random() std.Random {
  if(rng == null) {
    rng = .init(@truncate(@as(u128, @bitCast(std.time.nanoTimestamp()))));
  }
  return rng.?.random();
}

const Fragment = struct {
  const Owner = enum {
    allocator, glib, mmap
  };
  const Mmap = struct {
    is_corrupt: bool = false,
    // A file descriptor's inode number is constant. Even then, an mmap is
    // technically bound to the inode, and not the file descriptor.
    st_dev: posix.dev_t,
    st_ino: posix.ino_t,
    file_monitor: ?*gio.GFileMonitor = null,
    data_lock: std.Thread.RwLock = .{},
    load_lock: std.Thread.Mutex = .{},
  };
  refc: std.atomic.Value(i32) = .init(0),
  owner: Owner,
  data: []u8,
  mmap: ?*Mmap = null,

  fn create(editor: *Editor, owner: Owner, data: []u8) Allocator.Error!*Fragment {
    assert(owner != .mmap);
    const self = try editor.allocator.create(Fragment);
    self.* = .{
      .owner = owner,
      .data = data,
    };
    return self;
  }

  fn create_mmap(editor: *Editor, data: []u8, st_dev: posix.dev_t, st_ino: posix.ino_t, path: [*:0]const u8, err_msg: ?*?[]u8) GioError!*Fragment {
    const mmap = try editor.allocator.create(Mmap);
    errdefer editor.allocator.destroy(mmap);
    mmap.* = .{
      .st_dev = st_dev,
      .st_ino = st_ino,
    };
    const self = try editor.allocator.create(Fragment);
    errdefer editor.allocator.destroy(self);
    self.* = .{
      .owner = .mmap,
      .data = data,
      .mmap = mmap,
    };

    const file = gio.g_file_new_for_path(path);
    defer gio.g_object_unref(file);

    gio.g_main_context_push_thread_default(editor.gio_async_ctx);
    defer gio.g_main_context_pop_thread_default(editor.gio_async_ctx);

    var err: ?*gio.GError = null;
    mmap.file_monitor = gio.g_file_monitor_file(file, gio.G_FILE_MONITOR_WATCH_HARD_LINKS, null, &err) orelse return handle_gio_error(err.?, editor.allocator, err_msg);
    errdefer gio.g_object_unref(mmap.file_monitor);

    const user_data = try editor.allocator.create(GioCallbackUserData);
    errdefer editor.allocator.destroy(user_data);
    user_data.* = .{ .self = self, .editor = editor };
    _ = gio.g_signal_connect_data(mmap.file_monitor, "changed", @ptrCast(&gio_file_monitor_callback), user_data, @ptrCast(&gio_destroy_user_data), gio.G_CONNECT_DEFAULT);

    editor.lock.lock();
    defer editor.lock.unlock();
    try editor.mmaps.append(editor.allocator, mmap);

    return self;
  }

  const GioCallbackUserData = struct { self: *Fragment, editor: *Editor };
  fn gio_file_monitor_callback(file_monitor: *gio.GFileMonitor, _: *gio.GFile, _: *gio.GFile, event: gio.GFileMonitorEvent, user_data: *GioCallbackUserData) callconv(.c) void {
    // We don't have to check for deletion since the mmap keeps the file
    // contents alive.
    if(event != gio.G_FILE_MONITOR_EVENT_CHANGED) return;
    const self = user_data.self;
    const editor = user_data.editor;
    const mmap = self.mmap.?;

    if(@cmpxchgStrong(?*gio.GFileMonitor, &mmap.file_monitor, file_monitor, null, .acquire, .monotonic) != null) return;
    gio.g_object_unref(file_monitor);

    // Unfortunately, when the backing file is modified, the whole mmapped
    // range is trashed, so we can't zero out only the unloaded pages.
    // (I've tried.)
    mmap.is_corrupt = true;
    assert((posix.mmap(@alignCast(self.data.ptr), self.data.len, posix.PROT.READ, .{ .TYPE = .PRIVATE, .ANONYMOUS = true, .FIXED = true }, -1, 0) catch unreachable).ptr == self.data.ptr);
    editor.lock.lock();
    for(editor.buffers.items) |buffer| {
      buffer.needs_mmap_stats_update.store(true, .monotonic);
    }
    editor.lock.unlock();
    editor.were_mmaps_corrupted = true;
  }
  fn gio_destroy_user_data(user_data: *GioCallbackUserData, _: *gio.GClosure) callconv(.c) void {
    user_data.editor.allocator.destroy(user_data);
  }

  fn ref(self: *Fragment) *Fragment {
    _ = self.refc.fetchAdd(1, .monotonic);
    return self;
  }

  fn unref(self: *Fragment, editor: *Editor) void {
    if(self.refc.fetchSub(1, .release) != 1) return;
    _ = self.refc.load(.acquire);

    switch(self.owner) {
      .allocator => {
        editor.allocator.free(self.data);
      },
      .glib => {
        gio.g_free(self.data.ptr);
      },
      .mmap => {
        posix.munmap(@alignCast(self.data));
        if(self.mmap.?.file_monitor) |x| gio.g_object_unref(x);
        editor.lock.lock();
        _ = editor.mmaps.swapRemove(std.mem.indexOfScalar(*Mmap, editor.mmaps.items, self.mmap.?).?);
        editor.lock.unlock();
      },
    }
    if(self.mmap) |x| editor.allocator.destroy(x);
    editor.allocator.destroy(self);
  }

  fn acquire_data(self: *Fragment) []const u8 {
    if(self.owner != .mmap) {
      return self.data;
    }
    self.mmap.?.data_lock.lockShared();
    if(self.owner != .mmap) {
      @branchHint(.cold);
      self.mmap.?.data_lock.unlockShared();
    }
    return self.data;
  }

  fn release_data(self: *Fragment) void {
    if(self.owner != .mmap) return;
    self.mmap.?.data_lock.unlockShared();
  }

  fn load(self: *Fragment, editor: *Editor) Allocator.Error!void {
    if(self.owner != .mmap) return;
    const mmap = self.mmap.?;
    mmap.load_lock.lock();
    defer mmap.load_lock.unlock();

    if(self.owner != .mmap or mmap.is_corrupt) return;

    const old = self.data;
    posix.madvise(@alignCast(old.ptr), old.len, posix.MADV.SEQUENTIAL) catch {};
    const new = try editor.allocator.dupe(u8, old);

    mmap.data_lock.lock();
    self.data = new;
    self.owner = .allocator;
    mmap.data_lock.unlock();

    posix.munmap(@alignCast(old));
    if(mmap.file_monitor) |x| gio.g_object_unref(x);
    editor.lock.lock();
    _ = editor.mmaps.swapRemove(std.mem.indexOfScalar(*Mmap, editor.mmaps.items, mmap).?);
    for(editor.buffers.items) |buffer| {
      buffer.needs_mmap_stats_update.store(true, .monotonic);
    }
    editor.lock.unlock();
  }
};

const Node = struct {
  refc: std.atomic.Value(i32) = .init(0),
  is_frozen: bool = false,
  value: struct {
    frag: *Fragment,
    offset: usize,
    len: usize,

    fn acquire(self: @This()) []const u8 {
      return self.frag.acquire_data()[self.offset ..][0 .. self.len];
    }

    fn release(self: @This()) void {
      self.frag.release_data();
    }
  },

  priority: u32,
  left: ?*Node = null,
  right: ?*Node = null,
  stats: struct {
    len: usize,
    has_healthy_mmap: bool,
    has_corrupt_mmap: bool,
  },
  stats_version: std.atomic.Value(u32) = .init(0),
  stats_lock: std.Thread.Mutex = .{},

  fn create(editor: *Editor, frag: *Fragment, offset: usize, len: usize) Allocator.Error!*Node {
    assert(offset + len <= frag.data.len and len > 0);
    const self = try editor.allocator.create(Node);
    self.* = .{
      .value = .{
        .frag = frag.ref(),
        .offset = offset,
        .len = len,
      },
      .priority = random().int(@TypeOf(self.priority)),
      .stats = undefined,
    };
    self.update_stats(false);
    return self;
  }

  fn ref(self: *Node) *Node {
    _ = self.refc.fetchAdd(1, .monotonic);
    return self;
  }

  fn unref(self: *Node, editor: *Editor) void {
    if(self.refc.fetchSub(1, .release) != 1) return;
    _ = self.refc.load(.acquire);

    if(self.left) |x| {
      x.unref(editor);
    }
    if(self.right) |x| {
      x.unref(editor);
    }
    self.value.frag.unref(editor);
    editor.allocator.destroy(self);
  }

  fn thaw(self: *Node, editor: *Editor) Allocator.Error!*Node {
    if(!self.is_frozen) {
      return self;
    }
    if(self.left) |x| {
      x.is_frozen = true;
    }
    if(self.right) |x| {
      x.is_frozen = true;
    }
    const copy = try editor.allocator.create(Node);
    copy.* = .{
      .value = .{
        .frag = self.value.frag.ref(),
        .offset = self.value.offset,
        .len = self.value.len,
      },
      .priority = self.priority,
      .left = if(self.left) |x| x.ref() else null,
      .right = if(self.right) |x| x.ref() else null,
      .stats = self.stats,
    };
    return copy;
  }

  fn load(self: *Node, editor: *Editor) Allocator.Error!void {
    try self.value.frag.load(editor);
    if(self.left) |x| {
      try x.load(editor);
    }
    if(self.right) |x| {
      try x.load(editor);
    }
  }

  fn set_left(self: *Node, editor: *Editor, value: ?*Node) void {
    assert(!self.is_frozen);
    if(self.left == value) return;
    if(self.left) |x| {
      x.unref(editor);
    }
    self.left = if(value) |x| x.ref() else null;
  }

  fn set_right(self: *Node, editor: *Editor, value: ?*Node) void {
    assert(!self.is_frozen);
    if(self.right == value) return;
    if(self.right) |x| {
      x.unref(editor);
    }
    self.right = if(value) |x| x.ref() else null;
  }

  fn update_stats(self: *Node, should_recurse: bool) void {
    const version = self.stats_version.fetchAdd(1, .acquire) + 1;

    var stats = @TypeOf(self.stats){
      .len = self.value.len,
      .has_healthy_mmap = false,
      .has_corrupt_mmap = false,
    };
    if(self.value.frag.owner == .mmap) {
      if(self.value.frag.mmap.?.is_corrupt) {
        stats.has_corrupt_mmap = true;
      } else {
        stats.has_healthy_mmap = true;
      }
    }

    if(self.left) |x| {
      if(should_recurse) {
        x.update_stats(true);
      }
      stats.len += x.stats.len;
      if(x.stats.has_healthy_mmap) {
        stats.has_healthy_mmap = true;
      }
      if(x.stats.has_corrupt_mmap) {
        stats.has_corrupt_mmap = true;
      }
    }

    if(self.right) |x| {
      if(should_recurse) {
        x.update_stats(true);
      }
      stats.len += x.stats.len;
      if(x.stats.has_healthy_mmap) {
        stats.has_healthy_mmap = true;
      }
      if(x.stats.has_corrupt_mmap) {
        stats.has_corrupt_mmap = true;
      }
    }

    self.stats_lock.lock();
    if(self.stats_version.load(.monotonic) == version) {
      self.stats = stats;
    }
    self.stats_lock.unlock();
  }

  fn read(self: *Node, offset_: usize, dest: []u8) error {OutOfBounds}!usize {
    var offset = offset_;
    if(offset > self.stats.len) return error.OutOfBounds;
    if(dest.len <= 0) {
      return 0;
    }

    var readc: usize = 0;

    if(self.left) |left| {
      if(offset < left.stats.len) {
        readc += try left.read(offset, dest);
        offset = 0;
      } else {
        offset -= left.stats.len;
      }
    }

    if(offset < self.value.len) {
      const data_slice = self.value.acquire()[offset .. @min(offset + dest.len - readc, self.value.len)];
      defer self.value.release();
      @memcpy(dest[readc ..].ptr, data_slice);
      readc += data_slice.len;
      offset = 0;
    } else {
      offset -= self.value.len;
    }

    if(self.right) |right| {
      readc += try right.read(offset, dest[readc ..]);
    }

    return readc;
  }

  fn save(self: *Node, editor: *Editor, output: *gio.GOutputStream, err_msg: ?*?[]u8) GioError!void {
    if(self.left) |x| {
      try x.save(editor, output, err_msg);
    }

    {
      const data = self.value.acquire();
      defer self.value.release();
      var err: ?*gio.GError = null;
      if(gio.g_output_stream_write_all(output, data.ptr, data.len, null, null, &err) == 0) return handle_gio_error(err.?, editor.allocator, err_msg);
    }

    if(self.right) |x| {
      try x.save(editor, output, err_msg);
    }
  }

  fn merge(editor: *Editor, maybe_a: ?*Node, maybe_b: ?*Node) Allocator.Error!?*Node {
    const a = maybe_a orelse return maybe_b;
    const b = maybe_b orelse return maybe_a;
    if(a.priority >= b.priority) {
      const result = try a.thaw(editor);
      result.set_right(editor, try Node.merge(editor, a.right, b));
      result.update_stats(false);
      return result;
    } else {
      const result = try b.thaw(editor);
      result.set_left(editor, try Node.merge(editor, a, b.left));
      result.update_stats(false);
      return result;
    }
  }

  // We do this reference juggling so that a cleanly split off child doesn't get
  // garbage collected when unlinked from the parent.
  fn split_ref(self: *Node, editor: *Editor, offset_: usize) (Allocator.Error || error {OutOfBounds})!struct {?*Node, ?*Node} {
    var offset = offset_;
    if(offset == 0) {
      return .{null, self.ref()};
    }

    if(self.left) |left| {
      if(offset <= left.stats.len) {
        const b = try self.thaw(editor);
        const sub = try left.split_ref(editor, offset);
        b.set_left(editor, sub[1]);
        if(sub[1]) |x| x.unref(editor);
        b.update_stats(false);
        return .{sub[0], b.ref()};
      }
      offset -= left.stats.len;
    }

    if(offset < self.value.len) {
      const b = try Node.create(editor, self.value.frag, self.value.offset + offset, self.value.len - offset);
      b.set_right(editor, self.right);
      b.update_stats(false);
      const a = try self.thaw(editor);
      a.value.len = offset;
      a.set_right(editor, null);
      a.update_stats(false);
      return .{a.ref(), b.ref()};
    }
    offset -= self.value.len;

    if(self.right) |right| {
      if(offset < right.stats.len) {
        const a = try self.thaw(editor);
        const sub = try right.split_ref(editor, offset);
        a.set_right(editor, sub[0]);
        if(sub[0]) |x| x.unref(editor);
        a.update_stats(false);
        return .{a.ref(), sub[1]};
      }
      offset -= right.stats.len;
    }

    return if(offset == 0) .{self.ref(), null} else error.OutOfBounds;
  }
};

pub const Buffer = struct {
  editor: *Editor,
  root: ?*Node,
  needs_mmap_stats_update: std.atomic.Value(bool) = .init(false),

  pub fn create(editor: *Editor, root: ?*Node) Allocator.Error!*Buffer {
    const self = try editor.allocator.create(Buffer);
    errdefer editor.allocator.destroy(self);
    self.* = .{
      .editor = editor,
      .root = if(root) |x| x.ref() else null,
    };

    editor.lock.lock();
    defer editor.lock.unlock();
    try editor.buffers.append(editor.allocator, self);

    return self;
  }

  pub fn destroy(self: *Buffer) void {
    if(self.root) |x| {
      x.unref(self.editor);
    }
    self.editor.lock.lock();
    _ = self.editor.buffers.swapRemove(std.mem.indexOfScalar(*Buffer, self.editor.buffers.items, self).?);
    self.editor.lock.unlock();
    self.editor.allocator.destroy(self);
  }

  pub fn load(self: *Buffer) Allocator.Error!void {
    if(self.root) |x| {
      return x.load(self.editor);
    }
  }

  pub fn len(self: *Buffer) usize {
    return if(self.root) |x| x.stats.len else 0;
  }

  pub fn has_healthy_mmap(self: *Buffer) bool {
    if(self.root) |x| {
      if(self.needs_mmap_stats_update.cmpxchgStrong(true, false, .acquire, .monotonic) == null) {
        x.update_stats(true);
      }
      return x.stats.has_healthy_mmap;
    } else {
      return false;
    }
  }

  pub fn has_corrupt_mmap(self: *Buffer) bool {
    if(self.root) |x| {
      if(self.needs_mmap_stats_update.cmpxchgStrong(true, false, .acquire, .monotonic) == null) {
        x.update_stats(true);
      }
      return x.stats.has_corrupt_mmap;
    } else {
      return false;
    }
  }

  pub fn read(self: *Buffer, offset: usize, dest: []u8) error {OutOfBounds}!usize {
    if(self.root) |x| {
      return x.read(offset, dest);
    } else if(offset > 0) {
      return error.OutOfBounds;
    } else {
      return 0;
    }
  }

  pub fn iter(self: *Buffer, offset_: usize) error {OutOfBounds}!Iterator {
    var offset = offset_;
    if(offset > self.len()) return error.OutOfBounds;

    var result = Iterator{ .buffer = self };
    if(self.root == null) return result;
    result.descend(self.root.?);

    while(true) {
      const node = result.node();

      if(node.left) |x| {
        if(offset < x.stats.len) {
          result.descend(x);
          continue;
        } else {
          offset -= x.stats.len;
        }
      }

      if(offset < node.value.len) {
        result.offset_in_node = offset;
        break;
      } else {
        offset -= node.value.len;
      }

      if(node.right) |x| {
        result.descend(x);
      } else {
        result.offset_in_node = std.math.maxInt(@TypeOf(result.offset_in_node));
        break;
      }
    }

    return result;
  }

  pub const Iterator = struct {
    buffer: *Buffer,
    // With the high-end amount of RAM in today's computers, we can only store
    // at most two billion nodes. In a perfectly balanced binary tree that would
    // result in a height of around 31 - double that should be enough to account
    // for the unbalancedness of a treap.
    path_buf: [63]*Node = undefined,
    path_len: u6 = 0,
    offset_in_node: usize = 0,
    last_advance: usize = 0,

    pub fn deinit(self: *Iterator) void {
      while(self.path_len > 0) {
        _ = self.ascend();
      }
    }

    fn node(self: *Iterator) *Node {
      return self.path_buf[self.path_len - 1];
    }

    fn descend(self: *Iterator, into: *Node) void {
      self.path_buf[self.path_len] = into.ref();
      self.path_len += 1;
    }

    fn ascend(self: *Iterator) *Node {
      self.path_len -= 1;
      const result = self.path_buf[self.path_len];
      result.unref(self.buffer.editor);
      return result;
    }

    fn next_node(self: *Iterator) error {OutOfBounds}!void {
      if(self.path_len <= 0) {
        if(self.offset_in_node > 0 or self.buffer.root == null) {
          return error.OutOfBounds;
        }
        self.descend(self.buffer.root.?);
        while(self.node().left) |x| {
          self.descend(x);
        }

      } else if(self.node().right) |x| {
        self.descend(x);
        while(self.node().left) |y| {
          self.descend(y);
        }

      } else while(true) {
        const child = self.ascend();
        if(self.path_len <= 0) {
          self.offset_in_node = std.math.maxInt(@TypeOf(self.offset_in_node));
          return error.OutOfBounds;
        }
        const parent = self.node();
        if(child != parent.right) break;
      }

      self.offset_in_node = 0;
    }

    fn prev_node(self: *Iterator) error {OutOfBounds}!void {
      if(self.path_len <= 0) {
        if(self.offset_in_node <= 0 or self.buffer.root == null) {
          return error.OutOfBounds;
        }
        self.descend(self.buffer.root.?);
        while(self.node().right) |x| {
          self.descend(x);
        }

      } else if(self.node().left) |x| {
        self.descend(x);
        while(self.node().right) |y| {
          self.descend(y);
        }

      } else while(true) {
        const child = self.ascend();
        if(self.path_len <= 0) {
          self.offset_in_node = 0;
          return error.OutOfBounds;
        }
        const parent = self.node();
        if(child != parent.left) break;
      }

      self.offset_in_node = self.node().value.len;
    }

    pub fn next(self: *Iterator) ?u8 {
      if(self.path_len <= 0 or self.offset_in_node >= self.node().value.len) {
        self.next_node() catch return null;
      }
      defer self.offset_in_node += 1;
      defer self.node().value.release();
      return self.node().value.acquire()[self.offset_in_node];
    }

    pub fn prev(self: *Iterator) ?u8 {
      if(self.path_len <= 0 or self.offset_in_node <= 0) {
        self.prev_node() catch return null;
      }
      self.offset_in_node -= 1;
      defer self.node().value.release();
      return self.node().value.acquire()[self.offset_in_node];
    }

    pub fn skip(self: *Iterator, count_: usize) error {OutOfBounds}!void {
      var count = count_;
      if(self.path_len <= 0) {
        try self.next_node();
      }
      while(count > 0) {
        if(self.offset_in_node >= self.node().value.len) {
          try self.next_node();
        }
        const addend = @min(count, self.node().value.len - self.offset_in_node);
        count -= addend;
        self.offset_in_node += addend;
      }
    }

    pub fn rewind(self: *Iterator, count_: usize) error {OutOfBounds}!void {
      var count = count_;
      if(self.path_len <= 0) {
        try self.prev_node();
      }
      while(count > 0) {
        if(self.offset_in_node <= 0) {
          try self.prev_node();
        }
        const subtrahend = @min(count, self.offset_in_node);
        count -= subtrahend;
        self.offset_in_node -= subtrahend;
      }
    }

    // Deviates from Subsection "U+FFFD Substitution of Maximal Subparts",
    // Chapter 3 only in the handling of truncated overlong encodings and
    // truncated surrogate halves.
    pub fn next_codepoint(self: *Iterator) error {InvalidUtf8}!?u21 {
      var buf: [4]u8 = undefined;
      buf[0] = self.next() orelse return null;
      self.last_advance = 1;

      const bytec = std.unicode.utf8ByteSequenceLength(buf[0]) catch return error.InvalidUtf8;
      for(1 .. bytec) |i| {
        buf[i] = self.next() orelse return error.InvalidUtf8;
        if(buf[i] & 0b1100_0000 == 0b1000_0000) {
          self.last_advance += 1;
        } else {
          self.rewind(1) catch unreachable;
          return error.InvalidUtf8;
        }
      }

      return std.unicode.utf8Decode(buf[0 .. bytec]) catch {
        self.rewind(bytec - 1) catch unreachable;
        self.last_advance = 1;
        return error.InvalidUtf8;
      };
    }

    // Writing the result into a fixed-size buffer is inherently unsafe
    // because grapheme clusters can be arbitrarily long - see "Zalgo text".
    // Stops at a grapheme cluster break, or before the first UTF-8 error.
    pub fn next_grapheme(self: *Iterator, dest: *std.array_list.Managed(u8)) (Allocator.Error || error {InvalidUtf8})!?[]u8 {
      const start = dest.items.len;

      var buf: [4]u8 = undefined;
      var last_codepoint = try self.next_codepoint() orelse return null;
      try dest.appendSlice(buf[0 .. std.unicode.utf8Encode(last_codepoint, &buf) catch unreachable]);
      var last_advance = self.last_advance;
      defer self.last_advance = last_advance;

      var state: u16 = 0;
      while(true) {
        const lookahead = self.next_codepoint() catch {
          self.rewind(self.last_advance) catch unreachable;
          break;
        } orelse break;
        if(grapheme.grapheme_is_character_break(last_codepoint, lookahead, &state)) {
          self.rewind(self.last_advance) catch unreachable;
          break;
        }
        try dest.appendSlice(buf[0 .. std.unicode.utf8Encode(lookahead, &buf) catch unreachable]);
        last_codepoint = lookahead;
        last_advance += self.last_advance;
      }

      return dest.items[start ..];
    }
  };

  pub fn save(self: *Buffer, path: []const u8, err_msg: ?*?[]u8) (GioError || posix.OpenError || posix.RealPathError || posix.RenameError || posix.TruncateError || error {MultipleHardLinks})!void {
    const path_z = try self.editor.allocator.dupeZ(u8, path);
    defer self.editor.allocator.free(path_z);
    return self.save_z(path_z, err_msg);
  }

  pub fn save_z(self: *Buffer, path: [*:0]const u8, err_msg: ?*?[]u8) (GioError || posix.OpenError || posix.RealPathError || posix.RenameError || posix.TruncateError || error {MultipleHardLinks})!void {
    if(gio.g_uri_is_valid(path, gio.G_URI_FLAGS_NONE, null) != 0) {
      const file = gio.g_file_new_for_uri(path);
      defer gio.g_object_unref(file);
      var err: ?*gio.GError = null;
      const output = gio.g_file_replace(file, null, 0, gio.G_FILE_CREATE_NONE, null, &err) orelse return handle_gio_error(err.?, self.editor.allocator, err_msg);
      defer gio.g_object_unref(output);
      if(self.root) |x| {
        try x.save(self.editor, @ptrCast(output), err_msg);
      }
      if(gio.g_output_stream_close(@ptrCast(output), null, &err) == 0) return handle_gio_error(err.?, self.editor.allocator, err_msg);

    } else {
      var fd: ?posix.fd_t = null;
      defer if(fd) |x| posix.close(x);

      // This whole mess is here just to prevent us from overwriting existing
      // files mmapped by us, which would corrupt the mmaps in question. To
      // accomplish this goal of buffer integrity, we check whether the
      // destination file in question is actually mmapped, and if it is then we
      // have to move it to a temporary destination on the same drive (that's
      // what the realpath here is for) and create a new file. Oh, and by the
      // way, naively operating on paths would be prone to data races, so we
      // play with directory file descriptors instead.

      // This is morally wrong: https://insanecoding.blogspot.com/2007/11/pathmax-simply-isnt.html
      var buf: [std.fs.max_path_bytes]u8 = undefined;
      // This does return error.FileNotFound even if a symlink exists but is broken.
      const real_path = posix.realpathZ(path, &buf);

      if(real_path == error.FileNotFound) {
        fd = try posix.openZ(path, .{ .ACCMODE = .WRONLY, .CREAT = true, .EXCL = true }, std.fs.File.default_mode);

      } else {
        const dir_path = std.fs.path.dirname(try real_path) orelse return error.IsDir;
        const dir_fd = try posix.open(dir_path, .{ .ACCMODE = .RDONLY, .DIRECTORY = true }, 0);
        var should_close_dir_fd = true;
        defer if(should_close_dir_fd) posix.close(dir_fd);

        const name = std.fs.path.basename(real_path catch unreachable);
        fd = try posix.openat(dir_fd, name, .{ .ACCMODE = .WRONLY }, 0);
        const stat = try posix.fstat(fd.?);

        var is_mmap = false;
        self.editor.lock.lock();
        for(self.editor.mmaps.items) |mmap| {
          if(mmap.st_dev == stat.dev and mmap.st_ino == stat.ino) {
            is_mmap = true;
            break;
          }
        }
        self.editor.lock.unlock();

        if(is_mmap) {
          // If the destination file has multiple hard links pointing it, then
          // it would be far more sensible to write directly to it, but at the
          // same time we can't do that because it's mmapped and doing that
          // would corrupt buffers, including maybe even this very one that
          // we're trying to save.
          if(stat.nlink > 1) return error.MultipleHardLinks;

          const new_name = try std.fmt.allocPrintSentinel(self.editor.allocator, ".{s}.skak-{x:0>8}", .{name, random().int(u32)}, 0);
          try posix.renameat(dir_fd, name, dir_fd, new_name);
          {
            self.editor.lock.lock();
            defer self.editor.lock.unlock();
            try self.editor.moved_mmapped_files.append(self.editor.allocator, .{ .dir_fd = dir_fd, .name = new_name });
            should_close_dir_fd = false;
          }

          posix.close(fd.?);
          fd = null;
          fd = try posix.openat(dir_fd, name, .{ .ACCMODE = .WRONLY, .CREAT = true, .EXCL = true }, stat.mode);
        }
      }

      const output = gio.g_unix_output_stream_new(fd.?, 0);
      defer gio.g_object_unref(output);
      if(self.root) |x| {
        try x.save(self.editor, output, err_msg);
      }
      if(posix.lseek_CUR_get(fd.?)) |size| {
        try posix.ftruncate(fd.?, size);
      } else |err| if(err != error.Unseekable) return @errorCast(err);
    }
  }

  pub fn insert(self: *Buffer, offset: usize, data: []const u8) (Allocator.Error || error {OutOfBounds})!void {
    if(offset > self.len()) return error.OutOfBounds;
    if(data.len <= 0) return;

    const copied_data = try self.editor.allocator.dupe(u8, data);
    errdefer self.editor.allocator.free(copied_data);
    const frag = try Fragment.create(self.editor, .allocator, copied_data);
    errdefer frag.ref().unref(self.editor);
    const node = try Node.create(self.editor, frag, 0, data.len);
    errdefer node.ref().unref(self.editor);

    if(self.root) |root| {
      self.root = null;
      defer root.unref(self.editor);

      const a, const b = try root.split_ref(self.editor, offset);
      defer {
        if(a) |x| x.unref(self.editor);
        if(b) |x| x.unref(self.editor);
      }
      self.root = (try Node.merge(self.editor, try Node.merge(self.editor, a, node), b)).?.ref();

    } else {
      self.root = node.ref();
    }
  }

  pub fn delete(self: *Buffer, start: usize, end: usize) (Allocator.Error || error {NegativeRange, OutOfBounds})!void {
    if(start > end) return error.NegativeRange;
    if(end > self.len()) return error.OutOfBounds;
    if(start == end) return;

    const root = self.root.?;
    self.root = null;
    defer root.unref(self.editor);

    const ab, const c = try root.split_ref(self.editor, end);
    defer {
      ab.?.unref(self.editor);
      if(c) |x| x.unref(self.editor);
    }
    const a, const b = try ab.?.split_ref(self.editor, start);
    defer {
      if(a) |x| x.unref(self.editor);
      b.?.unref(self.editor);
    }
    if(try Node.merge(self.editor, a, c)) |x| {
      self.root = x.ref();
    }
  }

  pub fn copy(self: *Buffer, offset: usize, src: *Buffer, start: usize, end: usize) (Allocator.Error || error {NegativeRange, OutOfBounds})!void {
    assert(self.editor == src.editor);
    if(start > end) return error.NegativeRange;
    if(offset > self.len() or end > src.len()) return error.OutOfBounds;
    if(start == end) return;

    src.root.?.is_frozen = true;
    const ab, const c = try src.root.?.split_ref(self.editor, end);
    defer {
      ab.?.unref(self.editor);
      if(c) |x| x.unref(self.editor);
    }
    const a, const b = try ab.?.split_ref(self.editor, start);
    defer {
      if(a) |x| x.unref(self.editor);
      b.?.unref(self.editor);
    }

    if(self.root) |root| {
      self.root = null;
      defer root.unref(self.editor);

      const p, const q = try root.split_ref(self.editor, offset);
      defer {
        if(p) |x| x.unref(self.editor);
        if(q) |x| x.unref(self.editor);
      }
      self.root = (try Node.merge(self.editor, try Node.merge(self.editor, p, b), q)).?.ref();

    } else {
      self.root = b.?.ref();
    }
  }
};

pub const Editor = struct {
  allocator: Allocator,

  // This is actually a real configuration variable.
  max_open_size: usize = 100_000_000,

  lock: std.Thread.Mutex = .{},
  mmaps: std.ArrayList(*Fragment.Mmap) = .empty,
  buffers: std.ArrayList(*Buffer) = .empty,
  moved_mmapped_files: std.ArrayList(struct {
    dir_fd: posix.fd_t,
    name: [:0]u8,
  }) = .empty,

  gio_async_ctx: *gio.GMainContext,
  were_mmaps_corrupted: bool = false,

  pub fn init(allocator: Allocator) Editor {
    return .{
      .allocator = allocator,
      .gio_async_ctx = gio.g_main_context_new().?,
    };
  }

  pub fn deinit(self: *Editor) void {
    self.mmaps.deinit(self.allocator);
    for(self.buffers.items) |x| {
      x.destroy();
    }
    self.buffers.deinit(self.allocator);
    for(self.moved_mmapped_files.items) |file| {
      // Multiple fragments can refer to the same file, just how there can be
      // many file descriptors referring to one file.
      posix.unlinkatZ(file.dir_fd, file.name, 0) catch {};
      posix.close(file.dir_fd);
      self.allocator.free(file.name);
    }
    self.moved_mmapped_files.deinit(self.allocator);
    gio.g_main_context_unref(self.gio_async_ctx);
  }

  pub fn open(self: *Editor, path: []const u8, err_msg: ?*?[]u8) (GioError || posix.OpenError || posix.ReadError || posix.MMapError)!*Buffer {
    const path_z = try self.allocator.dupeZ(u8, path);
    defer self.allocator.free(path_z);
    return self.open_z(path_z, err_msg);
  }

  pub fn open_z(self: *Editor, path: [*:0]const u8, err_msg: ?*?[]u8) (GioError || posix.OpenError || posix.ReadError || posix.MMapError)!*Buffer {
    var err: ?*gio.GError = null;

    var frag: *Fragment = undefined;
    if(gio.g_uri_is_valid(path, gio.G_URI_FLAGS_NONE, null) != 0) {
      const file = gio.g_file_new_for_uri(path); // TODO: Mount admin:// locations
      defer gio.g_object_unref(file);

      var data: []u8 = undefined;
      if(gio.g_file_load_contents(file, null, @ptrCast(&data.ptr), &data.len, null, &err) == 0) return handle_gio_error(err.?, self.allocator, err_msg);
      errdefer gio.g_free(data.ptr);
      frag = try Fragment.create(self, .glib, data);

    } else {
      const fd = try posix.openZ(path, .{ .ACCMODE = .RDONLY }, 0);
      defer posix.close(fd);
      const stat = try posix.fstat(fd);

      const size: usize = @intCast(stat.size);
      if(size <= self.max_open_size) {
        var data = try self.allocator.alloc(u8, size);
        errdefer self.allocator.free(data);
        data.len = try posix.read(fd, data);
        frag = try Fragment.create(self, .allocator, data);

      } else {
        const data = try posix.mmap(null, size, posix.PROT.READ, .{ .TYPE = .PRIVATE }, fd, 0);
        errdefer posix.munmap(@alignCast(data));
        frag = try Fragment.create_mmap(self, data, stat.dev, stat.ino, path, err_msg);
      }
    }

    if(frag.data.len > 0) {
      errdefer frag.ref().unref(self);
      const root = try Node.create(self, frag, 0, frag.data.len);
      errdefer root.ref().unref(self);
      return Buffer.create(self, root);
    } else {
      frag.ref().unref(self);
      return Buffer.create(self, null);
    }
  }

  pub fn validate_mmaps(self: *Editor) bool {
    self.were_mmaps_corrupted = false;
    _ = gio.g_main_context_iteration(self.gio_async_ctx, 0);
    return !self.were_mmaps_corrupted;
  }
};

pub const GioError = error {
  AccessDenied,
  BadPathName,
  ConnectionRefused,
  ConnectionResetByPeer,
  ConnectionTimedOut,
  DbusFailure,
  DeviceBusy,
  FdQuotaExceeded,
  FileNotFound,
  FileNotMounted,
  IsDir,
  LinkQuotaExceeded,
  NameServerFailure,
  NameTooLong,
  NetworkUnreachable,
  NoDevice,
  NoSpaceLeft,
  OutOfMemory,
  TemporaryNameServerFailure,
  TlsInitializationFailed,
  Unexpected,
  UnknownHostName,
};

// We try to mimic std.http.Client's and std.fs.File's errors here. Note that
// this handles only the errors that matter to Editor.open and Buffer.save.
// Both Glib's and Zig's errors are just some reduction and renaming of the
// POSIX errors, so to obtain this mapping I just had to search for the Glib
// error in its source code and then search for the corresponding POSIX error
// in std.posix's source code.
fn handle_gio_error(err: *gio.GError, allocator: Allocator, msg: ?*?[]u8) GioError {
  defer gio.g_error_free(err);
  if(msg) |x| {
    x.* = allocator.dupe(u8, std.mem.span(err.message)) catch null;
  }
  // Normally, in C code, one would use G_DBUS_ERROR, G_IO_ERROR,
  // G_RESOLVER_ERROR and G_TLS_ERROR here, but Zig is different and we are
  // *not* allowed to do that because those are macros to function calls.
  // I mean, Zig could at least turn those forbidden macros into functions,
  // and not tell us to just go jump in the lake.
  if(err.domain == gio.g_dbus_error_quark()) {
    return switch(err.code) {
      gio.G_DBUS_ERROR_NO_MEMORY => error.OutOfMemory,
      gio.G_DBUS_ERROR_SPAWN_NO_MEMORY => error.OutOfMemory,
      else => error.DbusFailure,
    };
  } else if(err.domain == gio.g_io_error_quark()) {
    return switch(err.code) {
      gio.G_IO_ERROR_NOT_FOUND => error.FileNotFound,
      gio.G_IO_ERROR_IS_DIRECTORY => error.IsDir,
      gio.G_IO_ERROR_FILENAME_TOO_LONG => error.NameTooLong,
      gio.G_IO_ERROR_INVALID_FILENAME => error.BadPathName,
      gio.G_IO_ERROR_TOO_MANY_LINKS => error.LinkQuotaExceeded,
      gio.G_IO_ERROR_NO_SPACE => error.NoSpaceLeft,
      gio.G_IO_ERROR_PERMISSION_DENIED => error.AccessDenied,
      gio.G_IO_ERROR_NOT_MOUNTED => error.FileNotMounted,
      gio.G_IO_ERROR_TIMED_OUT => error.ConnectionTimedOut,
      gio.G_IO_ERROR_BUSY => error.DeviceBusy,
      gio.G_IO_ERROR_HOST_NOT_FOUND => error.UnknownHostName,
      gio.G_IO_ERROR_TOO_MANY_OPEN_FILES => error.FdQuotaExceeded,
      gio.G_IO_ERROR_DBUS_ERROR => error.DbusFailure,
      gio.G_IO_ERROR_HOST_UNREACHABLE => error.NetworkUnreachable,
      gio.G_IO_ERROR_NETWORK_UNREACHABLE => error.NetworkUnreachable,
      gio.G_IO_ERROR_CONNECTION_REFUSED => error.ConnectionRefused,
      gio.G_IO_ERROR_CONNECTION_CLOSED => error.ConnectionResetByPeer,
      gio.G_IO_ERROR_NO_SUCH_DEVICE => error.NoDevice,
      else => error.Unexpected,
    };
  } else if(err.domain == gio.g_resolver_error_quark()) {
    return switch(err.code) {
      gio.G_RESOLVER_ERROR_NOT_FOUND => error.UnknownHostName,
      gio.G_RESOLVER_ERROR_TEMPORARY_FAILURE => error.TemporaryNameServerFailure,
      gio.G_RESOLVER_ERROR_INTERNAL => error.NameServerFailure,
      else => error.Unexpected,
    };
  } else if(err.domain == gio.g_tls_error_quark()) {
    return error.TlsInitializationFailed;
  } else {
    return error.Unexpected;
  }
}

var default_editor: Editor = undefined;

fn raise_err(vm: *lua.Lua, err: Error, err_msg: ?[]u8) noreturn {
  // Most of these were ripped straight out of glibc.
  const zig_err = switch(err) {
    error.AccessDenied => "permission denied",
    error.AntivirusInterference => "antivirus interfered with file operations",
    error.BadPathName => "invalid path name",
    error.BrokenPipe => "broken pipe",
    error.Canceled => unreachable, // We don't use timerfd (https://github.com/ziglang/zig/pull/20311).
    error.ConnectionRefused => "connection refused",
    error.ConnectionResetByPeer => "connection reset by peer",
    error.ConnectionTimedOut => "connection timed out",
    error.DbusFailure => "dbus failure",
    error.DeviceBusy => "device or resource busy",
    error.DiskQuota => "disk quota exceeded",
    error.FdQuotaExceeded => "too many open files",
    error.FileBusy => "device or resource busy",
    error.FileLocksNotSupported => unreachable, // We don't use O_TMPFILE.
    error.FileNotFound => "no such file or directory",
    error.FileNotMounted => "file not mounted",
    error.FileSystem => unreachable, // Never actually generated with libc - from posix.realPath in Buffer.save
    error.FileTooBig => "file too large",
    error.InputOutput => "input/output error",
    error.InvalidUtf8 => "invalid UTF-8 code",
    error.InvalidWtf8 => "invalid WTF-8 code",
    error.IsDir => "is a directory",
    error.LinkQuotaExceeded => "too many links",
    error.LockedMemoryLimitExceeded => unreachable, // We don't use MAP_LOCKED.
    error.LockViolation => "file locked by another process",
    error.MappingAlreadyExists => unreachable, // We don't use MAP_FIXED_NOREPLACE.
    error.MemoryMappingNotSupported => "mmap not supported",
    error.MultipleHardLinks => "file has multiple hard links",
    error.NameServerFailure => "unknown failure in name resolution",
    error.NameTooLong => "file name too long",
    error.NegativeRange => "negative range",
    error.NetworkNotFound => "no such file or directory on network",
    error.NetworkUnreachable => "network is unreachable",
    error.NoDevice => "no such device",
    error.NoSpaceLeft => "no space left on device",
    error.NotDir => "not a directory",
    error.NotOpenForReading => unreachable, // from posix.read in Editor.open
    error.NonResizable => "file not resizable",
    error.NotSupported => "operation not supported",
    error.OperationAborted => unreachable, // Never actually generated.
    error.OutOfBounds => "index out of bounds",
    error.OutOfMemory => "cannot allocate memory",
    error.PathAlreadyExists => unreachable, // Always a race condition - from posix.open in Buffer.save
    error.PermissionDenied => unreachable, // We don't use PROT_EXEC.
    error.PipeBusy => "all pipe instances are busy",
    error.ProcessFdQuotaExceeded => "too many open files",
    error.ProcessNotFound => unreachable, // We don't access the /proc filesystem (https://github.com/ziglang/zig/pull/21430).
    error.ReadOnlyFileSystem => "read-only file system",
    error.RenameAcrossMountPoints => unreachable, // from posix.rename in Buffer.save
    error.SharingViolation => unreachable, // Never actually generated.
    error.SocketNotConnected => unreachable, // from posix.read in Editor.open
    error.SymLinkLoop => "too many levels of symbolic links",
    error.SystemFdQuotaExceeded => "too many open files in system",
    error.SystemResources => "cannot allocate memory",
    error.TemporaryNameServerFailure => "temporary failure in name resolution",
    error.TlsInitializationFailed => "tls initialization failed",
    error.Unexpected => "unexpected error",
    error.UnknownHostName => "name or service not known",
    error.UnrecognizedVolume => "unrecognized volume file system",
    error.WouldBlock => unreachable, // We don't use O_NONBLOCK.
  };
  if(err_msg) |x| {
    vm.raiseErrorStr("%s (%s)", .{x.ptr, zig_err.ptr});
  } else {
    vm.raiseErrorStr("%s", .{zig_err.ptr});
  }
}

fn buffer_new(vm: *lua.Lua) i32 {
  vm.newUserdata(*Buffer, 0).* = Buffer.create(&default_editor, null) catch |err| raise_err(vm, err, null);
  vm.setMetatableRegistry("core.buffer");
  return 1;
}

fn buffer_open(vm: *lua.Lua) i32 {
  const path = vm.checkString(1);

  assert(vm.getSubtable(lua.registry_index, "_LOADED"));
  assert(vm.getSubtable(-1, "core.buffer"));
  _ = vm.getField(-1, "max_open_size");
  default_editor.max_open_size = @intCast(@max(vm.checkInteger(-1), 0));
  vm.pop(3);

  var err_msg: ?[]u8 = null;
  vm.newUserdata(*Buffer, 0).* = default_editor.open_z(path, &err_msg) catch |err| raise_err(vm, err, err_msg);
  vm.setMetatableRegistry("core.buffer");
  return 1;
}

fn buffer_gc(vm: *lua.Lua) i32 {
  vm.checkUserdata(*Buffer, 1, "core.buffer").*.destroy();
  return 0;
}

fn buffer_save(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*Buffer, 1, "core.buffer").*;
  const path = vm.checkString(2);
  var err_msg: ?[]u8 = null;
  self.save_z(path, &err_msg) catch |err| raise_err(vm, err, null);
  return 0;
}

fn buffer_len(vm: *lua.Lua) i32 {
  vm.pushInteger(@intCast(vm.checkUserdata(*Buffer, 1, "core.buffer").*.len()));
  return 1;
}

fn buffer_read(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*Buffer, 1, "core.buffer").*;
  const from = vm.checkInteger(2);
  const to = vm.checkInteger(3);
  if(to - from + 1 < 0) {
    raise_err(vm, error.NegativeRange, null);
  } else if(from < 1 or to > self.len()) {
    raise_err(vm, error.OutOfBounds, null);
  } else if(from > to) {
    _ = vm.pushString("");
    return 1;
  }
  var result: lua.Buffer = undefined;
  const readc = self.read(@bitCast(from - 1), result.initSize(vm, @intCast(to - from + 1))) catch |err| raise_err(vm, err, null);
  assert(readc == to - from + 1);
  result.pushResultSize(readc);
  return 1;
}

fn buffer_iter(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*Buffer, 1, "core.buffer").*;
  const from = vm.optInteger(2) orelse 1;
  vm.newUserdata(Buffer.Iterator, 0).* = self.iter(@bitCast(from - 1)) catch |err| raise_err(vm, err, null);
  vm.setMetatableRegistry("core.buffer.iter");
  return 1;
}

fn buffer_insert(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*Buffer, 1, "core.buffer").*;
  const idx = vm.checkInteger(2);
  const data = vm.checkString(3);
  self.insert(@bitCast(idx - 1), data) catch |err| raise_err(vm, err, null);
  return 0;
}

fn buffer_delete(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*Buffer, 1, "core.buffer").*;
  const from = vm.checkInteger(2);
  const to = vm.checkInteger(3);
  self.delete(@bitCast(from - 1), @bitCast(to)) catch |err| raise_err(vm, err, null);
  return 0;
}

fn buffer_copy(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*Buffer, 1, "core.buffer").*;
  const idx = vm.checkInteger(2);
  const src = vm.checkUserdata(*Buffer, 3, "core.buffer").*;
  const from = vm.checkInteger(4);
  const to = vm.checkInteger(5);
  if(from < 1) {
    raise_err(vm, error.OutOfBounds, null);
  }
  self.copy(@bitCast(idx - 1), src, @bitCast(from - 1), @bitCast(to)) catch |err| raise_err(vm, err, null);
  return 0;
}

fn buffer_load(vm: *lua.Lua) i32 {
  vm.checkUserdata(*Buffer, 1, "core.buffer").*.load() catch |err| raise_err(vm, err, null);
  return 0;
}

fn buffer_has_healthy_mmap(vm: *lua.Lua) i32 {
  vm.pushBoolean(vm.checkUserdata(*Buffer, 1, "core.buffer").*.has_healthy_mmap());
  return 1;
}

fn buffer_has_corrupt_mmap(vm: *lua.Lua) i32 {
  vm.pushBoolean(vm.checkUserdata(*Buffer, 1, "core.buffer").*.has_corrupt_mmap());
  return 1;
}

fn buffer_validate_mmaps(vm: *lua.Lua) i32 {
  vm.pushBoolean(default_editor.validate_mmaps());
  return 1;
}

const buffer_methods = blk: {
  @setEvalBranchQuota(100_000);
  break :blk [_]lua.FnReg{
    .{ .name = "new", .func = lua.wrap(buffer_new) },
    .{ .name = "open", .func = lua.wrap(buffer_open) },
    .{ .name = "__gc", .func = lua.wrap(buffer_gc) },
    .{ .name = "save", .func = lua.wrap(buffer_save) },

    .{ .name = "__len", .func = lua.wrap(buffer_len) },
    .{ .name = "read", .func = lua.wrap(buffer_read) },
    .{ .name = "iter", .func = lua.wrap(buffer_iter) },

    .{ .name = "insert", .func = lua.wrap(buffer_insert) },
    .{ .name = "delete", .func = lua.wrap(buffer_delete) },
    .{ .name = "copy", .func = lua.wrap(buffer_copy) },

    .{ .name = "load", .func = lua.wrap(buffer_load) },
    .{ .name = "has_healthy_mmap", .func = lua.wrap(buffer_has_healthy_mmap) },
    .{ .name = "has_corrupt_mmap", .func = lua.wrap(buffer_has_corrupt_mmap) },
    .{ .name = "validate_mmaps", .func = lua.wrap(buffer_validate_mmaps) },
  };
};

fn iter_gc(vm: *lua.Lua) i32 {
  vm.checkUserdata(Buffer.Iterator, 1, "core.buffer.iter").deinit();
  return 0;
}

fn iter_next(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(Buffer.Iterator, 1, "core.buffer.iter");
  vm.pushAny(self.next()) catch unreachable;
  return 1;
}

fn iter_prev(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(Buffer.Iterator, 1, "core.buffer.iter");
  vm.pushAny(self.prev()) catch unreachable;
  return 1;
}

fn iter_skip(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(Buffer.Iterator, 1, "core.buffer.iter");
  const count = vm.checkInteger(2);
  if(count < 0) {
    vm.raiseErrorStr("count is negative", .{});
  }
  self.skip(@intCast(count)) catch |err| raise_err(vm, err, null);
  return 0;
}

fn iter_rewind(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(Buffer.Iterator, 1, "core.buffer.iter");
  const count = vm.checkInteger(2);
  if(count < 0) {
    vm.raiseErrorStr("count is negative", .{});
  }
  self.rewind(@intCast(count)) catch |err| raise_err(vm, err, null);
  return 0;
}

fn iter_next_codepoint(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(Buffer.Iterator, 1, "core.buffer.iter");
  vm.pushAny(self.next_codepoint() catch |err| raise_err(vm, err, null)) catch unreachable;
  return 1;
}

fn iter_next_grapheme(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(Buffer.Iterator, 1, "core.buffer.iter");

  var dest = std.array_list.Managed(u8).init(vm.allocator());
  defer dest.deinit();
  const maybe_grapheme = self.next_grapheme(&dest) catch |err| {
    dest.deinit();
    raise_err(vm, err, null);
  };

  if(maybe_grapheme) |grapheme_indeed| {
    _ = vm.pushString(grapheme_indeed);
  } else {
    vm.pushNil();
  }
  return 1;
}

fn iter_last_advance(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(Buffer.Iterator, 1, "core.buffer.iter");
  vm.pushInteger(@intCast(self.last_advance));
  return 1;
}

const iter_methods = blk: {
  @setEvalBranchQuota(100_000);
  break :blk [_]lua.FnReg{
    .{ .name = "__gc", .func = lua.wrap(iter_gc) },
    .{ .name = "next", .func = lua.wrap(iter_next) },
    .{ .name = "prev", .func = lua.wrap(iter_prev) },
    .{ .name = "skip", .func = lua.wrap(iter_skip) },
    .{ .name = "rewind", .func = lua.wrap(iter_rewind) },
    .{ .name = "next_codepoint", .func = lua.wrap(iter_next_codepoint) },
    .{ .name = "next_grapheme", .func = lua.wrap(iter_next_grapheme) },
    .{ .name = "last_advance", .func = lua.wrap(iter_last_advance) },
  };
};

fn cleanup(_: *lua.Lua) i32 {
  default_editor.deinit();
  return 0;
}

fn luaopen(vm: *lua.Lua) i32 {
  default_editor = .init(vm.allocator());

  vm.newTable();
  vm.newTable();
  vm.pushFunction(lua.wrap(cleanup));
  vm.setField(-2, "__gc");
  vm.setMetatable(-2);
  vm.pushValue(-1);
  vm.setTable(lua.registry_index);

  vm.newMetatable("core.buffer") catch unreachable;
  vm.setFuncs(&buffer_methods, 0);
  vm.pushValue(-1);
  vm.setField(-2, "__index");
  vm.pushInteger(@intCast(default_editor.max_open_size));
  vm.setField(-2, "max_open_size");

  vm.newMetatable("core.buffer.iter") catch unreachable;
  vm.setFuncs(&iter_methods, 0);
  vm.pushValue(-1);
  vm.setField(-2, "__index");
  vm.pop(1);

  return 1;
}

comptime {
  if(@This() == @import("root")) {
    _ = lua.exportFn("core_buffer", luaopen);
  }
}
