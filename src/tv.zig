//! The game on a Samsung television (Tizen 9). The engine (tvengine, a submodule at `engine/`) owns the
//! window, the OpenGL ES context, the frame loop paced to the display's refresh (50 or 60 Hz, as the
//! television is set), the controllers and the remote; this file is the game's side of it, and the
//! counterpart of `main.zig` on a desktop: it builds the renderer and the application, turns the engine's
//! controller events and the remote's keys into a frame's input, and runs one frame per call. What
//! happens inside a frame is in `runtime.zig`, shared with the desktop.
//!
//! The game is flown with an Xbox controller. The remote reaches every menu (arrows, OK, Back), which is
//! enough to start the game, change the language and leave, and not enough to fly.

const std = @import("std");
const engine = @import("engine");
const options = @import("build_options");
const runtime = @import("runtime.zig");
const gpu = @import("gpu.zig");
const gles = @import("gpu/gles.zig");
const app_mod = @import("app.zig");
const audio_mod = @import("audio.zig");
const input = @import("input.zig");
const game = @import("game.zig");
const tvpad = @import("platform/tvpad.zig");
const tv_files = @import("os/tv_files.zig");
const i18n = @import("i18n.zig");
const log = engine.log;

/// The engine's window: the television gives an application a 1920x1080 plane whatever the panel is.
const out_w = 1920;
const out_h = 1080;

var arena_state: std.heap.ArenaAllocator = .init(std.heap.c_allocator);
var eng: runtime.Engine = undefined;
var audio: audio_mod.Audio = .{};
var audio_on = false;
var ready = false;
var pads: tvpad.Pads = .{};
var mapper: input.Mapper = .{};
var tracker: input.Tracker = .{};
/// What the remote pressed since the last frame.
var remote: app_mod.UiInput = .{};
var remote_back_on_title = false;

/// The scripted run of a debug build: the pilot flies a chapter and the log says how it went.
const Selftest = struct {
    stage: ?game.Stage = null,
    done_at_ns: u64 = 0,
    shots: u32 = 0,
    next_shot_ns: u64 = 0,
};
var selftest: Selftest = .{};
var stats_at_ns: u64 = 0;
var stats_frames: u32 = 0;
var stats_work_ms: f32 = 0;
var stats_work_max_ms: f32 = 0;
var stats_rows: u32 = 0;
var stats_rows_min: u32 = std.math.maxInt(u32);
var stats_slow: u32 = 0;
var shown_late: u32 = 0;
var shown_repeats: u32 = 0;
/// PROFILE=1: time in the simulation and in drawing (which includes the GPU's phases below), and the
/// GPU backend's own account of the latter.
var cpu_ns: [2]u64 = .{ 0, 0 };
var gpu_profile: gles.Profile = .{};

extern "c" fn dlopen(path: ?[*:0]const u8, mode: c_int) ?*anyopaque;
extern "c" fn dlsym(handle: ?*anyopaque, name: [*:0]const u8) ?*anyopaque;
extern "c" fn getenv(name: [*:0]const u8) ?[*:0]const u8;
extern "c" fn free(?*anyopaque) void;

/// The language of the television's menus, as far as the game has it. Tizen keeps it in its settings
/// store under a key that every profile has; the environment's LANG is the fallback, and English the
/// default.
fn systemLanguage() i18n.Lang {
    if (dlopen("libvconf.so.0", 0x101)) |lib| {
        if (dlsym(lib, "vconf_get_str")) |sym| {
            const get: *const fn ([*:0]const u8) callconv(.c) ?[*:0]u8 = @ptrCast(@alignCast(sym));
            if (get("db/menu_widget/language")) |value| {
                defer free(value);
                log.event("LANGUAGE settings={s}", .{std.mem.span(value)});
                return i18n.Lang.fromPreferences(std.mem.span(value));
            }
        }
    }
    const env = std.mem.span(getenv("LANG") orelse "");
    log.event("LANGUAGE env={s}", .{env});
    return i18n.Lang.fromPreferences(env);
}

