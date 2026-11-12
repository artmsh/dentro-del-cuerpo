//! Glyph atlas rasterised once at startup from the fonts compiled into the binary. The rasteriser is the
//! vendored stb_truetype, so this file makes no platform calls and runs the same in headless tests.

const std = @import("std");
const utf8 = @import("utf8.zig");

/// The two text faces, and the face that supplies the arrows and geometric marks they lack.
const face_data = [2][]const u8{ @embedFile("font-regular"), @embedFile("font-bold") };
const symbol_data = @embedFile("font-symbols");

/// Storage for a stbtt_fontinfo; src/stb_truetype.c asserts that it is large enough.
const FontInfo = extern struct { storage: [256]u8 align(8) };

extern fn stbtt_InitFont(info: *FontInfo, data: [*]const u8, offset: c_int) c_int;
extern fn stbtt_ScaleForMappingEmToPixels(info: *const FontInfo, pixels: f32) f32;
extern fn stbtt_FindGlyphIndex(info: *const FontInfo, codepoint: c_int) c_int;
extern fn stbtt_GetGlyphHMetrics(info: *const FontInfo, glyph: c_int, advance: *c_int, left_bearing: *c_int) void;
extern fn stbtt_GetGlyphBitmapBox(info: *const FontInfo, glyph: c_int, sx: f32, sy: f32, x0: *c_int, y0: *c_int, x1: *c_int, y1: *c_int) void;
extern fn stbtt_MakeGlyphBitmap(info: *const FontInfo, out: [*]u8, w: c_int, h: c_int, stride: c_int, sx: f32, sy: f32, glyph: c_int) void;

pub const atlas_w = 4096;
pub const atlas_h = 2048;
/// Pixels per em in the atlas.
pub const base_px: f32 = 96;
/// Distance from the top of a line to its baseline, in ems. The HUD is laid out against this constant
/// rather than the font's own ascent, which differs between families of the same cap height and would move
/// every line of text whenever the font changed.
pub const ascent_em: f32 = 1.0;
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
    /// False when none of the bundled fonts has this code point; it then draws as nothing.
    present: bool = false,
};

pub const Face = enum(u8) { regular = 0, bold = 1 };

/// Blocks taken whole: ASCII, Latin-1, and Cyrillic Ѐ–џ plus Ґ ґ (everything Ukrainian needs).
const ranges = [_][2]u21{ .{ 0x20, 0x7E }, .{ 0xA0, 0xFF }, .{ 0x400, 0x45F }, .{ 0x490, 0x491 } };
/// Individual code points: ʼ ‘ ’ “ ” „ – — • … № − and the marks ← ↑ → ↓ ● ▲ ▶ ◆ ✓.
const singles = [_]u21{ 0x2BC, 0x2013, 0x2014, 0x2018, 0x2019, 0x201C, 0x201D, 0x201E, 0x2022, 0x2026, 0x2116, 0x2190, 0x2191, 0x2192, 0x2193, 0x2212, 0x25B2, 0x25B6, 0x25C6, 0x25CF, 0x2713 };

/// Every code point the atlas holds, ascending.
pub const charset = blk: {
    var n: usize = singles.len;
    for (ranges) |r| n += r[1] - r[0] + 1;
    var set: [n]u21 = undefined;
    var i: usize = 0;
    for (ranges) |r| {
        var cp = r[0];
        while (cp <= r[1]) : (cp += 1) {
            set[i] = cp;
            i += 1;
        }
    }
    for (singles) |cp| {
        set[i] = cp;
        i += 1;
    }
    @setEvalBranchQuota(100_000);
    std.mem.sort(u21, &set, {}, std.sort.asc(u21));
    for (set[1..], set[0 .. n - 1]) |b, a| if (a == b) @compileError("duplicate code point in the atlas character set");
    break :blk set;
};

/// Index of `cp` in `charset`, or null if the atlas does not hold it.
pub fn slot(cp: u21) ?usize {
    var lo: usize = 0;
    var hi: usize = charset.len;
    while (lo < hi) {
        const mid = (lo + hi) / 2;
        if (charset[mid] < cp) lo = mid + 1 else hi = mid;
    }
    return if (lo < charset.len and charset[lo] == cp) lo else null;
}

const fallback_slot = slot('?').?;

