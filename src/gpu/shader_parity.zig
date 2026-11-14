//! Holds the three shader files together. `shaders.metal`, `shaders.hlsl` and `shaders.glsl` are the same
//! program in three dialects, ported by hand, and a change to the lighting in one that is not made in the
//! others would leave the platforms looking different with nothing to say so. The tests here read the
//! sources and require that they declare the same functions in the same order, and that the functions
//! with no platform-specific plumbing in them (the noise helpers, the whole of the scene's fragment
//! function, the particle and post-processing fragment functions) are the same text once the Metal
//! spelling is rewritten in the other dialect's. They run on any machine, since they only compare text.
//!
//! The GLSL file holds more than the other two: a second set of the pattern functions that read baked
//! textures (the television uses those), a `main` for each stage, and the pass that scales the scene up
//! to the output. The comparison takes the last definition of each name, which is the computed one, and
//! leaves the rest alone.

const std = @import("std");

const metal = @embedFile("../shaders/shaders.metal");
const hlsl = @embedFile("../shaders/shaders.hlsl");
const glsl = @embedFile("../shaders/shaders.glsl");

/// Functions whose bodies must match line for line. The vertex functions and the HUD's fragment function
/// are left out: they are a few lines each and differ in how a stage reaches its buffers, which is the
/// part of a port that cannot be the same.
const shared_bodies = [_][]const u8{ "hash1", "vnoise", "fbm", "hash2", "cellHash", "voronoi", "scene_fs", "part_fs", "aces", "post_fs" };

/// Whole lines that are allowed to differ, Metal first. Everything else that differs between the dialects
/// is covered by the spelling rules in `toHlsl`.
const line_exceptions = [_][2][]const u8{
    // HLSL has no one-argument vector constructor; a scalar exponent is applied to each component.
    .{ "col = pow(saturate(col), float3(1.0 / 2.2));", "col = pow(saturate(col), 1.0 / 2.2);" },
};

/// The same for the GLSL file, Metal first. GLSL converts with constructors where Metal casts, has no
/// implicit conversion from an integer literal to a vector, and its post-processing leaves the grain and
/// the fade to the scaling pass when one follows (`last_pass` is 0 then).
const glsl_exceptions = [_][2][]const u8{
    .{ "return (float)(v.x >> 8) * (1.0 / 16777216.0);", "return float(v.x >> 8) * (1.0 / 16777216.0);" },
    .{ "if (period > 0.5) c.x = (float)((uint)(int)(c.x + period * 8.0) % (uint)max(period, 1.0));", "if (period > 0.5) c.x = float(uint(int(c.x + period * 8.0)) % uint(max(period, 1.0)));" },
    .{ "float2 mg = 0, mr = 0;", "float2 mg = float2(0.0), mr = float2(0.0);" },
    .{ "float3 col = 0;", "float3 col = float3(0.0);" },
    .{ "float tot = 0;", "float tot = 0.0;" },
    .{ "float3 bloom = 0;", "float3 bloom = float3(0.0);" },
    .{ "col += (g - 0.5) * 0.018;", "col += (g - 0.5) * 0.018 * last_pass;" },
    .{ "col *= po.b.y;", "col *= mix(1.0, po.b.y, last_pass);" },
};

const Function = struct {
    name: []const u8,
    /// The lines between the braces, trimmed, without comments or blank lines.
    body: []const []const u8,
};

fn stripComment(line: []const u8) []const u8 {
    const cut = std.mem.indexOf(u8, line, "//") orelse line.len;
    return std.mem.trim(u8, line[0..cut], " \t\r");
}

