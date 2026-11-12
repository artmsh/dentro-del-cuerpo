//! Glyph atlas rasterised once at startup with CoreText (C API only).

const std = @import("std");
const objc = @import("objc.zig");

const CGGlyph = u16;
const Ref = ?*anyopaque;

extern fn CTFontCreateWithName(name: Ref, size: f64, matrix: ?*const anyopaque) Ref;
extern fn CTFontGetGlyphsForCharacters(font: Ref, chars: [*]const u16, glyphs: [*]CGGlyph, count: isize) bool;
extern fn CTFontGetAdvancesForGlyphs(font: Ref, orientation: u32, glyphs: [*]const CGGlyph, advances: [*]objc.Size, count: isize) f64;
extern fn CTFontGetBoundingRectsForGlyphs(font: Ref, orientation: u32, glyphs: [*]const CGGlyph, rects: [*]objc.Rect, count: isize) objc.Rect;
extern fn CTFontDrawGlyphs(font: Ref, glyphs: [*]const CGGlyph, positions: [*]const objc.Point, count: usize, ctx: Ref) void;
extern fn CTFontGetAscent(font: Ref) f64;
extern fn CTFontGetDescent(font: Ref) f64;
extern fn CGColorSpaceCreateDeviceGray() Ref;
extern fn CGBitmapContextCreate(data: ?*anyopaque, w: usize, h: usize, bits: usize, bytes_per_row: usize, space: Ref, info: u32) Ref;
extern fn CGContextSetGrayFillColor(ctx: Ref, gray: f64, alpha: f64) void;
extern fn CGContextRelease(ctx: Ref) void;
extern fn CGColorSpaceRelease(space: Ref) void;
extern fn CFRelease(r: Ref) void;

pub const atlas_w = 4096;
pub const atlas_h = 2048;
pub const base_px: f32 = 96;
const pad = 5;

pub const Glyph = struct {
    u0: f32 = 0,
    v0: f32 = 0,
    u1: f32 = 0,
    v1: f32 = 0,
    /// Quad offset from the pen position (x right, y down from the baseline) and size, in base pixels.
    ox: f32 = 0,
    oy: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,
    adv: f32 = 0,
};

pub const Face = enum(u8) { regular = 0, bold = 1 };

/// Code points outside Latin-1 that the HUD uses, stored in the unused control slots.
const extras = [_]u21{ 0x2014, 0x2026, 0x2192, 0x2190, 0x2191, 0x2193, 0x25CF, 0x25B2, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x25C6, 0x2713, 0x25B6 };

pub fn slot(cp: u21) u8 {
    if (cp >= 32 and cp < 256) return @intCast(cp);
    for (extras, 0..) |e, i| if (e == cp) return @intCast(i + 1);
    return '?';
}

