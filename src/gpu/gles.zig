//! The OpenGL ES 3.0 backend of `gpu.zig`, written for the Mali-G51 of a Samsung television and run on
//! any ES 3.0 implementation. It draws the frame the Metal and Direct3D backends draw: an HDR scene pass
//! (multisampled, resolved and mip-chained for bloom) and a post pass that tonemaps to the target and draws
//! the HUD.
//!
//! Where it differs from the other two, and why:
//!  * ES 3.0 has no buffer a shader can index by vertex and instance number, so vertex and instance data
//!    are attributes. A batch's base vertex and base instance are expressed by pointing the attributes at
//!    them, which ES 3.0 can do and a draw call's parameters cannot.
//!  * The game's projection puts depth in 0..1; the vertex shaders rescale it to OpenGL's -w..w.
//!  * OpenGL's textures have their origin at the bottom left. The scene is drawn and read back that way
//!    round, so nothing is flipped until `readback`, which hands out rows from the top as the others do.
//!  * The scene may be drawn smaller than the output (`tuning.scene_height`). It is then tonemapped at
//!    its own size and stretched to the output by one more pass, which adds the film grain, and the HUD
//!    is drawn at full size over that. The television's GPU cannot shade the scene's materials at
//!    1920x1080 at the display's rate.
//!  * How small is decided as the game runs, where the platform paces frames to a display and can say
//!    which were shown on time (it then calls `Gpu.paced`): the scene has a ladder of sizes between
//!    `tuning.scene_height` and `tuning.min_scene_height`, steps down when frames reach the display
//!    late or are dropped, and tries a step up when they have been on time for a while. A frame that misses the
//!    display's refresh is shown for two, which is seen as a stutter; a softer image is not. The GPU's
//!    own time cannot be had on the television: its driver has EXT_disjoint_timer_query and answers
//!    every query with zero, and it slows the GPU's clock under a light load, so that a fence at the
//!    end of a frame is signalled no sooner for a small scene than for one that just fits.
//!  * The first-person arms are drawn first, since nothing is ever in front of them, and what they
//!    cover is then not shaded. The rest of the opaque geometry is listed nearest first already.
//!  * A tile-based GPU pays for every attachment it has to write back to memory. Multisampling uses
//!    EXT_multisampled_render_to_texture where the driver has it, which resolves inside the tile, and the
//!    depth buffer is invalidated when the scene pass ends.
//!
//! No headers and no link-time library: the entry points are looked up in libGLESv2 when the backend
//! starts. On the television the engine has made a context current before the game is asked to draw. On
//! a desktop host the backend makes its own offscreen context through ANGLE (see `Host`), which is how the
//! port is checked without the television: `dentro --shots` then renders through this file.

const std = @import("std");
const builtin = @import("builtin");
const bake = @import("gles_bake.zig");
const common = @import("../gpu.zig");

const Vertex = common.Vertex;
const Instance = common.Instance;
const PVertex = common.PVertex;
const HVertex = common.HVertex;
const Frame = common.Frame;
const Post = common.Post;
const Pass = common.Pass;
const Batch = common.Batch;
const FrameDesc = common.FrameDesc;

/// The shader source this backend compiles, and the name it has beside the executable.
pub const shader_file = "shaders.glsl";
pub const embedded_shaders: [:0]const u8 = @embedFile("../shaders/shaders.glsl");

/// The television is the one Linux target; anywhere else this backend is a development tool.
const on_device = builtin.os.tag == .linux;

/// What the scene pass may spend. Set before `Gpu.init`.
pub const Tuning = struct {
    /// Height of the scene image in pixels; 0 draws it at the height of the output. The width follows
    /// the output's aspect ratio.
    scene_height: u32 = 0,
    /// The least height the scene image may shrink to when the GPU does not keep up with the display.
    /// 0, or a value not below `scene_height`, keeps the one size.
    min_scene_height: u32 = 0,
    /// Samples per pixel of the scene pass, clamped to what the driver offers; 1 turns multisampling off.
    samples: u32 = 4,
    /// Draw the materials' noise and cell patterns from baked textures (see gles_bake.zig) instead of
    /// computing them at every pixel. The television needs it; a desktop host, which is there to compare
    /// this backend's frames with the other backends', computes them unless told otherwise.
    baked_patterns: bool = on_device,
};
pub var tuning: Tuning = .{};

/// Where a frame's time goes, for a development build that asks. With `profile` pointing at one of these,
/// `submit` waits for the GPU after each phase and adds what the phase took, which makes the frame slower
/// than it is and its parts measurable.
pub const Profile = struct {
    frames: u32 = 0,
    /// Nanoseconds per phase, summed over `frames`.
    ns: [phase_names.len]u64 = @splat(0),
    /// Draw calls, instances and triangles of the scene passes, summed over `frames`.
    draws: u64 = 0,
    instances: u64 = 0,
    triangles: u64 = 0,

    pub const phase_names = [_][]const u8{ "upload", "arms", "solid", "blend", "mips", "post", "upscale", "hud" };
};
pub var profile: ?*Profile = null;

const Timespec = extern struct { sec: c_long, nsec: c_long };
extern "c" fn clock_gettime(id: c_int, ts: *Timespec) c_int;

/// The monotonic clock, in nanoseconds.
pub fn nowNs() u64 {
    var ts: Timespec = .{ .sec = 0, .nsec = 0 };
    _ = clock_gettime(if (builtin.os.tag == .linux) 1 else 6, &ts);
    return @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
}

/// End of a phase of `submit`: under a profile, wait for the GPU and book the time since `since`.
fn phaseEnd(index: usize, since: *u64) void {
    const p = profile orelse return;
    gl.glFinish();
    const now = nowNs();
    p.ns[index] += now - since.*;
    since.* = now;
}

/// The text of the last failure (a shader's compile log, a missing entry point), for a caller with no
/// terminal to print to. Empty when nothing has failed.
pub fn diagnostic() []const u8 {
    return diagnostic_buf[0..diagnostic_len];
}
var diagnostic_buf: [4096]u8 = undefined;
var diagnostic_len: usize = 0;

fn fail(comptime format: []const u8, args: anytype) void {
    const text = std.fmt.bufPrint(&diagnostic_buf, format, args) catch blk: {
        const marker = " [cut]";
        @memcpy(diagnostic_buf[diagnostic_buf.len - marker.len ..], marker);
        break :blk diagnostic_buf[0..];
    };
    diagnostic_len = text.len;
    std.debug.print("gles: {s}\n", .{text});
}

// ---------------------------------------------------------------------------------- the API, by name

const Enum = c_uint;
const Int = c_int;
const Uint = c_uint;

