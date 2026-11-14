//! Small file and environment helpers (screenshots, save file, logs). Paths are UTF-8 on every platform;
//! the implementation is picked at compile time, libc's stdio on POSIX systems and the wide-character
//! Win32 calls on Windows, where stdio would read a path in the legacy code page and fail on a user
//! name outside it.

const std = @import("std");
const builtin = @import("builtin");
const paths = @import("os/paths.zig");

const impl = switch (builtin.os.tag) {
    .windows => @import("os/windows_files.zig"),
    // The television is the one Linux target.
    .linux => @import("os/tv_files.zig"),
    else => @import("os/posix_files.zig"),
};

/// Write the parts one after another as the whole content of the file at `path`.
pub fn writeFileParts(path: [*:0]const u8, parts: []const []const u8) bool {
    return impl.writeFileParts(path, parts);
}

pub fn writeFile(path: [*:0]const u8, bytes: []const u8) bool {
    return impl.writeFileParts(path, &.{bytes});
}

/// Read up to `buf.len` bytes; returns the slice read or null if the file cannot be opened.
/// Write to standard output: the one thing the program prints that is an answer rather than a log.
pub fn writeStdout(bytes: []const u8) void {
    impl.writeStdout(bytes);
}

pub fn readFile(path: [*:0]const u8, buf: []u8) ?[]u8 {
    return impl.readFile(path, buf);
}

/// Create one directory; its parent must exist. An existing directory is not an error.
pub fn makeDir(path: [*:0]const u8) void {
    impl.makeDir(path);
}

pub fn isDir(path: [*:0]const u8) bool {
    return impl.isDir(path);
}

fn isSep(c: u8) bool {
    return c == '/' or (builtin.os.tag == .windows and c == '\\');
}

/// Create `path` and every missing directory above it. True if `path` is a directory afterwards.
pub fn makeDirs(path: []const u8) bool {
    var buf: [paths.max_path]u8 = undefined;
    if (path.len == 0 or path.len >= buf.len) return false;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    const z: [*:0]const u8 = @ptrCast(&buf);
    if (isDir(z)) return true;
    // Each prefix that ends before a separator, shortest first, then the whole path. A component that
    // exists already (or, on Windows, a prefix that is only a drive letter) makes the call fail, which
    // is fine; whether the whole succeeded is read off at the end.
    var i: usize = 1;
    while (i < path.len) : (i += 1) {
        if (!isSep(path[i])) continue;
        const c = buf[i];
        buf[i] = 0;
        makeDir(z);
        buf[i] = c;
    }
    makeDir(z);
    return isDir(z);
}

/// Replace the file at `path` with `bytes` so that a reader, or a crash at any moment, sees either the
/// old contents or the new and never a part of either: the bytes go to a temporary file beside it, are
/// flushed to the disk, and the file is renamed over `path`. The directory must exist.
pub fn writeFileAtomic(path: []const u8, bytes: []const u8) bool {
    return impl.writeFileAtomic(path, bytes);
}

/// True if the file was there and is gone.
pub fn removeFile(path: [*:0]const u8) bool {
    return impl.removeFile(path);
}

/// True if the directory was there, was empty, and is gone.
pub fn removeDir(path: [*:0]const u8) bool {
    return impl.removeDir(path);
}

/// Give the file at `from` a second name, `to`, in the same directory tree. The tests use it to hold on
/// to a file that is about to be replaced.
pub fn linkFile(from: [*:0]const u8, to: [*:0]const u8) bool {
    return impl.linkFile(from, to);
}

/// The value of an environment variable, copied into `buf` as UTF-8; null if it is unset, empty or does
/// not fit.
pub fn env(name: [*:0]const u8, buf: []u8) ?[]const u8 {
    return impl.env(name, buf);
}

/// True if the variable exists, even with an empty value.
pub fn envIsSet(name: [*:0]const u8) bool {
    return impl.envIsSet(name);
}

/// The directory the save file lives in: under Application Support in the user's Library on macOS,
/// under %APPDATA% on Windows, the application's data directory on the television. It is not created here; `makeDirs` does that when there is something to
/// save. Null if the system will not say where the user's files are kept.
pub fn saveDir(buf: []u8) ?[:0]const u8 {
    var root_buf: [paths.max_path]u8 = undefined;
    const root = impl.profileRoot(&root_buf) orelse return null;
    return impl.saveDirIn(buf, root);
}

/// Why `saveDir` has no answer, for the message that says so.
pub const no_save_dir_reason: []const u8 = impl.no_profile_reason;