const Game = struct {
    pub const config: engine.Config = .{
        // The engine's own quad renderer is not used; the game draws through its GPU backend.
        .max_quads = 16,
        .run_obscured = options.selftest,
        .hold_frequency = if (options.no_hold) .never else if (options.force_hold) .always else .auto,
    };

    pub fn init(ctx: *engine.Context) bool {
        const arena = arena_state.allocator();
        tv_files.setDataDir(ctx.dataPath());
        gles.tuning = .{ .scene_height = @intCast(options.scene_height), .min_scene_height = @intCast(options.min_scene_height), .samples = @intCast(options.msaa), .baked_patterns = !options.computed_patterns };
        // A scripted run must not touch the player's save file.
        eng.init(arena, gpu.embedded_shaders, .{}, !options.selftest, null, systemLanguage(), .{}) catch |e| {
            log.event("FATAL renderer {s}", .{@errorName(e)});
            log.text("FATAL_DETAIL", gles.diagnostic());
            return false;
        };
        eng.g.attach({}) catch return false;
        eng.g.resize(out_w, out_h, false);
        if (gles.diagnostic().len != 0) log.text("RENDERER_DETAIL", gles.diagnostic());
        var line: [256]u8 = undefined;
        log.event("RENDERER {s}", .{eng.g.describe(&line)});
        if (options.profile) log.text("GL_EXTENSIONS", eng.g.extensionList());
        const app = eng.app;
        app.prompts = .xbox;
        log.event("GAME language={s} save={s}", .{ app.lang.tag(), ctx.dataPath() });

        startAudio();
        log.event("AUDIO started={any}", .{audio_on});

        if (options.selftest) {
            app.unlock_all = true;
            app.chapter = @intCast(@max(options.chapter, 1) - 1);
            app.bot = .{};
            app.startChapter(0);
        }
        if (options.profile) gles.profile = &gpu_profile;
        if (options.profile) bench();
        ready = true;
        return true;
    }

    pub fn deinit(_: *engine.Context) void {
        stopAudio();
    }

    pub fn pad(_: *engine.Context, e: engine.input.Event) void {
        pads.apply(@enumFromInt(@intFromEnum(e.kind)), e.id, e.index, e.value);
    }

    /// A key of the remote. The names are the X server's, which is what the television reports.
    pub fn key(_: *engine.Context, name: []const u8) void {
        if (!ready) return;
        const eql = std.mem.eql;
        if (eql(u8, name, "Up")) remote.up = true;
        if (eql(u8, name, "Down")) remote.down = true;
        if (eql(u8, name, "Left")) remote.left = true;
        if (eql(u8, name, "Right")) remote.right = true;
        if (eql(u8, name, "Return") or eql(u8, name, "KP_Enter")) remote.confirm = true;
        if (eql(u8, name, "XF86Back") or eql(u8, name, "Escape")) {
            // Back on the first screen leaves the application, as the television's guidelines ask;
            // anywhere else it backs out of a menu, or pauses the flight.
            if (eng.app.screen == .title) remote_back_on_title = true else remote.back = true;
        }
    }

    pub fn suspended(_: *engine.Context) void {
        if (!ready) return;
        // Another application is in front, or the television is going to standby: the flight waits, the
        // sound stops, and whatever was held is forgotten, since its release will not be delivered.
        if (!options.selftest) eng.app.autoPause();
        pads.release();
        stopAudio();
    }

    pub fn resumed(_: *engine.Context) void {
        if (!ready) return;
        eng.g.settle();
        startAudio();
    }

    pub fn frame(ctx: *engine.Context) void {
        if (!ready) return;
        // What the display has reported since the last frame: frames that reached it a refresh later
        // than they were drawn for, and frames it showed for two refreshes.
        if (ctx.presentation) |shown| {
            eng.g.paced(shown.late != shown_late, shown.repeats != shown_repeats);
            shown_late = shown.late;
            shown_repeats = shown.repeats;
        }
        const app = eng.app;
        // Game time advances by the display's refresh period, one frame per vblank; the first frame after
        // a start or a resume has no previous one and takes one period.
        const dt_ns = if (ctx.dt_ns == 0) ctx.period_ns else ctx.dt_ns;
        const dt: f32 = @floatCast(std.math.clamp(@as(f64, @floatFromInt(dt_ns)) * 1e-9, 0.0005, 1.0 / 20.0));

        const from_pad = mapper.update(pads.state(), true, input.Context.of(app), dt);
        const from_remote: input.Out = .{ .controls = .{ .confirm = remote.confirm }, .ui = remote };
        const gathered = from_remote.merge(from_pad);
        remote = .{};
        // The prompts always name the controller: the television has no keyboard to name instead. The
        // tracker is kept for what it notices, which is the controller in use going away (switched off,
        // out of battery, out of range): the flight stops and waits.
        _ = tracker.update(.{}, &mapper.sample);
        if (tracker.lost_pad and !options.selftest) app.autoPause();

        const t0 = if (options.profile) gles.nowNs() else 0;
        runtime.advance(app, &audio, gathered, dt);
        if (app.want_quit or remote_back_on_title) ctx.quit();
        remote_back_on_title = false;
        runtime.mix(app, &audio);
        pumpAudio(ctx);
        const t1 = if (options.profile) gles.nowNs() else 0;
        _ = eng.renderFrame(dt, false);
        if (options.profile) {
            cpu_ns[0] += t1 - t0;
            cpu_ns[1] += gles.nowNs() - t1;
        }

        if (log.enabled) report(ctx);
        if (options.selftest) script(ctx);
    }
};

