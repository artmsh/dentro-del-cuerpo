//! The textures the OpenGL ES backend can draw the materials' patterns from instead of computing them
//! in the fragment shader: the lattice of the value noise, a tile of the cell pattern, the four-octave sum
//! of the noise (`fbm`) as a volume of its own, and a square of film grain. The shader's value noise hashes eight lattice points for every sample and its
//! cell pattern visits thirty-five cells; a vessel wall takes nine samples of the one and one of the
//! other at every pixel, which is more arithmetic than the television's GPU (a Mali-G51) can do sixty
//! thousand times a millisecond. Baked, a noise sample is one filtered fetch and a cell pattern is one
//! or two.
//!
//! All are made with the shader's own hashes, so the patterns have the character they have on the
//! other backends. What differs is that they repeat: the noise every `noise_n` lattice points along
//! each axis, the cells every `cell_period` cells and the summed noise every `fbm_period` units, where
//! the computed ones never do.

const std = @import("std");

/// Lattice points along each axis of the noise volume.
pub const noise_n = 64;
/// Cells along each side of the cell tile, and texels across one cell.
pub const cell_period = 32;
pub const cell_px = 16;
pub const cell_size = cell_period * cell_px;
/// The tile stores the distance to the nearest cell centre divided by this, so that the largest
/// distance a jittered grid produces fits in a byte.
pub const centre_range = 1.5;

/// `hash1` of shaders.glsl at a lattice point.
pub fn hash1(x: i32, y: i32, z: i32) f32 {
    var v: [3]u32 = .{ @bitCast(x), @bitCast(y), @bitCast(z) };
    for (&v) |*c| c.* = c.* *% 1664525 +% 1013904223;
    inline for (0..2) |round| {
        v[0] +%= v[1] *% v[2];
        v[1] +%= v[2] *% v[0];
        v[2] +%= v[0] *% v[1];
        if (round == 0) for (&v) |*c| {
            c.* ^= c.* >> 16;
        };
    }
    return @as(f32, @floatFromInt(v[0] >> 8)) * (1.0 / 16777216.0);
}

/// `hash2` of shaders.glsl at a cell.
pub fn hash2(x: i32, y: i32) [2]f32 {
    var v: [2]u32 = .{ @bitCast(x), @bitCast(y) };
    for (&v) |*c| c.* = c.* *% 1664525 +% 1013904223;
    inline for (0..2) |_| {
        v[0] +%= v[1] *% 1664525;
        v[1] +%= v[0] *% 1664525;
        for (&v) |*c| c.* ^= c.* >> 16;
    }
    return .{ @as(f32, @floatFromInt(v[0] >> 8)) * (1.0 / 16777216.0), @as(f32, @floatFromInt(v[1] >> 8)) * (1.0 / 16777216.0) };
}

fn byte(x: f32) u8 {
    return @intFromFloat(@round(std.math.clamp(x, 0, 1) * 255));
}

/// The noise volume: one byte per lattice point, x fastest, then y, then z. Sampled with linear
/// filtering and wrapping at a lattice coordinate plus half a texel, it interpolates the eight
/// surrounding hashes as `vnoise` does.
pub fn bakeNoise(out: []u8) void {
    std.debug.assert(out.len == noise_n * noise_n * noise_n);
    var i: usize = 0;
    for (0..noise_n) |z| for (0..noise_n) |y| for (0..noise_n) |x| {
        out[i] = byte(hash1(@intCast(x), @intCast(y), @intCast(z)));
        i += 1;
    };
}

/// Texels a side of the film grain's noise.
pub const grain_n = 256;

/// The film grain's noise: `hash1` at every texel, one byte each, row by row.
pub fn bakeGrain(out: []u8) void {
    std.debug.assert(out.len == grain_n * grain_n);
    for (0..grain_n) |y| for (0..grain_n) |x| {
        out[y * grain_n + x] = byte(hash1(@intCast(x), @intCast(y), 0));
    };
}