const Api = struct {
    glGetString: *const fn (Enum) callconv(.c) ?[*:0]const u8,
    glGetIntegerv: *const fn (Enum, *Int) callconv(.c) void,
    glGetError: *const fn () callconv(.c) Enum,
    glViewport: *const fn (Int, Int, Int, Int) callconv(.c) void,
    glDepthRangef: *const fn (f32, f32) callconv(.c) void,
    glClearColor: *const fn (f32, f32, f32, f32) callconv(.c) void,
    glClearDepthf: *const fn (f32) callconv(.c) void,
    glClear: *const fn (Uint) callconv(.c) void,
    glEnable: *const fn (Enum) callconv(.c) void,
    glDisable: *const fn (Enum) callconv(.c) void,
    glDepthFunc: *const fn (Enum) callconv(.c) void,
    glDepthMask: *const fn (u8) callconv(.c) void,
    glColorMask: *const fn (u8, u8, u8, u8) callconv(.c) void,
    glBlendFuncSeparate: *const fn (Enum, Enum, Enum, Enum) callconv(.c) void,
    glCreateShader: *const fn (Enum) callconv(.c) Uint,
    glShaderSource: *const fn (Uint, Int, [*]const [*]const u8, [*]const Int) callconv(.c) void,
    glCompileShader: *const fn (Uint) callconv(.c) void,
    glGetShaderiv: *const fn (Uint, Enum, *Int) callconv(.c) void,
    glGetShaderInfoLog: *const fn (Uint, Int, ?*Int, [*]u8) callconv(.c) void,
    glDeleteShader: *const fn (Uint) callconv(.c) void,
    glCreateProgram: *const fn () callconv(.c) Uint,
    glAttachShader: *const fn (Uint, Uint) callconv(.c) void,
    glLinkProgram: *const fn (Uint) callconv(.c) void,
    glGetProgramiv: *const fn (Uint, Enum, *Int) callconv(.c) void,
    glGetProgramInfoLog: *const fn (Uint, Int, ?*Int, [*]u8) callconv(.c) void,
    glUseProgram: *const fn (Uint) callconv(.c) void,
    glGetUniformLocation: *const fn (Uint, [*:0]const u8) callconv(.c) Int,
    glUniform1i: *const fn (Int, Int) callconv(.c) void,
    glUniform1f: *const fn (Int, f32) callconv(.c) void,
    glUniform2f: *const fn (Int, f32, f32) callconv(.c) void,
    glGetUniformBlockIndex: *const fn (Uint, [*:0]const u8) callconv(.c) Uint,
    glUniformBlockBinding: *const fn (Uint, Uint, Uint) callconv(.c) void,
    glBindBufferBase: *const fn (Enum, Uint, Uint) callconv(.c) void,
    glGenBuffers: *const fn (Int, [*]Uint) callconv(.c) void,
    glBindBuffer: *const fn (Enum, Uint) callconv(.c) void,
    glBufferData: *const fn (Enum, isize, ?*const anyopaque, Enum) callconv(.c) void,
    glGenVertexArrays: *const fn (Int, [*]Uint) callconv(.c) void,
    glBindVertexArray: *const fn (Uint) callconv(.c) void,
    glEnableVertexAttribArray: *const fn (Uint) callconv(.c) void,
    glVertexAttribPointer: *const fn (Uint, Int, Enum, u8, Int, usize) callconv(.c) void,
    glVertexAttribDivisor: *const fn (Uint, Uint) callconv(.c) void,
    glDrawArrays: *const fn (Enum, Int, Int) callconv(.c) void,
    glDrawArraysInstanced: *const fn (Enum, Int, Int, Int) callconv(.c) void,
    glDrawElementsInstanced: *const fn (Enum, Int, Enum, usize, Int) callconv(.c) void,
    glGenTextures: *const fn (Int, [*]Uint) callconv(.c) void,
    glDeleteTextures: *const fn (Int, [*]const Uint) callconv(.c) void,
    glBindTexture: *const fn (Enum, Uint) callconv(.c) void,
    glActiveTexture: *const fn (Enum) callconv(.c) void,
    glTexParameteri: *const fn (Enum, Enum, Int) callconv(.c) void,
    glTexImage2D: *const fn (Enum, Int, Int, Int, Int, Int, Enum, Enum, ?*const anyopaque) callconv(.c) void,
    glTexStorage2D: *const fn (Enum, Int, Enum, Int, Int) callconv(.c) void,
    glTexSubImage2D: *const fn (Enum, Int, Int, Int, Int, Int, Enum, Enum, ?*const anyopaque) callconv(.c) void,
    glTexStorage3D: *const fn (Enum, Int, Enum, Int, Int, Int) callconv(.c) void,
    glTexSubImage3D: *const fn (Enum, Int, Int, Int, Int, Int, Int, Int, Enum, Enum, ?*const anyopaque) callconv(.c) void,
    glPixelStorei: *const fn (Enum, Int) callconv(.c) void,
    glGenerateMipmap: *const fn (Enum) callconv(.c) void,
    glGenFramebuffers: *const fn (Int, [*]Uint) callconv(.c) void,
    glDeleteFramebuffers: *const fn (Int, [*]const Uint) callconv(.c) void,
    glBindFramebuffer: *const fn (Enum, Uint) callconv(.c) void,
    glFramebufferTexture2D: *const fn (Enum, Enum, Enum, Uint, Int) callconv(.c) void,
    glFramebufferRenderbuffer: *const fn (Enum, Enum, Enum, Uint) callconv(.c) void,
    glCheckFramebufferStatus: *const fn (Enum) callconv(.c) Enum,
    glGenRenderbuffers: *const fn (Int, [*]Uint) callconv(.c) void,
    glDeleteRenderbuffers: *const fn (Int, [*]const Uint) callconv(.c) void,
    glBindRenderbuffer: *const fn (Enum, Uint) callconv(.c) void,
    glRenderbufferStorage: *const fn (Enum, Enum, Int, Int) callconv(.c) void,
    glRenderbufferStorageMultisample: *const fn (Enum, Int, Enum, Int, Int) callconv(.c) void,
    glBlitFramebuffer: *const fn (Int, Int, Int, Int, Int, Int, Int, Int, Uint, Enum) callconv(.c) void,
    glInvalidateFramebuffer: *const fn (Enum, Int, [*]const Enum) callconv(.c) void,
    glReadPixels: *const fn (Int, Int, Int, Int, Enum, Enum, [*]u8) callconv(.c) void,
    glFinish: *const fn () callconv(.c) void,
    // EXT_multisampled_render_to_texture: a multisampled pass whose colour attachment is an ordinary
    // texture, resolved by the driver when the pass ends.
    glFramebufferTexture2DMultisampleEXT: ?*const fn (Enum, Enum, Enum, Uint, Int, Int) callconv(.c) void,
    glRenderbufferStorageMultisampleEXT: ?*const fn (Enum, Int, Enum, Int, Int) callconv(.c) void,
};

const GL = struct {
    const DEPTH_BUFFER_BIT = 0x0100;
    const COLOR_BUFFER_BIT = 0x4000;
    const TRIANGLES = 0x0004;
    const DEPTH_TEST = 0x0B71;
    const BLEND = 0x0BE2;
    const CULL_FACE = 0x0B44;
    const DITHER = 0x0BD0;
    const SCISSOR_TEST = 0x0C11;
    const LEQUAL = 0x0203;
    const ZERO = 0;
    const ONE = 1;
    const SRC_ALPHA = 0x0302;
    const ONE_MINUS_SRC_ALPHA = 0x0303;
    const FLOAT = 0x1406;
    const UNSIGNED_INT = 0x1405;
    const UNSIGNED_BYTE = 0x1401;
    const RGBA = 0x1908;
    const RED = 0x1903;
    const R8 = 0x8229;
    const RGBA8 = 0x8058;
    const RGBA16F = 0x881A;
    const DEPTH_COMPONENT24 = 0x81A6;
    const TEXTURE_2D = 0x0DE1;
    const TEXTURE_3D = 0x806F;
    const TEXTURE_WRAP_R = 0x8072;
    const REPEAT = 0x2901;
    const TEXTURE0 = 0x84C0;
    const TEXTURE_MIN_FILTER = 0x2801;
    const TEXTURE_MAG_FILTER = 0x2800;
    const TEXTURE_WRAP_S = 0x2802;
    const TEXTURE_WRAP_T = 0x2803;
    const TEXTURE_MAX_LEVEL = 0x813D;
    const LINEAR = 0x2601;
    const LINEAR_MIPMAP_LINEAR = 0x2703;
    const NEAREST = 0x2600;
    const CLAMP_TO_EDGE = 0x812F;
    const ARRAY_BUFFER = 0x8892;
    const ELEMENT_ARRAY_BUFFER = 0x8893;
    const UNIFORM_BUFFER = 0x8A11;
    const STATIC_DRAW = 0x88E4;
    const STREAM_DRAW = 0x88E0;
    const FRAGMENT_SHADER = 0x8B30;
    const VERTEX_SHADER = 0x8B31;
    const COMPILE_STATUS = 0x8B81;
    const LINK_STATUS = 0x8B82;
    const FRAMEBUFFER = 0x8D40;
    const READ_FRAMEBUFFER = 0x8CA8;
    const DRAW_FRAMEBUFFER = 0x8CA9;
    const RENDERBUFFER = 0x8D41;
    const COLOR_ATTACHMENT0 = 0x8CE0;
    const DEPTH_ATTACHMENT = 0x8D00;
    const FRAMEBUFFER_COMPLETE = 0x8CD5;
    const MAX_SAMPLES = 0x8D57;
    const RENDERER = 0x1F01;
    const VERSION = 0x1F02;
    const EXTENSIONS = 0x1F03;
    const UNPACK_ALIGNMENT = 0x0CF5;
    const PACK_ALIGNMENT = 0x0D05;
    const INVALID_INDEX = 0xFFFFFFFF;
};

extern "c" fn dlopen(path: ?[*:0]const u8, mode: c_int) ?*anyopaque;
extern "c" fn dlsym(handle: ?*anyopaque, name: [*:0]const u8) ?*anyopaque;
extern "c" fn getenv(name: [*:0]const u8) ?[*:0]const u8;

/// RTLD_LAZY | RTLD_GLOBAL, which are different numbers on Linux and on macOS.
const dl_mode: c_int = if (builtin.os.tag == .linux) 0x101 else 0x9;

/// Fill a struct of function pointers by field name. Optional fields may stay null; the name of a
/// required one that is missing is reported.
fn load(comptime T: type, lib: ?*anyopaque) !T {
    var table: T = undefined;
    inline for (@typeInfo(T).@"struct".field_names) |field| {
        const address = dlsym(lib, field ++ "\x00") orelse if (proc_address) |get| get(field ++ "\x00") else null;
        const F = @FieldType(T, field);
        if (@typeInfo(F) == .optional) {
            @field(table, field) = if (address) |a| @ptrCast(@alignCast(a)) else null;
        } else {
            @field(table, field) = @ptrCast(@alignCast(address orelse {
                fail("the OpenGL ES library has no {s}", .{field});
                return error.MissingGlFunction;
            }));
        }
    }
    return table;
}

var gl: Api = undefined;

