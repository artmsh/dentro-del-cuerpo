//! The parts of running the game that every entry point shares: building the renderer and the application,
//! advancing one frame of input, and feeding the synthesiser its continuous state. The desktop entry point
//! (`main.zig`) and the television's (`tv.zig`) differ in where a frame's input and time come from and in
//! who owns the loop; what happens inside a frame is here, once.

const std = @import("std");
const m = @import("math.zig");
const gpu = @import("gpu.zig");
const mesh = @import("mesh.zig");
const render = @import("render.zig");
const font = @import("font.zig");
const vein_mod = @import("vein.zig");
const app_mod = @import("app.zig");
const draw = @import("draw.zig");
const audio_mod = @import("audio.zig");
const bindings = @import("bindings.zig");
const input = @import("input.zig");
const i18n = @import("i18n.zig");
const Lang = i18n.Lang;

pub const Engine = struct {
    g: gpu.Gpu,
    r: render.Renderer,
    vm: vein_mod.Meshes,
    app: *app_mod.App,

    /// `shader_src` is what the GPU backend compiles. `lang` is the language asked for on the command
    /// line; `fallback` applies when neither it nor the save file names one. `window_keys` are the
    /// window's shortcuts as the platform names them, empty where it has none.
    pub fn init(e: *Engine, arena: std.mem.Allocator, shader_src: [:0]const u8, options: gpu.Options, persist: bool, lang: ?Lang, fallback: Lang, window_keys: bindings.WindowKeys) !void {
        e.g = try gpu.Gpu.init(shader_src, options);
        e.app = try arena.create(app_mod.App);
        e.app.init(persist, fallback);
        e.app.window_keys = window_keys;
        if (lang) |l| e.app.lang = l;
        var b = mesh.Builder.init(arena);
        const meshes = render.Meshes.build(&b);
        e.vm = vein_mod.buildMeshes(&b, &e.app.sim.vein);
        e.g.uploadMeshes(b.verts.items, b.indices.items);
        const f = try font.Font.build(arena);
        try e.g.uploadFont(arena, f.pixels, font.atlas_w, font.atlas_h);
        e.r = .{ .g = &e.g, .font = f, .meshes = meshes };
    }

    pub fn renderFrame(e: *Engine, dt: f32, wait: bool) bool {
        e.r.begin();
        const out = draw.frame(e.app, &e.r, &e.vm, dt);
        return e.r.end(out.scene, out.arm, out.post, wait);
    }
};

/// Advance the application by one displayed frame of `dt` seconds with the frame's input, and hand the
/// sounds it made to the synthesiser. The simulation is stepped at no less than 120 Hz, so a frame is
/// one to four steps; held controls apply to each and one-shot actions to the first.
pub fn advance(app: *app_mod.App, audio: *audio_mod.Audio, in: input.Out, dt: f32) void {
    const steps: usize = @intFromFloat(m.clamp(@ceil(dt * 120.0), 1, 4));
    const sub = dt / @as(f32, @floatFromInt(steps));
    for (0..steps) |k| {
        var c = in.controls;
        if (k > 0) {
            // One-shot actions belong to the frame, not to each step of it.
            c.look = .{ 0, 0 };
            c.cycle = .{ false, false };
            c.select = .{ null, null };
            c.examine = false;
            c.hint = false;
            c.confirm = false;
            c.skip = false;
            c.tether = false;
        }
        app.more_steps = k + 1 < steps;
        app.step(c, if (k == 0) in.ui else .{}, sub);
        for (app.sim.sfx[0..app.sim.nsfx]) |ev| audio.playSfx(ev);
        if (app.comm_chirp) audio.play(audio_mod.comm_chirp, 0, 1);
    }
}

/// The synthesiser's continuous state for the frame: drill load per arm, flow, heart rate, the alarm.
pub fn mix(app: *const app_mod.App, audio: *audio_mod.Audio) void {
    const s = &app.sim;
    const in_play = app.screen == .play and (s.mode == .playing or s.mode == .transit);
    const p = &audio.params;
    for (0..2) |k| {
        const a = &s.arms[k];
        p.drill_on[k] = if (in_play and a.tool == .drill and a.held and !a.overheated) 1 else 0;
        p.drill_bite[k] = if (in_play and a.engaged) 1 else 0;
    }
    p.flow = m.sat((s.flow.len() + s.vrel.len() * 0.6) / 500.0) + s.warp;
    p.heart_bpm = 68 + (100 - s.stability) * 0.75;
    p.alarm = if (in_play and s.stability < 25) 1 else 0;
    p.heart_gain = if (app.screen == .pause) 0.5 else 1;
}
