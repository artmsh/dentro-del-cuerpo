//! Image files written without an operating-system codec: BMP for the screenshots, PNG for the icon
//! master, and the Windows .ico container. Pixels come in as the renderer reads them back, top-down BGRA8.
//! The encoders work on memory, so they are the same code on every platform and are tested by decoding
//! what they produce.

const std = @import("std");
const flate = std.compress.flate;

/// The 54-byte header of a top-down 32-bit BMP of `w` by `h` pixels. The file is this followed by the
/// rows as they are.
pub fn bmpHeader(w: u32, h: u32) [54]u8 {
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
    return hdr;
}

/// Straight (not premultiplied) RGBA of one premultiplied BGRA pixel.
fn straight(px: *const [4]u8) [4]u8 {
    const a: u32 = px[3];
    if (a == 0) return .{ 0, 0, 0, 0 };
    const un = struct {
        fn f(c: u8, alpha: u32) u8 {
            return @intCast(@min(255, (@as(u32, c) * 255 + alpha / 2) / alpha));
        }
    }.f;
    return .{ un(px[2], a), un(px[1], a), un(px[0], a), px[3] };
}

fn paeth(a: u8, b: u8, c: u8) u8 {
    const p = @as(i32, a) + @as(i32, b) - @as(i32, c);
    const pa = @abs(p - a);
    const pb = @abs(p - b);
    const pc = @abs(p - c);
    if (pa <= pb and pa <= pc) return a;
    return if (pb <= pc) b else c;
}

fn chunk(out: *std.Io.Writer, tag: *const [4]u8, data: []const u8) !void {
    var len: [4]u8 = undefined;
    std.mem.writeInt(u32, &len, @intCast(data.len), .big);
    try out.writeAll(&len);
    try out.writeAll(tag);
    try out.writeAll(data);
    var crc: std.hash.Crc32 = .init();
    crc.update(tag);
    crc.update(data);
    var sum: [4]u8 = undefined;
    std.mem.writeInt(u32, &sum, crc.final(), .big);
    try out.writeAll(&sum);
}

/// Encode top-down premultiplied BGRA8 pixels as an 8-bit RGBA PNG with straight alpha. Each row takes
/// whichever of the five PNG filters leaves the smallest residue, the usual heuristic. The caller owns
/// the result.
pub fn encodePng(gpa: std.mem.Allocator, bgra: []const u8, w: u32, h: u32) ![]u8 {
    std.debug.assert(bgra.len >= @as(usize, w) * h * 4);
    const stride = @as(usize, w) * 4;

    var idat: std.Io.Writer.Allocating = try .initCapacity(gpa, 64 * 1024);
    defer idat.deinit();
    {
        const window = try gpa.alloc(u8, flate.max_window_len);
        defer gpa.free(window);
        var z = try flate.Compress.init(&idat.writer, window, .zlib, .default);
        const rows = try gpa.alloc(u8, stride * 3 + 1);
        defer gpa.free(rows);
        const cur = rows[0..stride];
        const prev = rows[stride .. stride * 2];
        const best = rows[stride * 2 .. stride * 3 + 1];
        var trial: [5][]u8 = undefined;
        const scratch = try gpa.alloc(u8, stride * 5);
        defer gpa.free(scratch);
        for (&trial, 0..) |*t, i| t.* = scratch[i * stride ..][0..stride];
        @memset(prev, 0);
        for (0..h) |y| {
            for (0..w) |x| cur[x * 4 ..][0..4].* = straight(bgra[y * stride + x * 4 ..][0..4]);
            var sums: [5]u64 = @splat(0);
            for (0..stride) |i| {
                const a: u8 = if (i >= 4) cur[i - 4] else 0;
                const b: u8 = prev[i];
                const c: u8 = if (i >= 4) prev[i - 4] else 0;
                const v = cur[i];
                trial[0][i] = v;
                trial[1][i] = v -% a;
                trial[2][i] = v -% b;
                trial[3][i] = v -% @as(u8, @intCast((@as(u16, a) + b) / 2));
                trial[4][i] = v -% paeth(a, b, c);
                inline for (0..5) |f| {
                    const s: i8 = @bitCast(trial[f][i]);
                    sums[f] += @abs(@as(i16, s));
                }
            }
            var pick: usize = 0;
            for (1..5) |f| {
                if (sums[f] < sums[pick]) pick = f;
            }
            best[0] = @intCast(pick);
            @memcpy(best[1..], trial[pick]);
            try z.writer.writeAll(best);
            @memcpy(prev, cur);
        }
        try z.finish();
    }

    var out: std.Io.Writer.Allocating = try .initCapacity(gpa, idat.written().len + 128);
    errdefer out.deinit();
    try out.writer.writeAll("\x89PNG\r\n\x1a\n");
    var ihdr: [13]u8 = undefined;
    std.mem.writeInt(u32, ihdr[0..4], w, .big);
    std.mem.writeInt(u32, ihdr[4..8], h, .big);
    ihdr[8..13].* = .{ 8, 6, 0, 0, 0 }; // 8 bits, RGBA, deflate, adaptive filtering, not interlaced
    try chunk(&out.writer, "IHDR", &ihdr);
    try chunk(&out.writer, "IDAT", idat.written());
    try chunk(&out.writer, "IEND", "");
    return out.toOwnedSlice();
}