/// EGL's own lookup of a GL entry point by name. A library need not export the functions of an
/// extension as symbols, and the television's does not; this finds them. Set before the API is loaded.
var proc_address: ?*const fn ([*:0]const u8) callconv(.c) ?*anyopaque = null;

// ---------------------------------------------------------------------------------- a context off the device

/// An offscreen OpenGL ES 3 context for a desktop host, made through ANGLE's libEGL. ANGLE is not
/// installed as a system library anywhere; every Chromium and Electron application carries a build of it,
/// and the directory holding its `libEGL` and `libGLESv2` is named with DENTRO_ANGLE_DIR. Without the
/// variable a few usual locations are tried.
const Host = struct {
    const Egl = struct {
        eglGetDisplay: *const fn (?*anyopaque) callconv(.c) ?*anyopaque,
        eglInitialize: *const fn (?*anyopaque, ?*c_int, ?*c_int) callconv(.c) c_uint,
        eglBindAPI: *const fn (c_uint) callconv(.c) c_uint,
        eglChooseConfig: *const fn (?*anyopaque, [*]const c_int, [*]?*anyopaque, c_int, *c_int) callconv(.c) c_uint,
        eglCreatePbufferSurface: *const fn (?*anyopaque, ?*anyopaque, [*]const c_int) callconv(.c) ?*anyopaque,
        eglCreateContext: *const fn (?*anyopaque, ?*anyopaque, ?*anyopaque, [*]const c_int) callconv(.c) ?*anyopaque,
        eglMakeCurrent: *const fn (?*anyopaque, ?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.c) c_uint,
        eglGetError: *const fn () callconv(.c) c_int,
    };

    const ext = if (builtin.os.tag == .macos) "dylib" else if (builtin.os.tag == .windows) "dll" else "so";
    const usual_dirs = [_][]const u8{
        "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Libraries",
        "/Applications/Visual Studio Code.app/Contents/Frameworks/Electron Framework.framework/Libraries",
        "/Applications/Chromium.app/Contents/Frameworks/Chromium Framework.framework/Libraries",
    };

    fn open(dir: []const u8, name: []const u8) ?*anyopaque {
        var buf: [1200]u8 = undefined;
        const path = std.fmt.bufPrintSentinel(&buf, "{s}/{s}.{s}", .{ dir, name, ext }, 0) catch return null;
        return dlopen(path.ptr, dl_mode);
    }

    /// Opens ANGLE, makes a context current on this thread and returns the library the GL entry points
    /// are in.
    fn create() !?*anyopaque {
        var gles: ?*anyopaque = null;
        var egl_lib: ?*anyopaque = null;
        if (getenv("DENTRO_ANGLE_DIR")) |dir| {
            gles = open(std.mem.span(dir), "libGLESv2");
            egl_lib = open(std.mem.span(dir), "libEGL");
        } else for (usual_dirs) |dir| {
            gles = open(dir, "libGLESv2");
            egl_lib = open(dir, "libEGL");
            if (gles != null and egl_lib != null) break;
        }
        if (gles == null or egl_lib == null) {
            fail("no ANGLE found: set DENTRO_ANGLE_DIR to a directory holding libEGL.{s} and libGLESv2.{s} (any Chromium or Electron application has one)", .{ ext, ext });
            return error.NoAngle;
        }
        const egl = try load(Egl, egl_lib);
        const display = egl.eglGetDisplay(null) orelse return error.NoEglDisplay;
        if (egl.eglInitialize(display, null, null) == 0) return error.NoEglDisplay;
        _ = egl.eglBindAPI(0x30A0); // EGL_OPENGL_ES_API
        // A pbuffer the backend never draws to: every pass goes to a framebuffer object.
        const want = [_]c_int{ 0x3033, 0x0001, 0x3040, 0x0040, 0x3024, 8, 0x3023, 8, 0x3022, 8, 0x3021, 8, 0x3038 };
        var config: [1]?*anyopaque = .{null};
        var count: c_int = 0;
        if (egl.eglChooseConfig(display, &want, &config, 1, &count) == 0 or count == 0) return error.NoEglConfig;
        const surface = egl.eglCreatePbufferSurface(display, config[0], &[_]c_int{ 0x3057, 16, 0x3056, 16, 0x3038 }) orelse return error.NoEglSurface;
        const context = egl.eglCreateContext(display, config[0], null, &[_]c_int{ 0x3098, 3, 0x3038 }) orelse {
            fail("ANGLE refused an OpenGL ES 3 context (EGL error 0x{x})", .{egl.eglGetError()});
            return error.NoEglContext;
        };
        if (egl.eglMakeCurrent(display, surface, surface, context) == 0) return error.NoEglContext;
        return gles;
    }
};

// ---------------------------------------------------------------------------------- the backend

/// Uniform block binding points.
const frame_binding = 0;
const post_binding = 1;
/// Texture units: 0 is whatever the pass in hand samples, 1 to 3 the baked patterns, and this the grain.
const grain_unit = 4;

const Program = enum { scene, part, post, hud, upscale };

const max_sizes = 8;
/// Each size of the ladder has this fraction of the height of the one above: seven tenths of its pixels.
const size_step = 0.84;

/// The adaptation's measures, in frames. A step up waits for `calm_needed` frames' worth of calm and for
/// the hold to run out; the hold starts at `hold_least` and doubles, up to `hold_most`, each time a step
/// up is taken back within `trial` frames, so a size the GPU cannot hold is tried rarely, and it returns
/// to `hold_least` when a step up lasts.
const settle_frames = 45;
const step_settle_frames = 8;
const calm_needed = 240;
const hold_least = 300;
const hold_most = 4800;
const trial = 900;
/// A frame shown a refresh late adds `late_strain` to the strain and any other takes one off; at
/// `strain_limit` the size steps down: two late frames close together, or three in a short while. One
/// alone, which any frame can be for reasons that are not the GPU's, passes.
const late_strain = 8;
const strain_limit = 14;
/// A frame shown for two refreshes is counted apart, and more leniently: the television shows a few a
/// second twice whatever the scene costs, and a dozen or more when the GPU cannot keep up. Each adds
/// `held_strain` and every frame takes one off, so four a second hold level and more than that reach
/// `held_limit` within the second.
const held_strain = 15;
const held_limit = 60;
/// What a late frame and a frame shown twice take from the calm that a step up waits for.
const calm_lost_late = 60;
const calm_lost_held = 15;

/// The render targets of one size of the scene image.
const Target = struct {
    w: u32 = 0,
    h: u32 = 0,
    /// The resolved scene: half-float colour, with the mip levels the bloom taps read.
    tex_hdr: Uint = 0,
    /// The scene pass's framebuffer, and where it is resolved to when the driver does not resolve it
    /// itself (0 when it does, or when the pass is not multisampled).
    fbo_scene: Uint = 0,
    fbo_resolve: Uint = 0,
    rb_depth: Uint = 0,
    rb_color: Uint = 0,
    /// The tonemapped image at the scene's size, when that is smaller than the output: the post pass
    /// draws into it and it is scaled up to the output, so the pass costs what the scene's size costs.
    tex_ldr: Uint = 0,
    fbo_ldr: Uint = 0,
};