/// PROFILE=1: what the arithmetic the simulation is made of costs on this processor, per call.
fn bench() void {
    const n = 20000;
    var acc: f32 = 0;
    var x: f32 = 0.1;
    var t = gles.nowNs();
    var out: [8]u64 = @splat(0);
    inline for (.{ "muladd", "sin", "cos", "exp", "floor", "sqrt", "mod", "pow" }, 0..) |name, k| {
        x = 0.1;
        for (0..n) |_| {
            x += 0.37;
            const v: f32 = if (comptime std.mem.eql(u8, name, "muladd")) x * 1.0001 + 0.5 else if (comptime std.mem.eql(u8, name, "sin")) @sin(x) else if (comptime std.mem.eql(u8, name, "cos")) @cos(x) else if (comptime std.mem.eql(u8, name, "exp")) @exp(-x * 0.001) else if (comptime std.mem.eql(u8, name, "floor")) @floor(x) else if (comptime std.mem.eql(u8, name, "sqrt")) @sqrt(x) else if (comptime std.mem.eql(u8, name, "mod")) @mod(x, 6.2831) else std.math.pow(f32, x, 1.5);
            acc += v;
            std.mem.doNotOptimizeAway(acc);
        }
        const now = gles.nowNs();
        out[k] = (now - t) / n;
        t = now;
    }
    log.event("BENCH ns_per_call muladd={d} sin={d} cos={d} exp={d} floor={d} sqrt={d} mod={d} pow={d} acc={d}", .{ out[0], out[1], out[2], out[3], out[4], out[5], out[6], out[7], acc });
    // And the simulation itself: a hundred steps of the chapter as it stands at the start.
    const app = eng.app;
    t = gles.nowNs();
    for (0..100) |_| app.step(.{}, .{}, 1.0 / 120.0);
    log.event("BENCH step_us={d}", .{(gles.nowNs() - t) / 100 / 1000});
}

/// The engine's stream is opened and the synthesiser set to feed it; without the stream the game is silent.
fn startAudio() void {
    if (options.mute or audio_on) return;
    comptime std.debug.assert(engine.audio.sample_rate == audio_mod.rate);
    engine.audio.init();
    engine.audio.resetWatchdog();
    audio_on = engine.audio.active() and audio.start();
}

fn stopAudio() void {
    if (!audio_on) return;
    audio.stop();
    engine.audio.stop();
    audio_on = false;
}

/// Sound is rendered here, on the game's thread, a little ahead of where the stream is playing: enough
/// that a frame shown for two refreshes does not run the queue dry, and no more, since what is queued is
/// heard that much late.
const audio_ahead_frames = 1764; // 80 ms
fn pumpAudio(ctx: *engine.Context) void {
    if (!audio_on) return;
    var block: [512]i16 = undefined;
    var blocks: u32 = 0;
    while (engine.audio.queuedFrames() < audio_ahead_frames and blocks < 16) : (blocks += 1) {
        audio.output.render(&block);
        engine.audio.submitStereo(&block);
    }
    engine.audio.maintain(ctx.time_ns);
}

