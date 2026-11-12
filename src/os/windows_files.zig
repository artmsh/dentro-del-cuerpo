//! `util.zig` on Windows: the wide-character Win32 file calls, with paths converted from UTF-8. libc's
//! stdio would read a path in the process's legacy code page, and a save file under a user name written
//! in another script would then fail to open.

const std = @import("std");
const w = @import("../platform/win32.zig");
const paths = @import("paths.zig");

fn wide(buf: *[paths.max_path]u16, path: [*:0]const u8) ?[:0]u16 {
    return w.toWide(buf, std.mem.span(path));
}

pub fn writeFileParts(path: [*:0]const u8, parts: []const []const u8) bool {
    var buf: [paths.max_path]u16 = undefined;
    const name = wide(&buf, path) orelse return false;
    const f = w.CreateFileW(name.ptr, w.GENERIC_WRITE, 0, null, w.CREATE_ALWAYS, w.FILE_ATTRIBUTE_NORMAL, null);
    if (f == w.invalid_handle) return false;
    defer _ = w.CloseHandle(f);
    for (parts) |bytes| {
        var rest = bytes;
        while (rest.len > 0) {
            const chunk: u32 = @intCast(@min(rest.len, 1 << 30));
            var written: u32 = 0;
            if (w.WriteFile(f, rest.ptr, chunk, &written, null) == 0 or written == 0) return false;
            rest = rest[written..];
        }
    }
    return true;
}

/// The handle is asked for at the time of the call, so this follows a console attached after startup,
/// which the C runtime's descriptor 1 would not.
pub fn writeStdout(bytes: []const u8) void {
    const h = w.GetStdHandle(w.STD_OUTPUT_HANDLE) orelse return;
    var rest = bytes;
    while (rest.len > 0) {
        var n: u32 = 0;
        if (w.WriteFile(h, rest.ptr, @intCast(rest.len), &n, null) == 0 or n == 0) return;
        rest = rest[n..];
    }
}

pub fn readFile(path: [*:0]const u8, out: []u8) ?[]u8 {
    var buf: [paths.max_path]u16 = undefined;
    const name = wide(&buf, path) orelse return null;
    const f = w.CreateFileW(name.ptr, w.GENERIC_READ, w.FILE_SHARE_READ, null, w.OPEN_EXISTING, w.FILE_ATTRIBUTE_NORMAL, null);
    if (f == w.invalid_handle) return null;
    defer _ = w.CloseHandle(f);
    var n: usize = 0;
    while (n < out.len) {
        var got: u32 = 0;
        if (w.ReadFile(f, out[n..].ptr, @intCast(@min(out.len - n, 1 << 30)), &got, null) == 0 or got == 0) break;
        n += got;
    }
    return out[0..n];
}

pub fn makeDir(path: [*:0]const u8) void {
    var buf: [paths.max_path]u16 = undefined;
    const name = wide(&buf, path) orelse return;
    _ = w.CreateDirectoryW(name.ptr, null);
}

pub fn isDir(path: [*:0]const u8) bool {
    var buf: [paths.max_path]u16 = undefined;
    const name = wide(&buf, path) orelse return false;
    const attrs = w.GetFileAttributesW(name.ptr);
    return attrs != w.INVALID_FILE_ATTRIBUTES and attrs & w.FILE_ATTRIBUTE_DIRECTORY != 0;
}

/// The bytes go to a temporary file beside the destination and are flushed to the disk; MoveFileEx then
/// replaces the destination in one step, and returns only when that too is on the disk.
pub fn writeFileAtomic(path: []const u8, bytes: []const u8) bool {
    var tmp8: [paths.max_path]u8 = undefined;
    var tmp_buf: [paths.max_path]u16 = undefined;
    var dest_buf: [paths.max_path]u16 = undefined;
    const tmp_name = std.fmt.bufPrint(&tmp8, "{s}.{d}.tmp", .{ path, w.GetCurrentProcessId() }) catch return false;
    const tmp = w.toWide(&tmp_buf, tmp_name) orelse return false;
    const dest = w.toWide(&dest_buf, path) orelse return false;
    const f = w.CreateFileW(tmp.ptr, w.GENERIC_WRITE, 0, null, w.CREATE_ALWAYS, w.FILE_ATTRIBUTE_NORMAL, null);
    if (f == w.invalid_handle) return false;
    var ok = true;
    var rest = bytes;
    while (ok and rest.len > 0) {
        var written: u32 = 0;
        ok = w.WriteFile(f, rest.ptr, @intCast(@min(rest.len, 1 << 30)), &written, null) != 0 and written > 0;
        if (ok) rest = rest[written..];
    }
    ok = w.FlushFileBuffers(f) != 0 and ok;
    ok = w.CloseHandle(f) != 0 and ok;
    ok = ok and w.MoveFileExW(tmp.ptr, dest.ptr, w.MOVEFILE_REPLACE_EXISTING | w.MOVEFILE_WRITE_THROUGH) != 0;
    if (!ok) _ = w.DeleteFileW(tmp.ptr);
    return ok;
}

