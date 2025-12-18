const std = @import("std");

pub fn build(b: *std.Build) void {
  const target = b.standardTargetOptions(.{});
  const optimize = b.standardOptimizeOption(.{});
  const dep_opts = .{ .target = target, .optimize = optimize };

  const exe = b.addExecutable(.{
    .name = "skak",
    .root_module = b.createModule(.{
      .root_source_file = b.path("src/main.zig"),
      .target = target,
      .optimize = optimize,
      .link_libc = true,
    }),
  });
  const zlua = b.dependency("zlua", dep_opts);
  exe.root_module.addImport("zlua", zlua.module("zlua"));
  exe.linkSystemLibrary(if(target.result.os.tag == .linux) "gio-unix-2.0" else "gio-2.0");
  exe.linkSystemLibrary("tinfo");

  const libgrapheme = b.addLibrary(.{
    .linkage = .static,
    .name = "grapheme",
    .root_module = b.createModule(.{
      .target = target,
      .optimize = optimize,
      .pic = true,
    }),
  });
  {
    const dep = b.dependency("libgrapheme", dep_opts);
    libgrapheme.addCSourceFiles(.{
      .root = dep.path("src"),
      .files = &.{"case.c", "character.c", "line.c", "sentence.c", "utf8.c", "util.c", "word.c"},
    });
    inline for(.{"case", "character", "line", "sentence", "word"}) |name| {
      const gen = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
          .target = b.graph.host,
          .link_libc = true,
        }),
      });
      gen.addCSourceFiles(.{
        .root = dep.path("gen"),
        .files = &.{std.mem.concat(b.allocator, u8, &.{name, ".c"}) catch @panic("OOM"), "util.c"},
      });
      const run = b.addRunArtifact(gen);
      run.setCwd(dep.path(""));
      run.captured_stdout = b.allocator.create(std.Build.Step.Run.Output) catch @panic("OOM");
      run.captured_stdout.?.* = .{
        .prefix = "",
        .basename = std.mem.concat(b.allocator, u8, &.{"gen/", name, ".h"}) catch @panic("OOM"),
        .generated_file = .{ .step = &run.step },
      };
      libgrapheme.addIncludePath(.{
        .generated = .{
          .file = &run.captured_stdout.?.generated_file,
          .up = 1,
        }
      });
    }
    libgrapheme.installHeadersDirectory(dep.path(""), ".", .{});
  }
  exe.linkLibrary(libgrapheme);

  var lua: ?*std.Build.Step.Compile = null; // Lazy dependencies are kinda half-baked to be honest…
  for(zlua.builder.install_tls.step.dependencies.items) |step| {
    const install_step = step.cast(std.Build.Step.InstallArtifact) orelse continue;
    if(std.mem.eql(u8, install_step.artifact.name, "lua")) {
      lua = install_step.artifact;
      break;
    }
  }

  {
    const lib = b.addLibrary(.{
      .linkage = .dynamic,
      .name = "core.enchant",
      .root_module = b.createModule(.{
        .root_source_file = b.path("src/core/enchant.zig"),
        .target = target,
        .optimize = optimize,
      }),
    });
    lib.root_module.addImport("zlua", zlua.module("zlua"));
    lib.linkSystemLibrary("enchant-2");
    b.getInstallStep().dependOn(&b.addInstallArtifact(lib, .{ .dest_sub_path = "core/enchant.so" }).step);
  }

  {
    const lib = b.addLibrary(.{
      .linkage = .dynamic,
      .name = "core.grapheme",
      .root_module = b.createModule(.{
        .root_source_file = b.path("src/core/grapheme.zig"),
        .target = target,
        .optimize = optimize,
      }),
    });
    lib.root_module.addImport("zlua", zlua.module("zlua"));
    lib.linkLibrary(libgrapheme);
    b.getInstallStep().dependOn(&b.addInstallArtifact(lib, .{ .dest_sub_path = "core/grapheme.so" }).step);
  }

  {
    const lib = b.addLibrary(.{
      .linkage = .dynamic,
      .name = "core.utils.timer",
      .root_module = b.createModule(.{
        .root_source_file = b.path("src/core/utils/timer.zig"),
        .target = target,
        .optimize = optimize,
      }),
    });
    lib.root_module.addImport("zlua", zlua.module("zlua"));
    b.getInstallStep().dependOn(&b.addInstallArtifact(lib, .{ .dest_sub_path = "core/utils/timer.so" }).step);
  }

  {
    const dep = b.dependency("lua_cjson", dep_opts);
    const lib = b.addLibrary(.{
      .linkage = .dynamic,
      .name = "cjson",
      .root_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
      }),
    });
    lib.addCSourceFiles(.{
      .root = dep.path(""),
      .files = &.{"fpconv.c", "lua_cjson.c", "strbuf.c"},
    });
    if(lua) |x| lib.linkLibrary(x);
    b.getInstallStep().dependOn(&b.addInstallArtifact(lib, .{ .dest_sub_path = "cjson.so" }).step);
  }

  {
    const dep = b.dependency("lua_gobject", dep_opts);
    const lib = b.addLibrary(.{
      .linkage = .dynamic,
      .name = "lua_gobject_core",
      .root_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
      }),
    });
    lib.addCSourceFiles(.{
      .root = dep.path("LuaGObject"),
      .files = &.{
        "buffer.c",
        "callable.c",
        "core.c",
        "gi.c",
        "marshal.c",
        "object.c",
        "record.c",
      },
    });
    lib.linkSystemLibrary("girepository-2.0");
    if(lua) |x| lib.linkLibrary(x);
    b.getInstallStep().dependOn(&b.addInstallArtifact(lib, .{ .dest_sub_path = "LuaGObject/lua_gobject_core.so" }).step);
    b.installDirectory(.{
      .source_dir = dep.path("LuaGObject"),
      .install_dir = .lib,
      .install_subdir = "LuaGObject",
      .include_extensions = &.{".lua"},
    });
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(b.addWriteFile("filename", "return '0.10.1'\n").getDirectory().path(b, "filename"), .lib, "LuaGObject/version.lua").step);
  }

  {
    const dep = b.dependency("lua_treesitter", dep_opts);
    const lib = b.addLibrary(.{
      .linkage = .dynamic,
      .name = "lua_tree_sitter",
      .root_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
      }),
    });
    lib.addCSourceFiles(.{
      .root = dep.path("src"),
      .files = &.{
        "init.c",
        "language.c",
        "node.c",
        "parser.c",
        "point.c",
        "query/capture.c",
        "query/cursor.c",
        "query/init.c",
        "query/match.c",
        "query/quantified_capture.c",
        "query/runner.c",
        "range/array.c",
        "range/init.c",
        "tree.c",
        "util.c",
      },
    });
    lib.addIncludePath(dep.path("include"));
    lib.linkLibrary(b.dependency("treesitter", dep_opts).artifact("tree-sitter"));
    if(lua) |x| lib.linkLibrary(x);
    b.getInstallStep().dependOn(&b.addInstallArtifact(lib, .{ .dest_sub_path = "lua_tree_sitter.so" }).step);
  }

  var version: []const u8 = undefined;
  if(b.option([]const u8, "version", "Application version string")) |x| {
    version = x;
  } else {
    const latest_commit = std.mem.trim(u8, b.run(&.{"git", "rev-parse", "--short", "HEAD"}), &std.ascii.whitespace);
    var git_output = std.mem.tokenizeAny(u8, b.run(&.{"git", "tag", "--sort=-v:refname"}), &std.ascii.whitespace);
    if(git_output.next()) |version_tag| {
      version = std.mem.trimLeft(u8, version_tag, "v");

      var exit_code: u8 = undefined;
      _ = b.runAllowFail(&.{"git", "diff", "--quiet", version_tag}, &exit_code, .Inherit) catch |err| if(err != error.ExitCodeFailure) {
        std.log.err("failed to git diff last version: {}", .{err});
        std.process.exit(1);
      };
      if(exit_code != 0) {
        version = std.mem.concat(b.allocator, u8, &.{version, "-dirty+", latest_commit}) catch @panic("OOM");
      }
    } else {
      version = std.mem.concat(b.allocator, u8, &.{"0.0.0+", latest_commit}) catch @panic("OOM");
    }
  }
  const options = b.addOptions();
  options.addOption([]const u8, "version", version);
  exe.root_module.addOptions("build", options);

  std.fs.deleteTreeAbsolute(b.install_path) catch unreachable;
  b.installArtifact(exe);
  b.lib_dir = "zig-out/lib/skakun";
  b.installDirectory(.{
    .source_dir = b.path("src"),
    .install_dir = .lib,
    .install_subdir = "",
    .include_extensions = &.{".lua"},
  });
  b.installDirectory(.{
    .source_dir = b.path("doc"),
    .install_dir = .{ .custom = "doc/skakun" },
    .install_subdir = "",
  });

  var run = b.addRunArtifact(exe);
  if(b.option([]const u8, "term", "The terminal to run the app in")) |term| {
    if(std.mem.eql(u8, term, "gnome-terminal")) {
      run = b.addSystemCommand(&.{"gnome-terminal", "--", "sh", "-c", "./zig-out/bin/skak \"$@\"; sh", ""});
    } else if(std.mem.eql(u8, term, "kitty")) {
      run = b.addSystemCommand(&.{"kitty", "--hold"});
      run.addArtifactArg(exe);
    } else if(std.mem.eql(u8, term, "konsole")) {
      run = b.addSystemCommand(&.{"konsole", "--hold", "-e"});
      run.addArtifactArg(exe);
    } else if(std.mem.eql(u8, term, "st")) {
      run = b.addSystemCommand(&.{"st", "-e", "sh", "-c", "./zig-out/bin/skak \"$@\"; sh", ""});
    } else if(std.mem.eql(u8, term, "xfce4-terminal")) {
      run = b.addSystemCommand(&.{"xfce4-terminal", "--hold", "-x"});
      run.addArtifactArg(exe);
    } else if(std.mem.eql(u8, term, "xterm")) {
      run = b.addSystemCommand(&.{"xterm", "-hold", "-e"});
      run.addArtifactArg(exe);
    } else {
      std.log.err("unknown terminal: {s}", .{term});
      std.process.exit(1);
    }
  }
  run.step.dependOn(b.getInstallStep());
  if(b.args) |args| {
    run.addArgs(args);
  }

  const run_step = b.step("run", "Run the app");
  run_step.dependOn(&run.step);
}