/// Texels a side of the fbm volume, and the lattice cells of its first octave it repeats over.
pub const fbm_n = 128;
pub const fbm_period = 8;
/// The most `fbm` of shaders.glsl returns: four octaves, each half the last, the first a half.
pub const fbm_range = 0.9375;

/// The fbm volume: the four octaves of noise `fbm` sums, already summed, one byte per texel (the sum over
/// `fbm_range`), x fastest. Each octave has twice the last one's frequency, exactly, where the computed
/// one has 2.03 times and an offset: that is what lets the volume repeat, and the result is the same kind
/// of pattern, not the same pattern. A material reads it with one filtered fetch where it would read the
/// noise volume four times.
pub fn bakeFbm(gpa: std.mem.Allocator, out: []u8) !void {
    std.debug.assert(out.len == fbm_n * fbm_n * fbm_n);
    const octaves = 4;
    const sum = try gpa.alloc(f32, out.len);
    defer gpa.free(sum);
    @memset(sum, 0);
    var amp: f32 = 0.5;
    inline for (0..octaves) |k| {
        // The octave's lattice, one period of it, hashed with an offset of its own.
        const cells: usize = fbm_period << k;
        const lattice = try gpa.alloc(f32, cells * cells * cells);
        defer gpa.free(lattice);
        for (0..cells) |z| for (0..cells) |y| for (0..cells) |x| {
            lattice[(z * cells + y) * cells + x] = hash1(@intCast(x + 977 * k), @intCast(y), @intCast(z + 131 * k));
        };
        // Texel centres in the octave's lattice: where along each axis, and with what smoothed weight.
        const step = @as(f32, @floatFromInt(cells)) / fbm_n;
        var lo_at: [fbm_n]usize = undefined;
        var hi_at: [fbm_n]usize = undefined;
        var w: [fbm_n]f32 = undefined;
        for (0..fbm_n) |t| {
            const at = (@as(f32, @floatFromInt(t)) + 0.5) * step;
            const whole = @floor(at);
            const f = at - whole;
            lo_at[t] = @as(usize, @intFromFloat(whole)) % cells;
            hi_at[t] = (lo_at[t] + 1) % cells;
            w[t] = f * f * (3 - 2 * f);
        }
        var i: usize = 0;
        for (0..fbm_n) |z| for (0..fbm_n) |y| {
            const r00 = (lo_at[z] * cells + lo_at[y]) * cells;
            const r01 = (lo_at[z] * cells + hi_at[y]) * cells;
            const r10 = (hi_at[z] * cells + lo_at[y]) * cells;
            const r11 = (hi_at[z] * cells + hi_at[y]) * cells;
            for (0..fbm_n) |x| {
                const a = lattice[r00 + lo_at[x]] + (lattice[r00 + hi_at[x]] - lattice[r00 + lo_at[x]]) * w[x];
                const b = lattice[r01 + lo_at[x]] + (lattice[r01 + hi_at[x]] - lattice[r01 + lo_at[x]]) * w[x];
                const c = lattice[r10 + lo_at[x]] + (lattice[r10 + hi_at[x]] - lattice[r10 + lo_at[x]]) * w[x];
                const d = lattice[r11 + lo_at[x]] + (lattice[r11 + hi_at[x]] - lattice[r11 + lo_at[x]]) * w[x];
                const lo = a + (b - a) * w[y];
                const hi = c + (d - c) * w[y];
                sum[i] += amp * (lo + (hi - lo) * w[z]);
                i += 1;
            }
        };
        amp *= 0.5;
    }
    for (out, sum) |*o, v| o.* = byte(v / fbm_range);
}

