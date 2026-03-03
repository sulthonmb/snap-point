const std = @import("std");

// SnapPoint build script (Zig 0.15)
// Produces a macOS menu-bar agent binary with ObjC interop via zig-objc.

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // zig-objc wraps the ObjC runtime: Class, Object, sel(), AutoreleasePool
    const objc_dep = b.dependency("zig_objc", .{
        .target = target,
        .optimize = optimize,
    });
    const objc_mod = objc_dep.module("objc");

    // Main executable module
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Every source file in this module can @import("objc")
    exe_mod.addImport("objc", objc_mod);

    // Required macOS frameworks
    exe_mod.linkFramework("AppKit", .{});
    exe_mod.linkFramework("ApplicationServices", .{}); // AXUIElement
    exe_mod.linkFramework("CoreGraphics", .{}); // CGEventTap, CGDisplay
    exe_mod.linkFramework("Carbon", .{}); // reserved
    exe_mod.linkFramework("ServiceManagement", .{}); // SMAppService

    const exe = b.addExecutable(.{
        .name = "SnapPoint",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    // Run step (bare binary, no bundle – event tap won't get TCC permission)
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run SnapPoint (bare binary)");
    run_step.dependOn(&run_cmd.step);

    // Bundle step: assemble zig-out/SnapPoint.app for TCC/Accessibility testing
    //   zig build bundle        → builds binary + assembles .app
    //   open zig-out/SnapPoint.app  → macOS registers bundle ID with TCC
    const bundle_cmd = b.addSystemCommand(&.{
        "bash", "-c",
        "set -e && " ++
            "mkdir -p zig-out/SnapPoint.app/Contents/MacOS && " ++
            "mkdir -p zig-out/SnapPoint.app/Contents/Resources && " ++
            "cp zig-out/bin/SnapPoint zig-out/SnapPoint.app/Contents/MacOS/SnapPoint && " ++
            "cp resources/Info.plist  zig-out/SnapPoint.app/Contents/Info.plist && " ++
            "echo 'Bundle ready: zig-out/SnapPoint.app'",
    });
    bundle_cmd.step.dependOn(b.getInstallStep());
    const bundle_step = b.step("bundle", "Assemble SnapPoint.app bundle (needed for Accessibility TCC)");
    bundle_step.dependOn(&bundle_cmd.step);

    // Unit test step
    const test_mod = b.createModule(.{
        .root_source_file = b.path("run_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addImport("objc", objc_mod);
    test_mod.linkFramework("AppKit", .{});
    test_mod.linkFramework("ApplicationServices", .{});
    test_mod.linkFramework("CoreGraphics", .{});
    test_mod.linkFramework("Carbon", .{});
    const tests = b.addTest(.{ .root_module = test_mod });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    // Integration test step (requires macOS system interaction)
    // These tests may require Accessibility permission granted to the terminal
    const integration_mod = b.createModule(.{
        .root_source_file = b.path("tests/integration_runner.zig"),
        .target = target,
        .optimize = .Debug, // Debug mode for better error messages
    });
    integration_mod.addImport("objc", objc_mod);
    integration_mod.linkFramework("AppKit", .{});
    integration_mod.linkFramework("ApplicationServices", .{});
    integration_mod.linkFramework("CoreGraphics", .{});
    integration_mod.linkFramework("Carbon", .{});
    integration_mod.linkFramework("ServiceManagement", .{});
    const integration_tests = b.addTest(.{ .root_module = integration_mod });
    const run_integration = b.addRunArtifact(integration_tests);
    const integration_step = b.step("test-integration", "Run macOS integration tests (requires Accessibility)");
    integration_step.dependOn(&run_integration.step);

    // Test-all step: runs both unit and integration tests
    const test_all_step = b.step("test-all", "Run all tests (unit + integration)");
    test_all_step.dependOn(&run_tests.step);
    test_all_step.dependOn(&run_integration.step);
}
