//! What the renderer asks of a graphics API: the vertex and uniform layouts shared with the shaders, the
//! frame description, and the `Gpu` that turns one into pixels. The layouts and limits are the same on
//! every platform; the implementation is picked at compile time (`gpu/metal.zig`, `gpu/d3d11.zig`), and
//! both draw the same frame: an HDR scene pass (4x MSAA, resolved and mip-chained for bloom) and a post
//! pass that tonemaps to the target and draws the HUD.
//!
//! A backend's `Gpu` has: `init(shader_src)`, `attach(surface)` for a window, `resizeSurface(w, h, scale)`
//! and `resize(w, h, with_offscreen)`, `uploadMeshes`, `uploadFont`, `submit(desc, wait)`, `readback`,
//! `describe`, the fields `width` and `height`, and the CPU-side arrays `instances`, `dyn_verts`,
//! `part_verts` and `hud_verts` that the next frame is written into.

const std = @import("std");
const builtin = @import("builtin");

// Layouts mirror the shader files (src/shaders/shaders.metal, shaders.hlsl), byte for byte.
pub const Vertex = extern struct { pos: [3]f32, nrm: [3]f32, uv: [2]f32 };
pub const Instance = extern struct { model: [16]f32, color: [4]f32, params: [4]f32 };
pub const PVertex = extern struct { pos: [3]f32, uv: [2]f32, color: [4]f32 };
pub const HVertex = extern struct { pos: [2]f32, uv: [2]f32, color: [4]f32 };

pub const Frame = extern struct {
    view_proj: [16]f32,
    cam_pos: [4]f32,
    cam_fwd: [4]f32,
    fog_color: [4]f32,
    ambient: [4]f32,
    lamp_color: [4]f32,
    misc: [4]f32,
};

pub const Post = extern struct {
    a: [4]f32 = .{ 1, 0.5, 0, 0 },
    b: [4]f32 = .{ 0, 1, 0.004, 0.6 },
    c: [4]f32 = .{ 0, 0, 0, 0 },
    tint: [4]f32 = .{ 1, 1, 1, 0 },
};

pub const Mesh = struct { index_start: u32 = 0, index_count: u32 = 0, base_vertex: u32 = 0 };

pub const Pass = enum(u8) { solid, blend, arm };

pub const Batch = struct {
    pass: Pass,
    dynamic: bool = false,
    mesh: Mesh = .{},
    vertex_start: u32 = 0,
    vertex_count: u32 = 0,
    first_instance: u32,
    instance_count: u32,
};

pub const max_instances = 48000;
pub const max_dyn_verts = 48000;
pub const max_part_verts = 96000;
pub const max_hud_verts = 96000;
pub const max_batches = 2048;

/// One frame, as `render.zig` assembled it. The counts say how much of each CPU-side array is in use.
pub const FrameDesc = struct {
    scene: Frame,
    arm: Frame,
    post: Post,
    batches: []const Batch,
    instance_count: u32,
    dyn_count: u32,
    part_count: u32,
    hud_count: u32,
};

/// A box-filtered mip chain of an 8-bit single-channel image, down to the last level that still has two
/// rows and two columns to average. Both backends upload the glyph atlas this way, so text is filtered
/// from the same texels on every platform.
pub const MipChain = struct {
    pub const Level = struct { pixels: []const u8, w: u32, h: u32 };
    levels: [16]Level = undefined,
    count: usize = 0,
    storage: []u8 = &.{},

    /// Level 0 is `pixels` itself, not a copy; it must outlive the chain.
    pub fn build(gpa: std.mem.Allocator, pixels: []const u8, w: u32, h: u32) !MipChain {
        var total: usize = 0;
        {
            var sw = w;
            var sh = h;
            while (sw > 1 and sh > 1) {
                sw /= 2;
                sh /= 2;
                total += @as(usize, sw) * sh;
            }
        }
        var chain: MipChain = .{ .storage = try gpa.alloc(u8, total) };
        chain.levels[0] = .{ .pixels = pixels, .w = w, .h = h };
        chain.count = 1;
        var src = pixels;
        var sw = w;
        var sh = h;
        var used: usize = 0;
        while (sw > 1 and sh > 1) {
            const dw = sw / 2;
            const dh = sh / 2;
            const dst = chain.storage[used..][0 .. @as(usize, dw) * dh];
            used += dst.len;
            for (0..dh) |y| for (0..dw) |x| {
                const a: u32 = src[(2 * y) * sw + 2 * x];
                const b: u32 = src[(2 * y) * sw + 2 * x + 1];
                const c: u32 = src[(2 * y + 1) * sw + 2 * x];
                const d: u32 = src[(2 * y + 1) * sw + 2 * x + 1];
                dst[y * dw + x] = @intCast((a + b + c + d + 2) / 4);
            };
            chain.levels[chain.count] = .{ .pixels = dst, .w = dw, .h = dh };
            chain.count += 1;
            src = dst;
            sw = dw;
            sh = dh;
        }
        return chain;
    }

    pub fn deinit(chain: *MipChain, gpa: std.mem.Allocator) void {
        gpa.free(chain.storage);
    }
};

/// Choices made on the command line that a backend may honour.
pub const Options = struct {
    /// Render on the system's software rasteriser instead of a GPU, where the API has one (WARP for
    /// Direct3D). Metal has none and ignores it.
    software: bool = false,
};

/// The implementation for the target.
pub const backend = switch (builtin.os.tag) {
    .macos => @import("gpu/metal.zig"),
    .windows => @import("gpu/d3d11.zig"),
    else => @compileError("no GPU backend for this operating system"),
};

pub const Gpu = backend.Gpu;
/// The shader source compiled into the binary, and the file name of the editable copy shipped beside it.
pub const embedded_shaders: [:0]const u8 = backend.embedded_shaders;
pub const shader_file: []const u8 = backend.shader_file;

comptime {
    std.debug.assert(@sizeOf(Vertex) == 32);
    std.debug.assert(@sizeOf(Instance) == 96);
    std.debug.assert(@sizeOf(PVertex) == 36);
    std.debug.assert(@sizeOf(HVertex) == 32);
    std.debug.assert(@sizeOf(Frame) == 160);
    std.debug.assert(@sizeOf(Post) == 64);
}

test {
    // The Direct3D declarations check their own vtable layouts at compile time, and the two shader files
    // are compared as text, so both are worth compiling on every host.
    _ = @import("gpu/d3d11_api.zig");
    _ = @import("gpu/shader_parity.zig");
}

test "the mip chain halves down to the last level with two rows, averaging with rounding" {
    const px = [_]u8{
        0,   255, 10, 20, 1, 1, 1, 2,
        255, 255, 30, 40, 1, 1, 2, 2,
        0,   0,   0,  0,  9, 9, 9, 9,
        0,   0,   0,  1,  9, 9, 9, 9,
    };
    var chain = try MipChain.build(std.testing.allocator, &px, 8, 4);
    defer chain.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 3), chain.count);
    try std.testing.expectEqual(@as(u32, 4), chain.levels[1].w);
    try std.testing.expectEqual(@as(u32, 2), chain.levels[1].h);
    try std.testing.expectEqualSlices(u8, &.{ 191, 25, 1, 2, 0, 0, 9, 9 }, chain.levels[1].pixels);
    try std.testing.expectEqual(@as(u32, 2), chain.levels[2].w);
    try std.testing.expectEqual(@as(u32, 1), chain.levels[2].h);
    try std.testing.expectEqualSlices(u8, &.{ 54, 5 }, chain.levels[2].pixels);
}