/// The cell tile, RGBA8, row by row: what `voronoi` of shaders.glsl returns at each texel's centre for
/// a pattern that repeats every `cell_period` cells both ways. Red is the distance to the nearest cell
/// centre over `centre_range`, green the distance to the cell's border, blue the cell's own hash.
pub fn bakeCells(out: []u8) void {
    std.debug.assert(out.len == cell_size * cell_size * 4);
    // Where each cell's centre sits within the cell.
    var jitter: [cell_period][cell_period][2]f32 = undefined;
    for (0..cell_period) |cy| for (0..cell_period) |cx| {
        jitter[cy][cx] = hash2(@intCast(cx), @intCast(cy));
    };
    const wrap = struct {
        fn f(c: i32) usize {
            return @intCast(@mod(c, cell_period));
        }
    }.f;
    for (0..cell_size) |ty| for (0..cell_size) |tx| {
        const nx: i32 = @intCast(tx / cell_px);
        const ny: i32 = @intCast(ty / cell_px);
        const fx = (@as(f32, @floatFromInt(tx % cell_px)) + 0.5) / cell_px;
        const fy = (@as(f32, @floatFromInt(ty % cell_px)) + 0.5) / cell_px;
        // The nearest centre, among the cell and its eight neighbours.
        var md: f32 = 8;
        var mr: [2]f32 = .{ 0, 0 };
        var mg: [2]i32 = .{ 0, 0 };
        var j: i32 = -1;
        while (j <= 1) : (j += 1) {
            var i: i32 = -1;
            while (i <= 1) : (i += 1) {
                const o = jitter[wrap(ny + j)][wrap(nx + i)];
                const r = [2]f32{ @as(f32, @floatFromInt(i)) + o[0] - fx, @as(f32, @floatFromInt(j)) + o[1] - fy };
                const d = r[0] * r[0] + r[1] * r[1];
                if (d < md) {
                    md = d;
                    mr = r;
                    mg = .{ i, j };
                }
            }
        }
        // The nearest border: the bisector between that centre and each centre around it.
        var border: f32 = 8;
        j = -2;
        while (j <= 2) : (j += 1) {
            var i: i32 = -2;
            while (i <= 2) : (i += 1) {
                const gx = mg[0] + i;
                const gy = mg[1] + j;
                const o = jitter[wrap(ny + gy)][wrap(nx + gx)];
                const r = [2]f32{ @as(f32, @floatFromInt(gx)) + o[0] - fx, @as(f32, @floatFromInt(gy)) + o[1] - fy };
                const dx = r[0] - mr[0];
                const dy = r[1] - mr[1];
                const len2 = dx * dx + dy * dy;
                if (len2 > 0.00001) {
                    const inv = 1 / @sqrt(len2);
                    border = @min(border, (0.5 * (mr[0] + r[0])) * dx * inv + (0.5 * (mr[1] + r[1])) * dy * inv);
                }
            }
        }
        const at = (ty * cell_size + tx) * 4;
        out[at + 0] = byte(@sqrt(md) / centre_range);
        out[at + 1] = byte(border);
        out[at + 2] = byte(jitter[wrap(ny + mg[1])][wrap(nx + mg[0])][0]);
        out[at + 3] = 255;
    };
}

// ---------------------------------------------------------------------------------------------- tests

test "the hashes are in [0, 1), differ between neighbours and fill the range" {
    var lo: f32 = 1;
    var hi: f32 = 0;
    var sum: f64 = 0;
    for (0..32) |z| for (0..32) |y| for (0..32) |x| {
        const h = hash1(@intCast(x), @intCast(y), @intCast(z));
        try std.testing.expect(h >= 0 and h < 1);
        lo = @min(lo, h);
        hi = @max(hi, h);
        sum += h;
    };
    try std.testing.expect(lo < 0.01 and hi > 0.99);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), sum / (32 * 32 * 32), 0.01);
    try std.testing.expect(hash1(3, 4, 5) != hash1(4, 4, 5) and hash1(3, 4, 5) != hash1(3, 5, 5) and hash1(3, 4, 5) != hash1(3, 4, 6));
    // Negative lattice points hash as the shader's conversion to unsigned makes them.
    try std.testing.expect(hash1(-1, 0, 0) >= 0 and hash1(-1, 0, 0) != hash1(1, 0, 0));
    const a = hash2(7, 9);
    const b = hash2(8, 9);
    try std.testing.expect(a[0] >= 0 and a[0] < 1 and a[1] >= 0 and a[1] < 1);
    try std.testing.expect(a[0] != b[0] and a[1] != b[1] and a[0] != a[1]);
}