fn isIdent(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

/// The functions of a shader source, in order. A function starts at a line outside any braces that has a
/// parenthesis and is not a declaration ending in a semicolon; its name is the identifier before the
/// first parenthesis.
fn parse(arena: std.mem.Allocator, src: []const u8) ![]Function {
    var out: std.ArrayList(Function) = .empty;
    var body: std.ArrayList([]const u8) = .empty;
    var depth: usize = 0;
    var name: ?[]const u8 = null;
    var in_header = false;
    var lines = std.mem.splitScalar(u8, src, '\n');
    while (lines.next()) |raw| {
        const line = stripComment(raw);
        if (line.len == 0) continue;
        const opens = std.mem.count(u8, line, "{");
        const closes = std.mem.count(u8, line, "}");
        if (depth == 0 and name == null and !in_header) {
            const paren = std.mem.indexOfScalar(u8, line, '(');
            const declaration = line[line.len - 1] == ';' or std.mem.startsWith(u8, line, "cbuffer") or std.mem.startsWith(u8, line, "struct") or std.mem.startsWith(u8, line, "layout") or line[0] == '#';
            if (paren != null and !declaration) {
                var start = paren.?;
                while (start > 0 and isIdent(line[start - 1])) start -= 1;
                name = line[start..paren.?];
                in_header = true;
            }
        }
        if (name != null) {
            if (in_header) {
                // A function written on one line (the `main` of a GLSL stage).
                if (depth == 0 and opens > 0 and opens == closes) {
                    const open = std.mem.indexOfScalar(u8, line, '{').?;
                    const close = std.mem.lastIndexOfScalar(u8, line, '}').?;
                    try body.append(arena, std.mem.trim(u8, line[open + 1 .. close], " \t"));
                    try out.append(arena, .{ .name = name.?, .body = try body.toOwnedSlice(arena) });
                    name = null;
                    in_header = false;
                    continue;
                }
                // The header runs to the line that opens the body.
                if (opens > closes) {
                    in_header = false;
                    depth += opens - closes;
                }
                continue;
            }
            const next_depth = depth + opens - closes;
            if (next_depth == 0) {
                try out.append(arena, .{ .name = name.?, .body = try body.toOwnedSlice(arena) });
                name = null;
            } else {
                try body.append(arena, line);
            }
            depth = next_depth;
        } else {
            depth = depth + opens - closes;
        }
    }
    return out.toOwnedSlice(arena);
}

fn replaceAll(arena: std.mem.Allocator, s: []const u8, from: []const u8, to: []const u8) ![]const u8 {
    return std.mem.replaceOwned(u8, arena, s, from, to);
}

/// `in` is a reserved word in HLSL and in GLSL; the stage input is called IN in both.
fn renameInput(arena: std.mem.Allocator, s: []const u8) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < s.len) {
        if (std.mem.startsWith(u8, s[i..], "in.") and (i == 0 or !isIdent(s[i - 1]))) {
            try buf.appendSlice(arena, "IN.");
            i += 3;
        } else {
            try buf.append(arena, s[i]);
            i += 1;
        }
    }
    return buf.items;
}

/// Texture taps. Metal's `hdr.sample(smp, uv)` leaves the mip level to the sampler and `level(x)` names
/// it; the other files always name it, 0 where Metal leaves it out (see the note on post_fs in the HLSL
/// file). The call becomes `open`, with or without the sampler argument, then the level.
fn renameTaps(arena: std.mem.Allocator, s: []const u8, open: []const u8, keep_sampler: bool) ![]const u8 {
    const call = "hdr.sample(";
    const sampler = "smp, ";
    var buf: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, s, i, call)) |at| {
        try buf.appendSlice(arena, s[i..at]);
        var close = at + call.len;
        var nest: usize = 1;
        while (close < s.len) : (close += 1) {
            if (s[close] == '(') nest += 1;
            if (s[close] == ')') {
                nest -= 1;
                if (nest == 0) break;
            }
        }
        var args = s[at + call.len .. close];
        if (!keep_sampler and std.mem.startsWith(u8, args, sampler)) args = args[sampler.len..];
        try buf.appendSlice(arena, open);
        if (std.mem.indexOf(u8, args, ", level(")) |lv| {
            try buf.appendSlice(arena, args[0..lv]);
            try buf.appendSlice(arena, ", ");
            try buf.appendSlice(arena, args[lv + ", level(".len .. args.len - 1]);
        } else {
            try buf.appendSlice(arena, args);
            try buf.appendSlice(arena, ", 0.0");
        }
        try buf.append(arena, ')');
        i = close + 1;
    }
    try buf.appendSlice(arena, s[i..]);
    return buf.items;
}

/// One line of the Metal file in HLSL's spelling.
fn toHlsl(arena: std.mem.Allocator, line: []const u8) ![]const u8 {
    for (line_exceptions) |e| {
        if (std.mem.eql(u8, line, e[0])) return e[1];
    }
    var s = try replaceAll(arena, line, "fract(", "frac(");
    s = try replaceAll(arena, s, "mix(", "lerp(");
    s = try renameInput(arena, s);
    return renameTaps(arena, s, "hdr.SampleLevel(", true);
}

/// One line of the Metal file in GLSL's spelling. The GLSL file defines Metal's type and function names
/// as macros, so little is left to rewrite.
fn toGlsl(arena: std.mem.Allocator, line: []const u8) ![]const u8 {
    for (glsl_exceptions) |e| {
        if (std.mem.eql(u8, line, e[0])) return e[1];
    }
    const s = try renameInput(arena, line);
    return renameTaps(arena, s, "tap(", false);
}