pub const Gpu = struct {
    width: u32 = 0,
    height: u32 = 0,
    /// Size of the scene image this frame; the output's, or smaller (see `Tuning.scene_height`).
    scene_w: u32 = 0,
    scene_h: u32 = 0,
    /// The sizes the scene image can have, largest first, each with its own render targets, and the one
    /// in use. One size unless the scene adapts to the GPU's time.
    sizes: [max_sizes]Target = @splat(.{}),
    size_count: u8 = 0,
    size: u8 = 0,
    /// Frames shown on time lately: up by one with each, down by a good many with each that was not.
    calm: u32 = 0,
    /// Rises with every frame shown late, falls with the rest; and the same for frames shown twice.
    strain: u32 = 0,
    held: u32 = 0,
    /// Frames until the size may next step up, the wait the next step down will set, and frames since
    /// the last step up, while that step is still on trial.
    hold: u32 = 0,
    hold_next: u32 = hold_least,
    on_trial: ?u32 = null,
    /// Frames still to pass before the adaptation judges any: the first frames after a start, a resume
    /// or a step compile shaders, fill caches, or were drawn at the size before.
    unsettled: u32 = settle_frames,
    /// Steps down and up since the start, for a log.
    steps_down: u32 = 0,
    steps_up: u32 = 0,

    // CPU-side arrays the next frame is written into; uploaded by `submit`.
    instances: [*]Instance = undefined,
    dyn_verts: [*]Vertex = undefined,
    part_verts: [*]PVertex = undefined,
    hud_verts: [*]HVertex = undefined,

    programs: [5]Uint = @splat(0),
    lod_bias_at: Int = -1,
    last_pass_at: Int = -1,
    grain_at: Int = -1,
    vao_mesh: Uint = 0,
    vao_dyn: Uint = 0,
    vao_part: Uint = 0,
    vao_hud: Uint = 0,
    vao_post: Uint = 0,
    vb_mesh: Uint = 0,
    ib_mesh: Uint = 0,
    vb_inst: Uint = 0,
    vb_dyn: Uint = 0,
    vb_part: Uint = 0,
    vb_hud: Uint = 0,
    ubo_scene: Uint = 0,
    ubo_arm: Uint = 0,
    ubo_post: Uint = 0,
    tex_font: Uint = 0,
    tex_offscreen: Uint = 0,
    /// The baked patterns, when the scene program draws from them.
    tex_noise: Uint = 0,
    tex_cells: Uint = 0,
    tex_fbm: Uint = 0,
    /// Noise the stretch to the output takes its film grain from.
    tex_grain: Uint = 0,
    fbo_offscreen: Uint = 0,
    samples: u32 = 1,
    /// EXT_multisampled_render_to_texture is there: the scene's colour attachment is the texture itself.
    implicit_resolve: bool = false,
    msrtt: bool = false,
    max_samples: u32 = 1,
    /// The post pass draws to the window (the default framebuffer) instead of the offscreen texture.
    to_window: bool = false,

    pub fn init(shader_src: [:0]const u8, _: common.Options) !Gpu {
        diagnostic_len = 0;
        const lib = if (on_device)
            dlopen("libGLESv2.so.2", dl_mode) orelse dlopen("libGLESv2.so", dl_mode) orelse {
                fail("libGLESv2 cannot be opened", .{});
                return error.NoGlLibrary;
            }
        else
            try Host.create();
        if (on_device) {
            if (dlopen("libEGL.so.1", dl_mode) orelse dlopen("libEGL.so", dl_mode)) |egl| {
                if (dlsym(egl, "eglGetProcAddress")) |f| proc_address = @ptrCast(@alignCast(f));
            }
        }
        gl = try load(Api, lib);
        if (gl.glGetString(GL.VERSION) == null) {
            fail("no OpenGL ES context is current on this thread", .{});
            return error.NoGlContext;
        }

        if (!on_device) {
            // A desktop host can be asked to draw as the television does, to look at what it will show.
            if (getenv("DENTRO_GLES_SCENE_HEIGHT")) |v| tuning.scene_height = std.fmt.parseInt(u32, std.mem.span(v), 10) catch tuning.scene_height;
            if (getenv("DENTRO_GLES_MIN_SCENE_HEIGHT")) |v| tuning.min_scene_height = std.fmt.parseInt(u32, std.mem.span(v), 10) catch tuning.min_scene_height;
            if (getenv("DENTRO_GLES_SAMPLES")) |v| tuning.samples = std.fmt.parseInt(u32, std.mem.span(v), 10) catch tuning.samples;
            if (getenv("DENTRO_GLES_BAKED")) |v| tuning.baked_patterns = v[0] == '1';
        }

        var g: Gpu = .{};
        const gpa = std.heap.c_allocator;
        g.instances = (try gpa.alloc(Instance, common.max_instances)).ptr;
        g.dyn_verts = (try gpa.alloc(Vertex, common.max_dyn_verts)).ptr;
        g.part_verts = (try gpa.alloc(PVertex, common.max_part_verts)).ptr;
        g.hud_verts = (try gpa.alloc(HVertex, common.max_hud_verts)).ptr;

        // An RGBA16F target is renderable in ES 3.2, and in ES 3.0 with either of two extensions.
        const extensions = std.mem.span(gl.glGetString(GL.EXTENSIONS) orelse "");
        const version = std.mem.span(gl.glGetString(GL.VERSION).?);
        const half_float_target = hasExtension(extensions, "GL_EXT_color_buffer_half_float") or hasExtension(extensions, "GL_EXT_color_buffer_float") or std.mem.indexOf(u8, version, "ES 3.2") != null;
        if (!half_float_target) {
            fail("the driver ({s}) cannot render to a half-float target", .{version});
            return error.NoFloatTarget;
        }
        var max_samples: Int = 1;
        gl.glGetIntegerv(GL.MAX_SAMPLES, &max_samples);
        g.samples = @max(1, @min(tuning.samples, @as(u32, @intCast(@max(1, max_samples)))));
        g.max_samples = @intCast(@max(1, max_samples));
        g.msrtt = hasExtension(extensions, "GL_EXT_multisampled_render_to_texture") and gl.glFramebufferTexture2DMultisampleEXT != null and gl.glRenderbufferStorageMultisampleEXT != null;
        g.implicit_resolve = g.samples > 1 and g.msrtt;

        inline for (.{ Program.scene, Program.part, Program.post, Program.hud, Program.upscale }, .{ "SCENE", "PART", "POST", "HUD", "UPSCALE" }) |which, name| {
            g.programs[@intFromEnum(which)] = try program(shader_src, name);
        }
        gl.glUseProgram(g.programs[@intFromEnum(Program.post)]);
        gl.glUniform1i(gl.glGetUniformLocation(g.programs[@intFromEnum(Program.post)], "hdr"), 0);
        g.lod_bias_at = gl.glGetUniformLocation(g.programs[@intFromEnum(Program.post)], "lod_bias");
        g.last_pass_at = gl.glGetUniformLocation(g.programs[@intFromEnum(Program.post)], "last_pass");
        gl.glUseProgram(g.programs[@intFromEnum(Program.upscale)]);
        gl.glUniform1i(gl.glGetUniformLocation(g.programs[@intFromEnum(Program.upscale)], "ldr"), 0);
        gl.glUniform1i(gl.glGetUniformLocation(g.programs[@intFromEnum(Program.upscale)], "grain"), grain_unit);
        g.grain_at = gl.glGetUniformLocation(g.programs[@intFromEnum(Program.upscale)], "grain_at");
        try g.uploadGrain(gpa);
        gl.glUseProgram(g.programs[@intFromEnum(Program.hud)]);
        gl.glUniform1i(gl.glGetUniformLocation(g.programs[@intFromEnum(Program.hud)], "font"), 0);
        if (tuning.baked_patterns) try g.uploadPatterns(gpa);

        var buffers: [9]Uint = @splat(0);
        gl.glGenBuffers(buffers.len, &buffers);
        g.vb_mesh, g.ib_mesh, g.vb_inst, g.vb_dyn, g.vb_part, g.vb_hud, g.ubo_scene, g.ubo_arm, g.ubo_post = buffers;
        var arrays: [5]Uint = @splat(0);
        gl.glGenVertexArrays(arrays.len, &arrays);
        g.vao_mesh, g.vao_dyn, g.vao_part, g.vao_hud, g.vao_post = arrays;

        // Scene geometry: position, normal and texture coordinate per vertex, then the instance's model
        // matrix (four attributes), colour and parameters, each advancing once per instance. The mesh
        // array's vertex pointers are set per batch, at the batch's base vertex.
        for ([_]Uint{ g.vao_mesh, g.vao_dyn }) |vao| {
            gl.glBindVertexArray(vao);
            for (0..9) |i| gl.glEnableVertexAttribArray(@intCast(i));
            for (3..9) |i| gl.glVertexAttribDivisor(@intCast(i), 1);
        }
        gl.glBindVertexArray(g.vao_mesh);
        gl.glBindBuffer(GL.ELEMENT_ARRAY_BUFFER, g.ib_mesh);
        gl.glBindVertexArray(g.vao_dyn);
        gl.glBindBuffer(GL.ARRAY_BUFFER, g.vb_dyn);
        vertexPointers(0);

        gl.glBindVertexArray(g.vao_part);
        gl.glBindBuffer(GL.ARRAY_BUFFER, g.vb_part);
        for (0..3) |i| gl.glEnableVertexAttribArray(@intCast(i));
        gl.glVertexAttribPointer(0, 3, GL.FLOAT, 0, @sizeOf(PVertex), @offsetOf(PVertex, "pos"));
        gl.glVertexAttribPointer(1, 2, GL.FLOAT, 0, @sizeOf(PVertex), @offsetOf(PVertex, "uv"));
        gl.glVertexAttribPointer(2, 4, GL.FLOAT, 0, @sizeOf(PVertex), @offsetOf(PVertex, "color"));

        gl.glBindVertexArray(g.vao_hud);
        gl.glBindBuffer(GL.ARRAY_BUFFER, g.vb_hud);
        for (0..3) |i| gl.glEnableVertexAttribArray(@intCast(i));
        gl.glVertexAttribPointer(0, 2, GL.FLOAT, 0, @sizeOf(HVertex), @offsetOf(HVertex, "pos"));
        gl.glVertexAttribPointer(1, 2, GL.FLOAT, 0, @sizeOf(HVertex), @offsetOf(HVertex, "uv"));
        gl.glVertexAttribPointer(2, 4, GL.FLOAT, 0, @sizeOf(HVertex), @offsetOf(HVertex, "color"));
        gl.glBindVertexArray(0);

        gl.glDisable(GL.CULL_FACE);
        gl.glDisable(GL.DITHER);
        gl.glDisable(GL.SCISSOR_TEST);
        gl.glDepthFunc(GL.LEQUAL);
        gl.glPixelStorei(GL.UNPACK_ALIGNMENT, 1);
        gl.glPixelStorei(GL.PACK_ALIGNMENT, 1);
        if (gl.glGetError() != 0) {
            fail("OpenGL ES reported an error while the backend was set up", .{});
            return error.GlSetupFailed;
        }
        return g;
    }

    /// The film grain's noise: one hash a texel, repeating, left bound to a texture unit of its own.
    fn uploadGrain(g: *Gpu, gpa: std.mem.Allocator) !void {
        const n = bake.grain_n;
        const texels = try gpa.alloc(u8, n * n);
        defer gpa.free(texels);
        bake.bakeGrain(texels);
        var ids: [1]Uint = .{0};
        gl.glGenTextures(1, &ids);
        g.tex_grain = ids[0];
        gl.glActiveTexture(GL.TEXTURE0 + grain_unit);
        gl.glBindTexture(GL.TEXTURE_2D, g.tex_grain);
        gl.glTexStorage2D(GL.TEXTURE_2D, 1, GL.R8, n, n);
        gl.glTexSubImage2D(GL.TEXTURE_2D, 0, 0, 0, n, n, GL.RED, GL.UNSIGNED_BYTE, texels.ptr);
        gl.glTexParameteri(GL.TEXTURE_2D, GL.TEXTURE_MIN_FILTER, GL.NEAREST);
        gl.glTexParameteri(GL.TEXTURE_2D, GL.TEXTURE_MAG_FILTER, GL.NEAREST);
        gl.glTexParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_S, GL.REPEAT);
        gl.glTexParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_T, GL.REPEAT);
        gl.glActiveTexture(GL.TEXTURE0);
    }

    /// Bake the noise volume, the cell tile and the fbm volume and leave them bound to texture units 1,
    /// 2 and 3, which nothing else uses, for the scene program to sample.
    fn uploadPatterns(g: *Gpu, gpa: std.mem.Allocator) !void {
        const scene = g.programs[@intFromEnum(Program.scene)];
        gl.glUseProgram(scene);
        gl.glUniform1i(gl.glGetUniformLocation(scene, "noise_tex"), 1);
        gl.glUniform1i(gl.glGetUniformLocation(scene, "cell_tex"), 2);
        gl.glUniform1i(gl.glGetUniformLocation(scene, "fbm_tex"), 3);

        const n = bake.noise_n;
        const noise = try gpa.alloc(u8, n * n * n);
        defer gpa.free(noise);
        bake.bakeNoise(noise);
        const fn_ = bake.fbm_n;
        const fbm = try gpa.alloc(u8, fn_ * fn_ * fn_);
        defer gpa.free(fbm);
        try bake.bakeFbm(gpa, fbm);
        var ids: [3]Uint = .{ 0, 0, 0 };
        gl.glGenTextures(3, &ids);
        g.tex_noise, g.tex_cells, g.tex_fbm = ids;
        inline for (.{ g.tex_noise, g.tex_fbm }, .{ 1, 3 }, .{ n, fn_ }, .{ noise, fbm }) |tex, unit, side, texels| {
            gl.glActiveTexture(GL.TEXTURE0 + unit);
            gl.glBindTexture(GL.TEXTURE_3D, tex);
            gl.glTexStorage3D(GL.TEXTURE_3D, 1, GL.R8, side, side, side);
            gl.glTexSubImage3D(GL.TEXTURE_3D, 0, 0, 0, 0, side, side, side, GL.RED, GL.UNSIGNED_BYTE, texels.ptr);
            gl.glTexParameteri(GL.TEXTURE_3D, GL.TEXTURE_MIN_FILTER, GL.LINEAR);
            gl.glTexParameteri(GL.TEXTURE_3D, GL.TEXTURE_MAG_FILTER, GL.LINEAR);
            inline for (.{ GL.TEXTURE_WRAP_S, GL.TEXTURE_WRAP_T, GL.TEXTURE_WRAP_R }) |axis| gl.glTexParameteri(GL.TEXTURE_3D, axis, GL.REPEAT);
        }

        const size = bake.cell_size;
        const cells = try gpa.alloc(u8, size * size * 4);
        defer gpa.free(cells);
        bake.bakeCells(cells);
        gl.glActiveTexture(GL.TEXTURE0 + 2);
        gl.glBindTexture(GL.TEXTURE_2D, g.tex_cells);
        gl.glTexStorage2D(GL.TEXTURE_2D, std.math.log2_int(u32, size) + 1, GL.RGBA8, size, size);
        gl.glTexSubImage2D(GL.TEXTURE_2D, 0, 0, 0, size, size, GL.RGBA, GL.UNSIGNED_BYTE, cells.ptr);
        gl.glGenerateMipmap(GL.TEXTURE_2D);
        gl.glTexParameteri(GL.TEXTURE_2D, GL.TEXTURE_MIN_FILTER, GL.LINEAR_MIPMAP_LINEAR);
        gl.glTexParameteri(GL.TEXTURE_2D, GL.TEXTURE_MAG_FILTER, GL.LINEAR);
        gl.glTexParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_S, GL.REPEAT);
        gl.glTexParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_T, GL.REPEAT);
        gl.glActiveTexture(GL.TEXTURE0);
    }

    /// The driver's extension list, for a log.
    pub fn extensionList(_: *const Gpu) []const u8 {
        return std.mem.span(gl.glGetString(GL.EXTENSIONS) orelse "");
    }

    fn hasExtension(list: []const u8, name: []const u8) bool {
        var it = std.mem.tokenizeScalar(u8, list, ' ');
        while (it.next()) |e| if (std.mem.eql(u8, e, name)) return true;
        return false;
    }

    /// One stage of one program: the shader file behind the version line and the two definitions that
    /// select its sections. `#line 1` keeps the compiler's line numbers those of the file.
    fn shader(kind: Enum, src: [:0]const u8, which: []const u8) !Uint {
        var head_buf: [160]u8 = undefined;
        const head = std.fmt.bufPrint(&head_buf, "#version 300 es\n#define {s}\n#define {s}\n{s}#line 1\n", .{ which, if (kind == GL.VERTEX_SHADER) "VERTEX" else "FRAGMENT", if (tuning.baked_patterns) "#define BAKED_PATTERNS\n" else "" }) catch unreachable;
        const s = gl.glCreateShader(kind);
        gl.glShaderSource(s, 2, &[_][*]const u8{ head.ptr, src.ptr }, &[_]Int{ @intCast(head.len), @intCast(src.len) });
        gl.glCompileShader(s);
        var ok: Int = 0;
        gl.glGetShaderiv(s, GL.COMPILE_STATUS, &ok);
        if (ok == 0) {
            var log: [3000]u8 = @splat(0);
            var len: Int = 0;
            gl.glGetShaderInfoLog(s, log.len, &len, &log);
            fail("{s} {s} shader: {s}", .{ which, if (kind == GL.VERTEX_SHADER) "vertex" else "fragment", log[0..@intCast(@max(0, len))] });
            return error.ShaderCompileFailed;
        }
        return s;
    }

    fn program(src: [:0]const u8, which: []const u8) !Uint {
        const vs = try shader(GL.VERTEX_SHADER, src, which);
        const fs = try shader(GL.FRAGMENT_SHADER, src, which);
        const p = gl.glCreateProgram();
        gl.glAttachShader(p, vs);
        gl.glAttachShader(p, fs);
        gl.glLinkProgram(p);
        gl.glDeleteShader(vs);
        gl.glDeleteShader(fs);
        var ok: Int = 0;
        gl.glGetProgramiv(p, GL.LINK_STATUS, &ok);
        if (ok == 0) {
            var log: [3000]u8 = @splat(0);
            var len: Int = 0;
            gl.glGetProgramInfoLog(p, log.len, &len, &log);
            fail("{s} program: {s}", .{ which, log[0..@intCast(@max(0, len))] });
            return error.PipelineFailed;
        }
        // A block a program does not use has no index there.
        inline for (.{ "FrameBlock", "PostBlock" }, .{ frame_binding, post_binding }) |block, binding| {
            const index = gl.glGetUniformBlockIndex(p, block);
            if (index != GL.INVALID_INDEX) gl.glUniformBlockBinding(p, index, binding);
        }
        return p;
    }

    /// The three per-vertex attributes of the scene program, read from the bound buffer starting at
    /// vertex `base`.
    fn vertexPointers(base: u32) void {
        const at = @as(usize, base) * @sizeOf(Vertex);
        gl.glVertexAttribPointer(0, 3, GL.FLOAT, 0, @sizeOf(Vertex), at + @offsetOf(Vertex, "pos"));
        gl.glVertexAttribPointer(1, 3, GL.FLOAT, 0, @sizeOf(Vertex), at + @offsetOf(Vertex, "nrm"));
        gl.glVertexAttribPointer(2, 2, GL.FLOAT, 0, @sizeOf(Vertex), at + @offsetOf(Vertex, "uv"));
    }

    /// The six per-instance attributes, read from the instance buffer starting at instance `base`.
    fn instancePointers(g: *Gpu, base: u32) void {
        const at = @as(usize, base) * @sizeOf(Instance);
        gl.glBindBuffer(GL.ARRAY_BUFFER, g.vb_inst);
        for (0..4) |column| gl.glVertexAttribPointer(@intCast(3 + column), 4, GL.FLOAT, 0, @sizeOf(Instance), at + column * 16);
        gl.glVertexAttribPointer(7, 4, GL.FLOAT, 0, @sizeOf(Instance), at + @offsetOf(Instance, "color"));
        gl.glVertexAttribPointer(8, 4, GL.FLOAT, 0, @sizeOf(Instance), at + @offsetOf(Instance, "params"));
    }

    /// The window is the engine's and the context is already bound to it; from here the post pass draws
    /// to the default framebuffer. A desktop host has no window for this backend.
    pub fn attach(g: *Gpu, _: anytype) !void {
        if (!on_device) return error.OffscreenOnly;
        g.to_window = true;
    }

    /// The window's drawable changed size.
    pub fn resizeSurface(g: *Gpu, w: u32, h: u32, _: f64) void {
        g.resize(w, h, false);
    }

    /// A line for the log saying what is rendering.
    pub fn describe(g: *Gpu, buf: []u8) []const u8 {
        const renderer = std.mem.span(gl.glGetString(GL.RENDERER) orelse "unnamed renderer");
        const version = std.mem.span(gl.glGetString(GL.VERSION) orelse "");
        const last = g.sizes[g.size_count - 1];
        var range_buf: [40]u8 = undefined;
        const range = if (g.size_count > 1) std.fmt.bufPrint(&range_buf, " down to {d}x{d} in {d} sizes", .{ last.w, last.h, g.size_count }) catch "" else "";
        return std.fmt.bufPrint(buf, "OpenGL ES, {s} ({s}), scene {d}x{d}{s} at {d} samples{s}{s}{s}", .{ renderer, version, g.sizes[0].w, g.sizes[0].h, range, g.samples, if (g.implicit_resolve) ", resolved in the tile" else "", if (g.tex_noise != 0) ", baked patterns" else "", if (g.sizes[0].fbo_ldr != 0) ", post at the scene's size" else "" }) catch "OpenGL ES";
    }

    fn texture(min_filter: Int) Uint {
        var ids: [1]Uint = .{0};
        gl.glGenTextures(1, &ids);
        gl.glActiveTexture(GL.TEXTURE0);
        gl.glBindTexture(GL.TEXTURE_2D, ids[0]);
        gl.glTexParameteri(GL.TEXTURE_2D, GL.TEXTURE_MIN_FILTER, min_filter);
        gl.glTexParameteri(GL.TEXTURE_2D, GL.TEXTURE_MAG_FILTER, GL.LINEAR);
        gl.glTexParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_S, GL.CLAMP_TO_EDGE);
        gl.glTexParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_T, GL.CLAMP_TO_EDGE);
        return ids[0];
    }

    fn renderbuffer(g: *Gpu, format: Enum, w: u32, h: u32, multisampled: bool) Uint {
        var ids: [1]Uint = .{0};
        gl.glGenRenderbuffers(1, &ids);
        gl.glBindRenderbuffer(GL.RENDERBUFFER, ids[0]);
        if (!multisampled) {
            gl.glRenderbufferStorage(GL.RENDERBUFFER, format, @intCast(w), @intCast(h));
        } else if (g.implicit_resolve) {
            gl.glRenderbufferStorageMultisampleEXT.?(GL.RENDERBUFFER, @intCast(g.samples), format, @intCast(w), @intCast(h));
        } else {
            gl.glRenderbufferStorageMultisample(GL.RENDERBUFFER, @intCast(g.samples), format, @intCast(w), @intCast(h));
        }
        return ids[0];
    }

    fn framebuffer() Uint {
        var ids: [1]Uint = .{0};
        gl.glGenFramebuffers(1, &ids);
        gl.glBindFramebuffer(GL.FRAMEBUFFER, ids[0]);
        return ids[0];
    }

    fn complete(what: []const u8) void {
        const status = gl.glCheckFramebufferStatus(GL.FRAMEBUFFER);
        if (status != GL.FRAMEBUFFER_COMPLETE) fail("the {s} framebuffer is incomplete (0x{x})", .{ what, status });
    }

    /// (Re)create the render targets for an output of `w` x `h` pixels.
    pub fn resize(g: *Gpu, w: u32, h: u32, with_offscreen: bool) void {
        if (w == g.width and h == g.height and g.size_count != 0) return;
        for (g.sizes[0..g.size_count]) |*t| {
            gl.glDeleteTextures(2, &[_]Uint{ t.tex_hdr, t.tex_ldr });
            gl.glDeleteRenderbuffers(2, &[_]Uint{ t.rb_depth, t.rb_color });
            gl.glDeleteFramebuffers(3, &[_]Uint{ t.fbo_scene, t.fbo_resolve, t.fbo_ldr });
            t.* = .{};
        }
        g.width = @max(w, 8);
        g.height = @max(h, 8);

        // The ladder of sizes.
        const top: u32 = if (tuning.scene_height == 0) g.height else @max(8, @min(tuning.scene_height, g.height));
        const floor: u32 = if (tuning.min_scene_height != 0) @max(8, @min(tuning.min_scene_height, top)) else top;
        g.size_count = 0;
        var rows: f32 = @floatFromInt(top);
        while (g.size_count < max_sizes) : (rows *= size_step) {
            const scene_h: u32 = @intFromFloat(@round(rows));
            if (scene_h < floor) break;
            g.sizes[g.size_count] = g.makeTarget((g.width * scene_h + g.height / 2) / g.height, scene_h);
            g.size_count += 1;
        }
        g.use(0);

        if (with_offscreen) {
            if (g.tex_offscreen != 0) {
                gl.glDeleteTextures(1, &[_]Uint{g.tex_offscreen});
                gl.glDeleteFramebuffers(1, &[_]Uint{g.fbo_offscreen});
            }
            g.tex_offscreen = texture(GL.NEAREST);
            gl.glTexStorage2D(GL.TEXTURE_2D, 1, GL.RGBA8, @intCast(g.width), @intCast(g.height));
            g.fbo_offscreen = framebuffer();
            gl.glFramebufferTexture2D(GL.FRAMEBUFFER, GL.COLOR_ATTACHMENT0, GL.TEXTURE_2D, g.tex_offscreen, 0);
            complete("offscreen");
        }
        gl.glBindFramebuffer(GL.FRAMEBUFFER, 0);
    }

    /// The render targets of a scene image of `w` x `h` pixels.
    fn makeTarget(g: *Gpu, w: u32, h: u32) Target {
        var t: Target = .{ .w = @max(w, 8), .h = @max(h, 8) };
        // Half-float colour with the mip levels the bloom taps read. The widest tap is at level 6.5 of
        // an image the size of the output, which is a lower level of a smaller scene.
        t.tex_hdr = texture(GL.LINEAR_MIPMAP_LINEAR);
        const all_levels: Int = @intCast(std.math.log2_int(u32, @max(t.w, t.h)) + 1);
        const tapped: Int = @intFromFloat(@ceil(@max(6.5 + g.lodBias(t.h), 0)) + 1);
        gl.glTexStorage2D(GL.TEXTURE_2D, @min(all_levels, tapped), GL.RGBA16F, @intCast(t.w), @intCast(t.h));

        const multisampled = g.samples > 1;
        t.rb_depth = g.renderbuffer(GL.DEPTH_COMPONENT24, t.w, t.h, multisampled);
        t.fbo_scene = framebuffer();
        gl.glFramebufferRenderbuffer(GL.FRAMEBUFFER, GL.DEPTH_ATTACHMENT, GL.RENDERBUFFER, t.rb_depth);
        if (!multisampled) {
            gl.glFramebufferTexture2D(GL.FRAMEBUFFER, GL.COLOR_ATTACHMENT0, GL.TEXTURE_2D, t.tex_hdr, 0);
        } else if (g.implicit_resolve) {
            gl.glFramebufferTexture2DMultisampleEXT.?(GL.FRAMEBUFFER, GL.COLOR_ATTACHMENT0, GL.TEXTURE_2D, t.tex_hdr, 0, @intCast(g.samples));
        } else {
            t.rb_color = g.renderbuffer(GL.RGBA16F, t.w, t.h, true);
            gl.glBindFramebuffer(GL.FRAMEBUFFER, t.fbo_scene);
            gl.glFramebufferRenderbuffer(GL.FRAMEBUFFER, GL.COLOR_ATTACHMENT0, GL.RENDERBUFFER, t.rb_color);
        }
        complete("scene");
        if (multisampled and !g.implicit_resolve) {
            t.fbo_resolve = framebuffer();
            gl.glFramebufferTexture2D(GL.FRAMEBUFFER, GL.COLOR_ATTACHMENT0, GL.TEXTURE_2D, t.tex_hdr, 0);
            complete("resolve");
        }
        if (t.h < g.height) {
            t.tex_ldr = texture(GL.LINEAR);
            gl.glTexStorage2D(GL.TEXTURE_2D, 1, GL.RGBA8, @intCast(t.w), @intCast(t.h));
            t.fbo_ldr = framebuffer();
            gl.glFramebufferTexture2D(GL.FRAMEBUFFER, GL.COLOR_ATTACHMENT0, GL.TEXTURE_2D, t.tex_ldr, 0);
            complete("tonemapped");
        }
        return t;
    }

    /// Draw the scene at size `index` of the ladder from the next frame on.
    fn use(g: *Gpu, index: u8) void {
        g.size = index;
        g.scene_w = g.sizes[index].w;
        g.scene_h = g.sizes[index].h;
        g.calm = 0;
        g.strain = 0;
        g.held = 0;
        g.unsettled = @max(g.unsettled, step_settle_frames);
    }

    /// For a platform to call when frames resume after a pause: the next few are not judged.
    pub fn settle(g: *Gpu) void {
        g.unsettled = settle_frames;
        g.calm = 0;
        g.strain = 0;
        g.held = 0;
    }

    /// For a platform that paces frames to a display: call once a frame, saying whether the display
    /// has since the last call shown a frame a refresh later than it was drawn for (`late`), and whether
    /// it has shown one for two refreshes (`held`). Either, often enough, steps the scene's size down; a
    /// long enough run of frames on time lets it try the size above.
    pub fn paced(g: *Gpu, late: bool, held: bool) void {
        if (g.size_count < 2) return;
        if (g.unsettled > 0) {
            g.unsettled -= 1;
            return;
        }
        g.hold -|= 1;
        if (g.on_trial) |*frames| {
            frames.* += 1;
            if (frames.* >= trial) {
                // The step up has lasted: the next one need wait no longer than the least.
                g.on_trial = null;
                g.hold_next = hold_least;
            }
        }
        g.strain = if (late) g.strain + late_strain else g.strain -| 1;
        g.held = if (held) g.held + held_strain else g.held -| 1;
        if (late) g.calm -|= calm_lost_late;
        if (held) g.calm -|= calm_lost_held;
        if (!late and !held) g.calm += 1;
        if (g.strain >= strain_limit or g.held >= held_limit) {
            if (g.size + 1 < g.size_count) {
                // A step up taken back: the next is tried after twice the wait.
                if (g.on_trial != null) g.hold_next = @min(g.hold_next * 2, hold_most);
                g.on_trial = null;
                g.hold = g.hold_next;
                g.steps_down += 1;
                g.use(g.size + 1);
            } else {
                g.strain = 0;
                g.held = 0;
            }
        } else if (g.size > 0 and g.calm >= calm_needed and g.hold == 0) {
            g.steps_up += 1;
            g.use(g.size - 1);
            g.on_trial = 0;
        }
    }

    /// What is added to the mip level of a bloom tap: a scene image half the output's height has its
    /// level 1 where an image of the output's size has level 2.
    fn lodBias(g: *const Gpu, scene_h: u32) f32 {
        return -@log2(@as(f32, @floatFromInt(g.height)) / @as(f32, @floatFromInt(scene_h)));
    }

    pub fn uploadMeshes(g: *Gpu, verts: []const Vertex, indices: []const u32) void {
        gl.glBindVertexArray(g.vao_mesh);
        gl.glBindBuffer(GL.ARRAY_BUFFER, g.vb_mesh);
        gl.glBufferData(GL.ARRAY_BUFFER, @intCast(verts.len * @sizeOf(Vertex)), verts.ptr, GL.STATIC_DRAW);
        gl.glBufferData(GL.ELEMENT_ARRAY_BUFFER, @intCast(indices.len * 4), indices.ptr, GL.STATIC_DRAW);
        gl.glBindVertexArray(0);
    }

    /// Upload the glyph atlas with a box-filtered mip chain, so text stays clean at every HUD size.
    pub fn uploadFont(g: *Gpu, gpa: std.mem.Allocator, pixels: []const u8, w: u32, h: u32) !void {
        var chain = try common.MipChain.build(gpa, pixels, w, h);
        defer chain.deinit(gpa);
        g.tex_font = texture(GL.LINEAR_MIPMAP_LINEAR);
        gl.glTexParameteri(GL.TEXTURE_2D, GL.TEXTURE_MAX_LEVEL, @intCast(chain.count - 1));
        for (chain.levels[0..chain.count], 0..) |level, i| {
            gl.glTexImage2D(GL.TEXTURE_2D, @intCast(i), GL.R8, @intCast(level.w), @intCast(level.h), 0, GL.RED, GL.UNSIGNED_BYTE, level.pixels.ptr);
        }
    }

    fn stream(buffer: Uint, target: Enum, ptr: *const anyopaque, bytes: usize) void {
        gl.glBindBuffer(target, buffer);
        // A fresh store every frame, so the driver never waits for the one the last frame is reading.
        gl.glBufferData(target, @intCast(bytes), ptr, GL.STREAM_DRAW);
    }

    /// Draw one frame. With `wait` it returns only when the GPU has finished it. Always true: there is
    /// no drawable to run out of.
    pub fn submit(g: *Gpu, d: *const FrameDesc, wait: bool) bool {
        var t: u64 = if (profile != null) nowNs() else 0;
        const tg = g.sizes[g.size];
        if (d.instance_count > 0) stream(g.vb_inst, GL.ARRAY_BUFFER, g.instances, @as(usize, d.instance_count) * @sizeOf(Instance));
        if (d.dyn_count > 0) stream(g.vb_dyn, GL.ARRAY_BUFFER, g.dyn_verts, @as(usize, d.dyn_count) * @sizeOf(Vertex));
        if (d.part_count > 0) stream(g.vb_part, GL.ARRAY_BUFFER, g.part_verts, @as(usize, d.part_count) * @sizeOf(PVertex));
        if (d.hud_count > 0) stream(g.vb_hud, GL.ARRAY_BUFFER, g.hud_verts, @as(usize, d.hud_count) * @sizeOf(HVertex));
        var post = d.post;
        post.c[0] = 1.0 / @as(f32, @floatFromInt(g.width));
        post.c[1] = 1.0 / @as(f32, @floatFromInt(g.height));
        stream(g.ubo_scene, GL.UNIFORM_BUFFER, &d.scene, @sizeOf(Frame));
        stream(g.ubo_arm, GL.UNIFORM_BUFFER, &d.arm, @sizeOf(Frame));
        stream(g.ubo_post, GL.UNIFORM_BUFFER, &post, @sizeOf(Post));
        gl.glBindBufferBase(GL.UNIFORM_BUFFER, post_binding, g.ubo_post);
        phaseEnd(0, &t);

        // Scene.
        gl.glBindFramebuffer(GL.FRAMEBUFFER, tg.fbo_scene);
        gl.glViewport(0, 0, @intCast(tg.w), @intCast(tg.h));
        gl.glColorMask(1, 1, 1, 1);
        gl.glDepthMask(1);
        const fc = d.scene.fog_color;
        gl.glClearColor(fc[0], fc[1], fc[2], 1);
        gl.glClearDepthf(1);
        gl.glClear(GL.COLOR_BUFFER_BIT | GL.DEPTH_BUFFER_BIT);
        gl.glEnable(GL.DEPTH_TEST);
        gl.glDisable(GL.BLEND);
        gl.glUseProgram(g.programs[@intFromEnum(Program.scene)]);

        // First-person arms: own projection, front slice of the depth range so the world never clips
        // them. They are drawn first because nothing is ever in front of them.
        gl.glDepthRangef(0.0, 0.1);
        gl.glBindBufferBase(GL.UNIFORM_BUFFER, frame_binding, g.ubo_arm);
        g.drawPass(d.batches, .arm);
        phaseEnd(1, &t);

        gl.glDepthRangef(0.1, 1.0);
        gl.glBindBufferBase(GL.UNIFORM_BUFFER, frame_binding, g.ubo_scene);
        g.drawPass(d.batches, .solid);
        phaseEnd(2, &t);

        gl.glEnable(GL.BLEND);
        gl.glBlendFuncSeparate(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA, GL.ONE, GL.ONE_MINUS_SRC_ALPHA);
        gl.glDepthMask(0);
        g.drawPass(d.batches, .blend);

        if (d.part_count > 0) {
            gl.glUseProgram(g.programs[@intFromEnum(Program.part)]);
            gl.glBlendFuncSeparate(GL.ONE, GL.ONE, GL.ZERO, GL.ONE);
            gl.glBindVertexArray(g.vao_part);
            gl.glDrawArrays(GL.TRIANGLES, 0, @intCast(d.part_count));
        }
        gl.glDisable(GL.BLEND);
        gl.glDepthMask(1);
        phaseEnd(3, &t);

        // Nothing reads the depth buffer after the pass, and saying so spares a tile-based GPU writing
        // it back to memory.
        gl.glInvalidateFramebuffer(GL.FRAMEBUFFER, 1, &[_]Enum{GL.DEPTH_ATTACHMENT});
        if (tg.fbo_resolve != 0) {
            gl.glBindFramebuffer(GL.READ_FRAMEBUFFER, tg.fbo_scene);
            gl.glBindFramebuffer(GL.DRAW_FRAMEBUFFER, tg.fbo_resolve);
            const sw: Int = @intCast(tg.w);
            const sh: Int = @intCast(tg.h);
            gl.glBlitFramebuffer(0, 0, sw, sh, 0, 0, sw, sh, GL.COLOR_BUFFER_BIT, GL.NEAREST);
            gl.glInvalidateFramebuffer(GL.READ_FRAMEBUFFER, 1, &[_]Enum{GL.COLOR_ATTACHMENT0});
        }

        // Tonemap. Binding the target ends the scene pass, which is when a driver that resolves in the
        // tile does so; the mip chain for the bloom taps is made from the resolved image.
        const output: Uint = if (g.to_window) 0 else g.fbo_offscreen;
        gl.glBindFramebuffer(GL.FRAMEBUFFER, if (tg.fbo_ldr != 0) tg.fbo_ldr else output);
        gl.glActiveTexture(GL.TEXTURE0);
        gl.glBindTexture(GL.TEXTURE_2D, tg.tex_hdr);
        gl.glGenerateMipmap(GL.TEXTURE_2D);
        phaseEnd(4, &t);
        if (tg.fbo_ldr != 0) gl.glViewport(0, 0, @intCast(tg.w), @intCast(tg.h)) else gl.glViewport(0, 0, @intCast(g.width), @intCast(g.height));
        gl.glDisable(GL.DEPTH_TEST);
        gl.glDepthRangef(0.0, 1.0);
        // The post pass covers every pixel; the clear only tells a tile-based GPU that the target's old
        // contents need not be loaded.
        gl.glClearColor(0, 0, 0, 1);
        gl.glClear(GL.COLOR_BUFFER_BIT);
        gl.glUseProgram(g.programs[@intFromEnum(Program.post)]);
        gl.glUniform1f(g.lod_bias_at, g.lodBias(tg.h));
        gl.glUniform1f(g.last_pass_at, if (tg.fbo_ldr != 0) 0 else 1);
        gl.glBindVertexArray(g.vao_post);
        gl.glDrawArrays(GL.TRIANGLES, 0, 3);
        phaseEnd(5, &t);
        if (tg.fbo_ldr != 0) {
            // The tonemapped image, scaled up to the output with the grain added at the output's size;
            // the HUD is then drawn over it. The pass covers every pixel, and the clear says so.
            gl.glBindFramebuffer(GL.FRAMEBUFFER, output);
            gl.glViewport(0, 0, @intCast(g.width), @intCast(g.height));
            gl.glClear(GL.COLOR_BUFFER_BIT);
            gl.glUseProgram(g.programs[@intFromEnum(Program.upscale)]);
            // The grain moves to another place in its noise every frame.
            const turn = @floor(post.b[0] * 977.0);
            gl.glUniform2f(g.grain_at, @mod(turn * 0.618034, 1.0), @mod(turn * 0.754878, 1.0));
            gl.glBindTexture(GL.TEXTURE_2D, tg.tex_ldr);
            gl.glDrawArrays(GL.TRIANGLES, 0, 3);
        }
        phaseEnd(6, &t);
        if (d.hud_count > 0 and g.tex_font != 0) {
            // The window has an alpha channel the television's compositor honours. The post pass wrote 1
            // to it everywhere, and it is left at that.
            gl.glColorMask(1, 1, 1, 0);
            gl.glEnable(GL.BLEND);
            gl.glBlendFuncSeparate(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA, GL.ONE, GL.ONE_MINUS_SRC_ALPHA);
            gl.glUseProgram(g.programs[@intFromEnum(Program.hud)]);
            gl.glBindTexture(GL.TEXTURE_2D, g.tex_font);
            gl.glBindVertexArray(g.vao_hud);
            gl.glDrawArrays(GL.TRIANGLES, 0, @intCast(d.hud_count));
            gl.glDisable(GL.BLEND);
            gl.glColorMask(1, 1, 1, 1);
        }
        gl.glBindVertexArray(0);
        phaseEnd(7, &t);
        if (profile) |p| p.frames += 1;
        if (wait) gl.glFinish();
        return true;
    }

    fn drawPass(g: *Gpu, batches: []const Batch, pass: Pass) void {
        for (batches) |b| {
            if (b.pass != pass or b.instance_count == 0) continue;
            if (profile) |p| {
                p.draws += 1;
                p.instances += b.instance_count;
                p.triangles += @as(u64, if (b.dynamic) b.vertex_count else b.mesh.index_count) / 3 * b.instance_count;
            }
            if (b.dynamic) {
                gl.glBindVertexArray(g.vao_dyn);
                g.instancePointers(b.first_instance);
                gl.glDrawArraysInstanced(GL.TRIANGLES, @intCast(b.vertex_start), @intCast(b.vertex_count), @intCast(b.instance_count));
            } else {
                gl.glBindVertexArray(g.vao_mesh);
                gl.glBindBuffer(GL.ARRAY_BUFFER, g.vb_mesh);
                vertexPointers(b.mesh.base_vertex);
                g.instancePointers(b.first_instance);
                gl.glDrawElementsInstanced(GL.TRIANGLES, @intCast(b.mesh.index_count), GL.UNSIGNED_INT, @as(usize, b.mesh.index_start) * 4, @intCast(b.instance_count));
            }
        }
    }

    /// Copy the offscreen target out as tightly packed BGRA8 rows, top row first.
    pub fn readback(g: *Gpu, out: []u8) void {
        const row = @as(usize, g.width) * 4;
        std.debug.assert(out.len >= row * g.height);
        gl.glBindFramebuffer(GL.FRAMEBUFFER, g.fbo_offscreen);
        gl.glReadPixels(0, 0, @intCast(g.width), @intCast(g.height), GL.RGBA, GL.UNSIGNED_BYTE, out.ptr);
        gl.glBindFramebuffer(GL.FRAMEBUFFER, 0);
        toTopDownBgra(out[0 .. row * g.height], row);
    }
};