/// Path separator of the target.
pub const sep: u8 = if (builtin.os.tag == .windows) '\\' else '/';

/// A throwaway user profile for tests of the save file. While it is in place `saveDir` answers with a
/// directory under a fresh, empty temporary one, in which nothing has been created yet; `end` puts the
/// real profile back and removes the save file and its directories.
pub const ScratchProfile = struct {
    root_buf: [paths.max_path:0]u8 = undefined,
    root_len: usize = 0,
    old_buf: [paths.max_path:0]u8 = undefined,
    old_len: ?usize = null,

    /// Null if no temporary directory can be made, in which case the test is skipped.
    pub fn begin(sp: *ScratchProfile) ?void {
        const made = impl.makeTempDir(&sp.root_buf) orelse return null;
        sp.root_len = made.len;
        if (env(impl.profile_var, sp.old_buf[0..paths.max_path])) |old| {
            sp.old_buf[old.len] = 0;
            sp.old_len = old.len;
        }
        if (!impl.setEnv(impl.profile_var, sp.root_buf[0..sp.root_len :0])) return null;
    }

    pub fn root(sp: *const ScratchProfile) [:0]const u8 {
        return sp.root_buf[0..sp.root_len :0];
    }

    /// The save directory under this profile.
    pub fn dir(sp: *const ScratchProfile, buf: []u8) [:0]const u8 {
        return impl.saveDirIn(buf, sp.root()).?;
    }

    /// The first thing a save creates under the profile: the top directory on the way to the save
    /// directory (Library on macOS, the game's own folder on Windows).
    pub fn top(sp: *const ScratchProfile, buf: []u8) [:0]const u8 {
        const full = sp.dir(buf);
        var end_at: usize = sp.root_len + 1;
        while (end_at < full.len and !isSep(full[end_at])) end_at += 1;
        buf[end_at] = 0;
        return buf[0..end_at :0];
    }

    /// A file named `name` in the save directory.
    pub fn file(sp: *const ScratchProfile, buf: []u8, name: []const u8) [:0]const u8 {
        var dir_buf: [paths.max_path]u8 = undefined;
        return std.fmt.bufPrintSentinel(buf, "{s}{c}{s}", .{ sp.dir(&dir_buf), sep, name }, 0) catch unreachable;
    }

    /// Restores the real profile and removes the scratch one: the save file, then each directory from
    /// the save directory up to the scratch root. Anything else a test put there it removes itself.
    pub fn end(sp: *ScratchProfile) void {
        _ = impl.setEnv(impl.profile_var, if (sp.old_len) |n| sp.old_buf[0..n :0] else null);
        var buf: [paths.max_path]u8 = undefined;
        var file_buf: [paths.max_path]u8 = undefined;
        _ = removeFile(sp.file(&file_buf, paths.save_file_name).ptr);
        var len = sp.dir(&buf).len;
        while (len > sp.root_len) {
            buf[len] = 0;
            const z: [*:0]const u8 = @ptrCast(&buf);
            // A test may have left a file where a directory would be.
            if (!removeDir(z)) _ = removeFile(z);
            while (len > sp.root_len and !isSep(buf[len - 1])) len -= 1;
            len -|= 1;
        }
        _ = removeDir(sp.root().ptr);
    }
};

test "directories are made with their parents, and a file is replaced whole" {
    var profile: ScratchProfile = .{};
    profile.begin() orelse return error.SkipZigTest;
    defer profile.end();
    var b1: [paths.max_path]u8 = undefined;
    var b2: [paths.max_path]u8 = undefined;
    var content: [64]u8 = undefined;
    const dir = profile.dir(&b1);
    try std.testing.expect(!isDir(profile.top(&b2).ptr));
    try std.testing.expect(makeDirs(dir));
    try std.testing.expect(isDir(dir.ptr));
    try std.testing.expect(makeDirs(dir));

    const path = profile.file(&b2, paths.save_file_name);
    try std.testing.expect(writeFileAtomic(path, "one\n"));
    try std.testing.expectEqualStrings("one\n", readFile(path.ptr, &content).?);
    try std.testing.expect(writeFileAtomic(path, "two, and longer\n"));
    try std.testing.expectEqualStrings("two, and longer\n", readFile(path.ptr, &content).?);
    // Nothing is left beside it: the directory is empty once the file is gone.
    try std.testing.expect(removeFile(path.ptr));
    try std.testing.expect(removeDir(dir.ptr));
    try std.testing.expect(!writeFileAtomic(path, "the directory is gone\n"));
}

test {
    _ = paths;
}