test "the cell tile is a cell pattern that closes on itself" {
    const gpa = std.testing.allocator;
    const px = try gpa.alloc(u8, cell_size * cell_size * 4);
    defer gpa.free(px);
    bakeCells(px);
    const at = struct {
        fn f(p: []const u8, x: usize, y: usize, c: usize) f32 {
            return @as(f32, @floatFromInt(p[((y % cell_size) * cell_size + (x % cell_size)) * 4 + c])) / 255.0;
        }
    }.f;
    var on_border: usize = 0;
    var at_centre: usize = 0;
    var worst_seam: f32 = 0;
    for (0..cell_size) |y| {
        for (0..cell_size) |x| {
            const centre = at(px, x, y, 0) * centre_range;
            const border = at(px, x, y, 1);
            // Inside a cell both distances are positive, and a point is never farther from its border
            // than a cell is wide.
            try std.testing.expect(border <= 1.0 and centre <= centre_range);
            if (border < 0.02) on_border += 1;
            if (centre < 0.05) at_centre += 1;
            // The distance to the border is continuous, and so it is across the tile's edges, where a
            // texel's neighbour is the one on the opposite side.
            const step = @abs(border - at(px, x + 1, y, 1));
            if (x == cell_size - 1) worst_seam = @max(worst_seam, step);
            try std.testing.expect(step < 1.5 / @as(f32, cell_px) + 2.0 / 255.0);
        }
    }
    try std.testing.expect(worst_seam < 1.5 / @as(f32, cell_px) + 2.0 / 255.0);
    // Every cell has a border and a centre: about cell_period² of each, spread over the tile.
    try std.testing.expect(on_border > cell_period * cell_period * 4);
    try std.testing.expect(at_centre > cell_period * cell_period / 2);
}

test "the noise volume holds the lattice hashes" {
    const gpa = std.testing.allocator;
    const v = try gpa.alloc(u8, noise_n * noise_n * noise_n);
    defer gpa.free(v);
    bakeNoise(v);
    try std.testing.expectEqual(byte(hash1(5, 6, 7)), v[(7 * noise_n + 6) * noise_n + 5]);
    try std.testing.expectEqual(byte(hash1(0, 0, 0)), v[0]);
}

test "the fbm volume fills its range evenly and closes on itself" {
    const gpa = std.testing.allocator;
    const px = try gpa.alloc(u8, fbm_n * fbm_n * fbm_n);
    defer gpa.free(px);
    try bakeFbm(gpa, px);
    var total: f64 = 0;
    var inside: f64 = 0;
    var seam: f64 = 0;
    for (0..fbm_n) |z| for (0..fbm_n) |y| {
        const row = px[(z * fbm_n + y) * fbm_n ..][0..fbm_n];
        for (row) |v| total += @floatFromInt(v);
        // The step across the wrap is no larger than a step between neighbours inside.
        inside += @abs(@as(f64, @floatFromInt(row[1])) - @as(f64, @floatFromInt(row[0])));
        seam += @abs(@as(f64, @floatFromInt(row[0])) - @as(f64, @floatFromInt(row[fbm_n - 1])));
    };
    try std.testing.expectApproxEqAbs(@as(f64, 127.5), total / (fbm_n * fbm_n * fbm_n), 4);
    try std.testing.expect(seam < inside * 1.3);
}
