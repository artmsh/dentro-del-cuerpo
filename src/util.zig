//! Small libc-backed file helpers (screenshots, save file, logs).

const std = @import("std");

const FILE = opaque {};
extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*FILE;
extern "c" fn fwrite(ptr: [*]const u8, size: usize, n: usize, f: *FILE) usize;
extern "c" fn fread(ptr: [*]u8, size: usize, n: usize, f: *FILE) usize;
extern "c" fn fclose(f: *FILE) c_int;
extern "c" fn mkdir(path: [*:0]const u8, mode: c_uint) c_int;
extern "c" fn getenv(name: [*:0]const u8) ?[*:0]const u8;

pub fn writeFile(path: [*:0]const u8, bytes: []const u8) bool {
    const f = fopen(path, "wb") orelse return false;
    defer _ = fclose(f);
    return fwrite(bytes.ptr, 1, bytes.len, f) == bytes.len;
}

/// Read up to `buf.len` bytes; returns the slice read or null if the file cannot be opened.
pub fn readFile(path: [*:0]const u8, buf: []u8) ?[]u8 {
    const f = fopen(path, "rb") orelse return null;
    defer _ = fclose(f);
    const n = fread(buf.ptr, 1, buf.len, f);
    return buf[0..n];
}

pub fn makeDir(path: [*:0]const u8) void {
    _ = mkdir(path, 0o755);
}

extern "c" fn rename(from: [*:0]const u8, to: [*:0]const u8) c_int;
extern "c" fn remove(path: [*:0]const u8) c_int;
extern "c" fn fflush(f: *FILE) c_int;
extern "c" fn fileno(f: *FILE) c_int;
extern "c" fn fsync(fd: c_int) c_int;
extern "c" fn getpid() c_int;
extern "c" fn opendir(path: [*:0]const u8) ?*anyopaque;
extern "c" fn closedir(dir: *anyopaque) c_int;

pub fn isDir(path: [*:0]const u8) bool {
    const d = opendir(path) orelse return false;
    _ = closedir(d);
    return true;
}

/// Create `path` and every missing directory above it. True if `path` is a directory afterwards.
pub fn makeDirs(path: []const u8) bool {
    var buf: [1024]u8 = undefined;
    if (path.len == 0 or path.len >= buf.len) return false;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    const z: [*:0]const u8 = @ptrCast(&buf);
    if (isDir(z)) return true;
    // Each prefix that ends before a separator, shortest first, then the whole path. A component that
    // exists already makes mkdir fail, which is fine; whether the whole succeeded is read off at the end.
    var i: usize = 1;
    while (i < path.len) : (i += 1) {
        if (path[i] != '/') continue;
        buf[i] = 0;
        _ = mkdir(z, 0o755);
        buf[i] = '/';
    }
    _ = mkdir(z, 0o755);
    return isDir(z);
}

/// Replace the file at `path` with `bytes` so that a reader, or a crash at any moment, sees either the
/// old contents or the new and never a part of either: the bytes go to a temporary file beside it, are
/// flushed to the disk, and the file is renamed over `path`. The directory must exist.
pub fn writeFileAtomic(path: []const u8, bytes: []const u8) bool {
    var tmp_buf: [1100]u8 = undefined;
    var path_buf: [1024]u8 = undefined;
    const tmp = std.fmt.bufPrintSentinel(&tmp_buf, "{s}.{d}.tmp", .{ path, getpid() }, 0) catch return false;
    const dest = std.fmt.bufPrintSentinel(&path_buf, "{s}", .{path}, 0) catch return false;
    const f = fopen(tmp.ptr, "wb") orelse return false;
    var ok = fwrite(bytes.ptr, 1, bytes.len, f) == bytes.len;
    ok = fflush(f) == 0 and ok;
    ok = fsync(fileno(f)) == 0 and ok;
    ok = fclose(f) == 0 and ok;
    ok = ok and rename(tmp.ptr, dest.ptr) == 0;
    if (!ok) _ = remove(tmp.ptr);
    return ok;
}

pub fn env(name: [*:0]const u8) ?[]const u8 {
    const p = getenv(name) orelse return null;
    return std.mem.span(p);
}

extern fn CGColorSpaceCreateDeviceRGB() ?*anyopaque;
extern fn CGDataProviderCreateWithData(info: ?*anyopaque, data: [*]const u8, size: usize, release: ?*anyopaque) ?*anyopaque;
extern fn CGImageCreate(w: usize, h: usize, bpc: usize, bpp: usize, bpr: usize, space: ?*anyopaque, info: u32, provider: ?*anyopaque, decode: ?*anyopaque, interpolate: bool, intent: i32) ?*anyopaque;
extern fn CGImageDestinationCreateWithURL(url: ?*anyopaque, uti: ?*anyopaque, count: usize, opts: ?*anyopaque) ?*anyopaque;
extern fn CGImageDestinationAddImage(dest: ?*anyopaque, image: ?*anyopaque, props: ?*anyopaque) void;
extern fn CGImageDestinationFinalize(dest: ?*anyopaque) bool;

/// Write top-down premultiplied BGRA8 pixels as a PNG (ImageIO).
pub fn writePng(path: [*:0]const u8, bgra: []const u8, w: u32, h: u32) bool {
    const objc = @import("objc.zig");
    const space = CGColorSpaceCreateDeviceRGB();
    const provider = CGDataProviderCreateWithData(null, bgra.ptr, bgra.len, null);
    const image = CGImageCreate(w, h, 8, 32, @as(usize, w) * 4, space, (2 << 12) | 2, provider, null, false, 0) orelse return false;
    const url = objc.send(fn (objc.id, objc.SEL, objc.id) callconv(.c) objc.id, objc.class("NSURL"), "fileURLWithPath:", .{objc.nsString(std.mem.span(path))});
    const dest = CGImageDestinationCreateWithURL(url, objc.nsString("public.png"), 1, null) orelse return false;
    CGImageDestinationAddImage(dest, image, null);
    return CGImageDestinationFinalize(dest);
}

/// Write top-down BGRA8 pixels as a 32-bit BMP.
pub fn writeBmp(path: [*:0]const u8, bgra: []const u8, w: u32, h: u32) bool {
    var hdr: [54]u8 = @splat(0);
    const size: u32 = 54 + w * h * 4;
    hdr[0] = 'B';
    hdr[1] = 'M';
    std.mem.writeInt(u32, hdr[2..6], size, .little);
    std.mem.writeInt(u32, hdr[10..14], 54, .little);
    std.mem.writeInt(u32, hdr[14..18], 40, .little);
    std.mem.writeInt(i32, hdr[18..22], @intCast(w), .little);
    std.mem.writeInt(i32, hdr[22..26], -@as(i32, @intCast(h)), .little);
    std.mem.writeInt(u16, hdr[26..28], 1, .little);
    std.mem.writeInt(u16, hdr[28..30], 32, .little);
    const f = fopen(path, "wb") orelse return false;
    defer _ = fclose(f);
    if (fwrite(&hdr, 1, 54, f) != 54) return false;
    return fwrite(bgra.ptr, 1, bgra.len, f) == bgra.len;
}