pub fn removeFile(path: [*:0]const u8) bool {
    var buf: [paths.max_path]u16 = undefined;
    const name = wide(&buf, path) orelse return false;
    return w.DeleteFileW(name.ptr) != 0;
}

pub fn removeDir(path: [*:0]const u8) bool {
    var buf: [paths.max_path]u16 = undefined;
    const name = wide(&buf, path) orelse return false;
    return w.RemoveDirectoryW(name.ptr) != 0;
}

pub fn linkFile(from: [*:0]const u8, to: [*:0]const u8) bool {
    var from_buf: [paths.max_path]u16 = undefined;
    var to_buf: [paths.max_path]u16 = undefined;
    const existing = wide(&from_buf, from) orelse return false;
    const new = wide(&to_buf, to) orelse return false;
    return w.CreateHardLinkW(new.ptr, existing.ptr, null) != 0;
}

pub fn envIsSet(name: [*:0]const u8) bool {
    var name_buf: [128]u16 = undefined;
    const wname = w.toWide(&name_buf, std.mem.span(name)) orelse return false;
    // With no buffer the call returns the size needed, and 0 with ERROR_ENVVAR_NOT_FOUND (203) if there
    // is no such variable; an empty value also returns 0 but leaves that error unset.
    if (w.GetEnvironmentVariableW(wname.ptr, null, 0) > 0) return true;
    return w.GetLastError() != 203;
}

pub fn env(name: [*:0]const u8, out: []u8) ?[]const u8 {
    var name_buf: [128]u16 = undefined;
    const wname = w.toWide(&name_buf, std.mem.span(name)) orelse return null;
    var value: [paths.max_path]u16 = undefined;
    const n = w.GetEnvironmentVariableW(wname.ptr, &value, value.len);
    if (n == 0 or n >= value.len) return null;
    return w.fromWide(out, value[0..n]);
}

/// The roaming application-data directory: %APPDATA% as the process sees it, and if the variable has been
/// stripped from the environment, the folder the shell knows by that name.
pub fn profileRoot(out: []u8) ?[]const u8 {
    if (env("APPDATA", out)) |v| return v;
    var path: ?[*:0]u16 = null;
    defer w.CoTaskMemFree(path);
    if (w.failed(w.SHGetKnownFolderPath(&w.FOLDERID_RoamingAppData, 0, null, &path))) return null;
    return w.fromWide(out, std.mem.span(path orelse return null));
}

pub fn saveDirIn(out: []u8, root: []const u8) ?[:0]const u8 {
    return paths.winSaveDir(out, root);
}

pub const no_profile_reason = "Windows did not say where application data is kept (%APPDATA%), so there is nowhere to keep a save file";

/// The variable `profileRoot` reads first, which a scratch profile points somewhere else.
pub const profile_var = "APPDATA";

pub fn setEnv(name: [*:0]const u8, value: ?[:0]const u8) bool {
    var name_buf: [128]u16 = undefined;
    var value_buf: [paths.max_path]u16 = undefined;
    const wname = w.toWide(&name_buf, std.mem.span(name)) orelse return false;
    const wvalue: ?w.LPCWSTR = if (value) |v| (w.toWide(&value_buf, v) orelse return false).ptr else null;
    return w.SetEnvironmentVariableW(wname.ptr, wvalue) != 0;
}

/// A new, empty directory under the user's temporary folder, named for this process and moment.
pub fn makeTempDir(buf: []u8) ?[:0]const u8 {
    var tmp: [paths.max_path]u16 = undefined;
    const n = w.GetTempPathW(tmp.len, &tmp);
    if (n == 0 or n >= tmp.len) return null;
    var tmp8: [paths.max_path]u8 = undefined;
    const base = w.fromWide(&tmp8, tmp[0..n]) orelse return null;
    var qpc: i64 = 0;
    _ = w.QueryPerformanceCounter(&qpc);
    // GetTempPath ends in a separator.
    const made = std.fmt.bufPrintSentinel(buf, "{s}dentro-test-{d}-{x}", .{ base, w.GetCurrentProcessId(), @as(u64, @bitCast(qpc)) }, 0) catch return null;
    makeDir(made.ptr);
    return if (isDir(made.ptr)) made else null;
}