/// Scale premultiplied BGRA8 down from `sw` by `sh` to `dw` by `dh` by averaging the source area each
/// destination pixel covers, with partial coverage at the edges of that area. Averaging premultiplied
/// values is what keeps a transparent border from darkening the edge of the shape.
pub fn downscale(gpa: std.mem.Allocator, src: []const u8, sw: u32, sh: u32, dw: u32, dh: u32) ![]u8 {
    std.debug.assert(dw <= sw and dh <= sh and src.len >= @as(usize, sw) * sh * 4);
    const dst = try gpa.alloc(u8, @as(usize, dw) * dh * 4);
    const fx = @as(f64, @floatFromInt(sw)) / @as(f64, @floatFromInt(dw));
    const fy = @as(f64, @floatFromInt(sh)) / @as(f64, @floatFromInt(dh));
    for (0..dh) |y| {
        const y0 = @as(f64, @floatFromInt(y)) * fy;
        const y1 = y0 + fy;
        for (0..dw) |x| {
            const x0 = @as(f64, @floatFromInt(x)) * fx;
            const x1 = x0 + fx;
            var acc: [4]f64 = @splat(0);
            var sy: usize = @intFromFloat(@floor(y0));
            while (sy < sh and @as(f64, @floatFromInt(sy)) < y1) : (sy += 1) {
                const wy = @min(y1, @as(f64, @floatFromInt(sy + 1))) - @max(y0, @as(f64, @floatFromInt(sy)));
                var sx: usize = @intFromFloat(@floor(x0));
                while (sx < sw and @as(f64, @floatFromInt(sx)) < x1) : (sx += 1) {
                    const wx = @min(x1, @as(f64, @floatFromInt(sx + 1))) - @max(x0, @as(f64, @floatFromInt(sx)));
                    const p = src[(sy * sw + sx) * 4 ..][0..4];
                    for (0..4) |c| acc[c] += @as(f64, @floatFromInt(p[c])) * wx * wy;
                }
            }
            const area = fx * fy;
            for (0..4) |c| dst[(y * dw + x) * 4 + c] = @intFromFloat(@min(255.0, @round(acc[c] / area)));
        }
    }
    return dst;
}

/// The sizes a Windows icon carries: the shell picks 16, 20, 24, 32, 40, 48 and 64 for small and medium
/// views at the usual display scales, and 256 for the large ones.
pub const ico_sizes = [_]u32{ 16, 20, 24, 32, 40, 48, 64, 128, 256 };

