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
extern "c" fn rename(from: [*:0]const u8, to: [*:0]const u8) c_int;
extern "c" fn link(from: [*:0]const u8, to: [*:0]const u8) c_int;
extern "c" fn fflush(f: *FILE) c_int;
extern "c" fn fileno(f: *FILE) c_int;
extern "c" fn fsync(fd: c_int) c_int;
extern "c" fn getpid() c_int;
extern "c" fn opendir(path: [*:0]const u8) ?*anyopaque;
extern "c" fn closedir(dir: *anyopaque) c_int;

pub fn writeFileParts(path: [*:0]const u8, parts: []const []const u8) bool {
    const f = fopen(path, "wb") orelse return false;
    defer _ = fclose(f);
    for (parts) |bytes| {
        if (fwrite(bytes.ptr, 1, bytes.len, f) != bytes.len) return false;
    }
    return true;
}

extern "c" fn write(fd: c_int, buf: [*]const u8, n: usize) isize;

pub fn writeStdout(bytes: []const u8) void {
    var rest = bytes;
    while (rest.len > 0) {
        const n = write(1, rest.ptr, rest.len);
        if (n <= 0) return;
        rest = rest[@intCast(n)..];
    }
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

pub fn isDir(path: [*:0]const u8) bool {
    const d = opendir(path) orelse return false;
    _ = closedir(d);
    return true;
}

pub fn writeFileAtomic(path: []const u8, bytes: []const u8) bool {
    var tmp_buf: [paths.max_path + 32]u8 = undefined;
    var path_buf: [paths.max_path]u8 = undefined;
    const tmp = std.fmt.bufPrintSentinel(&tmp_buf, "{s}.{d}.tmp", .{ path, getpid() }, 0) catch return false;
    const dest = std.fmt.bufPrintSentinel(&path_buf, "{s}", .{path}, 0) catch return false;
    const f = fopen(tmp.ptr, "wb") orelse return false;
    var ok = fwrite(bytes.ptr, 1, bytes.len, f) == bytes.len;
    ok = fflush(f) == 0 and ok;
    ok = fsync(fileno(f)) == 0 and ok;
    ok = fclose(f) == 0 and ok;
    ok = ok and rename(tmp.ptr, dest.ptr) == 0;
    if (!ok) _ = unlink(tmp.ptr);
    return ok;
}

pub fn removeFile(path: [*:0]const u8) bool {
    return unlink(path) == 0;
}

pub fn removeDir(path: [*:0]const u8) bool {
    return rmdir(path) == 0;
}

pub fn linkFile(from: [*:0]const u8, to: [*:0]const u8) bool {
    return link(from, to) == 0;
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

pub const no_profile_reason = "HOME is not set, so there is nowhere to keep a save file";

/// The variable `profileRoot` reads, which a scratch profile points somewhere else.
pub const profile_var = "HOME";

pub fn setEnv(name: [*:0]const u8, value: ?[:0]const u8) bool {
    return if (value) |v| setenv(name, v.ptr, 1) == 0 else unsetenv(name) == 0;
}

/// A new, empty directory under /tmp.
pub fn makeTempDir(buf: []u8) ?[:0]const u8 {
    const template = "/tmp/dentro-test-XXXXXX";
    if (buf.len <= template.len) return null;
    @memcpy(buf[0..template.len], template);
    buf[template.len] = 0;
    const made = mkdtemp(@ptrCast(buf.ptr)) orelse return null;
    return std.mem.span(made);
}
