const std = @import("std");
const builtin = @import("builtin");
const miniaudio_header_dir = "src/c";
const miniaudio_src_file = "src/c/miniaudio.c";
const main_file = "src/main.zig";
const test_file = "src/main.zig";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const strip = b.option(bool, "strip", "Strip the artifacts") orelse (optimize != .Debug);

    // configure and install exe
    //
    const exe = b.addExecutable(.{
        .name = "miniaudio.zig",
        .root_source_file = b.path(main_file),
        .target = target,
        .optimize = optimize,
        .strip = strip,
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
        const install_docs = b.addInstallDirectory(.{
            .source_dir = exe.getEmittedDocs(),
            .install_dir = .prefix,
            .install_subdir = "docs/",
        });
        docs_step.dependOn(&install_docs.step);

        // docs.com (requires curl,zip)
        //
        {
            const docs_com_step = b.step("docscom", "Build docs.com (documentation http server powered by redbean.com)");

            const download_redbean = b.addSystemCommand(&.{ "curl", "-fsSLo", "docs.com", "https://redbean.dev/redbean-2.2.com", "--ssl-no-revoke" });
            download_redbean.has_side_effects = true;
            download_redbean.setCwd(.{ .path = b.install_path });
            download_redbean.expectExitCode(0);

            const zip_docs_into_redbean = b.addSystemCommand(&.{ "zip", "-r", "docs.com", "docs" });
            zip_docs_into_redbean.has_side_effects = true;
            zip_docs_into_redbean.setCwd(.{ .path = b.install_path });
            zip_docs_into_redbean.expectExitCode(0);
            zip_docs_into_redbean.step.dependOn(&download_redbean.step);

            docs_com_step.dependOn(docs_step);
            docs_com_step.dependOn(&zip_docs_into_redbean.step);
        }
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