/// Build a Windows .ico from a square premultiplied BGRA8 master of `n` pixels a side, which must be at
/// least 256. The 256-pixel image is stored as PNG and the smaller ones as 32-bit bitmaps with their
/// 1-bit masks, which is the combination every version of the shell that reads .ico accepts. The caller
/// owns the result.
pub fn encodeIco(gpa: std.mem.Allocator, master: []const u8, n: u32) ![]u8 {
    std.debug.assert(n >= 256);
    var images: [ico_sizes.len][]u8 = undefined;
    var made: usize = 0;
    defer for (images[0..made]) |im| gpa.free(im);
    for (ico_sizes) |size| {
        const px = try downscale(gpa, master, n, n, size, size);
        defer gpa.free(px);
        images[made] = if (size >= 256) try encodePng(gpa, px, size, size) else try icoBitmap(gpa, px, size);
        made += 1;
    }
    var total: usize = 6 + 16 * ico_sizes.len;
    for (images[0..made]) |im| total += im.len;
    const out = try gpa.alloc(u8, total);
    @memset(out[0..6], 0);
    std.mem.writeInt(u16, out[2..4], 1, .little); // type: icon
    std.mem.writeInt(u16, out[4..6], ico_sizes.len, .little);
    var offset: usize = 6 + 16 * ico_sizes.len;
    for (ico_sizes, 0..) |size, i| {
        const e = out[6 + 16 * i ..][0..16];
        e[0] = @truncate(size); // 256 is written as 0
        e[1] = @truncate(size);
        e[2] = 0; // no palette
        e[3] = 0;
        std.mem.writeInt(u16, e[4..6], 1, .little); // planes
        std.mem.writeInt(u16, e[6..8], 32, .little); // bits per pixel
        std.mem.writeInt(u32, e[8..12], @intCast(images[i].len), .little);
        std.mem.writeInt(u32, e[12..16], @intCast(offset), .little);
        @memcpy(out[offset..][0..images[i].len], images[i]);
        offset += images[i].len;
    }
    return out;
}

/// One icon image in the bitmap form: a BITMAPINFOHEADER whose height counts the colour rows and the mask
/// rows, the colour rows bottom-up as straight BGRA, then a 1-bit mask (set where the pixel is fully
/// transparent) with rows padded to 32 bits.
fn icoBitmap(gpa: std.mem.Allocator, premul: []const u8, size: u32) ![]u8 {
    const mask_stride = ((size + 31) / 32) * 4;
    const len = 40 + size * size * 4 + mask_stride * size;
    const out = try gpa.alloc(u8, len);
    @memset(out, 0);
    std.mem.writeInt(u32, out[0..4], 40, .little);
    std.mem.writeInt(i32, out[4..8], @intCast(size), .little);
    std.mem.writeInt(i32, out[8..12], @intCast(size * 2), .little);
    std.mem.writeInt(u16, out[12..14], 1, .little);
    std.mem.writeInt(u16, out[14..16], 32, .little);
    std.mem.writeInt(u32, out[20..24], size * size * 4 + mask_stride * size, .little);
    const mask = out[40 + size * size * 4 ..];
    for (0..size) |y| {
        const row = size - 1 - y; // bottom-up
        for (0..size) |x| {
            const rgba = straight(premul[(y * size + x) * 4 ..][0..4]);
            out[40 + (row * size + x) * 4 ..][0..4].* = .{ rgba[2], rgba[1], rgba[0], rgba[3] };
            if (rgba[3] == 0) mask[row * mask_stride + x / 8] |= @as(u8, 0x80) >> @intCast(x % 8);
        }
    }
    return out;
}

// ---------------------------------------------------------------------------- tests

/// Decode a PNG this file wrote: undo the filters and return straight RGBA.
fn decodePng(gpa: std.mem.Allocator, png: []const u8, w: u32, h: u32) ![]u8 {
    try std.testing.expectEqualSlices(u8, "\x89PNG\r\n\x1a\n", png[0..8]);
    var pos: usize = 8;
    var idat: []const u8 = &.{};
    var seen_end = false;
    while (pos + 12 <= png.len) {
        const len = std.mem.readInt(u32, png[pos..][0..4], .big);
        const tag = png[pos + 4 ..][0..4];
        const data = png[pos + 8 ..][0..len];
        var crc: std.hash.Crc32 = .init();
        crc.update(tag);
        crc.update(data);
        try std.testing.expectEqual(crc.final(), std.mem.readInt(u32, png[pos + 8 + len ..][0..4], .big));
        if (std.mem.eql(u8, tag, "IHDR")) {
            try std.testing.expectEqual(w, std.mem.readInt(u32, data[0..4], .big));
            try std.testing.expectEqual(h, std.mem.readInt(u32, data[4..8], .big));
            try std.testing.expectEqualSlices(u8, &.{ 8, 6, 0, 0, 0 }, data[8..13]);
        }
        if (std.mem.eql(u8, tag, "IDAT")) idat = data;
        if (std.mem.eql(u8, tag, "IEND")) seen_end = true;
        pos += 12 + len;
    }
    try std.testing.expect(seen_end and pos == png.len);
    const stride = @as(usize, w) * 4;
    var in: std.Io.Reader = .fixed(idat);
    var window: [flate.max_window_len]u8 = undefined;
    var z: flate.Decompress = .init(&in, .zlib, &window);
    const raw = try z.reader.allocRemaining(gpa, .unlimited);
    defer gpa.free(raw);
    try std.testing.expectEqual((stride + 1) * h, raw.len);
    const out = try gpa.alloc(u8, stride * h);
    for (0..h) |y| {
        const filter = raw[y * (stride + 1)];
        const line = raw[y * (stride + 1) + 1 ..][0..stride];
        for (0..stride) |i| {
            const a: u8 = if (i >= 4) out[y * stride + i - 4] else 0;
            const b: u8 = if (y > 0) out[(y - 1) * stride + i] else 0;
            const c: u8 = if (y > 0 and i >= 4) out[(y - 1) * stride + i - 4] else 0;
            out[y * stride + i] = line[i] +% switch (filter) {
                0 => @as(u8, 0),
                1 => a,
                2 => b,
                3 => @as(u8, @intCast((@as(u16, a) + b) / 2)),
                4 => paeth(a, b, c),
                else => return error.BadFilter,
            };
        }
    }
    return out;
}