/// The functions of the GLSL file that the other two also have: no `main`, no `cellTap` (a helper of the
/// baked patterns), and of the pattern functions that are defined twice, the second, computed one.
fn glslShared(arena: std.mem.Allocator, all: []const Function) ![]Function {
    var out: std.ArrayList(Function) = .empty;
    for (all, 0..) |f, i| {
        if (std.mem.eql(u8, f.name, "main") or std.mem.eql(u8, f.name, "cellTap")) continue;
        if (find(all[i + 1 ..], f.name) != null) continue;
        try out.append(arena, f);
    }
    return out.toOwnedSlice(arena);
}

fn find(fns: []const Function, name: []const u8) ?Function {
    for (fns) |f| {
        if (std.mem.eql(u8, f.name, name)) return f;
    }
    return null;
}

test "the shader files declare the same functions in the same order" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const m = try parse(arena, metal);
    const h = try parse(arena, hlsl);
    const g = try glslShared(arena, try parse(arena, glsl));
    const want = [_][]const u8{ "hash1", "vnoise", "fbm", "hash2", "cellHash", "voronoi", "scene_vs", "scene_fs", "part_vs", "part_fs", "post_vs", "aces", "post_fs", "hud_vs", "hud_fs" };
    try std.testing.expectEqual(want.len, m.len);
    try std.testing.expectEqual(want.len, h.len);
    try std.testing.expectEqual(want.len, g.len);
    for (want, m, h, g) |name, mf, hf, gf| {
        try std.testing.expectEqualStrings(name, mf.name);
        try std.testing.expectEqualStrings(name, hf.name);
        try std.testing.expectEqualStrings(name, gf.name);
    }
}

test "the shared shader functions are the same text in both dialects" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const m = try parse(arena, metal);
    const h = try parse(arena, hlsl);
    var different: usize = 0;
    for (shared_bodies) |name| {
        const mf = find(m, name) orelse return error.MissingInMetal;
        const hf = find(h, name) orelse return error.MissingInHlsl;
        if (mf.body.len != hf.body.len) {
            std.debug.print("{s}: {d} lines in shaders.metal, {d} in shaders.hlsl\n", .{ name, mf.body.len, hf.body.len });
            different += 1;
        }
        for (0..@min(mf.body.len, hf.body.len)) |i| {
            const ported = try toHlsl(arena, mf.body[i]);
            if (!std.mem.eql(u8, ported, hf.body[i])) {
                std.debug.print("{s}, line {d} of the body:\n  metal as hlsl: {s}\n  hlsl:          {s}\n", .{ name, i + 1, ported, hf.body[i] });
                different += 1;
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 0), different);
}

test "the shared shader functions are the same text in Metal and GLSL" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const m = try parse(arena, metal);
    const g = try glslShared(arena, try parse(arena, glsl));
    var different: usize = 0;
    for (shared_bodies) |name| {
        const mf = find(m, name) orelse return error.MissingInMetal;
        const gf = find(g, name) orelse return error.MissingInGlsl;
        if (mf.body.len != gf.body.len) {
            std.debug.print("{s}: {d} lines in shaders.metal, {d} in shaders.glsl\n", .{ name, mf.body.len, gf.body.len });
            different += 1;
        }
        for (0..@min(mf.body.len, gf.body.len)) |i| {
            const ported = try toGlsl(arena, mf.body[i]);
            if (!std.mem.eql(u8, ported, gf.body[i])) {
                std.debug.print("{s}, line {d} of the body:\n  metal as glsl: {s}\n  glsl:          {s}\n", .{ name, i + 1, ported, gf.body[i] });
                different += 1;
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 0), different);
}

test "the baked patterns of the GLSL file stand in for the computed ones" {
    // The first definitions of the pattern functions are the baked ones, and they take the same arguments
    // as the computed ones they replace, so the scene's code calls either.
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const all = try parse(arena, glsl);
    for ([_][]const u8{ "vnoise", "fbm", "voronoi" }) |name| {
        var count: usize = 0;
        for (all) |f| count += @intFromBool(std.mem.eql(u8, f.name, name));
        try std.testing.expectEqual(@as(usize, 2), count);
        var headers: [2][]const u8 = undefined;
        var found: usize = 0;
        var lines = std.mem.splitScalar(u8, glsl, '\n');
        while (lines.next()) |raw| {
            const line = stripComment(raw);
            const at = std.mem.indexOf(u8, line, name) orelse continue;
            if (at == 0 or line[at - 1] != ' ' or line[line.len - 1] != '{' or line[0] == ' ') continue;
            if (!std.mem.startsWith(u8, line[at + name.len ..], "(")) continue;
            headers[found] = line;
            found += 1;
        }
        try std.testing.expectEqual(@as(usize, 2), found);
        try std.testing.expectEqualStrings(headers[0], headers[1]);
    }
}

