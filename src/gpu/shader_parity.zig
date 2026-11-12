//! Holds the two shader files together. `shaders.metal` and `shaders.hlsl` are the same program in two
//! dialects, ported by hand, and a change to the lighting in one that is not made in the other would
//! leave the platforms looking different with nothing to say so. The tests here read both sources and
//! require that they declare the same functions in the same order, and that the functions with no
//! platform-specific plumbing in them (the noise helpers, the whole of the scene's fragment function, the
//! particle and post-processing fragment functions) are the same text once the Metal spelling is rewritten
//! in HLSL's. They run on any machine, since they only compare text.

const std = @import("std");

const metal = @embedFile("../shaders/shaders.metal");
const hlsl = @embedFile("../shaders/shaders.hlsl");

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
            const declaration = line[line.len - 1] == ';' or std.mem.startsWith(u8, line, "cbuffer") or std.mem.startsWith(u8, line, "struct") or line[0] == '#';
            if (paren != null and !declaration) {
                var start = paren.?;
                while (start > 0 and isIdent(line[start - 1])) start -= 1;
                name = line[start..paren.?];
                in_header = true;
            }
        }
        if (name != null) {
            if (in_header) {
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

/// One line of the Metal file in HLSL's spelling.
fn toHlsl(arena: std.mem.Allocator, line: []const u8) ![]const u8 {
    for (line_exceptions) |e| {
        if (std.mem.eql(u8, line, e[0])) return e[1];
    }
    var s = try replaceAll(arena, line, "fract(", "frac(");
    s = try replaceAll(arena, s, "mix(", "lerp(");
    // `in` is a reserved word in HLSL; the stage input is called IN there.
    {
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
        s = buf.items;
    }
    // Texture taps: Metal's `t.sample(smp, uv)` leaves the mip level to the sampler and `level(x)` names
    // it; the HLSL file always names it, 0 where Metal leaves it out (see the note on post_fs there).
    {
        const call = "hdr.sample(";
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
            const args = s[at + call.len .. close];
            try buf.appendSlice(arena, "hdr.SampleLevel(");
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
        s = buf.items;
    }
    return s;
}

fn find(fns: []const Function, name: []const u8) ?Function {
    for (fns) |f| {
        if (std.mem.eql(u8, f.name, name)) return f;
    }
    return null;
}

test "both shader files declare the same functions in the same order" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const m = try parse(arena, metal);
    const h = try parse(arena, hlsl);
    const want = [_][]const u8{ "hash1", "vnoise", "fbm", "hash2", "cellHash", "voronoi", "scene_vs", "scene_fs", "part_vs", "part_fs", "post_vs", "aces", "post_fs", "hud_vs", "hud_fs" };
    try std.testing.expectEqual(want.len, m.len);
    try std.testing.expectEqual(want.len, h.len);
    for (want, m, h) |name, mf, hf| {
        try std.testing.expectEqualStrings(name, mf.name);
        try std.testing.expectEqualStrings(name, hf.name);
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

test "the same materials are switched on in both files" {
    // Every `mat == N` of one file appears in the other, the same number of times.
    for (0..16) |id| {
        var needle_buf: [16]u8 = undefined;
        const needle = try std.fmt.bufPrint(&needle_buf, "mat == {d})", .{id});
        try std.testing.expectEqual(std.mem.count(u8, metal, needle), std.mem.count(u8, hlsl, needle));
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
}