test "a PNG decodes back to the pixels it was given, alpha un-premultiplied" {
    const gpa = std.testing.allocator;
    const w = 37;
    const h = 23;
    var px: [w * h * 4]u8 = undefined;
    var rng: std.Random.DefaultPrng = .init(7);
    for (0..w * h) |i| {
        // A gradient with noise on it and three kinds of alpha, premultiplied as the renderer leaves it.
        const a: u32 = switch (i % 5) {
            0 => 0,
            1, 2 => 255,
            else => 1 + rng.random().uintLessThan(u32, 254),
        };
        for (0..3) |c| {
            const v: u32 = (@as(u32, @intCast(i)) * (3 + @as(u32, @intCast(c))) + rng.random().uintLessThan(u32, 9)) % 256;
            px[i * 4 + c] = @intCast((v * a + 127) / 255);
        }
        px[i * 4 + 3] = @intCast(a);
    }
    const png = try encodePng(gpa, &px, w, h);
    defer gpa.free(png);
    const rgba = try decodePng(gpa, png, w, h);
    defer gpa.free(rgba);
    for (0..w * h) |i| {
        const want = straight(px[i * 4 ..][0..4]);
        try std.testing.expectEqualSlices(u8, &want, rgba[i * 4 ..][0..4]);
    }
    // Opaque pixels come through exactly, with red and blue in PNG order.
    try std.testing.expectEqual(straight(&.{ 10, 20, 30, 255 }), [4]u8{ 30, 20, 10, 255 });
    try std.testing.expectEqual(straight(&.{ 64, 0, 128, 128 }), [4]u8{ 255, 0, 128, 128 });
}

test "a flat image compresses, and a BMP header describes top-down 32-bit rows" {
    const gpa = std.testing.allocator;
    const px = try gpa.alloc(u8, 256 * 256 * 4);
    defer gpa.free(px);
    @memset(px, 0x80);
    const png = try encodePng(gpa, px, 256, 256);
    defer gpa.free(png);
    try std.testing.expect(png.len < 4096);

    const hdr = bmpHeader(1600, 1000);
    try std.testing.expectEqualSlices(u8, "BM", hdr[0..2]);
    try std.testing.expectEqual(@as(u32, 54 + 1600 * 1000 * 4), std.mem.readInt(u32, hdr[2..6], .little));
    try std.testing.expectEqual(@as(i32, 1600), std.mem.readInt(i32, hdr[18..22], .little));
    try std.testing.expectEqual(@as(i32, -1000), std.mem.readInt(i32, hdr[22..26], .little));
    try std.testing.expectEqual(@as(u16, 32), std.mem.readInt(u16, hdr[28..30], .little));
}

