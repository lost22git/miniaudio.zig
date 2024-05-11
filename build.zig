const std = @import("std");
const builtin = @import("builtin");
const miniaudio_header_dir = "src/c";
const miniaudio_src_file = "src/c/miniaudio.c";
const main_file = "src/main.zig";
const test_file = "src/main.zig";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // configure and install exe
    //
    const exe = b.addExecutable(.{
        .name = "miniaudio.zig",
        .root_source_file = b.path(main_file),
        .target = target,
        .optimize = optimize,
    });
    exe.addCSourceFile(.{ .file = .{
        .path = miniaudio_src_file,
    }, .flags = &.{
        "-fno-sanitize=undefined",
    } });
    exe.addIncludePath(.{ .path = miniaudio_header_dir });
    exe.linkLibC();
    if (target.result.os.tag == .linux) {
        exe.linkSystemLibrary("pthread");
        exe.linkSystemLibrary("m");
        exe.linkSystemLibrary("dl");
    }
    b.installArtifact(exe);

    // run
    //
    {
        const run_step = b.step("run", "Run the app");
        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        run_step.dependOn(&run_cmd.step);
    }

    // tests
    //
    {
        const test_step = b.step("test", "Run unit tests");
        const unit_tests = b.addTest(.{
            .root_source_file = .{ .path = test_file },
            .target = target,
            .optimize = optimize,
        });
        const run_unit_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_unit_tests.step);
    }

    // docs
    //
    {
        const docs_step = b.step("docs", "Build the project documentation");
        // const doc_obj = b.addObject(.{
        //     .name = "docs",
        //     .root_source_file = .{ .path = main_file },
        //     .target = target,
        //     .optimize = optimize,
        // });
        // doc_obj.addCSourceFile(.{ .file = .{
        //     .path = miniaudio_src_file,
        // }, .flags = &.{
        //     "-fno-sanitize=undefined",
        // } });
        // doc_obj.addIncludePath(.{ .path = miniaudio_header_dir });
        // doc_obj.linkLibC();
        // if (target.result.os.tag == .linux) {
        //     doc_obj.linkSystemLibrary("pthread");
        //     doc_obj.linkSystemLibrary("m");
        //     doc_obj.linkSystemLibrary("dl");
        // }
        const install_docs = b.addInstallDirectory(.{
            // .source_dir = doc_obj.getEmittedDocs(),
            .source_dir = exe.getEmittedDocs(),
            .install_dir = .prefix,
            .install_subdir = "docs/",
        });
        docs_step.dependOn(&install_docs.step);
    }

    // clean
    //
    {
        const clean_step = b.step("clean", "Clean install dir and cache dir");

        const delete_install_dir = b.addRemoveDirTree(b.install_path);
        clean_step.dependOn(&delete_install_dir.step);

        if (b.cache_root.path) |cache_dir| {
            if (builtin.os.tag == .windows) {
                // Cannot work for windows
                //
            } else {
                const delete_cache_dir = b.addRemoveDirTree(cache_dir);
                clean_step.dependOn(&delete_cache_dir.step);
            }
        }
    }
}