test "the same materials are switched on in every file" {
    // Every `mat == N` of one file appears in the other, the same number of times.
    for (0..16) |id| {
        var needle_buf: [16]u8 = undefined;
        const needle = try std.fmt.bufPrint(&needle_buf, "mat == {d})", .{id});
        try std.testing.expectEqual(std.mem.count(u8, metal, needle), std.mem.count(u8, hlsl, needle));
        try std.testing.expectEqual(std.mem.count(u8, metal, needle), std.mem.count(u8, glsl, needle));
    }
    try std.testing.expect(std.mem.count(u8, hlsl, "mat == 12)") == 1);
}

test "the spelling rules do what they say" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings("float g = lerp(frac(IN.uv.x), sin(x), 0.5);", try toHlsl(arena, "float g = mix(fract(in.uv.x), sin(x), 0.5);"));
    try std.testing.expectEqualStrings("col += hdr.SampleLevel(smp, 0.5 + c * k, 0.0).rgb * w;", try toHlsl(arena, "col += hdr.sample(smp, 0.5 + c * k).rgb * w;"));
    try std.testing.expectEqualStrings("bloom += hdr.SampleLevel(smp, uv, 3.5).rgb * 0.3;", try toHlsl(arena, "bloom += hdr.sample(smp, uv, level(3.5)).rgb * 0.3;"));
    try std.testing.expectEqualStrings("float mainline = margin.x;", try toHlsl(arena, "float mainline = margin.x;"));
    try std.testing.expectEqualStrings("float g = mix(fract(IN.uv.x), sin(x), 0.5);", try toGlsl(arena, "float g = mix(fract(in.uv.x), sin(x), 0.5);"));
    try std.testing.expectEqualStrings("col += tap(0.5 + c * k, 0.0).rgb * w;", try toGlsl(arena, "col += hdr.sample(smp, 0.5 + c * k).rgb * w;"));
    try std.testing.expectEqualStrings("bloom += tap(uv, 3.5).rgb * 0.3;", try toGlsl(arena, "bloom += hdr.sample(smp, uv, level(3.5)).rgb * 0.3;"));
}

/// `hash1` of the shader files, step for step.
fn hash1(p: [3]i32) f32 {
    var v: [3]u32 = undefined;
    for (&v, p) |*o, c| o.* = @as(u32, @bitCast(c)) *% 1664525 +% 1013904223;
    for (0..2) |round| {
        v[0] +%= v[1] *% v[2];
        v[1] +%= v[2] *% v[0];
        v[2] +%= v[0] *% v[1];
        if (round == 0) {
            for (&v) |*o| o.* ^= o.* >> 16;
        }
    }
    return @as(f32, @floatFromInt(v[0] >> 8)) * (1.0 / 16777216.0);
}

/// `hash2` of the shader files, step for step.
fn hash2(p: [2]i32) [2]f32 {
    var v: [2]u32 = undefined;
    for (&v, p) |*o, c| o.* = @as(u32, @bitCast(c)) *% 1664525 +% 1013904223;
    for (0..2) |_| {
        v[0] +%= v[1] *% 1664525;
        v[1] +%= v[0] *% 1664525;
        for (&v) |*o| o.* ^= o.* >> 16;
    }
    return .{ @as(f32, @floatFromInt(v[0] >> 8)) * (1.0 / 16777216.0), @as(f32, @floatFromInt(v[1] >> 8)) * (1.0 / 16777216.0) };
}

test "the hashes are integer arithmetic on whole-number coordinates" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    // A hash built on a sine or on the fraction of a floating-point product depends on how the last bit of
    // its argument is rounded, which differs between GPUs and, on some drivers, between two call sites
    // in one shader: the cell patterns then disagree with themselves. Neither file may go back to that.
    for ([_][]const u8{ metal, hlsl }) |src| {
        const fns = try parse(arena, src);
        for ([_][]const u8{ "hash1", "hash2", "cellHash" }) |name| {
            const f = find(fns, name) orelse return error.MissingFunction;
            for (f.body) |line| {
                for ([_][]const u8{ "sin(", "cos(", "frac(", "fract(", "fmod(", "dot(" }) |call|
                    try std.testing.expect(std.mem.indexOf(u8, line, call) == null);
            }
        }
        try std.testing.expect(std.mem.indexOf(u8, src, "43758.5453") == null);
        for ([_][]const u8{ "1664525u", "1013904223u", "(1.0 / 16777216.0)" }) |c|
            try std.testing.expect(std.mem.indexOf(u8, src, c) != null);
    }
}

