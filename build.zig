const std = @import("std");

const app_dir = "Dentro del cuerpo.app/Contents/";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.linkSystemLibrary("objc", .{});
    for ([_][]const u8{ "AppKit", "Foundation", "QuartzCore", "Metal", "CoreGraphics", "CoreText", "CoreFoundation", "AudioToolbox", "ImageIO" }) |fw| mod.linkFramework(fw, .{});

    const exe = b.addExecutable(.{ .name = "dentro", .root_module = mod });
    b.installArtifact(exe);

    // Finder-launchable bundle with the shader source and icon it loads at runtime, sealed with an ad-hoc
    // signature so Gatekeeper sees one consistent bundle rather than a bare linker-signed binary.
    const app = b.step("app", "Assemble and sign zig-out/Dentro del cuerpo.app");
    const sign = b.addSystemCommand(&.{ "codesign", "--force", "--sign", "-", "--identifier", "game.dentro-del-cuerpo" });
    sign.addArg("zig-out/Dentro del cuerpo.app"); // assumes the default install prefix
    sign.setCwd(b.path("."));
    sign.step.dependOn(&b.addInstallFile(exe.getEmittedBin(), app_dir ++ "MacOS/dentro").step);
    sign.step.dependOn(&b.addInstallFile(b.path("res/Info.plist"), app_dir ++ "Info.plist").step);
    sign.step.dependOn(&b.addInstallFile(b.path("src/shaders/shaders.metal"), app_dir ++ "Resources/shaders/shaders.metal").step);
    sign.step.dependOn(&b.addInstallFile(b.path("res/AppIcon.icns"), app_dir ++ "Resources/AppIcon.icns").step);
    app.dependOn(&sign.step);
    b.getInstallStep().dependOn(app);

    const tests = b.addTest(.{ .root_module = mod });
    b.step("test", "Unit tests (math, meshes, game rules, scripted chapter playthrough)").dependOn(&b.addRunArtifact(tests).step);

    const run = b.addRunArtifact(exe);
    run.addPassthruArgs();
    b.step("run", "Run the game binary directly").dependOn(&run.step);
}
