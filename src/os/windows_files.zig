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

pub fn removeFile(path: [*:0]const u8) void {
    var buf: [paths.max_path]u16 = undefined;
    const name = wide(&buf, path) orelse return;
    _ = w.DeleteFileW(name.ptr);
}

pub fn removeDir(path: [*:0]const u8) void {
    var buf: [paths.max_path]u16 = undefined;
    const name = wide(&buf, path) orelse return;
    _ = w.RemoveDirectoryW(name.ptr);
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

pub const ScratchProfile = struct {
    root: [paths.max_path:0]u8 = undefined,
    root_len: usize = 0,
    old: [paths.max_path]u16 = undefined,
    old_len: ?usize = null,

    const appdata = std.unicode.utf8ToUtf16LeStringLiteral("APPDATA");

    /// Null if no temporary directory can be made, in which case the test is skipped.
    pub fn begin(sp: *ScratchProfile) ?void {
        var tmp: [paths.max_path]u16 = undefined;
        const n = w.GetTempPathW(tmp.len, &tmp);
        if (n == 0 or n >= tmp.len) return null;
        var tmp8: [paths.max_path]u8 = undefined;
        const base = w.fromWide(&tmp8, tmp[0..n]) orelse return null;
        var qpc: i64 = 0;
        _ = w.QueryPerformanceCounter(&qpc);
        // GetTempPath ends in a separator. The name is unique to this process and moment.
        const root = std.fmt.bufPrintSentinel(&sp.root, "{s}dentro-test-{d}-{x}", .{ base, w.GetCurrentProcessId(), @as(u64, @bitCast(qpc)) }, 0) catch return null;
        sp.root_len = root.len;
        makeDir(root.ptr);
        const had = w.GetEnvironmentVariableW(appdata, &sp.old, sp.old.len);
        if (had > 0 and had < sp.old.len) {
            sp.old[had] = 0;
            sp.old_len = had;
        }
        var wroot: [paths.max_path]u16 = undefined;
        const wr = w.toWide(&wroot, root) orelse return null;
        if (w.SetEnvironmentVariableW(appdata, wr.ptr) == 0) return null;
    }

    /// Restores the real profile and removes the scratch one, which holds at most the save file.
    pub fn end(sp: *ScratchProfile) void {
        if (sp.old_len) |n| {
            _ = w.SetEnvironmentVariableW(appdata, sp.old[0..n :0].ptr);
        } else _ = w.SetEnvironmentVariableW(appdata, null);
        const root = sp.root[0..sp.root_len];
        var bufs: [2][paths.max_path]u8 = undefined;
        if (std.fmt.bufPrintSentinel(&bufs[0], "{s}\\" ++ paths.app_dir_name ++ "\\" ++ paths.save_file_name, .{root}, 0)) |p| removeFile(p.ptr) else |_| {}
        if (std.fmt.bufPrintSentinel(&bufs[1], "{s}\\" ++ paths.app_dir_name, .{root}, 0)) |p| removeDir(p.ptr) else |_| {}
        removeDir(sp.root[0..sp.root_len :0].ptr);
    }
};