/// Mean, variance and the correlation between a value and its neighbour `lag` steps on, for a sequence
/// that should be uniform on [0, 1) and independent.
const Stats = struct {
    n: f64 = 0,
    sum: f64 = 0,
    sq: f64 = 0,
    cross: f64 = 0,

    fn add(s: *Stats, a: f32, b: f32) void {
        s.n += 1;
        s.sum += a;
        s.sq += @as(f64, a) * a;
        s.cross += @as(f64, a) * b;
    }
    fn check(s: Stats) !void {
        const mean = s.sum / s.n;
        try std.testing.expectApproxEqAbs(@as(f64, 0.5), mean, 0.01);
        try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 12.0), s.sq / s.n - mean * mean, 0.003);
        // The covariance of independent values is zero; this many samples leave about 0.0003 of noise.
        try std.testing.expectApproxEqAbs(@as(f64, 0), s.cross / s.n - mean * mean, 0.002);
    }
};

test "the cell hash is uniform and neighbouring cells are unrelated" {
    // Cell coordinates as the materials produce them: small, of either sign.
    const size = 300;
    const steps = [_][2]i32{ .{ 1, 0 }, .{ 0, 1 }, .{ 1, 1 }, .{ 1, -1 }, .{ 2, 0 }, .{ 0, 2 }, .{ 7, 3 } };
    for (steps) |step| {
        var same: Stats = .{};
        var other: Stats = .{};
        var y: i32 = -size / 2;
        while (y < size / 2) : (y += 1) {
            var x: i32 = -size / 2;
            while (x < size / 2) : (x += 1) {
                const a = hash2(.{ x, y });
                const b = hash2(.{ x + step[0], y + step[1] });
                same.add(a[0], b[0]);
                other.add(a[1], b[1]);
            }
        }
        try same.check();
        try other.check();
    }
    // The two numbers of one cell place its centre, so they must not follow one another either.
    var pair: Stats = .{};
    var y: i32 = -size / 2;
    while (y < size / 2) : (y += 1) {
        var x: i32 = -size / 2;
        while (x < size / 2) : (x += 1) {
            const a = hash2(.{ x, y });
            pair.add(a[0], a[1]);
        }
    }
    try pair.check();
}

test "the lattice hash is uniform and unrelated along every axis, the film grain's included" {
    // The film grain is this hash of the pixel and the frame, so a relation between neighbours along x, y,
    // a diagonal or time would show as stripes or as a pattern that stands still.
    const steps = [_][3]i32{ .{ 1, 0, 0 }, .{ 0, 1, 0 }, .{ 0, 0, 1 }, .{ 1, 1, 0 }, .{ 1, -1, 0 }, .{ 2, 0, 0 }, .{ 0, 2, 0 }, .{ 3, 1, 0 }, .{ 1, 1, 1 } };
    const origins = [_][3]i32{ .{ 0, 0, 0 }, .{ 1700, 900, 58_620 }, .{ -40, -40, -40 } };
    for (origins) |origin| {
        for (steps) |step| {
            var st: Stats = .{};
            for (0..12) |zi| {
                for (0..160) |yi| {
                    for (0..160) |xi| {
                        const c = [3]i32{ origin[0] + @as(i32, @intCast(xi)), origin[1] + @as(i32, @intCast(yi)), origin[2] + @as(i32, @intCast(zi)) };
                        st.add(hash1(c), hash1(.{ c[0] + step[0], c[1] + step[1], c[2] + step[2] }));
                    }
                }
            }
            try st.check();
        }
    }
}

test "a cell on a closed pattern has one hash however its column is reached" {
    // cellHash wraps the column with an integer remainder after adding eight periods, as the shader does.
    var period: i32 = 6;
    while (period <= 60) : (period += 1) {
        var column: i32 = -3;
        while (column <= period + 3) : (column += 1) {
            const wrapped: i32 = @intCast(@as(u32, @intCast(column + period * 8)) % @as(u32, @intCast(period)));
            try std.testing.expect(wrapped >= 0 and wrapped < period);
            try std.testing.expectEqual(@mod(column, period), wrapped);
        }
    }
}