pub const Font = struct {
    glyphs: [2][charset.len]Glyph = undefined,
    /// Baseline offset and descender depth at `base_px`.
    ascent: f32 = base_px * ascent_em,
    descent: f32 = 0,
    pixels: []u8 = &.{},

    /// The glyph for `cp`, or the question mark if the atlas does not hold it.
    pub fn glyph(f: *const Font, face: Face, cp: u21) *const Glyph {
        return &f.glyphs[@intFromEnum(face)][slot(cp) orelse fallback_slot];
    }

    /// True if `cp` draws as its own glyph in `face`.
    pub fn covers(f: *const Font, face: Face, cp: u21) bool {
        const s = slot(cp) orelse return false;
        return f.glyphs[@intFromEnum(face)][s].present;
    }

    pub fn build(gpa: std.mem.Allocator) !Font {
        var f: Font = .{};
        f.pixels = try gpa.alloc(u8, atlas_w * atlas_h);
        errdefer gpa.free(f.pixels);
        @memset(f.pixels, 0);

        var symbols: FontInfo = undefined;
        if (stbtt_InitFont(&symbols, symbol_data.ptr, 0) == 0) return error.BadFont;
        const symbol_scale = stbtt_ScaleForMappingEmToPixels(&symbols, base_px);

        var pen_x: usize = pad;
        var pen_y: usize = pad;
        var row_h: usize = 0;
        for (face_data, 0..) |data, face| {
            var primary: FontInfo = undefined;
            if (stbtt_InitFont(&primary, data.ptr, 0) == 0) return error.BadFont;
            const primary_scale = stbtt_ScaleForMappingEmToPixels(&primary, base_px);
            for (charset, 0..) |cp, s| {
                var g: Glyph = .{};
                var info: *const FontInfo = &primary;
                var scale = primary_scale;
                var index = stbtt_FindGlyphIndex(info, cp);
                if (index == 0) {
                    info = &symbols;
                    scale = symbol_scale;
                    index = stbtt_FindGlyphIndex(info, cp);
                }
                if (index != 0) {
                    g.present = true;
                    var adv: c_int = 0;
                    var lsb: c_int = 0;
                    stbtt_GetGlyphHMetrics(info, index, &adv, &lsb);
                    g.adv = @as(f32, @floatFromInt(adv)) * scale;
                    var x0: c_int = 0;
                    var y0: c_int = 0;
                    var x1: c_int = 0;
                    var y1: c_int = 0;
                    stbtt_GetGlyphBitmapBox(info, index, scale, scale, &x0, &y0, &x1, &y1);
                    if (x1 > x0 and y1 > y0) {
                        const bw: usize = @intCast(x1 - x0);
                        const bh: usize = @intCast(y1 - y0);
                        const gw = bw + 2 * pad;
                        const gh = bh + 2 * pad;
                        if (pen_x + gw + pad > atlas_w) {
                            pen_x = pad;
                            pen_y += row_h + pad;
                            row_h = 0;
                        }
                        if (pen_y + gh + pad > atlas_h) return error.AtlasFull;
                        const origin = (pen_y + pad) * atlas_w + pen_x + pad;
                        stbtt_MakeGlyphBitmap(info, f.pixels.ptr + origin, @intCast(bw), @intCast(bh), atlas_w, scale, scale, index);
                        g.u0 = @as(f32, @floatFromInt(pen_x)) / atlas_w;
                        g.v0 = @as(f32, @floatFromInt(pen_y)) / atlas_h;
                        g.u1 = @as(f32, @floatFromInt(pen_x + gw)) / atlas_w;
                        g.v1 = @as(f32, @floatFromInt(pen_y + gh)) / atlas_h;
                        g.w = @floatFromInt(gw);
                        g.h = @floatFromInt(gh);
                        g.ox = @as(f32, @floatFromInt(x0)) - pad;
                        g.oy = @as(f32, @floatFromInt(y0)) - pad;
                        pen_x += gw + pad;
                        row_h = @max(row_h, gh);
                        if (face == 0) f.descent = @max(f.descent, @as(f32, @floatFromInt(y1)));
                    }
                }
                f.glyphs[face][s] = g;
            }
        }
        return f;
    }
};

test "the character set is sorted and searchable" {
    for (charset, 0..) |cp, i| try std.testing.expectEqual(@as(?usize, i), slot(cp));
    try std.testing.expectEqual(@as(?usize, null), slot(0x1F));
    try std.testing.expectEqual(@as(?usize, null), slot(0x3A9));
    try std.testing.expectEqual(@as(?usize, null), slot(0x10FFFF));
    var i: usize = 0;
    const s = "ЇїЄєҐґІі’«»—…→✓";
    while (i < s.len) try std.testing.expect(slot(utf8.next(s, &i)) != null);
}

test "every code point of the character set has a glyph in both faces" {
    const f = try Font.build(std.testing.allocator);
    defer std.testing.allocator.free(f.pixels);
    for ([_]Face{ .regular, .bold }) |face| {
        for (charset) |cp| {
            if (!f.covers(face, cp)) {
                std.debug.print("U+{X:0>4} has no glyph in the {s} face\n", .{ cp, @tagName(face) });
                return error.MissingGlyph;
            }
        }
        // Letters have ink and a positive advance; the question mark stands in for anything outside the set.
        const zhe = f.glyph(face, 0x416);
        try std.testing.expect(zhe.w > 20 and zhe.adv > 20);
        try std.testing.expectEqual(f.glyph(face, '?'), f.glyph(face, 0x3A9));
    }
    try std.testing.expect(f.descent > 10 and f.descent < 40);
}