test "downscaling averages areas, also when the ratio is not whole" {
    const gpa = std.testing.allocator;
    // 4x4 to 2x2: each output pixel is the mean of a 2x2 block.
    var src: [4 * 4 * 4]u8 = undefined;
    for (0..16) |i| src[i * 4 ..][0..4].* = @splat(@intCast(i * 16));
    const half = try downscale(gpa, &src, 4, 4, 2, 2);
    defer gpa.free(half);
    try std.testing.expectEqual(@as(u8, (0 + 16 + 64 + 80) / 4), half[0]);
    try std.testing.expectEqual(@as(u8, (160 + 176 + 224 + 240) / 4), half[3 * 4]);
    // 3x1 to 2x1: each output pixel covers one and a half source pixels.
    const row = [_]u8{ 0, 0, 0, 0, 90, 90, 90, 90, 240, 240, 240, 240 };
    const two = try downscale(gpa, &row, 3, 1, 2, 1);
    defer gpa.free(two);
    try std.testing.expectEqual(@as(u8, 30), two[0]); // (0 * 1 + 90 * 0.5) / 1.5
    try std.testing.expectEqual(@as(u8, 190), two[4]); // (90 * 0.5 + 240 * 1) / 1.5
    // A constant image stays constant at any ratio.
    const flat = try gpa.alloc(u8, 100 * 100 * 4);
    defer gpa.free(flat);
    @memset(flat, 77);
    const small = try downscale(gpa, flat, 100, 100, 24, 24);
    defer gpa.free(small);
    for (small) |v| try std.testing.expectEqual(@as(u8, 77), v);
}

test "an .ico lists every size, each entry pointing at a bitmap or a PNG of that size" {
    const gpa = std.testing.allocator;
    const n = 256;
    const master = try gpa.alloc(u8, n * n * 4);
    defer gpa.free(master);
    // An opaque disc on a transparent ground, premultiplied.
    for (0..n) |y| for (0..n) |x| {
        const dx = @as(f32, @floatFromInt(x)) - 127.5;
        const dy = @as(f32, @floatFromInt(y)) - 127.5;
        const inside = dx * dx + dy * dy < 100 * 100;
        master[(y * n + x) * 4 ..][0..4].* = if (inside) .{ 200, 100, 50, 255 } else .{ 0, 0, 0, 0 };
    };
    const ico = try encodeIco(gpa, master, n);
    defer gpa.free(ico);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 1, 0, ico_sizes.len, 0 }, ico[0..6]);
    var end: usize = 6 + 16 * ico_sizes.len;
    for (ico_sizes, 0..) |size, i| {
        const e = ico[6 + 16 * i ..][0..16];
        try std.testing.expectEqual(@as(u8, @truncate(size)), e[0]);
        try std.testing.expectEqual(@as(u16, 32), std.mem.readInt(u16, e[6..8], .little));
        const len = std.mem.readInt(u32, e[8..12], .little);
        const off = std.mem.readInt(u32, e[12..16], .little);
        try std.testing.expectEqual(end, @as(usize, off));
        end += len;
        const body = ico[off..][0..len];
        if (size >= 256) {
            try std.testing.expectEqualSlices(u8, "\x89PNG", body[0..4]);
            try std.testing.expectEqual(size, std.mem.readInt(u32, body[16..20], .big));
        } else {
            try std.testing.expectEqual(@as(u32, 40), std.mem.readInt(u32, body[0..4], .little));
            try std.testing.expectEqual(@as(i32, @intCast(size)), std.mem.readInt(i32, body[4..8], .little));
            try std.testing.expectEqual(@as(i32, @intCast(size * 2)), std.mem.readInt(i32, body[8..12], .little));
            // The centre is the disc's colour, opaque; the bottom-left corner (first row stored) is clear
            // and masked out.
            const mid = body[40 + ((size / 2) * size + size / 2) * 4 ..][0..4];
            try std.testing.expectEqualSlices(u8, &.{ 200, 100, 50, 255 }, mid);
            try std.testing.expectEqual(@as(u8, 0), body[40 + 3]);
            const mask = body[40 + size * size * 4 ..];
            try std.testing.expect(mask[0] & 0x80 != 0);
            const mask_stride = ((size + 31) / 32) * 4;
            const centre_bit = mask[(size / 2) * mask_stride + (size / 2) / 8] & (@as(u8, 0x80) >> @intCast((size / 2) % 8));
            try std.testing.expectEqual(@as(u8, 0), centre_bit);
        }
    }
    try std.testing.expectEqual(ico.len, end);
}