/// OpenGL hands rows out from the bottom, as RGBA; the callers of `readback` want them from the top, as
/// BGRA. Both are done in place.
fn toTopDownBgra(px: []u8, row: usize) void {
    const rows = px.len / row;
    for (0..rows / 2) |y| {
        const a = px[y * row ..][0..row];
        const b = px[(rows - 1 - y) * row ..][0..row];
        for (a, b) |*p, *q| std.mem.swap(u8, p, q);
    }
    var i: usize = 0;
    while (i + 3 < px.len) : (i += 4) std.mem.swap(u8, &px[i], &px[i + 2]);
}

test "readback rows come out from the top, in BGRA" {
    // Three rows of one pixel each, bottom row first, as glReadPixels fills them.
    var px = [_]u8{ 1, 2, 3, 4, 10, 20, 30, 40, 100, 110, 120, 130 };
    toTopDownBgra(&px, 4);
    try std.testing.expectEqualSlices(u8, &.{ 120, 110, 100, 130, 30, 20, 10, 40, 3, 2, 1, 4 }, &px);
    // An even number of rows, two pixels wide.
    var px2 = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 };
    toTopDownBgra(&px2, 8);
    try std.testing.expectEqualSlices(u8, &.{ 11, 10, 9, 12, 15, 14, 13, 16, 3, 2, 1, 4, 7, 6, 5, 8 }, &px2);
}

test "the attribute layouts are the ones the shader file declares" {
    // shaders.glsl gives the model matrix locations 3 to 6 and reads a column from each: sixteen bytes
    // apart, at the start of the instance.
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(Instance, "model"));
    try std.testing.expectEqual(@as(usize, 64), @offsetOf(Instance, "color"));
    try std.testing.expectEqual(@as(usize, 80), @offsetOf(Instance, "params"));
    try std.testing.expectEqual(@as(usize, 12), @offsetOf(Vertex, "nrm"));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(Vertex, "uv"));
    try std.testing.expectEqual(@as(usize, 20), @offsetOf(PVertex, "color"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(HVertex, "color"));
    // std140 lays the two uniform blocks out as the extern structs are: a mat4 then vec4s, no padding.
    try std.testing.expectEqual(@as(usize, 64), @offsetOf(Frame, "cam_pos"));
    try std.testing.expectEqual(@as(usize, 48), @offsetOf(Post, "tint"));
}
