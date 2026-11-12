//! Small file and environment helpers (screenshots, save file, logs). Paths are UTF-8 on every platform;
//! the implementation is picked at compile time, libc's stdio on POSIX systems and the wide-character
//! Win32 calls on Windows, where stdio would read a path in the legacy code page and fail on a user
//! name outside it.

const std = @import("std");
const builtin = @import("builtin");
const paths = @import("os/paths.zig");

const impl = switch (builtin.os.tag) {
    .windows => @import("os/windows_files.zig"),
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
pub fn readFile(path: [*:0]const u8, buf: []u8) ?[]u8 {
    return impl.readFile(path, buf);
}

/// Create one directory; its parent must exist. An existing directory is not an error.
pub fn makeDir(path: [*:0]const u8) void {
    impl.makeDir(path);
}

pub fn removeFile(path: [*:0]const u8) void {
    impl.removeFile(path);
}

pub fn removeDir(path: [*:0]const u8) void {
    impl.removeDir(path);
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

/// The directory the save file lives in, created if it was missing: under Application Support in the
/// user's Library on macOS, under %APPDATA% on Windows. Null if the system will not say where that is.
pub fn saveDir(buf: []u8) ?[:0]const u8 {
    var root_buf: [paths.max_path]u8 = undefined;
    const root = impl.profileRoot(&root_buf) orelse return null;
    const dir = impl.saveDirIn(buf, root) orelse return null;
    makeDir(dir.ptr);
    return dir;
}

/// Path separator of the target.
pub const sep: u8 = if (builtin.os.tag == .windows) '\\' else '/';

/// A throwaway user profile for tests of the save file: while it is in place `saveDir` answers with a
/// directory under a fresh temporary one, and `end` puts the real profile back and removes what the test
/// left behind.
pub const ScratchProfile = impl.ScratchProfile;

test {
    _ = paths;
}
