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
