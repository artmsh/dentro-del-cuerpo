//! The Metal backend of `gpu.zig`, through the Objective-C runtime. One HDR scene pass (4x MSAA, resolved
//! and mip-chained for bloom) and one post pass that tonemaps to the drawable and draws the HUD.

const std = @import("std");
const objc = @import("../platform/objc.zig");
const common = @import("../gpu.zig");
const id = objc.id;
const SEL = objc.SEL;

const Vertex = common.Vertex;
const Instance = common.Instance;
const PVertex = common.PVertex;
const HVertex = common.HVertex;
const Frame = common.Frame;
const Post = common.Post;
const Pass = common.Pass;
const Batch = common.Batch;
const FrameDesc = common.FrameDesc;
const max_instances = common.max_instances;
const max_dyn_verts = common.max_dyn_verts;
const max_part_verts = common.max_part_verts;
const max_hud_verts = common.max_hud_verts;

extern fn MTLCreateSystemDefaultDevice() id;

/// The shader source this backend compiles, and the name it has beside the executable.
pub const shader_file = "shaders.metal";
pub const embedded_shaders: [:0]const u8 = @embedFile("../shaders/shaders.metal");

const frames_in_flight = 3;

const fmt_bgra8: u64 = 80;
const fmt_rgba16f: u64 = 115;
const fmt_depth32f: u64 = 252;
const fmt_r8: u64 = 10;
const samples: u64 = 4;

const ClearColor = extern struct { r: f64, g: f64, b: f64, a: f64 };
const Viewport = extern struct { x: f64, y: f64, w: f64, h: f64, znear: f64, zfar: f64 };
const Region = extern struct { x: u64, y: u64, z: u64, w: u64, h: u64, d: u64 };

const BufferSet = struct {
    inst: id,
    dyn: id,
    part: id,
    hud: id,
};

const Blend = enum { none, alpha, additive };

