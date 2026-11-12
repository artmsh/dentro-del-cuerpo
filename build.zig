const std = @import("std");

const app_dir = "Dentro del cuerpo.app/Contents/";

pub fn build(b: *std.Build) void {
    // A native macOS build would stamp the host's OS version as the minimum and refuse to launch on anything
    // older, so the deployment target is pinned. Pinning it makes the target non-native to the build system,
    // which then no longer searches the SDK on its own; the SDK paths are added below.
    var query = b.standardTargetOptionsQueryOnly(.{});
    const host_is_mac = b.graph.host.result.os.tag == .macos;
    if (host_is_mac and (query.os_tag == null or query.os_tag == .macos) and query.os_version_min == null)
        query.os_version_min = .{ .semver = .{ .major = 14, .minor = 0, .patch = 0 } };
    const target = b.resolveTargetQuery(query);
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (host_is_mac and target.result.os.tag == .macos) {
        const sdk = std.mem.trim(u8, b.run(&.{ "xcrun", "--sdk", "macosx", "--show-sdk-path" }), " \r\n");
        mod.addSystemFrameworkPath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "System/Library/Frameworks" }) });
        mod.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "usr/lib" }) });
    }
    mod.linkSystemLibrary("objc", .{});
    for ([_][]const u8{ "AppKit", "Foundation", "QuartzCore", "Metal", "CoreGraphics", "CoreFoundation", "AudioToolbox", "ImageIO", "GameController" }) |fw| mod.linkFramework(fw, .{});

    // Text: the vendored rasteriser as one C translation unit, and the fonts it reads, embedded by name
    // because they live outside the module's source directory. UBSan is off for the C file: it is third-party
    // code whose arithmetic is not ours to audit, and a Debug build would otherwise trap inside it.
    mod.link_libc = true;
    mod.addIncludePath(b.path("vendor/stb"));
    mod.addCSourceFile(.{ .file = b.path("src/stb_truetype.c"), .flags = &.{"-fno-sanitize=undefined"} });
    inline for (.{
        .{ "font-regular", "res/fonts/NotoSans-ExtraCondensedMedium.ttf" },
        .{ "font-bold", "res/fonts/NotoSans-ExtraCondensedSemiBold.ttf" },
        .{ "font-symbols", "res/fonts/DejaVuSans.ttf" },
    }) |f| mod.addAnonymousImport(f[0], .{ .root_source_file = b.path(f[1]) });

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
    // The fonts are inside the binary; their licences ask to travel with every copy, so they go in the bundle.
    inline for (.{
        .{ "res/fonts/OFL-NotoSans.txt", "NotoSans-OFL.txt" },
        .{ "res/fonts/LICENSE-DejaVu.txt", "DejaVuSans-LICENSE.txt" },
        .{ "vendor/stb/LICENSE", "stb_truetype-LICENSE.txt" },
    }) |f| sign.step.dependOn(&b.addInstallFile(b.path(f[0]), app_dir ++ "Resources/licenses/" ++ f[1]).step);
    app.dependOn(&sign.step);
    b.getInstallStep().dependOn(app);

    const tests = b.addTest(.{ .root_module = mod });
    b.step("test", "Unit tests (math, meshes, game rules, scripted chapter playthrough)").dependOn(&b.addRunArtifact(tests).step);

    const run = b.addRunArtifact(exe);
    run.addPassthruArgs();
    b.step("run", "Run the game binary directly").dependOn(&run.step);
}