/// A line of the game's own state for the observer every few seconds, beside the engine's PERF lines.
fn report(ctx: *engine.Context) void {
    stats_frames += 1;
    stats_work_ms += ctx.work_ms;
    stats_work_max_ms = @max(stats_work_max_ms, ctx.work_ms);
    stats_rows += eng.g.scene_h;
    stats_rows_min = @min(stats_rows_min, eng.g.scene_h);
    if (ctx.dt_ns > ctx.period_ns * 3 / 2) stats_slow += 1;
    if (ctx.time_ns - stats_at_ns < 5_000_000_000) return;
    const app = eng.app;
    const s = &app.sim;
    // scene_rows: the scene image's height, averaged and at its least; slow: frames shown for more than
    // one refresh.
    log.event("STATE screen={s} mode={s} stage={s} hull={d:.0} stability={d:.0} pad={any} fps={d:.1} work_ms={d:.2} work_max_ms={d:.2} scene_rows={d} scene_rows_min={d} steps_down={d} steps_up={d} slow={d} audio_frames={d} audio_underruns={d}", .{
        @tagName(app.screen), @tagName(s.mode), @tagName(s.stage), s.hull, s.stability, pads.state().connected, ctx.fps orelse 0, //
        stats_work_ms / @as(f32, @floatFromInt(@max(stats_frames, 1))), stats_work_max_ms, //
        stats_rows / @max(stats_frames, 1), stats_rows_min, eng.g.steps_down, eng.g.steps_up, stats_slow, audio.output.pulled, engine.audio.underruns.load(.monotonic),
    });
    if (options.profile and gpu_profile.frames > 0) {
        const n: f64 = @floatFromInt(gpu_profile.frames);
        var line: [256]u8 = undefined;
        var len: usize = 0;
        for (gles.Profile.phase_names, gpu_profile.ns) |name, ns| {
            len += (std.fmt.bufPrint(line[len..], " {s}_ms={d:.2}", .{ name, @as(f64, @floatFromInt(ns)) / n / 1e6 }) catch break).len;
        }
        log.event("PROFILE frames={d} sim_ms={d:.2} draw_ms={d:.2}{s} draws={d:.0} instances={d:.0} triangles={d:.0}", .{ gpu_profile.frames, @as(f64, @floatFromInt(cpu_ns[0])) / n / 1e6, @as(f64, @floatFromInt(cpu_ns[1])) / n / 1e6, line[0..len], @as(f64, @floatFromInt(gpu_profile.draws)) / n, @as(f64, @floatFromInt(gpu_profile.instances)) / n, @as(f64, @floatFromInt(gpu_profile.triangles)) / n });
        gpu_profile = .{};
        cpu_ns = .{ 0, 0 };
    }
    stats_at_ns = ctx.time_ns;
    stats_frames = 0;
    stats_work_ms = 0;
    stats_work_max_ms = 0;
    stats_rows = 0;
    stats_rows_min = std.math.maxInt(u32);
    stats_slow = 0;
}

/// The scripted run: log each stage the pilot reaches, send a frame to the capture server now and then,
/// and leave a little after the chapter is complete.
fn script(ctx: *engine.Context) void {
    const app = eng.app;
    const s = &app.sim;
    if (selftest.stage == null or selftest.stage.? != s.stage) {
        selftest.stage = s.stage;
        log.event("SELFTEST stage={s} hull={d:.0} stability={d:.0}", .{ @tagName(s.stage), s.hull, s.stability });
    }
    if (options.capture and ctx.time_ns >= selftest.next_shot_ns and selftest.shots < 24) {
        var name: [24]u8 = undefined;
        ctx.captureFrame(std.fmt.bufPrint(&name, "dentro-{d:0>2}", .{selftest.shots}) catch "dentro");
        selftest.shots += 1;
        selftest.next_shot_ns = ctx.time_ns + 15_000_000_000;
    }
    if (s.mode == .complete and selftest.done_at_ns == 0) {
        selftest.done_at_ns = ctx.time_ns;
        log.event("SELFTEST complete chapter={d} grade={c} stability={d:.0} retries={d}", .{ app.chapter + 1, s.grade(), s.stability, s.stats.retries });
    }
    if (selftest.done_at_ns != 0 and ctx.time_ns - selftest.done_at_ns > 4_000_000_000) ctx.quit();
}

pub export fn main(argc: c_int, argv: [*][*:0]u8) c_int {
    return engine.run(Game, argc, argv);
}
