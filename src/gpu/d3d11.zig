//! The Direct3D 11 backend of `gpu.zig`. It draws the frame the Metal backend draws, pass for pass: the
//! scene into a 4x multisampled RGBA16F target, a resolve and a mip chain for the bloom taps, then a post
//! pass that tonemaps to the window's back buffer (or to an offscreen target for `--shots`) and draws the
//! HUD over it. Vertices and instances are not fed through an input layout; the vertex shaders index
//! structured buffers by SV_VertexID and SV_InstanceID, which is how the Metal shaders read theirs.
//!
//! The shaders are compiled from HLSL source at startup by the D3DCompile in d3dcompiler_47.dll, which is
//! part of Windows 10 and later, so a modder can edit the file shipped beside the executable as on macOS.
//!
//! A device can be taken away at any time (a driver update, a remote-desktop session, the adapter being
//! unplugged). Everything the device owns can be rebuilt from what this file keeps on the CPU side: the
//! shader source, the mesh and font data, and the window handle. `recover` does that, and `submit` calls
//! it when a present reports the device gone.

const std = @import("std");
const common = @import("../gpu.zig");
const util = @import("../util.zig");
const w = @import("../platform/win32.zig");
const d = @import("d3d11_api.zig");

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

/// The shader source this backend compiles, and the name it has beside the executable.
pub const shader_file = "shaders.hlsl";
pub const embedded_shaders: [:0]const u8 = @embedFile("../shaders/shaders.hlsl");

const samples = 4;

/// What `DrawBuffer` in the shader file holds: the offsets Metal folds into its vertex and instance ids.
const Draw = extern struct { base_vertex: u32, base_instance: u32, unused: [2]u32 = .{ 0, 0 } };

/// Set to a frame number to have the device torn down and rebuilt before that frame is drawn, as if the
/// system had removed it. CI uses it to check that a recovered renderer draws the same picture.
const loss_env = "DENTRO_FORCE_DEVICE_LOSS";
/// Set to print the shader compiler's warnings, which are otherwise only shown with an error.
const log_env = "DENTRO_GPU_LOG";

const gpa = std.heap.page_allocator;

const Shaders = struct {
    scene_vs: ?*d.VertexShader = null,
    scene_fs: ?*d.PixelShader = null,
    part_vs: ?*d.VertexShader = null,
    part_fs: ?*d.PixelShader = null,
    post_vs: ?*d.VertexShader = null,
    post_fs: ?*d.PixelShader = null,
    hud_vs: ?*d.VertexShader = null,
    hud_fs: ?*d.PixelShader = null,
};

/// A CPU-written array the vertex shaders read as a StructuredBuffer.
const Stream = struct {
    buf: ?*d.Buffer = null,
    srv: ?*d.ShaderResourceView = null,
};

