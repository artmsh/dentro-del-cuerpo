//! `util.zig` on POSIX systems: libc's stdio, whose paths are bytes and so already UTF-8.

const std = @import("std");
const paths = @import("paths.zig");

const FILE = opaque {};
extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*FILE;
extern "c" fn fwrite(ptr: [*]const u8, size: usize, n: usize, f: *FILE) usize;
extern "c" fn fread(ptr: [*]u8, size: usize, n: usize, f: *FILE) usize;
extern "c" fn fclose(f: *FILE) c_int;
extern "c" fn mkdir(path: [*:0]const u8, mode: c_uint) c_int;
extern "c" fn getenv(name: [*:0]const u8) ?[*:0]const u8;
extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(name: [*:0]const u8) c_int;
extern "c" fn mkdtemp(template: [*:0]u8) ?[*:0]u8;
extern "c" fn unlink(path: [*:0]const u8) c_int;
extern "c" fn rmdir(path: [*:0]const u8) c_int;

pub fn writeFileParts(path: [*:0]const u8, parts: []const []const u8) bool {
    const f = fopen(path, "wb") orelse return false;
    defer _ = fclose(f);
    for (parts) |bytes| {
        if (fwrite(bytes.ptr, 1, bytes.len, f) != bytes.len) return false;
    }
    return true;
}

pub fn readFile(path: [*:0]const u8, buf: []u8) ?[]u8 {
    const f = fopen(path, "rb") orelse return null;
    defer _ = fclose(f);
    const n = fread(buf.ptr, 1, buf.len, f);
    return buf[0..n];
}

pub fn makeDir(path: [*:0]const u8) void {
    _ = mkdir(path, 0o755);
}

pub fn removeFile(path: [*:0]const u8) void {
    _ = unlink(path);
}

pub fn removeDir(path: [*:0]const u8) void {
    _ = rmdir(path);
}

pub fn envIsSet(name: [*:0]const u8) bool {
    return getenv(name) != null;
}

pub fn env(name: [*:0]const u8, buf: []u8) ?[]const u8 {
    const p = getenv(name) orelse return null;
    const v = std.mem.span(p);
    if (v.len == 0 or v.len > buf.len) return null;
    @memcpy(buf[0..v.len], v);
    return buf[0..v.len];
}

/// The user's home directory.
pub fn profileRoot(buf: []u8) ?[]const u8 {
    return env("HOME", buf);
}

pub fn saveDirIn(buf: []u8, root: []const u8) ?[:0]const u8 {
    return paths.macSaveDir(buf, root);
}

pub const ScratchProfile = struct {
    home: [64:0]u8 = undefined,
    old_home: [paths.max_path:0]u8 = undefined,
    had_home: bool = false,

    /// Null if no temporary directory can be made, in which case the test is skipped.
    pub fn begin(sp: *ScratchProfile) ?void {
        const template = "/tmp/dentro-test-XXXXXX";
        @memcpy(sp.home[0..template.len], template);
        sp.home[template.len] = 0;
        const home = std.mem.span(mkdtemp(&sp.home) orelse return null);
        var bufs: [2][256]u8 = undefined;
        const lib = std.fmt.bufPrintSentinel(&bufs[0], "{s}/Library", .{home}, 0) catch return null;
        const support = std.fmt.bufPrintSentinel(&bufs[1], "{s}/Library/Application Support", .{home}, 0) catch return null;
        makeDir(lib.ptr);
        makeDir(support.ptr);
        if (getenv("HOME")) |h| {
            const old = std.mem.span(h);
            if (old.len >= sp.old_home.len) return null;
            @memcpy(sp.old_home[0..old.len], old);
            sp.old_home[old.len] = 0;
            sp.had_home = true;
        }
        _ = setenv("HOME", &sp.home, 1);
    }

    /// Restores the real profile and removes the scratch one, which holds at most the save file.
    pub fn end(sp: *ScratchProfile) void {
        if (sp.had_home) _ = setenv("HOME", &sp.old_home, 1) else _ = unsetenv("HOME");
        const home = std.mem.span(@as([*:0]const u8, &sp.home));
        var bufs: [4][256]u8 = undefined;
        const tails = [_][]const u8{
            "/Library/Application Support/" ++ paths.app_dir_name ++ "/" ++ paths.save_file_name,
            "/Library/Application Support/" ++ paths.app_dir_name,
            "/Library/Application Support",
            "/Library",
        };
        for (tails, 0..) |tail, i| {
            const p = std.fmt.bufPrintSentinel(&bufs[i], "{s}{s}", .{ home, tail }, 0) catch continue;
            if (i == 0) removeFile(p.ptr) else removeDir(p.ptr);
        }
        removeDir(&sp.home);
    }
};