pub const Font = struct {
    glyphs: [2][256]Glyph = undefined,
    ascent: f32 = 0,
    descent: f32 = 0,
    pixels: []u8 = &.{},

    pub fn build(gpa: std.mem.Allocator) !Font {
        var f: Font = .{};
        f.pixels = try gpa.alloc(u8, atlas_w * atlas_h);
        @memset(f.pixels, 0);
        const space = CGColorSpaceCreateDeviceGray();
        defer CGColorSpaceRelease(space);
        const ctx = CGBitmapContextCreate(f.pixels.ptr, atlas_w, atlas_h, 8, atlas_w, space, 0) orelse return error.NoBitmapContext;
        defer CGContextRelease(ctx);
        CGContextSetGrayFillColor(ctx, 1, 1);

        var pen_x: usize = pad;
        var pen_y: usize = pad;
        var row_h: usize = 0;
        const names = [2][*:0]const u8{ "AvenirNextCondensed-Medium", "AvenirNextCondensed-DemiBold" };
        for (names, 0..) |name, face| {
            const primary = CTFontCreateWithName(objc.nsString(name), base_px, null) orelse return error.NoFont;
            defer CFRelease(primary);
            // Arrows and geometric marks are not in Avenir Next Condensed; take them from faces that have them.
            const fallbacks = [2]Ref{ CTFontCreateWithName(objc.nsString("HelveticaNeue"), base_px, null), CTFontCreateWithName(objc.nsString("AppleSymbols"), base_px, null) };
            defer for (fallbacks) |fb| if (fb != null) CFRelease(fb);
            const font = primary;
            if (face == 0) {
                f.ascent = @floatCast(CTFontGetAscent(font));
                f.descent = @floatCast(CTFontGetDescent(font));
            }
            for (0..256) |s| {
                var g: Glyph = .{};
                const cp: u21 = if (s >= 32) @intCast(s) else if (s >= 1 and s <= extras.len) extras[s - 1] else 0;
                if (cp != 0) {
                    var ch = [1]u16{@intCast(cp)};
                    var glyph = [1]CGGlyph{0};
                    var use: Ref = font;
                    var have = CTFontGetGlyphsForCharacters(use, &ch, &glyph, 1);
                    for (fallbacks) |fb| {
                        if (have or fb == null) continue;
                        use = fb;
                        have = CTFontGetGlyphsForCharacters(use, &ch, &glyph, 1);
                    }
                    if (have) {
                        var adv = [1]objc.Size{.{ .w = 0, .h = 0 }};
                        var bb = [1]objc.Rect{.{ .x = 0, .y = 0, .w = 0, .h = 0 }};
                        _ = CTFontGetAdvancesForGlyphs(use, 0, &glyph, &adv, 1);
                        _ = CTFontGetBoundingRectsForGlyphs(use, 0, &glyph, &bb, 1);
                        g.adv = @floatCast(adv[0].w);
                        if (bb[0].w > 0 and bb[0].h > 0) {
                            const bx = @floor(bb[0].x);
                            const by = @floor(bb[0].y);
                            const gw: usize = @intFromFloat(@ceil(bb[0].x + bb[0].w) - bx + 2 * pad);
                            const gh: usize = @intFromFloat(@ceil(bb[0].y + bb[0].h) - by + 2 * pad);
                            if (pen_x + gw + pad > atlas_w) {
                                pen_x = pad;
                                pen_y += row_h + pad;
                                row_h = 0;
                            }
                            if (pen_y + gh + pad > atlas_h) return error.AtlasFull;
                            // CoreGraphics has its origin at the bottom left; the buffer's first row is the top.
                            const pos = [1]objc.Point{.{
                                .x = @as(f64, @floatFromInt(pen_x + pad)) - bx,
                                .y = @as(f64, @floatFromInt(atlas_h - pen_y - gh + pad)) - by,
                            }};
                            CTFontDrawGlyphs(use, &glyph, &pos, 1, ctx);
                            g.u0 = @as(f32, @floatFromInt(pen_x)) / atlas_w;
                            g.v0 = @as(f32, @floatFromInt(pen_y)) / atlas_h;
                            g.u1 = @as(f32, @floatFromInt(pen_x + gw)) / atlas_w;
                            g.v1 = @as(f32, @floatFromInt(pen_y + gh)) / atlas_h;
                            g.w = @floatFromInt(gw);
                            g.h = @floatFromInt(gh);
                            g.ox = @as(f32, @floatCast(bx)) - pad;
                            g.oy = -(@as(f32, @floatCast(by)) + @as(f32, @floatFromInt(gh)) - pad);
                            pen_x += gw + pad;
                            row_h = @max(row_h, gh);
                        }
                    }
                }
                f.glyphs[face][s] = g;
            }
        }
        return f;
    }
};

/// Minimal UTF-8 decoder: returns the code point and advances `i`.
pub fn nextCodepoint(s: []const u8, i: *usize) u21 {
    const c = s[i.*];
    if (c < 0x80) {
        i.* += 1;
        return c;
    }
    const n: usize = if (c >= 0xF0) 4 else if (c >= 0xE0) 3 else 2;
    if (i.* + n > s.len) {
        i.* = s.len;
        return '?';
    }
    var cp: u21 = switch (n) {
        2 => c & 0x1F,
        3 => c & 0x0F,
        else => c & 0x07,
    };
    for (1..n) |k| cp = (cp << 6) | (s[i.* + k] & 0x3F);
    i.* += n;
    return cp;
}

test "utf8 decode" {
    var i: usize = 0;
    const s = "aµ—";
    try std.testing.expectEqual(@as(u21, 'a'), nextCodepoint(s, &i));
    try std.testing.expectEqual(@as(u21, 0xB5), nextCodepoint(s, &i));
    try std.testing.expectEqual(@as(u21, 0x2014), nextCodepoint(s, &i));
    try std.testing.expectEqual(s.len, i);
    try std.testing.expectEqual(@as(u8, 1), slot(0x2014));
}