pub const Gpu = struct {
    device: ?*d.Device = null,
    ctx: ?*d.Context = null,
    software: bool = false,
    adapter_name: [128]u8 = undefined,
    adapter_name_len: usize = 0,
    compile_ms: f64 = 0,

    // Window output. Null when rendering offscreen.
    hwnd: w.HWND = null,
    swap: ?*d.SwapChain = null,
    back_rtv: ?*d.RenderTargetView = null,
    occluded: bool = false,

    sh: Shaders = .{},
    raster: ?*d.RasterizerState = null,
    blend_none: ?*d.BlendState = null,
    blend_alpha: ?*d.BlendState = null,
    blend_add: ?*d.BlendState = null,
    ds_rw: ?*d.DepthStencilState = null,
    ds_ro: ?*d.DepthStencilState = null,
    ds_off: ?*d.DepthStencilState = null,
    sampler: ?*d.SamplerState = null,

    cb_scene: ?*d.Buffer = null,
    cb_arm: ?*d.Buffer = null,
    cb_post: ?*d.Buffer = null,
    cb_draw: ?*d.Buffer = null,

    inst: Stream = .{},
    dyn: Stream = .{},
    part: Stream = .{},
    hud: Stream = .{},
    mesh: Stream = .{},
    mesh_ib: ?*d.Buffer = null,

    hdr_ms: ?*d.Texture2D = null,
    hdr_ms_rtv: ?*d.RenderTargetView = null,
    depth_ms: ?*d.Texture2D = null,
    depth_dsv: ?*d.DepthStencilView = null,
    hdr: ?*d.Texture2D = null,
    hdr_srv: ?*d.ShaderResourceView = null,
    offscreen: ?*d.Texture2D = null,
    offscreen_rtv: ?*d.RenderTargetView = null,
    staging: ?*d.Texture2D = null,
    font_tex: ?*d.Texture2D = null,
    font_srv: ?*d.ShaderResourceView = null,

    width: u32 = 0,
    height: u32 = 0,
    with_offscreen: bool = false,
    frame_no: u64 = 0,
    lose_at: ?u64 = null,
    recoveries: u32 = 0,

    // What a lost device is rebuilt from.
    shader_src: [:0]const u8 = "",
    options: common.Options = .{},
    mesh_verts: []Vertex = &.{},
    mesh_indices: []u32 = &.{},
    font_pixels: []u8 = &.{},
    font_w: u32 = 0,
    font_h: u32 = 0,

    // The next frame, written by the renderer and copied to the device in `submit`.
    instances: [*]Instance = undefined,
    dyn_verts: [*]Vertex = undefined,
    part_verts: [*]PVertex = undefined,
    hud_verts: [*]HVertex = undefined,

    pub fn init(shader_src: [:0]const u8, options: common.Options) !Gpu {
        var g: Gpu = .{ .shader_src = shader_src, .options = options };
        g.instances = (try gpa.alloc(Instance, max_instances)).ptr;
        g.dyn_verts = (try gpa.alloc(Vertex, max_dyn_verts)).ptr;
        g.part_verts = (try gpa.alloc(PVertex, max_part_verts)).ptr;
        g.hud_verts = (try gpa.alloc(HVertex, max_hud_verts)).ptr;
        var env_buf: [32]u8 = undefined;
        if (util.env(loss_env, &env_buf)) |text| g.lose_at = std.fmt.parseInt(u64, text, 10) catch null;
        try g.createDevice();
        return g;
    }

    // ------------------------------------------------------------------------ device and its objects

    fn createDevice(g: *Gpu) !void {
        const levels = [_]u32{d.FEATURE_LEVEL_11_0};
        const kinds: []const u32 = if (g.options.software) &.{d.DRIVER_TYPE_WARP} else &.{ d.DRIVER_TYPE_HARDWARE, d.DRIVER_TYPE_WARP };
        var hr: w.HRESULT = 0;
        for (kinds) |kind| {
            hr = d.D3D11CreateDevice(null, kind, null, d.CREATE_DEVICE_BGRA_SUPPORT, &levels, levels.len, d.sdk_version, &g.device, null, &g.ctx);
            if (!w.failed(hr) and g.device != null) break;
        }
        if (g.device == null or g.ctx == null) {
            std.debug.print("Direct3D 11 is not available (0x{x:0>8}); the game needs feature level 11_0\n", .{@as(u32, @bitCast(hr))});
            return error.NoDirect3DDevice;
        }
        errdefer g.releaseDevice();
        g.identifyAdapter();
        try g.compileShaders();
        try g.createStates();

        g.cb_scene = try g.constantBuffer(@sizeOf(Frame));
        g.cb_arm = try g.constantBuffer(@sizeOf(Frame));
        g.cb_post = try g.constantBuffer(@sizeOf(Post));
        g.cb_draw = try g.constantBuffer(@sizeOf(Draw));
        g.inst = try g.stream(Instance, max_instances, null);
        g.dyn = try g.stream(Vertex, max_dyn_verts, null);
        g.part = try g.stream(PVertex, max_part_verts, null);
        g.hud = try g.stream(HVertex, max_hud_verts, null);
    }

    fn identifyAdapter(g: *Gpu) void {
        g.adapter_name_len = 0;
        g.software = g.options.software;
        var dxgi: ?*d.DxgiDevice = w.Com.query(g.device.?, &d.IID_IDXGIDevice, d.DxgiDevice);
        defer w.Com.release(&dxgi);
        if (dxgi == null) return;
        var adapter: ?*d.Adapter = null;
        if (w.failed(dxgi.?.vtbl.GetAdapter(dxgi.?, &adapter)) or adapter == null) return;
        defer w.Com.release(&adapter);
        var desc: d.ADAPTER_DESC = undefined;
        if (w.failed(adapter.?.vtbl.GetDesc(adapter.?, &desc))) return;
        const len = std.mem.indexOfScalar(u16, &desc.Description, 0) orelse desc.Description.len;
        if (w.fromWide(&g.adapter_name, desc.Description[0..len])) |name| g.adapter_name_len = name.len;
        // The Microsoft Basic Render Driver is WARP, whichever way the device came to be on it.
        if (desc.VendorId == 0x1414 and desc.DeviceId == 0x8c) g.software = true;
    }

    /// A line for the log saying what is rendering.
    pub fn describe(g: *Gpu, buf: []u8) []const u8 {
        const name = if (g.adapter_name_len > 0) g.adapter_name[0..g.adapter_name_len] else "unnamed adapter";
        return std.fmt.bufPrint(buf, "Direct3D 11, {s}{s}, shaders compiled in {d:.0} ms", .{ name, if (g.software) " (software rasteriser)" else "", g.compile_ms }) catch "Direct3D 11";
    }

    fn compileShaders(g: *Gpu) !void {
        var name_buf: [32]u16 = undefined;
        const dll = w.LoadLibraryW(w.toWide(&name_buf, "d3dcompiler_47.dll").?.ptr) orelse {
            std.debug.print("d3dcompiler_47.dll could not be loaded; it is part of Windows 10 and later\n", .{});
            return error.NoShaderCompiler;
        };
        const compile: d.CompileFn = @ptrCast(@alignCast(w.GetProcAddress(dll, "D3DCompile") orelse return error.NoShaderCompiler));
        const verbose = util.envIsSet(log_env);
        var t0: i64 = 0;
        var t1: i64 = 0;
        var freq: i64 = 1;
        _ = w.QueryPerformanceCounter(&t0);

        const dev = g.device.?;
        inline for (comptime std.meta.fieldNames(Shaders)) |name| {
            const is_vs = comptime std.mem.endsWith(u8, name, "_vs");
            var code: ?*d.Blob = null;
            var errors: ?*d.Blob = null;
            const hr = compile(g.shader_src.ptr, g.shader_src.len, shader_file, null, null, name, if (is_vs) "vs_5_0" else "ps_5_0", d.D3DCOMPILE_OPTIMIZATION_LEVEL3, 0, &code, &errors);
            defer w.Com.release(&code);
            defer w.Com.release(&errors);
            const failed = w.failed(hr) or code == null;
            if (errors) |e| {
                if (failed or verbose) std.debug.print("{s}: {s}\n", .{ name, std.mem.trimEnd(u8, e.bytes(), "\x00\r\n") });
            }
            if (failed) {
                std.debug.print("shader compile failed: {s} (0x{x:0>8})\n", .{ name, @as(u32, @bitCast(hr)) });
                return error.ShaderCompileFailed;
            }
            const bytes = code.?.bytes();
            const made = if (is_vs)
                dev.vtbl.CreateVertexShader(dev, bytes.ptr, bytes.len, null, &@field(g.sh, name))
            else
                dev.vtbl.CreatePixelShader(dev, bytes.ptr, bytes.len, null, &@field(g.sh, name));
            if (w.failed(made)) return error.ShaderCreateFailed;
        }
        _ = w.QueryPerformanceCounter(&t1);
        _ = w.QueryPerformanceFrequency(&freq);
        g.compile_ms = @as(f64, @floatFromInt(t1 - t0)) * 1000.0 / @as(f64, @floatFromInt(@max(freq, 1)));
    }

    fn createStates(g: *Gpu) !void {
        const dev = g.device.?;
        // No culling and depth clipping on, which are Metal's defaults and what the meshes are built for.
        if (w.failed(dev.vtbl.CreateRasterizerState(dev, &.{ .MultisampleEnable = 1 }, &g.raster))) return error.StateFailed;

        var blend: d.BLEND_DESC = .{};
        if (w.failed(dev.vtbl.CreateBlendState(dev, &blend, &g.blend_none))) return error.StateFailed;
        blend.RenderTarget[0] = .{ .BlendEnable = 1, .SrcBlend = d.BLEND_SRC_ALPHA, .DestBlend = d.BLEND_INV_SRC_ALPHA, .SrcBlendAlpha = d.BLEND_ONE, .DestBlendAlpha = d.BLEND_INV_SRC_ALPHA };
        if (w.failed(dev.vtbl.CreateBlendState(dev, &blend, &g.blend_alpha))) return error.StateFailed;
        blend.RenderTarget[0] = .{ .BlendEnable = 1, .SrcBlend = d.BLEND_ONE, .DestBlend = d.BLEND_ONE, .SrcBlendAlpha = d.BLEND_ZERO, .DestBlendAlpha = d.BLEND_ONE };
        if (w.failed(dev.vtbl.CreateBlendState(dev, &blend, &g.blend_add))) return error.StateFailed;

        if (w.failed(dev.vtbl.CreateDepthStencilState(dev, &.{ .DepthEnable = 1, .DepthWriteMask = d.DEPTH_WRITE_MASK_ALL, .DepthFunc = d.COMPARISON_LESS_EQUAL }, &g.ds_rw))) return error.StateFailed;
        if (w.failed(dev.vtbl.CreateDepthStencilState(dev, &.{ .DepthEnable = 1, .DepthWriteMask = d.DEPTH_WRITE_MASK_ZERO, .DepthFunc = d.COMPARISON_LESS_EQUAL }, &g.ds_ro))) return error.StateFailed;
        if (w.failed(dev.vtbl.CreateDepthStencilState(dev, &.{ .DepthEnable = 0, .DepthWriteMask = d.DEPTH_WRITE_MASK_ZERO, .DepthFunc = d.COMPARISON_ALWAYS }, &g.ds_off))) return error.StateFailed;

        // Linear in both directions and between mip levels, clamped at the edges: the Metal sampler.
        if (w.failed(dev.vtbl.CreateSamplerState(dev, &.{ .Filter = d.FILTER_MIN_MAG_MIP_LINEAR, .AddressU = d.TEXTURE_ADDRESS_CLAMP, .AddressV = d.TEXTURE_ADDRESS_CLAMP, .AddressW = d.TEXTURE_ADDRESS_CLAMP }, &g.sampler))) return error.StateFailed;
    }

    fn constantBuffer(g: *Gpu, size: u32) !?*d.Buffer {
        const dev = g.device.?;
        var buf: ?*d.Buffer = null;
        if (w.failed(dev.vtbl.CreateBuffer(dev, &.{ .ByteWidth = size, .Usage = d.USAGE_DYNAMIC, .BindFlags = d.BIND_CONSTANT_BUFFER, .CPUAccessFlags = d.CPU_ACCESS_WRITE }, null, &buf))) return error.BufferFailed;
        return buf;
    }

    /// A structured buffer of `count` elements of `T` and the view the vertex shaders read it through.
    /// With `initial` it is filled once and never written again; without, it is rewritten every frame.
    fn stream(g: *Gpu, comptime T: type, count: usize, initial: ?[]const T) !Stream {
        const dev = g.device.?;
        var s: Stream = .{};
        const desc: d.BUFFER_DESC = .{
            .ByteWidth = @intCast(count * @sizeOf(T)),
            .Usage = if (initial != null) d.USAGE_IMMUTABLE else d.USAGE_DYNAMIC,
            .BindFlags = d.BIND_SHADER_RESOURCE,
            .CPUAccessFlags = if (initial != null) 0 else d.CPU_ACCESS_WRITE,
            .MiscFlags = d.RESOURCE_MISC_BUFFER_STRUCTURED,
            .StructureByteStride = @sizeOf(T),
        };
        const data: d.SUBRESOURCE_DATA = .{ .pSysMem = if (initial) |i| i.ptr else null };
        if (w.failed(dev.vtbl.CreateBuffer(dev, &desc, if (initial != null) &data else null, &s.buf))) return error.BufferFailed;
        errdefer w.Com.release(&s.buf);
        const view: d.SHADER_RESOURCE_VIEW_DESC = .{ .ViewDimension = d.SRV_DIMENSION_BUFFER, .NumElements = @intCast(count) };
        if (w.failed(dev.vtbl.CreateShaderResourceView(dev, s.buf.?, &view, &s.srv))) return error.BufferFailed;
        return s;
    }

    fn releaseStream(s: *Stream) void {
        w.Com.release(&s.srv);
        w.Com.release(&s.buf);
    }

    fn releaseTargets(g: *Gpu) void {
        w.Com.release(&g.hdr_ms_rtv);
        w.Com.release(&g.hdr_ms);
        w.Com.release(&g.depth_dsv);
        w.Com.release(&g.depth_ms);
        w.Com.release(&g.hdr_srv);
        w.Com.release(&g.hdr);
        w.Com.release(&g.offscreen_rtv);
        w.Com.release(&g.offscreen);
        w.Com.release(&g.staging);
    }

    fn releaseDevice(g: *Gpu) void {
        if (g.ctx) |ctx| ctx.vtbl.ClearState(ctx);
        g.releaseTargets();
        w.Com.release(&g.back_rtv);
        w.Com.release(&g.swap);
        w.Com.release(&g.font_srv);
        w.Com.release(&g.font_tex);
        w.Com.release(&g.mesh_ib);
        releaseStream(&g.mesh);
        releaseStream(&g.inst);
        releaseStream(&g.dyn);
        releaseStream(&g.part);
        releaseStream(&g.hud);
        w.Com.release(&g.cb_scene);
        w.Com.release(&g.cb_arm);
        w.Com.release(&g.cb_post);
        w.Com.release(&g.cb_draw);
        w.Com.release(&g.sampler);
        w.Com.release(&g.ds_rw);
        w.Com.release(&g.ds_ro);
        w.Com.release(&g.ds_off);
        w.Com.release(&g.blend_none);
        w.Com.release(&g.blend_alpha);
        w.Com.release(&g.blend_add);
        w.Com.release(&g.raster);
        inline for (comptime std.meta.fieldNames(Shaders)) |name| w.Com.release(&@field(g.sh, name));
        w.Com.release(&g.ctx);
        w.Com.release(&g.device);
    }

    /// Rebuild the device and everything on it after the system took the old one away. The frame that was
    /// being drawn is lost; the next one is drawn normally.
    fn recover(g: *Gpu) !void {
        const width = g.width;
        const height = g.height;
        g.releaseDevice();
        try g.createDevice();
        if (g.mesh_verts.len > 0) try g.createMeshes();
        if (g.font_pixels.len > 0) try g.createFont();
        if (g.hwnd != null) try g.createSwapChain();
        g.width = 0;
        g.height = 0;
        g.resize(width, height, g.with_offscreen);
        g.recoveries += 1;
        std.debug.print("Direct3D device rebuilt after it was removed ({d})\n", .{g.recoveries});
    }

    // ------------------------------------------------------------------------ window

    /// Create the swap chain for the window. Flip-model presentation, which is what Windows 10 composes
    /// without a copy; Alt+Enter is left to the window code, which makes a borderless window of it.
    pub fn attach(g: *Gpu, hwnd: w.HWND) !void {
        g.hwnd = hwnd;
        try g.createSwapChain();
    }

    fn createSwapChain(g: *Gpu) !void {
        var dxgi: ?*d.DxgiDevice = w.Com.query(g.device.?, &d.IID_IDXGIDevice, d.DxgiDevice);
        defer w.Com.release(&dxgi);
        if (dxgi == null) return error.NoDxgiDevice;
        var adapter: ?*d.Adapter = null;
        if (w.failed(dxgi.?.vtbl.GetAdapter(dxgi.?, &adapter)) or adapter == null) return error.NoDxgiAdapter;
        defer w.Com.release(&adapter);
        var raw: ?*anyopaque = null;
        if (w.failed(adapter.?.vtbl.GetParent(adapter.?, &d.IID_IDXGIFactory2, &raw)) or raw == null) return error.NoDxgiFactory;
        var factory: ?*d.Factory2 = @ptrCast(@alignCast(raw));
        defer w.Com.release(&factory);

        var desc: d.SWAP_CHAIN_DESC1 = .{
            .Width = 0,
            .Height = 0,
            .Format = d.FORMAT_B8G8R8A8_UNORM,
            .BufferUsage = d.DXGI_USAGE_RENDER_TARGET_OUTPUT,
            .BufferCount = 2,
            .Scaling = d.DXGI_SCALING_STRETCH,
            .SwapEffect = d.DXGI_SWAP_EFFECT_FLIP_DISCARD,
            .AlphaMode = d.DXGI_ALPHA_MODE_IGNORE,
        };
        var hr = factory.?.vtbl.CreateSwapChainForHwnd(factory.?, g.device.?, g.hwnd, &desc, null, null, &g.swap);
        if (w.failed(hr) or g.swap == null) {
            // Flip-discard needs Windows 10; flip-sequential is the same model as Windows 8 had it.
            desc.SwapEffect = d.DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;
            hr = factory.?.vtbl.CreateSwapChainForHwnd(factory.?, g.device.?, g.hwnd, &desc, null, null, &g.swap);
        }
        if (w.failed(hr) or g.swap == null) {
            std.debug.print("swap chain creation failed (0x{x:0>8})\n", .{@as(u32, @bitCast(hr))});
            return error.SwapChainFailed;
        }
        _ = factory.?.vtbl.MakeWindowAssociation(factory.?, g.hwnd, d.DXGI_MWA_NO_ALT_ENTER);
        try g.createBackBufferView();
    }

    fn createBackBufferView(g: *Gpu) !void {
        const swap = g.swap.?;
        var raw: ?*anyopaque = null;
        if (w.failed(swap.vtbl.GetBuffer(swap, 0, &d.IID_ID3D11Texture2D, &raw)) or raw == null) return error.NoBackBuffer;
        var tex: ?*d.Texture2D = @ptrCast(raw);
        defer w.Com.release(&tex);
        const dev = g.device.?;
        if (w.failed(dev.vtbl.CreateRenderTargetView(dev, tex.?, null, &g.back_rtv))) return error.NoBackBuffer;
    }

    /// The window's client area changed size or moved to a display of another density. The scale is of no
    /// interest here: a swap chain is measured in pixels.
    pub fn resizeSurface(g: *Gpu, width: u32, height: u32, _: f64) void {
        g.resize(width, height, false);
    }

    // ------------------------------------------------------------------------ render targets

    fn texture(g: *Gpu, desc: d.TEXTURE2D_DESC) ?*d.Texture2D {
        const dev = g.device.?;
        var tex: ?*d.Texture2D = null;
        if (w.failed(dev.vtbl.CreateTexture2D(dev, &desc, null, &tex))) {
            std.debug.print("texture {d}x{d} format {d} could not be created\n", .{ desc.Width, desc.Height, desc.Format });
            return null;
        }
        return tex;
    }

    /// (Re)create the render targets for a target of `width` x `height` pixels.
    pub fn resize(g: *Gpu, width: u32, height: u32, with_offscreen: bool) void {
        if (width == g.width and height == g.height and g.hdr != null) return;
        const dev = g.device.?;
        const ctx = g.ctx.?;
        ctx.vtbl.OMSetRenderTargets(ctx, 0, null, null);
        g.releaseTargets();
        g.width = @max(width, 8);
        g.height = @max(height, 8);
        g.with_offscreen = with_offscreen;

        g.hdr_ms = g.texture(.{ .Width = g.width, .Height = g.height, .Format = d.FORMAT_R16G16B16A16_FLOAT, .SampleDesc = .{ .Count = samples }, .BindFlags = d.BIND_RENDER_TARGET });
        if (g.hdr_ms) |t| _ = dev.vtbl.CreateRenderTargetView(dev, t, null, &g.hdr_ms_rtv);
        g.depth_ms = g.texture(.{ .Width = g.width, .Height = g.height, .Format = d.FORMAT_D32_FLOAT, .SampleDesc = .{ .Count = samples }, .BindFlags = d.BIND_DEPTH_STENCIL });
        if (g.depth_ms) |t| _ = dev.vtbl.CreateDepthStencilView(dev, t, null, &g.depth_dsv);
        // The resolved image keeps a full mip chain, filled each frame, that the bloom taps read.
        g.hdr = g.texture(.{ .Width = g.width, .Height = g.height, .MipLevels = 0, .Format = d.FORMAT_R16G16B16A16_FLOAT, .BindFlags = d.BIND_RENDER_TARGET | d.BIND_SHADER_RESOURCE, .MiscFlags = d.RESOURCE_MISC_GENERATE_MIPS });
        if (g.hdr) |t| _ = dev.vtbl.CreateShaderResourceView(dev, t, null, &g.hdr_srv);
        if (with_offscreen) {
            g.offscreen = g.texture(.{ .Width = g.width, .Height = g.height, .Format = d.FORMAT_B8G8R8A8_UNORM, .BindFlags = d.BIND_RENDER_TARGET });
            if (g.offscreen) |t| _ = dev.vtbl.CreateRenderTargetView(dev, t, null, &g.offscreen_rtv);
            g.staging = g.texture(.{ .Width = g.width, .Height = g.height, .Format = d.FORMAT_B8G8R8A8_UNORM, .Usage = d.USAGE_STAGING, .BindFlags = 0, .CPUAccessFlags = d.CPU_ACCESS_READ });
        }
        if (g.swap) |swap| {
            // Every reference to the old back buffers has to be gone before they can be resized.
            w.Com.release(&g.back_rtv);
            ctx.vtbl.Flush(ctx);
            const hr = swap.vtbl.ResizeBuffers(swap, 0, g.width, g.height, d.FORMAT_UNKNOWN, 0);
            if (w.failed(hr)) std.debug.print("swap chain resize to {d}x{d} failed (0x{x:0>8})\n", .{ g.width, g.height, @as(u32, @bitCast(hr)) });
            g.createBackBufferView() catch {};
        }
    }

    // ------------------------------------------------------------------------ uploads

    /// The static meshes. A copy is kept so they can be uploaded again to a rebuilt device.
    pub fn uploadMeshes(g: *Gpu, verts: []const Vertex, indices: []const u32) void {
        g.mesh_verts = gpa.dupe(Vertex, verts) catch &.{};
        g.mesh_indices = gpa.dupe(u32, indices) catch &.{};
        g.createMeshes() catch std.debug.print("mesh upload failed\n", .{});
    }

    fn createMeshes(g: *Gpu) !void {
        const dev = g.device.?;
        g.mesh = try g.stream(Vertex, g.mesh_verts.len, g.mesh_verts);
        const desc: d.BUFFER_DESC = .{ .ByteWidth = @intCast(g.mesh_indices.len * 4), .Usage = d.USAGE_IMMUTABLE, .BindFlags = d.BIND_INDEX_BUFFER };
        if (w.failed(dev.vtbl.CreateBuffer(dev, &desc, &.{ .pSysMem = g.mesh_indices.ptr }, &g.mesh_ib))) return error.BufferFailed;
    }

    /// Upload the glyph atlas with a box-filtered mip chain, so text stays clean at every HUD size.
    pub fn uploadFont(g: *Gpu, _: std.mem.Allocator, pixels: []const u8, width: u32, height: u32) !void {
        g.font_pixels = try gpa.dupe(u8, pixels);
        g.font_w = width;
        g.font_h = height;
        try g.createFont();
    }

    fn createFont(g: *Gpu) !void {
        const dev = g.device.?;
        var chain = try common.MipChain.build(gpa, g.font_pixels, g.font_w, g.font_h);
        defer chain.deinit(gpa);
        var data: [16]d.SUBRESOURCE_DATA = undefined;
        for (chain.levels[0..chain.count], 0..) |level, i| data[i] = .{ .pSysMem = level.pixels.ptr, .SysMemPitch = level.w };
        const desc: d.TEXTURE2D_DESC = .{ .Width = g.font_w, .Height = g.font_h, .MipLevels = @intCast(chain.count), .Format = d.FORMAT_R8_UNORM, .Usage = d.USAGE_IMMUTABLE, .BindFlags = d.BIND_SHADER_RESOURCE };
        if (w.failed(dev.vtbl.CreateTexture2D(dev, &desc, &data, &g.font_tex))) return error.FontUploadFailed;
        if (w.failed(dev.vtbl.CreateShaderResourceView(dev, g.font_tex.?, null, &g.font_srv))) return error.FontUploadFailed;
    }

    // ------------------------------------------------------------------------ frame

    fn write(g: *Gpu, buf: ?*d.Buffer, bytes: []const u8) void {
        if (bytes.len == 0) return;
        const ctx = g.ctx.?;
        var map: d.MAPPED_SUBRESOURCE = .{};
        if (w.failed(ctx.vtbl.Map(ctx, buf orelse return, 0, d.MAP_WRITE_DISCARD, 0, &map))) return;
        const dst: [*]u8 = @ptrCast(map.pData orelse return);
        @memcpy(dst[0..bytes.len], bytes);
        ctx.vtbl.Unmap(ctx, buf.?, 0);
    }

    fn setViewport(g: *Gpu, znear: f32, zfar: f32) void {
        const ctx = g.ctx.?;
        const vp = [_]d.VIEWPORT{.{ .Width = @floatFromInt(g.width), .Height = @floatFromInt(g.height), .MinDepth = znear, .MaxDepth = zfar }};
        ctx.vtbl.RSSetViewports(ctx, 1, &vp);
    }

    fn setBlend(g: *Gpu, state: ?*d.BlendState) void {
        const ctx = g.ctx.?;
        ctx.vtbl.OMSetBlendState(ctx, state, null, 0xFFFFFFFF);
    }

    /// Encode and submit one frame. Returns false when nothing was drawn or shown: the window is hidden,
    /// or the device had to be rebuilt.
    pub fn submit(g: *Gpu, f: *const FrameDesc, wait: bool) bool {
        g.frame_no += 1;
        if (g.lose_at) |n| {
            if (g.frame_no == n) {
                g.lose_at = null;
                std.debug.print("{s}: dropping the device before frame {d}\n", .{ loss_env, n });
                g.recover() catch return false;
            }
        }
        const ctx = g.ctx.?;
        const target = if (g.swap != null) g.back_rtv else g.offscreen_rtv;
        if (target == null or g.hdr_ms_rtv == null or g.depth_dsv == null or g.hdr_srv == null) return false;
        if (g.occluded) {
            // Nothing can be seen. Ask without drawing whether that is still so.
            const hr = g.swap.?.vtbl.Present(g.swap.?, 0, d.DXGI_PRESENT_TEST);
            if (hr == d.DXGI_STATUS_OCCLUDED) return false;
            g.occluded = false;
        }

        g.write(g.inst.buf, std.mem.sliceAsBytes(g.instances[0..f.instance_count]));
        g.write(g.dyn.buf, std.mem.sliceAsBytes(g.dyn_verts[0..f.dyn_count]));
        g.write(g.part.buf, std.mem.sliceAsBytes(g.part_verts[0..f.part_count]));
        g.write(g.hud.buf, std.mem.sliceAsBytes(g.hud_verts[0..f.hud_count]));
        g.write(g.cb_scene, std.mem.asBytes(&f.scene));
        g.write(g.cb_arm, std.mem.asBytes(&f.arm));
        var post = f.post;
        post.c[0] = 1.0 / @as(f32, @floatFromInt(g.width));
        post.c[1] = 1.0 / @as(f32, @floatFromInt(g.height));
        g.write(g.cb_post, std.mem.asBytes(&post));

        ctx.vtbl.IASetInputLayout(ctx, null);
        ctx.vtbl.IASetPrimitiveTopology(ctx, d.PRIMITIVE_TOPOLOGY_TRIANGLELIST);
        ctx.vtbl.IASetIndexBuffer(ctx, g.mesh_ib, d.FORMAT_R32_UINT, 0);
        ctx.vtbl.RSSetState(ctx, g.raster);
        const samplers = [_]?*d.SamplerState{g.sampler};
        ctx.vtbl.PSSetSamplers(ctx, 0, 1, &samplers);
        const no_textures = [_]?*d.ShaderResourceView{ null, null };
        ctx.vtbl.PSSetShaderResources(ctx, 4, 2, &no_textures);
        // t0 is rebound per batch (static meshes or this frame's dynamic vertices); the rest stay.
        const streams = [_]?*d.ShaderResourceView{ g.inst.srv, g.part.srv, g.hud.srv };
        ctx.vtbl.VSSetShaderResources(ctx, 1, 3, &streams);

        // Scene.
        {
            const targets = [_]?*d.RenderTargetView{g.hdr_ms_rtv};
            ctx.vtbl.OMSetRenderTargets(ctx, 1, &targets, g.depth_dsv);
            const fc = f.scene.fog_color;
            ctx.vtbl.ClearRenderTargetView(ctx, g.hdr_ms_rtv.?, &.{ fc[0], fc[1], fc[2], 1 });
            ctx.vtbl.ClearDepthStencilView(ctx, g.depth_dsv.?, d.CLEAR_DEPTH, 1.0, 0);
            g.setViewport(0.1, 1.0);
            g.bindFrame(g.cb_scene);

            ctx.vtbl.VSSetShader(ctx, g.sh.scene_vs, null, 0);
            ctx.vtbl.PSSetShader(ctx, g.sh.scene_fs, null, 0);
            g.setBlend(g.blend_none);
            ctx.vtbl.OMSetDepthStencilState(ctx, g.ds_rw, 0);
            g.drawPass(f.batches, .solid);

            g.setBlend(g.blend_alpha);
            ctx.vtbl.OMSetDepthStencilState(ctx, g.ds_ro, 0);
            g.drawPass(f.batches, .blend);

            if (f.part_count > 0) {
                ctx.vtbl.VSSetShader(ctx, g.sh.part_vs, null, 0);
                ctx.vtbl.PSSetShader(ctx, g.sh.part_fs, null, 0);
                g.setBlend(g.blend_add);
                ctx.vtbl.Draw(ctx, f.part_count, 0);
            }

            // First-person arms: own projection, front slice of the depth range so the world never clips them.
            g.setViewport(0.0, 0.1);
            g.bindFrame(g.cb_arm);
            ctx.vtbl.VSSetShader(ctx, g.sh.scene_vs, null, 0);
            ctx.vtbl.PSSetShader(ctx, g.sh.scene_fs, null, 0);
            g.setBlend(g.blend_none);
            ctx.vtbl.OMSetDepthStencilState(ctx, g.ds_rw, 0);
            g.drawPass(f.batches, .arm);
        }

        // Resolve the samples, then the mip chain of the resolved HDR image feeds the bloom taps.
        ctx.vtbl.OMSetRenderTargets(ctx, 0, null, null);
        ctx.vtbl.ResolveSubresource(ctx, g.hdr.?, 0, g.hdr_ms.?, 0, d.FORMAT_R16G16B16A16_FLOAT);
        ctx.vtbl.GenerateMips(ctx, g.hdr_srv.?);

        // Tonemap + HUD.
        {
            const targets = [_]?*d.RenderTargetView{target};
            ctx.vtbl.OMSetRenderTargets(ctx, 1, &targets, null);
            g.setViewport(0.0, 1.0);
            const post_cb = [_]?*d.Buffer{g.cb_post};
            ctx.vtbl.PSSetConstantBuffers(ctx, 1, 1, &post_cb);
            ctx.vtbl.VSSetConstantBuffers(ctx, 1, 1, &post_cb);
            ctx.vtbl.OMSetDepthStencilState(ctx, g.ds_off, 0);
            g.setBlend(g.blend_none);
            ctx.vtbl.VSSetShader(ctx, g.sh.post_vs, null, 0);
            ctx.vtbl.PSSetShader(ctx, g.sh.post_fs, null, 0);
            const textures = [_]?*d.ShaderResourceView{ g.hdr_srv, g.font_srv };
            ctx.vtbl.PSSetShaderResources(ctx, 4, 2, &textures);
            ctx.vtbl.Draw(ctx, 3, 0);
            if (f.hud_count > 0 and g.font_srv != null) {
                ctx.vtbl.VSSetShader(ctx, g.sh.hud_vs, null, 0);
                ctx.vtbl.PSSetShader(ctx, g.sh.hud_fs, null, 0);
                g.setBlend(g.blend_alpha);
                ctx.vtbl.Draw(ctx, f.hud_count, 0);
            }
            // The HDR image is a render target again next frame and may not stay bound as an input.
            ctx.vtbl.PSSetShaderResources(ctx, 4, 2, &no_textures);
            ctx.vtbl.OMSetRenderTargets(ctx, 0, null, null);
        }

        if (g.swap) |swap| {
            const hr = swap.vtbl.Present(swap, 1, 0);
            if (hr == d.DXGI_STATUS_OCCLUDED) {
                g.occluded = true;
            } else if (hr == d.DXGI_ERROR_DEVICE_REMOVED or hr == d.DXGI_ERROR_DEVICE_RESET) {
                g.recover() catch |err| std.debug.print("the Direct3D device was removed and could not be rebuilt: {s}\n", .{@errorName(err)});
                return false;
            }
        } else {
            if (wait) ctx.vtbl.Flush(ctx);
            const dev = g.device.?;
            if (w.failed(dev.vtbl.GetDeviceRemovedReason(dev))) {
                g.recover() catch {};
                return false;
            }
        }
        return true;
    }

    fn bindFrame(g: *Gpu, cb: ?*d.Buffer) void {
        const ctx = g.ctx.?;
        const frame_cb = [_]?*d.Buffer{cb};
        ctx.vtbl.VSSetConstantBuffers(ctx, 0, 1, &frame_cb);
        ctx.vtbl.PSSetConstantBuffers(ctx, 0, 1, &frame_cb);
        const draw_cb = [_]?*d.Buffer{g.cb_draw};
        ctx.vtbl.VSSetConstantBuffers(ctx, 2, 1, &draw_cb);
    }

    fn drawPass(g: *Gpu, batches: []const Batch, pass: Pass) void {
        const ctx = g.ctx.?;
        var bound_dynamic: ?bool = null;
        for (batches) |b| {
            if (b.pass != pass or b.instance_count == 0) continue;
            if (bound_dynamic == null or bound_dynamic.? != b.dynamic) {
                const verts = [_]?*d.ShaderResourceView{if (b.dynamic) g.dyn.srv else g.mesh.srv};
                ctx.vtbl.VSSetShaderResources(ctx, 0, 1, &verts);
                bound_dynamic = b.dynamic;
            }
            // The draw itself starts at zero in both streams and the shader adds the bases, because
            // SV_VertexID and SV_InstanceID count from zero whatever the draw call's offsets are.
            const draw: Draw = .{ .base_vertex = if (b.dynamic) b.vertex_start else b.mesh.base_vertex, .base_instance = b.first_instance };
            g.write(g.cb_draw, std.mem.asBytes(&draw));
            if (b.dynamic) {
                ctx.vtbl.DrawInstanced(ctx, b.vertex_count, b.instance_count, 0, 0);
            } else {
                ctx.vtbl.DrawIndexedInstanced(ctx, b.mesh.index_count, b.instance_count, b.mesh.index_start, 0, 0);
            }
        }
    }

    /// Copy the offscreen target out as tightly packed BGRA8 rows.
    pub fn readback(g: *Gpu, out: []u8) void {
        const row = @as(usize, g.width) * 4;
        std.debug.assert(out.len >= row * g.height);
        const ctx = g.ctx.?;
        const staging = g.staging orelse return;
        ctx.vtbl.CopyResource(ctx, staging, g.offscreen orelse return);
        var map: d.MAPPED_SUBRESOURCE = .{};
        if (w.failed(ctx.vtbl.Map(ctx, staging, 0, d.MAP_READ, 0, &map))) return;
        defer ctx.vtbl.Unmap(ctx, staging, 0);
        const src: [*]const u8 = @ptrCast(map.pData orelse return);
        for (0..g.height) |y| @memcpy(out[y * row ..][0..row], src[y * map.RowPitch ..][0..row]);
    }
};