pub const Gpu = struct {
    device: id,
    queue: id,
    layer: id = null,
    pipe_solid: id = null,
    pipe_blend: id = null,
    pipe_part: id = null,
    pipe_post: id = null,
    pipe_hud: id = null,
    ds_rw: id = null,
    ds_ro: id = null,
    sampler: id = null,
    hdr_ms: id = null,
    depth_ms: id = null,
    hdr: id = null,
    offscreen: id = null,
    font_tex: id = null,
    mesh_vb: id = null,
    mesh_ib: id = null,
    sets: [frames_in_flight]BufferSet = undefined,
    frame_idx: usize = 0,
    width: u32 = 0,
    height: u32 = 0,

    // CPU-side views of the current frame's buffers.
    instances: [*]Instance = undefined,
    dyn_verts: [*]Vertex = undefined,
    part_verts: [*]PVertex = undefined,
    hud_verts: [*]HVertex = undefined,

    pub fn init(shader_src: [:0]const u8, _: common.Options) !Gpu {
        const device = MTLCreateSystemDefaultDevice() orelse return error.NoMetalDevice;
        var g: Gpu = .{ .device = device, .queue = objc.get(device, "newCommandQueue") };

        var err: id = null;
        const lib = objc.send(fn (id, SEL, id, id, *id) callconv(.c) id, device, "newLibraryWithSource:options:error:", .{ objc.nsString(shader_src.ptr), null, &err }) orelse {
            std.debug.print("shader compile failed: {s}\n", .{objc.cString(objc.get(err, "localizedDescription"))});
            return error.ShaderCompileFailed;
        };
        g.pipe_solid = try g.pipeline(lib, "scene_vs", "scene_fs", fmt_rgba16f, true, samples, .none);
        g.pipe_blend = try g.pipeline(lib, "scene_vs", "scene_fs", fmt_rgba16f, true, samples, .alpha);
        g.pipe_part = try g.pipeline(lib, "part_vs", "part_fs", fmt_rgba16f, true, samples, .additive);
        g.pipe_post = try g.pipeline(lib, "post_vs", "post_fs", fmt_bgra8, false, 1, .none);
        g.pipe_hud = try g.pipeline(lib, "hud_vs", "hud_fs", fmt_bgra8, false, 1, .alpha);

        g.ds_rw = g.depthState(true);
        g.ds_ro = g.depthState(false);

        const sd = objc.new("MTLSamplerDescriptor");
        objc.setU(sd, "setMinFilter:", 1);
        objc.setU(sd, "setMagFilter:", 1);
        objc.setU(sd, "setMipFilter:", 2);
        g.sampler = objc.send(fn (id, SEL, id) callconv(.c) id, device, "newSamplerStateWithDescriptor:", .{sd});

        for (&g.sets) |*s| {
            s.inst = g.buffer(max_instances * @sizeOf(Instance));
            s.dyn = g.buffer(max_dyn_verts * @sizeOf(Vertex));
            s.part = g.buffer(max_part_verts * @sizeOf(PVertex));
            s.hud = g.buffer(max_hud_verts * @sizeOf(HVertex));
        }
        g.mapFrame();
        return g;
    }

    fn buffer(g: *Gpu, len: usize) id {
        return objc.send(fn (id, SEL, u64, u64) callconv(.c) id, g.device, "newBufferWithLength:options:", .{ len, 0 });
    }

    fn mapFrame(g: *Gpu) void {
        const s = g.sets[g.frame_idx];
        g.instances = @ptrCast(@alignCast(objc.send(fn (id, SEL) callconv(.c) ?*anyopaque, s.inst, "contents", .{})));
        g.dyn_verts = @ptrCast(@alignCast(objc.send(fn (id, SEL) callconv(.c) ?*anyopaque, s.dyn, "contents", .{})));
        g.part_verts = @ptrCast(@alignCast(objc.send(fn (id, SEL) callconv(.c) ?*anyopaque, s.part, "contents", .{})));
        g.hud_verts = @ptrCast(@alignCast(objc.send(fn (id, SEL) callconv(.c) ?*anyopaque, s.hud, "contents", .{})));
    }

    fn depthState(g: *Gpu, write: bool) id {
        const d = objc.new("MTLDepthStencilDescriptor");
        objc.setU(d, "setDepthCompareFunction:", 3); // less-equal
        objc.setB(d, "setDepthWriteEnabled:", write);
        return objc.send(fn (id, SEL, id) callconv(.c) id, g.device, "newDepthStencilStateWithDescriptor:", .{d});
    }

    fn pipeline(g: *Gpu, lib: id, vs: [*:0]const u8, fs: [*:0]const u8, color_fmt: u64, depth: bool, sample_count: u64, blend: Blend) !id {
        const vf = objc.send(fn (id, SEL, id) callconv(.c) id, lib, "newFunctionWithName:", .{objc.nsString(vs)}) orelse return error.MissingShaderFunction;
        const ff = objc.send(fn (id, SEL, id) callconv(.c) id, lib, "newFunctionWithName:", .{objc.nsString(fs)}) orelse return error.MissingShaderFunction;
        const d = objc.new("MTLRenderPipelineDescriptor");
        objc.setObj(d, "setVertexFunction:", vf);
        objc.setObj(d, "setFragmentFunction:", ff);
        objc.setU(d, "setRasterSampleCount:", sample_count);
        if (depth) objc.setU(d, "setDepthAttachmentPixelFormat:", fmt_depth32f);
        const c0 = objc.send(fn (id, SEL, u64) callconv(.c) id, objc.get(d, "colorAttachments"), "objectAtIndexedSubscript:", .{0});
        objc.setU(c0, "setPixelFormat:", color_fmt);
        switch (blend) {
            .none => {},
            .alpha => {
                objc.setB(c0, "setBlendingEnabled:", true);
                objc.setU(c0, "setSourceRGBBlendFactor:", 4);
                objc.setU(c0, "setDestinationRGBBlendFactor:", 5);
                objc.setU(c0, "setSourceAlphaBlendFactor:", 1);
                objc.setU(c0, "setDestinationAlphaBlendFactor:", 5);
            },
            .additive => {
                objc.setB(c0, "setBlendingEnabled:", true);
                objc.setU(c0, "setSourceRGBBlendFactor:", 1);
                objc.setU(c0, "setDestinationRGBBlendFactor:", 1);
                objc.setU(c0, "setSourceAlphaBlendFactor:", 0);
                objc.setU(c0, "setDestinationAlphaBlendFactor:", 1);
            },
        }
        var err: id = null;
        return objc.send(fn (id, SEL, id, *id) callconv(.c) id, g.device, "newRenderPipelineStateWithDescriptor:error:", .{ d, &err }) orelse {
            std.debug.print("pipeline {s}/{s} failed: {s}\n", .{ vs, fs, objc.cString(objc.get(err, "localizedDescription")) });
            return error.PipelineFailed;
        };
    }

    /// Create the CAMetalLayer and give it to the window's content view, which hosts it.
    pub fn attach(g: *Gpu, view: id) !void {
        const layer = objc.new("CAMetalLayer");
        objc.setObj(layer, "setDevice:", g.device);
        objc.setU(layer, "setPixelFormat:", fmt_bgra8);
        objc.setB(layer, "setFramebufferOnly:", true);
        g.layer = layer;
        objc.setObj(view, "setLayer:", layer);
        objc.setB(view, "setWantsLayer:", true);
    }

    /// The window's drawable changed size or moved to a display of another density.
    pub fn resizeSurface(g: *Gpu, w: u32, h: u32, scale: f64) void {
        objc.send(fn (id, SEL, f64) callconv(.c) void, g.layer, "setContentsScale:", .{scale});
        g.resize(w, h, false);
    }

    /// A line for the log saying what is rendering.
    pub fn describe(g: *Gpu, buf: []u8) []const u8 {
        const name = objc.get(g.device, "name");
        return std.fmt.bufPrint(buf, "Metal, {s}", .{if (name != null) std.mem.span(objc.cString(name)) else "unnamed device"}) catch "Metal";
    }

    fn texture(g: *Gpu, format: u64, w: u32, h: u32, mipmapped: bool, sample_count: u64, usage: u64) id {
        const d = objc.send(fn (id, SEL, u64, u64, u64, bool) callconv(.c) id, objc.class("MTLTextureDescriptor"), "texture2DDescriptorWithPixelFormat:width:height:mipmapped:", .{ format, w, h, mipmapped });
        objc.setU(d, "setUsage:", usage);
        objc.setU(d, "setStorageMode:", if (sample_count > 1 or format == fmt_depth32f) 2 else 0);
        if (sample_count > 1) {
            objc.setU(d, "setTextureType:", 4);
            objc.setU(d, "setSampleCount:", sample_count);
        }
        return objc.send(fn (id, SEL, id) callconv(.c) id, g.device, "newTextureWithDescriptor:", .{d});
    }

    /// (Re)create the render targets for a drawable of `w` x `h` pixels.
    pub fn resize(g: *Gpu, w: u32, h: u32, with_offscreen: bool) void {
        if (w == g.width and h == g.height and g.hdr != null) return;
        objc.release(g.hdr_ms);
        objc.release(g.depth_ms);
        objc.release(g.hdr);
        g.width = @max(w, 8);
        g.height = @max(h, 8);
        g.hdr_ms = g.texture(fmt_rgba16f, g.width, g.height, false, samples, 4);
        g.depth_ms = g.texture(fmt_depth32f, g.width, g.height, false, samples, 4);
        g.hdr = g.texture(fmt_rgba16f, g.width, g.height, true, 1, 5);
        if (with_offscreen) {
            objc.release(g.offscreen);
            g.offscreen = g.texture(fmt_bgra8, g.width, g.height, false, 1, 5);
        }
        if (g.layer != null) {
            objc.send(fn (id, SEL, objc.Size) callconv(.c) void, g.layer, "setDrawableSize:", .{objc.Size{ .w = @floatFromInt(g.width), .h = @floatFromInt(g.height) }});
        }
    }

    pub fn uploadMeshes(g: *Gpu, verts: []const Vertex, indices: []const u32) void {
        g.mesh_vb = objc.send(fn (id, SEL, *const anyopaque, u64, u64) callconv(.c) id, g.device, "newBufferWithBytes:length:options:", .{ verts.ptr, verts.len * @sizeOf(Vertex), 0 });
        g.mesh_ib = objc.send(fn (id, SEL, *const anyopaque, u64, u64) callconv(.c) id, g.device, "newBufferWithBytes:length:options:", .{ indices.ptr, indices.len * 4, 0 });
    }

    /// Upload the glyph atlas with a box-filtered mip chain, so text stays clean at every HUD size.
    pub fn uploadFont(g: *Gpu, gpa: std.mem.Allocator, pixels: []const u8, w: u32, h: u32) !void {
        g.font_tex = g.texture(fmt_r8, w, h, true, 1, 1);
        var chain = try common.MipChain.build(gpa, pixels, w, h);
        defer chain.deinit(gpa);
        for (chain.levels[0..chain.count], 0..) |level, i| {
            objc.send(fn (id, SEL, Region, u64, *const anyopaque, u64) callconv(.c) void, g.font_tex, "replaceRegion:mipmapLevel:withBytes:bytesPerRow:", .{ Region{ .x = 0, .y = 0, .z = 0, .w = level.w, .h = level.h, .d = 1 }, @as(u64, i), level.pixels.ptr, @as(u64, level.w) });
        }
    }

    /// Encode and submit one frame. Returns false when no drawable was available.
    pub fn submit(g: *Gpu, d: *const FrameDesc, wait: bool) bool {
        var drawable: id = null;
        var target: id = g.offscreen;
        if (g.layer != null) {
            drawable = objc.get(g.layer, "nextDrawable") orelse return false;
            target = objc.get(drawable, "texture");
        }
        const set = g.sets[g.frame_idx];
        const cmd = objc.get(g.queue, "commandBuffer");

        // Scene.
        {
            const pass = objc.get(objc.class("MTLRenderPassDescriptor"), "renderPassDescriptor");
            const c0 = objc.send(fn (id, SEL, u64) callconv(.c) id, objc.get(pass, "colorAttachments"), "objectAtIndexedSubscript:", .{0});
            objc.setObj(c0, "setTexture:", g.hdr_ms);
            objc.setObj(c0, "setResolveTexture:", g.hdr);
            objc.setU(c0, "setLoadAction:", 2);
            objc.setU(c0, "setStoreAction:", 2);
            const fc = d.scene.fog_color;
            objc.send(fn (id, SEL, ClearColor) callconv(.c) void, c0, "setClearColor:", .{ClearColor{ .r = fc[0], .g = fc[1], .b = fc[2], .a = 1 }});
            const da = objc.get(pass, "depthAttachment");
            objc.setObj(da, "setTexture:", g.depth_ms);
            objc.setU(da, "setLoadAction:", 2);
            objc.setU(da, "setStoreAction:", 0);
            objc.send(fn (id, SEL, f64) callconv(.c) void, da, "setClearDepth:", .{1.0});

            const enc = objc.send(fn (id, SEL, id) callconv(.c) id, cmd, "renderCommandEncoderWithDescriptor:", .{pass});
            const fw: f64 = @floatFromInt(g.width);
            const fh: f64 = @floatFromInt(g.height);
            setViewport(enc, fw, fh, 0.1, 1.0);
            setBuffer(enc, true, set.inst, 1);
            setBytes(enc, true, &d.scene, @sizeOf(Frame), 2);
            setBytes(enc, false, &d.scene, @sizeOf(Frame), 2);

            objc.setObj(enc, "setRenderPipelineState:", g.pipe_solid);
            objc.setObj(enc, "setDepthStencilState:", g.ds_rw);
            g.drawPass(enc, set, d.batches, .solid);

            objc.setObj(enc, "setRenderPipelineState:", g.pipe_blend);
            objc.setObj(enc, "setDepthStencilState:", g.ds_ro);
            g.drawPass(enc, set, d.batches, .blend);

            if (d.part_count > 0) {
                objc.setObj(enc, "setRenderPipelineState:", g.pipe_part);
                setBuffer(enc, true, set.part, 0);
                objc.send(fn (id, SEL, u64, u64, u64) callconv(.c) void, enc, "drawPrimitives:vertexStart:vertexCount:", .{ 3, 0, d.part_count });
            }

            // First-person arms: own projection, front slice of the depth range so the world never clips them.
            setViewport(enc, fw, fh, 0.0, 0.1);
            setBytes(enc, true, &d.arm, @sizeOf(Frame), 2);
            setBytes(enc, false, &d.arm, @sizeOf(Frame), 2);
            objc.setObj(enc, "setRenderPipelineState:", g.pipe_solid);
            objc.setObj(enc, "setDepthStencilState:", g.ds_rw);
            g.drawPass(enc, set, d.batches, .arm);
            objc.call(enc, "endEncoding");
        }

        // Mip chain of the resolved HDR image feeds the bloom taps.
        {
            const blit = objc.get(cmd, "blitCommandEncoder");
            objc.setObj(blit, "generateMipmapsForTexture:", g.hdr);
            objc.call(blit, "endEncoding");
        }

        // Tonemap + HUD.
        {
            const pass = objc.get(objc.class("MTLRenderPassDescriptor"), "renderPassDescriptor");
            const c0 = objc.send(fn (id, SEL, u64) callconv(.c) id, objc.get(pass, "colorAttachments"), "objectAtIndexedSubscript:", .{0});
            objc.setObj(c0, "setTexture:", target);
            objc.setU(c0, "setLoadAction:", 0);
            objc.setU(c0, "setStoreAction:", 1);
            const enc = objc.send(fn (id, SEL, id) callconv(.c) id, cmd, "renderCommandEncoderWithDescriptor:", .{pass});
            var post = d.post;
            post.c[0] = 1.0 / @as(f32, @floatFromInt(g.width));
            post.c[1] = 1.0 / @as(f32, @floatFromInt(g.height));
            objc.setObj(enc, "setRenderPipelineState:", g.pipe_post);
            setBytes(enc, false, &post, @sizeOf(Post), 0);
            objc.send(fn (id, SEL, id, u64) callconv(.c) void, enc, "setFragmentTexture:atIndex:", .{ g.hdr, 0 });
            objc.send(fn (id, SEL, id, u64) callconv(.c) void, enc, "setFragmentSamplerState:atIndex:", .{ g.sampler, 0 });
            objc.send(fn (id, SEL, u64, u64, u64) callconv(.c) void, enc, "drawPrimitives:vertexStart:vertexCount:", .{ 3, 0, 3 });
            if (d.hud_count > 0 and g.font_tex != null) {
                objc.setObj(enc, "setRenderPipelineState:", g.pipe_hud);
                setBuffer(enc, true, set.hud, 0);
                setBytes(enc, true, &post, @sizeOf(Post), 1);
                objc.send(fn (id, SEL, id, u64) callconv(.c) void, enc, "setFragmentTexture:atIndex:", .{ g.font_tex, 0 });
                objc.send(fn (id, SEL, u64, u64, u64) callconv(.c) void, enc, "drawPrimitives:vertexStart:vertexCount:", .{ 3, 0, d.hud_count });
            }
            objc.call(enc, "endEncoding");
        }

        if (drawable != null) objc.setObj(cmd, "presentDrawable:", drawable);
        objc.call(cmd, "commit");
        if (wait) objc.call(cmd, "waitUntilCompleted");

        g.frame_idx = (g.frame_idx + 1) % frames_in_flight;
        g.mapFrame();
        return true;
    }

    fn drawPass(g: *Gpu, enc: id, set: BufferSet, batches: []const Batch, pass: Pass) void {
        var bound_dynamic: ?bool = null;
        for (batches) |b| {
            if (b.pass != pass or b.instance_count == 0) continue;
            if (bound_dynamic == null or bound_dynamic.? != b.dynamic) {
                setBuffer(enc, true, if (b.dynamic) set.dyn else g.mesh_vb, 0);
                bound_dynamic = b.dynamic;
            }
            if (b.dynamic) {
                objc.send(fn (id, SEL, u64, u64, u64, u64, u64) callconv(.c) void, enc, "drawPrimitives:vertexStart:vertexCount:instanceCount:baseInstance:", .{ 3, b.vertex_start, b.vertex_count, b.instance_count, b.first_instance });
            } else {
                objc.send(fn (id, SEL, u64, u64, u64, id, u64, u64, i64, u64) callconv(.c) void, enc, "drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:instanceCount:baseVertex:baseInstance:", .{ 3, b.mesh.index_count, 1, g.mesh_ib, @as(u64, b.mesh.index_start) * 4, b.instance_count, @as(i64, b.mesh.base_vertex), b.first_instance });
            }
        }
    }

    /// Copy the offscreen target out as tightly packed BGRA8 rows.
    pub fn readback(g: *Gpu, out: []u8) void {
        std.debug.assert(out.len >= @as(usize, g.width) * g.height * 4);
        objc.send(fn (id, SEL, [*]u8, u64, Region, u64) callconv(.c) void, g.offscreen, "getBytes:bytesPerRow:fromRegion:mipmapLevel:", .{ out.ptr, @as(u64, g.width) * 4, Region{ .x = 0, .y = 0, .z = 0, .w = g.width, .h = g.height, .d = 1 }, 0 });
    }
};

fn setViewport(enc: id, w: f64, h: f64, znear: f64, zfar: f64) void {
    objc.send(fn (id, SEL, Viewport) callconv(.c) void, enc, "setViewport:", .{Viewport{ .x = 0, .y = 0, .w = w, .h = h, .znear = znear, .zfar = zfar }});
}

fn setBuffer(enc: id, vertex: bool, buf: id, index: u64) void {
    objc.send(fn (id, SEL, id, u64, u64) callconv(.c) void, enc, if (vertex) "setVertexBuffer:offset:atIndex:" else "setFragmentBuffer:offset:atIndex:", .{ buf, 0, index });
}

fn setBytes(enc: id, vertex: bool, ptr: *const anyopaque, len: u64, index: u64) void {
    objc.send(fn (id, SEL, *const anyopaque, u64, u64) callconv(.c) void, enc, if (vertex) "setVertexBytes:length:atIndex:" else "setFragmentBytes:length:atIndex:", .{ ptr, len, index });
}
