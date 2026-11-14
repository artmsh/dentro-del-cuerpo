//! Dentro del cuerpo — entry point.
//!
//!   dentro                     windowed game
//!   dentro --demo              windowed, flown by the scripted pilot (end-to-end run on the real display)
//!   dentro --demo --pad        the same, with the pilot's controls passed through a game controller's state
//!   dentro --inputtest         windowed, posts key events into its own queue and checks they reach the arms
//!   dentro --padtest           windowed, plays from the title screen with a synthetic game controller
//!   dentro --selftest          headless: scripted pilot plays chapter 1, prints the timeline
//!   dentro --shots <dir>       headless GPU: renders every screen offscreen and writes BMP frames
//!   dentro --icon <file>       headless GPU: renders the app icon as a .png master or a Windows .ico
//!   dentro --help              the usage text
//!
//! `--prompts kbm|xbox|ps` fixes the device the on-screen prompts are written for; without it they follow
//! the device last used. `--lang en|uk` picks the language for the run. Without it the game uses the language the player chose in
//! the game, or else the first supported one in the system's preference list; the scripted modes, whose
//! output is compared between runs, use English.

const std = @import("std");
const m = @import("math.zig");
const gpu = @import("gpu.zig");
const mesh = @import("mesh.zig");
const render = @import("render.zig");
const font = @import("font.zig");
const platform = @import("platform.zig");
const util = @import("util.zig");
const image = @import("image.zig");
const game = @import("game.zig");
const ch2 = @import("ch2.zig");
const ch4 = @import("ch4.zig");
const kidney = @import("kidney.zig");
const bot = @import("bot.zig");
const vein_mod = @import("vein.zig");
const app_mod = @import("app.zig");
const draw = @import("draw.zig");
const audio_mod = @import("audio.zig");
const i18n = @import("i18n.zig");
const strings = @import("strings.zig");
const guide = @import("guide.zig");
const campaign = @import("campaign.zig");
const l10n = @import("l10n.zig");
const pad = @import("pad.zig");
const bindings = @import("bindings.zig");
const input = @import("input.zig");
const cli = @import("cli.zig");
const runtime = @import("runtime.zig");
const Lang = i18n.Lang;
const Text = i18n.Text;

const Mode = cli.Mode;

/// Read by `gpu.zig`: this build draws with the OpenGL ES backend instead of the system's own (`-Dgles`).
pub const dentro_host_gles = @import("build_config").gles;

pub fn main(init: std.process.Init) !void {
    platform.initProcess();
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    var why: [200]u8 = undefined;
    const o = switch (cli.parse(args[@min(1, args.len)..], &why)) {
        .run => |options| options,
        .help => {
            util.writeStdout(cli.usage);
            return;
        },
        .bad => |reason| {
            std.debug.print("dentro: {s}\n\n" ++ cli.usage, .{reason});
            std.process.exit(2);
        },
    };
    const gpu_options: gpu.Options = .{ .software = o.software };
    const result = switch (o.mode) {
        .selftest => runSelftest(arena),
        .shots => runShots(arena, gpu_options, o.path, o.chapter, o.lang, o.prompts orelse .kbm),
        .icon => runIcon(arena, gpu_options, o.path),
        else => runWindow(arena, o.mode, .{ .fullscreen = o.fullscreen, .start_chapter = o.chapter, .lang = o.lang, .prompts = o.prompts, .via_pad = o.via_pad, .gpu = gpu_options }),
    };
    result catch |err| {
        // A player who double-clicked the game has no terminal to read the error from.
        if (o.mode == .play) platform.reportFatal(@errorName(err));
        return err;
    };
}

/// The language the system would like, for a first launch: the first supported one in its preference list.
fn systemLanguage() Lang {
    var buf: [512]u8 = undefined;
    return Lang.fromPreferences(platform.preferredLanguages(&buf));
}

/// NUL-terminated copies of the menu titles in `lang`, for the platform layer.
const MenuText = struct {
    fullscreen: [96:0]u8 = undefined,
    quit: [96:0]u8 = undefined,

    fn set(mt: *MenuText, lang: Lang) platform.MenuTitles {
        return .{
            .fullscreen = terminate(&mt.fullscreen, strings.menu.fullscreen.get(lang)),
            .quit = terminate(&mt.quit, strings.menu.quit.get(lang)),
        };
    }

    fn terminate(out: *[96:0]u8, s: []const u8) [*:0]const u8 {
        const n = @min(s.len, out.len);
        @memcpy(out[0..n], s[0..n]);
        out[n] = 0;
        return out;
    }
};

fn runSelftest(arena: std.mem.Allocator) !void {
    const sim = try arena.create(game.Sim);
    const cp = try arena.create(game.Sim);
    bot.trace = util.envIsSet("DENTRO_TRACE");
    {
        std.debug.print("--- chapter 4: kidneys\n", .{});
        const r4 = bot.runHeadlessChapter(sim, cp, 3, 1500, true);
        const g = &sim.g4;
        std.debug.print("selftest ch4: completed={} stage={s} sim_time={d:.1}s deaths={d} stability={d:.1} grade={c} atlas={d}\n  clean_splits={d} wave_splits={d} bare_blows={d} lodged={d} blocked={d:.1}s passed={d} shards={d} shards_shot={d} shards_escaped={d} cuts={d} jet_time={d:.1}s tissue_hits={d} dual_arm_time={d:.1}s\n", .{ r4.completed, @tagName(r4.stage), r4.sim_seconds, r4.deaths, r4.stability, r4.grade, r4.atlas, g.clean_splits, g.wave_splits, g.bad_punches, g.lodged, g.blocked_t, g.passed, g.shards_made, g.shards_shot, g.shards_escaped, g.cuts, g.jet_time, r4.stats.tissue_hits, r4.stats.dual_time });
        if (!r4.completed) std.process.exit(1);
    }
    {
        std.debug.print("--- chapter 3: stomach\n", .{});
        const r3 = bot.runHeadlessChapter(sim, cp, 2, 1500, true);
        const g = &sim.g3;
        std.debug.print("selftest ch3: completed={} stage={s} sim_time={d:.1}s deaths={d} stability={d:.1} grade={c} atlas={d}\n  colonies={d}/{d} swimmers_killed={d} waves_survived={d} crush_hits={d} acid_time={d:.1}s coat_time={d:.1}s weld_time={d:.1}s bled={d:.1}s tissue_hits={d} tether_uses={d} dual_arm_time={d:.1}s\n", .{ r3.completed, @tagName(r3.stage), r3.sim_seconds, r3.deaths, r3.stability, r3.grade, r3.atlas, g.cleared, g.total, g.swimmers_killed, g.waves_survived, g.crush_hits, g.acid_time, g.coat_time, g.cautery_t, g.blood_lost, r3.stats.tissue_hits, g.tether_uses, r3.stats.dual_time });
        if (!r3.completed) std.process.exit(1);
    }
    {
        std.debug.print("--- chapter 2: intestines\n", .{});
        const r2 = bot.runHeadlessChapter(sim, cp, 1, 1500, true);
        const g = &sim.g;
        std.debug.print("selftest ch2: completed={} stage={s} sim_time={d:.1}s deaths={d} stability={d:.1} grade={c} atlas={d}\n  cleared={d}/{d} extruded={d} spread={d} bursts={d} commensals_lost={d} tissue_hits={d} crush_hits={d} waves_survived={d} tether_uses={d} dual_arm_time={d:.1}s\n", .{ r2.completed, @tagName(r2.stage), r2.sim_seconds, r2.deaths, r2.stability, r2.grade, r2.atlas, g.cleared, g.total, g.extruded, g.spread, g.bursts, g.commensals_lost, r2.stats.tissue_hits, g.crush_hits, g.waves_survived, g.tether_uses, r2.stats.dual_time });
        if (!r2.completed) std.process.exit(1);
        std.debug.print("--- chapter 1: vein\n", .{});
    }
    const r = bot.runHeadless(sim, cp, 1500, true);
    std.debug.print(
        \\selftest: completed={} stage={s} sim_time={d:.1}s deaths={d}
        \\  stability={d:.1} hull={d:.0} grade={c} atlas={d}
        \\  dual_arm_time={d:.1}s sync_strikes={d} kills={d} emboli_lysed={d} emboli_escaped={d} tissue_hits={d} friendly_fire={d}
        \\
    , .{ r.completed, @tagName(r.stage), r.sim_seconds, r.deaths, r.stability, r.hull, r.grade, r.atlas, r.stats.dual_time, r.stats.sync_strikes, r.stats.kills, r.stats.emboli_lysed, r.stats.emboli_escaped, r.stats.tissue_hits, r.stats.friendly_fire });
    if (!r.completed) std.process.exit(1);
}

/// Shader source: the copy shipped beside the executable if present (so it can be edited without
/// rebuilding), otherwise the one compiled into the binary.
fn shaderSource(arena: std.mem.Allocator) [:0]const u8 {
    var path_buf: [1200]u8 = undefined;
    const path = platform.shaderPath(&path_buf, gpu.shader_file) orelse return gpu.embedded_shaders;
    const buf = arena.alloc(u8, 256 * 1024) catch return gpu.embedded_shaders;
    const data = util.readFile(path.ptr, buf[0 .. buf.len - 1]) orelse return gpu.embedded_shaders;
    if (data.len <= 100) return gpu.embedded_shaders;
    buf[data.len] = 0;
    return buf[0..data.len :0];
}

const Engine = runtime.Engine;

/// The renderer and the application, with this platform's shader source and window shortcuts.
fn initEngine(e: *Engine, arena: std.mem.Allocator, options: gpu.Options, persist: bool, lang: ?Lang, fallback: Lang) !void {
    try e.init(arena, shaderSource(arena), options, persist, lang, fallback, .{ .fullscreen = platform.fullscreen_keys, .quit = platform.quit_keys });
}

// ---------------------------------------------------------------------------- offscreen screenshots

/// The atlas entry whose long text is longest in `lang`.
fn longestDeep(lang: Lang) Text {
    var best = guide.entry(@enumFromInt(0)).deep;
    for (1..guide.Topic.count) |k| {
        const d = guide.entry(@enumFromInt(k)).deep;
        if (d.get(lang).len > best.get(lang).len) best = d;
    }
    return best;
}

fn runShots(arena: std.mem.Allocator, options: gpu.Options, dir: []const u8, only: ?u8, lang: ?Lang, prompts: bindings.Device) !void {
    const pool = platform.scopeBegin();
    defer platform.scopeEnd(pool);
    // A run that cannot write its frames is a failed run, and is found out before anything is rendered.
    if (!util.makeDirs(dir)) {
        std.debug.print("shots: cannot create the directory {s}\n", .{dir});
        std.process.exit(1);
    }
    const e = try arena.create(Engine);
    try initEngine(e, arena, options, false, lang, .en);
    e.app.prompts = prompts;
    const w: u32 = 1600;
    const h: u32 = 1000;
    e.g.resize(w, h, true);
    {
        var name: [256]u8 = undefined;
        std.debug.print("shots: rendering with {s}\n", .{e.g.describe(&name)});
    }
    const px = try arena.alloc(u8, w * h * 4);
    const app = e.app;
    const dt: f32 = 1.0 / 60.0;

    const Shooter = struct {
        e: *Engine,
        px: []u8,
        dir: []const u8,
        n: u32 = 0,
        fn snap(sh: *@This(), name: []const u8) void {
            const p2 = platform.scopeBegin();
            defer platform.scopeEnd(p2);
            _ = sh.e.renderFrame(1.0 / 60.0, true);
            sh.e.g.readback(sh.px);
            var path: [1200]u8 = undefined;
            const full = std.fmt.bufPrintSentinel(&path, "{s}/{d:0>2}-{s}.bmp", .{ sh.dir, sh.n, name }, 0) catch {
                std.debug.print("shots: the path for frame {d} ({s}) is too long\n", .{ sh.n, name });
                std.process.exit(1);
            };
            // The first frame that cannot be written ends the run: the rest would fail the same way.
            const hdr = image.bmpHeader(sh.e.g.width, sh.e.g.height);
            if (!util.writeFileParts(full.ptr, &.{ &hdr, sh.px })) {
                std.debug.print("shots: could not write {s}\n", .{full});
                std.process.exit(1);
            }
            std.debug.print("wrote {s}\n", .{full});
            sh.n += 1;
        }
    };
    var sh: Shooter = .{ .e = e, .px = px, .dir = dir };

    // Menus. The language key is pressed on the title screen to show the switch taking effect at once,
    // then pressed until the run is back in its own language.
    for (0..150) |_| app.step(.{}, .{}, dt);
    sh.snap("title");
    for (1..app_mod.TitleItem.count) |_| app.step(.{}, .{ .down = true }, dt);
    sh.snap("title-quit-selected");
    app.step(.{}, .{ .down = true }, dt);
    for (1..Lang.count) |_| {
        app.step(.{}, .{ .language = true }, dt);
        sh.snap("title-language-switched");
    }
    app.step(.{}, .{ .language = true }, dt);
    // The route map with each chapter selected in turn, before anything is unlocked.
    app.step(.{}, .{ .map = true }, dt);
    for (0..30) |_| app.step(.{}, .{}, dt);
    for (0..campaign.chapters.len) |k| {
        var nb: [24]u8 = undefined;
        sh.snap(if (k == 0) "map" else std.fmt.bufPrint(&nb, "map-row{d:0>2}", .{k + 1}) catch "map");
        app.step(.{}, .{ .down = true }, dt);
    }
    app.step(.{}, .{ .back = true }, dt);
    app.step(.{}, .{ .confirm = true }, dt);
    for (0..strings.briefing.pages.len) |k| {
        for (0..600) |_| app.step(.{}, .{}, dt);
        var nb: [24]u8 = undefined;
        sh.snap(if (k == 0) "briefing" else std.fmt.bufPrint(&nb, "briefing-page{d}", .{k + 1}) catch "briefing");
        if (k + 1 < strings.briefing.pages.len) app.step(.{}, .{ .confirm = true }, dt);
    }

    // The chapters, flown by the scripted pilot.
    app.bot = .{};
    app.unlock_all = true;
    var all_done = true;
    // The game as it stood when the current stage began, and room to set the present aside.
    const at_entry = try arena.create(app_mod.App);
    const present = try arena.create(app_mod.App);
    for (0..campaign.playable_count) |ch| {
        if (only) |o| {
            if (o != ch) continue;
        }
        app.chapter = @intCast(ch);
        app.startChapter(0);
        var last_stage: ?game.Stage = null;
        var since: f32 = 0;
        var extra: u32 = 0;
        var t: f32 = 0;
        var done_mode: [6]bool = @splat(false);
        var ring_shot = false;
        var marker_shot = false;
        var stage_shot = false;
        while (t < 900) : (t += dt) {
            app.step(.{}, .{}, dt);
            const s = &app.sim;
            since += dt;
            if (last_stage == null or last_stage.? != s.stage) {
                // The pilot is through some stages sooner than their frame is due (it identifies a villus
                // in the step it arrives). Such a stage is photographed now from where it began: the game
                // goes back to that moment with the pilot held off, runs until Marín starts the stage's
                // own line, and is then put back exactly as it was, so the pilot's run is not disturbed.
                if (last_stage) |missed| {
                    if (!stage_shot) {
                        present.* = app.*;
                        app.* = at_entry.*;
                        app.bot = null;
                        const serial = s.voice.serial;
                        var held: u32 = 0;
                        while (held < 100 and s.stage == missed and (held < 12 or s.voice.serial == serial)) : (held += 1) app.step(.{}, .{}, dt);
                        for (0..2) |_| app.step(.{}, .{}, dt);
                        s.voice.age = 60;
                        sh.snap(@tagName(missed));
                        app.* = present.*;
                    }
                }
                at_entry.* = app.*;
                last_stage = s.stage;
                since = 0;
                extra = 0;
                stage_shot = false;
            }
            const delay: f32 = switch (s.stage) {
                .needle => 1.0,
                .valve1_pass => 2.0,
                .treat => 3.0,
                .septum_break => 1.2,
                .exit => 0.6,
                .g_arrive => 2.5,
                .g_wave => 9.0,
                .g_exit => 0.8,
                .s_arrive => 2.5,
                .s_gradient => 0.9,
                .s_wave => 6.0,
                .s_exit => 0.6,
                .k_arrive => 2.5,
                .k_jets => 1.0,
                .k_exit => 1.0,
                else => 1.4,
            };
            if (since >= delay and since < delay + dt) {
                sh.snap(@tagName(s.stage));
                stage_shot = true;
            }
            const busy = switch (s.stage) {
                .treat, .g_extrude, .g_factory, .g_flume, .g_wave, .s_wave, .s_swim, .s_margin, .s_cautery, .k_neck, .k_split, .k_resonance => true,
                else => false,
            };
            const every: f32 = if (s.stage == .treat) 5.0 else 3.0;
            if (busy and since > delay + 1 and extra < 5 and @mod(since, every) < dt) {
                extra += 1;
                var nb: [40]u8 = undefined;
                sh.snap(std.fmt.bufPrint(&nb, "{s}-more", .{@tagName(s.stage)}) catch "more");
            }
            // The pilot shelters facing a villus; the contraction itself is overhead, so look at it once.
            if (s.stage == .g_wave and !ring_shot and s.gut.squeeze(s.pos.z) > 0.7) {
                ring_shot = true;
                const keep = s.pitch;
                s.pitch = 1.05;
                sh.snap("g_wave-ring-overhead");
                s.pitch = 0.45;
                sh.snap("g_wave-ring-ahead");
                s.pitch = keep;
            }
            // The same in the stomach: the pilot is down a pit, and the far wall is closing on its mouth.
            if (s.stage == .s_wave and !ring_shot and s.sto.squeeze(s.pos.z) > 0.7) {
                ring_shot = true;
                const keep = s.pitch;
                s.pitch = 1.2;
                sh.snap("s_wave-ring-overhead");
                s.pitch = keep;
            }
            // In the kidney the pilot keeps clear of the ducts, so look at one while it spurts.
            if (s.stage == .k_jets and !ring_shot) {
                for (0..kidney.duct_count) |i| {
                    const at = kidney.ductPos(i);
                    if (kidney.jetStrength(i, s.clock) < 0.9 or at.dist(s.pos) > 420) continue;
                    ring_shot = true;
                    const keep = [2]f32{ s.yaw, s.pitch };
                    const d = at.add(kidney.ductNormal(i).scale(70)).sub(s.pos).norm();
                    s.yaw = std.math.atan2(d.x, d.z);
                    s.pitch = std.math.asin(d.y);
                    sh.snap("k_jets-spurt");
                    s.yaw = keep[0];
                    s.pitch = keep[1];
                    break;
                }
            }
            // The transit marker stands in the fornix, out of sight from the stone until the pilot turns for it.
            if (s.stage == .k_exit and !marker_shot and ch4.exitSite().dist(s.pos) < 700) {
                marker_shot = true;
                const keep = [2]f32{ s.yaw, s.pitch };
                const d = ch4.exitSite().sub(s.pos).norm();
                s.yaw = std.math.atan2(d.x, d.z);
                s.pitch = std.math.asin(d.y);
                sh.snap("k_exit-marker");
                s.yaw = keep[0];
                s.pitch = keep[1];
            }
            const mi = @intFromEnum(s.mode);
            if (s.mode != .playing and !done_mode[mi]) {
                done_mode[mi] = true;
                // Hold the pilot off so a card it would dismiss stays up for the frame.
                const name = @tagName(s.mode);
                const pilot = app.bot;
                app.bot = null;
                for (0..30) |_| app.step(.{}, .{}, dt);
                sh.snap(name);
                app.bot = pilot;
            }
            if (s.mode == .complete) break;
        }
        all_done = all_done and app.sim.mode == .complete;
    }

    // The route map as the debrief leaves it, with the flown chapters logged.
    if (app.sim.mode == .complete) {
        app.step(.{}, .{ .confirm = true }, dt);
        for (0..30) |_| app.step(.{}, .{}, dt);
        sh.snap("map-after-debrief");
        while (app.map_sel > 0) {
            app.step(.{}, .{ .up = true }, dt);
            var nb: [32]u8 = undefined;
            sh.snap(std.fmt.bufPrint(&nb, "map-logged-row{d:0>2}", .{app.map_sel + 1}) catch "map");
        }
    }

    // Text the pilot's run does not reach. Each case is put on screen directly: the worst case for the
    // subtitle box from each source of lines, the HUD warnings, the failure cards and the debrief notes.
    app.bot = null;
    for (0..campaign.playable_count) |ch| {
        app.chapter = @intCast(ch);
        app.startChapter(0);
        for (0..40) |_| app.step(.{}, .{}, dt);
        const s = &app.sim;
        const tag: []const u8 = switch (ch) {
            0 => "vein",
            1 => "gut",
            2 => "stomach",
            else => "kidney",
        };
        var nb: [48]u8 = undefined;
        if (ch == 0) {
            const cases = [_]struct { []const u8, Text }{
                .{ "subtitle-longest-line", l10n.longestIn(strings.line, app.lang) },
                .{ "subtitle-longest-hint", l10n.longestIn(strings.hint, app.lang) },
                .{ "subtitle-longest-atlas", longestDeep(app.lang) },
            };
            for (cases) |case| {
                s.voice.clear();
                s.voice.say(case[1], .normal);
                s.voice.age = 60;
                sh.snap(case[0]);
            }
            s.voice.clear();
            s.arms[0].tool = .drill;
            s.arms[0].overheated = true;
            s.arms[1].tool = .shoot;
            s.tissue_flash = 1;
            s.checkpoint_toast = 2;
            s.hidden_unlocked = true;
            sh.snap("hud-warnings");
            s.tissue_flash = 0;
            s.checkpoint_toast = 0;
            s.mode = .dead;
            sh.snap("dead");
        }
        s.voice.clear();
        s.mode = .lost;
        sh.snap(std.fmt.bufPrint(&nb, "lost-{s}", .{tag}) catch "lost");
        // The debrief with the notes a clean run does not earn.
        s.mode = .complete;
        s.stats.emboli_escaped = 3;
        s.hidden_unlocked = true;
        s.g.spread = 2;
        sh.snap(std.fmt.bufPrint(&nb, "complete-notes-{s}", .{tag}) catch "complete");
        if (ch == 1) {
            s.g.commensals_lost = 5;
            sh.snap("complete-notes-gut-flora");
        }
        if (ch == 2) {
            s.g3.blood_lost = 61;
            s.g3.acid_time = 38.5;
            s.g3.crush_hits = 2;
            sh.snap("complete-notes-stomach-bled");
            s.stats.tissue_hits = 6;
            sh.snap("complete-notes-stomach-lining");
            // The HUD's warnings in the stomach: acid on a bare hull, then on the coat, and the pause
            // menu's row for the coat.
            s.mode = .playing;
            s.stats.tissue_hits = 0;
            s.pos.y = 420;
            for (0..20) |_| app.step(.{}, .{}, dt);
            s.voice.clear();
            sh.snap("hud-acid-bare-hull");
            s.g3.has_coat = true;
            s.g3.coat = 7.4;
            for (0..3) |_| app.step(.{}, .{}, dt);
            s.voice.clear();
            sh.snap("hud-acid-coat-holding");
            app.openPause();
            sh.snap("pause-with-coat");
            app.step(.{}, .{ .back = true }, dt);
        }
        if (ch == 3) {
            s.g4.lodged = 2;
            s.g4.bad_punches = 3;
            s.g4.clean_splits = 7;
            sh.snap("complete-notes-kidney-lodged");
            s.g4.lodged = 0;
            s.g4.shards_escaped = 5;
            sh.snap("complete-notes-kidney-shards");
            // The HUD's warnings in the kidney: a piece wedged in the outlet, a notch that is ready, and
            // the pause menu's row for Resonance.
            s.mode = .playing;
            s.stats.emboli_escaped = 0;
            s.hidden_unlocked = false;
            s.stage = .k_split;
            s.g4.neck_cut = true;
            if (s.find(.calculus)) |st| {
                st.state = 2;
                st.pos = m.v3(0, ch4.stopY(st.radius).?, 0);
            }
            s.pos = m.v3(0, 1500, -500);
            s.yaw = 0.25;
            s.pitch = 1.0;
            for (0..3) |_| app.step(.{}, .{}, dt);
            s.voice.clear();
            sh.snap("hud-outlet-blocked");
            if (s.find(.calculus)) |st| {
                st.state = 0;
                st.pos = m.v3(0, 900, 900);
                st.vel = .{};
                st.aux = 1;
                st.timer = 0.25;
                s.pos = st.pos.add(m.v3(0, 0, -(st.radius + 14)));
                s.yaw = 0;
                s.pitch = 0;
            }
            s.arms[0].tool = .punch;
            s.arms[1].tool = .drill;
            for (0..2) |_| app.step(.{ .arm = .{ false, true } }, .{}, dt);
            s.voice.clear();
            sh.snap("hud-notch-ready");
            s.g4.has_resonance = true;
            app.openPause();
            sh.snap("pause-with-resonance");
            app.step(.{}, .{ .back = true }, dt);
        }
        s.mode = .playing;
    }

    // Pause screen, the language key on it, and the selection moved down to the language entry.
    app.openPause();
    sh.snap("pause");
    for (1..Lang.count) |_| {
        app.step(.{}, .{ .language = true }, dt);
        sh.snap("pause-language-switched");
    }
    app.step(.{}, .{ .language = true }, dt);
    for (1..app_mod.PauseItem.count) |_| app.step(.{}, .{ .down = true }, dt);
    sh.snap("pause-language-selected");
    app.step(.{}, .{ .up = true }, dt);
    sh.snap("pause-quit-selected");
    // The control list gains a row once the drone carries the tether.
    app.sim.has_tether = true;
    sh.snap("pause-with-tether");
    std.debug.print("shots: {d} frames, chapters complete = {}\n", .{ sh.n, all_done });
    // The frames are evidence only of a run that got to the end of what it was asked to fly.
    if (!all_done) std.process.exit(1);
}

/// Render the app icon from the title backdrop and the reticle mark, 2048 px and clipped to a rounded
/// square. A path ending in .ico gets the Windows icon, every size it carries scaled down from that
/// render; any other path gets the 2048 px PNG that the macOS iconset is made from.
fn runIcon(arena: std.mem.Allocator, options: gpu.Options, path: []const u8) !void {
    const pool = platform.scopeBegin();
    defer platform.scopeEnd(pool);
    const e = try arena.create(Engine);
    try initEngine(e, arena, options, false, null, .en);
    const n: u32 = 2048; // supersampled; the iconset step scales it down
    e.g.resize(n, n, true);
    const px = try arena.alloc(u8, n * n * 4);
    e.app.icon_mode = true;
    for (0..240) |_| e.app.step(.{}, .{}, 1.0 / 60.0);
    _ = e.renderFrame(1.0 / 60.0, true);
    e.g.readback(px);
    const ico = std.ascii.endsWithIgnoreCase(path, ".ico");
    // The macOS icon grid leaves a margin: the shape fills 824/1024 of the canvas, as a superellipse.
    // Windows draws an icon edge to edge, so there the same shape fills the canvas but for a pixel or
    // two of the smallest size.
    const half: f32 = if (ico) 992 else 824;
    for (0..n) |y| for (0..n) |x| {
        const dx = @abs(@as(f32, @floatFromInt(x)) + 0.5 - 1024) / half;
        const dy = @abs(@as(f32, @floatFromInt(y)) + 0.5 - 1024) / half;
        const d = std.math.pow(f32, std.math.pow(f32, dx, 5) + std.math.pow(f32, dy, 5), 0.2);
        const a = m.sat((1 - d) * half / 1.5);
        const o = (y * n + x) * 4;
        for (0..3) |c| px[o + c] = @intFromFloat(@as(f32, @floatFromInt(px[o + c])) * a);
        px[o + 3] = @intFromFloat(255 * a);
    };
    var zbuf: [1024]u8 = undefined;
    const z = try std.fmt.bufPrintSentinel(&zbuf, "{s}", .{path}, 0);
    const bytes = if (ico) try image.encodeIco(arena, px, n) else try image.encodePng(arena, px, n, n);
    if (!util.writeFile(z.ptr, bytes)) return error.IconWriteFailed;
    std.debug.print("icon: {s}\n", .{path});
}

// ---------------------------------------------------------------------------- windowed game

/// Keyboard and mouse as the game's actions. The controller's half of this is `input.Mapper`.
fn gather(in: *const platform.Input, captured: bool, dt: f32) input.Out {
    var c: game.Controls = .{};
    const f = struct {
        fn axis(keys: *const platform.Input, pos: platform.Key, neg: platform.Key) f32 {
            return @as(f32, if (keys.down(pos)) 1 else 0) - @as(f32, if (keys.down(neg)) 1 else 0);
        }
    };
    c.move = m.v3(f.axis(in, .d, .a), f.axis(in, .space, .c), f.axis(in, .w, .s));
    c.boost = in.down(.shift);
    const key_rate: f32 = 2.1;
    c.look[0] = f.axis(in, .right, .left) * key_rate * dt;
    c.look[1] = f.axis(in, .up, .down) * key_rate * dt;
    if (captured) {
        c.look[0] += in.mouse_dx * 0.0024;
        c.look[1] -= in.mouse_dy * 0.0024;
    }
    c.arm[0] = in.down(.q) or (captured and in.lmb);
    c.arm[1] = in.down(.e) or (captured and in.rmb);
    c.cycle = .{ in.hit(.z), in.hit(.x) };
    if (in.hit(.n1)) c.select[0] = .punch;
    if (in.hit(.n2)) c.select[0] = .drill;
    if (in.hit(.n3)) c.select[0] = .shoot;
    if (in.hit(.n8)) c.select[1] = .punch;
    if (in.hit(.n9)) c.select[1] = .drill;
    if (in.hit(.n0)) c.select[1] = .shoot;
    c.examine = in.hit(.t) or in.hit(.f);
    c.hint = in.hit(.h);
    c.tether = in.hit(.g);
    c.confirm = in.hit(.enter);
    c.skip = in.hit(.tab);
    const ui: app_mod.UiInput = .{
        .confirm = in.hit(.enter),
        .back = in.hit(.escape),
        .up = in.hit(.up) or in.hit(.w),
        .down = in.hit(.down) or in.hit(.s),
        .map = in.hit(.m),
        .retry = in.hit(.r),
        .restart = in.hit(.n),
        .quit_to_title = in.hit(.l),
        .language = in.hit(.tab),
    };
    return .{ .controls = c, .ui = ui };
}

var live_audio: ?*audio_mod.Audio = null;

fn stopAudioOnTerminate() void {
    if (live_audio) |a| a.stop();
}

const WindowOptions = struct {
    fullscreen: bool = false,
    start_chapter: ?u8 = null,
    lang: ?Lang = null,
    /// The device the prompts are written for, if the command line fixed it.
    prompts: ?bindings.Device = null,
    /// `--demo --pad`: the scripted pilot holds a controller instead of handing its controls to the game.
    via_pad: bool = false,
    gpu: gpu.Options = .{},
};

const SyntheticPad = platform.SyntheticPad;

fn runWindow(arena: std.mem.Allocator, mode: Mode, opts: WindowOptions) !void {
    const fullscreen = opts.fullscreen;
    const start_chapter = opts.start_chapter;
    const lang = opts.lang;
    const outer = platform.scopeBegin();
    defer platform.scopeEnd(outer);
    const e = try arena.create(Engine);
    // The scripted tests assert on their output, so they do not follow the machine they run on.
    try initEngine(e, arena, opts.gpu, mode == .play, lang, if (mode == .inputtest or mode == .padtest) .en else systemLanguage());
    const app = e.app;
    if (opts.prompts) |d| app.prompts = d;
    var menu_text: MenuText = .{};
    var menu_lang = app.lang;
    var plat = platform.Platform.init(app_mod.title, menu_text.set(menu_lang), 1440, 900);
    try e.g.attach(plat.surface());
    plat.show();
    if (fullscreen) plat.toggleFullscreen();

    const audio = try arena.create(audio_mod.Audio);
    audio.* = .{};
    const audio_ok = audio.start();
    defer audio.stop();
    live_audio = audio;
    platform.setTerminateHook(&stopAudioOnTerminate);
    if (!audio_ok) std.debug.print("audio: output queue failed to start; continuing silent\n", .{});

    if (start_chapter) |ch| {
        app.unlock_all = true;
        app.chapter = ch;
    }
    const pad_pilot = mode == .demo and opts.via_pad;
    if (mode == .demo) {
        if (!pad_pilot) app.bot = .{};
        app.startChapter(0);
    } else if (mode == .play and start_chapter != null) {
        app.startChapter(0);
    }
    var it: InputTest = .{};
    if (mode == .inputtest) it.begin(app);
    var pt: PadTest = .{};
    if (mode == .padtest) pt.begin(&plat, app);
    var held_pad: SyntheticPad = .{};
    if (pad_pilot) held_pad = SyntheticPad.attach(&plat);
    var pilot: bot.Bot = .{};
    var pilot_retries: u32 = 0;
    var puppet: input.Puppet = .{};
    var mapper: input.Mapper = .{};
    var tracker: input.Tracker = .{};
    if (mode == .demo) {
        var prefs: [512]u8 = undefined;
        std.debug.print("[demo] language {s} (asked for: {s}; system preference: {s})\n", .{ app.lang.tag(), if (lang) |l| l.tag() else "-", platform.preferredLanguages(&prefs) });
    }

    var last = platform.now();
    var frames: u64 = 0;
    var demo_logged: ?game.Stage = null;
    const t_start = last;
    while (!plat.shouldQuit()) {
        const pool = platform.scopeBegin();
        defer platform.scopeEnd(pool);

        const now = platform.now();
        const dt: f32 = @floatCast(@min(@max(now - last, 0.0005), 1.0 / 20.0));
        last = now;

        if (mode == .inputtest) it.post(&plat, app);
        if (mode == .padtest) pt.drive(&plat, app, dt);
        if (pad_pilot) {
            // The pilot decides what it wants, and a controller is held the way that takes. From here its
            // input is a controller's: read by the platform, mapped, merged with the keyboard's.
            const s = &app.sim;
            if (s.stats.retries != pilot_retries) {
                pilot_retries = s.stats.retries;
                pilot = .{};
            }
            var want: game.Controls = .{};
            if (app.screen == .play) {
                want = pilot.think(s, dt);
                if (s.mode == .dead and app.screen_t > 1) want.confirm = true;
            }
            held_pad.set(&plat, puppet.drive(want, input.Context.of(app), dt));
        }
        const lost_focus = plat.pump();
        if (lost_focus and mode == .play) app.autoPause();
        const size = plat.pixelSize();
        if (size.w != e.g.width or size.h != e.g.height) e.g.resizeSurface(size.w, size.h, size.scale);

        // Both devices are read every frame and their input is added together; the prompts are written
        // for whichever was used last.
        const from_pad = mapper.update(plat.pad, plat.padFocused(), input.Context.of(app), dt);
        const gathered = gather(&plat.input, plat.captured, dt).merge(from_pad);
        const used = tracker.update(.{ .pressed = plat.input.anyPressed(), .held = plat.input.anyHeld() }, &mapper.sample);
        app.prompts = opts.prompts orelse used;
        // The controller the player was flying with has gone (unplugged, out of battery, out of range):
        // the game stops and waits rather than fly on with nobody at the controls.
        if (tracker.lost_pad and (mode == .play or mode == .padtest)) app.autoPause();

        runtime.advance(app, audio, gathered, dt);
        plat.input.endFrame();
        // Quit chosen from a menu ends the game the way the menu bar's Quit does. The scripted modes leave
        // the request standing for their script to read.
        if (app.want_quit and (mode == .play or mode == .demo)) plat.quit();
        plat.capture(app.want_capture and mode == .play);
        if (app.lang != menu_lang) {
            menu_lang = app.lang;
            plat.setMenuTitles(menu_text.set(menu_lang));
        }

        runtime.mix(app, audio);

        _ = e.renderFrame(dt, false);
        frames += 1;
        if (mode == .demo and frames == 30) {
            std.debug.print("[demo] controller: {s}, {s}; {s}\n", .{
                if (plat.pad.connected) @tagName(plat.pad.family) else "none attached",
                switch (plat.pad_source) {
                    .system => "polled from the system",
                    else => held_pad.describe(),
                },
                platform.padBackendStatus(),
            });
        }

        if (mode == .demo) {
            const s = &app.sim;
            if (demo_logged == null or demo_logged.? != s.stage) {
                demo_logged = s.stage;
                std.debug.print("[demo {d:6.1}s] stage {s} hull {d:.0} stability {d:.0}\n", .{ now - t_start, @tagName(s.stage), s.hull, s.stability });
            }
            if (s.mode == .complete and app.screen_t > 0) {
                const secs = now - t_start;
                if (it.linger == 0) std.debug.print("demo: chapter complete on the display. grade={c} stability={d:.0} dual_arm_time={d:.1}s sync_strikes={d} retries={d} frames={d} avg_fps={d:.0} drawable={d}x{d} audio={} input={s}\n", .{ s.grade(), s.stability, s.stats.dual_time, s.stats.sync_strikes, s.stats.retries, frames, @as(f64, @floatFromInt(frames)) / secs, e.g.width, e.g.height, audio_ok, if (pad_pilot) held_pad.describe() else "pilot's controls, direct" });
                // linger on the debrief for a moment so it is visible
                if (it.linger == 0) it.linger = now;
                if (now - it.linger > 2.5) return;
            }
            if (now - t_start > 600) {
                std.debug.print("demo: timed out in stage {s}\n", .{@tagName(s.stage)});
                std.process.exit(1);
            }
        }
        if (mode == .inputtest and it.finished) {
            std.debug.print("inputtest: {s} ({d} checks, {d} failed) drawable={d}x{d}\n", .{ if (it.failed == 0) "PASS" else "FAIL", it.checks, it.failed, e.g.width, e.g.height });
            if (it.failed != 0) {
                audio.stop();
                std.process.exit(1);
            }
            return;
        }
        if (mode == .padtest and pt.finished) {
            std.debug.print("padtest: {s} ({d} checks, {d} failed) pad={s} drawable={d}x{d}\n", .{ if (pt.failed == 0) "PASS" else "FAIL", pt.checks, pt.failed, pt.held.describe(), e.g.width, e.g.height });
            if (pt.failed != 0) {
                audio.stop();
                std.process.exit(1);
            }
            return;
        }
    }
}

/// Drives the real event path: key events are posted to this application's own queue, drained by the
/// normal pump, mapped by `gather`, and the result is read back from the simulation.
const InputTest = struct {
    frame: u32 = 0,
    checks: u32 = 0,
    failed: u32 = 0,
    finished: bool = false,
    linger: f64 = 0,
    start_pos: m.Vec3 = .{},
    start_yaw: f32 = 0,
    stone_hp: f32 = 0,
    saw_both: bool = false,
    saw_drill_and_shoot: bool = false,
    start_lang: Lang = .en,
    yaw_after_release: f32 = 0,
    saw_shortcut_down: bool = false,
    menu_hits: u32 = 0,
    quit_hits: u32 = 0,

    fn begin(it: *InputTest, app: *app_mod.App) void {
        _ = it;
        app.startChapter(0);
        standAtStone(app);
    }

    /// Stand in front of the phlebolith with the upgrade installed, both arms on Punch.
    fn standAtStone(app: *app_mod.App) void {
        const s = &app.sim;
        s.in_bore = false;
        s.stage = .septum_break;
        s.station = 2;
        s.has_sync = true;
        s.voice.clear();
        const stone = s.findConst(.phlebolith).?;
        s.pos = stone.pos.add(m.v3(0, 0, -(stone.radius + 14)));
        s.yaw = 0;
        s.pitch = 0;
        s.sides = .{};
        s.arms[0].tool = .punch;
        s.arms[1].tool = .punch;
        app.checkpoint = s.*;
    }

    /// Turn the view until the tether would (or would not) find tissue. Test setup only: the key press
    /// that follows still travels the real event path.
    fn aim(s: *game.Sim, want_hit: bool) bool {
        const pitches = [_]f32{ 0, -0.3, 0.3, -0.8, 0.8, 1.2, 1.45 };
        for (pitches) |p| {
            for (0..24) |k| {
                s.pitch = p;
                s.yaw = @as(f32, @floatFromInt(k)) * std.math.tau / 24.0;
                if ((ch2.tetherTarget(s) != null) == want_hit) return true;
            }
        }
        return false;
    }

    fn check(it: *InputTest, ok: bool, what: []const u8) void {
        it.checks += 1;
        if (!ok) it.failed += 1;
        std.debug.print("  [{s}] {s}\n", .{ if (ok) "ok" else "FAIL", what });
    }

    fn post(it: *InputTest, plat: *platform.Platform, app: *app_mod.App) void {
        const s = &app.sim;
        it.frame += 1;
        if (s.arms[0].held and s.arms[1].held) it.saw_both = true;
        if (s.arms[0].held and s.arms[1].held and s.arms[0].tool != s.arms[1].tool) it.saw_drill_and_shoot = true;
        // The modifier that makes a key a command for the window (Cmd on a Mac, Alt on Windows), and the
        // key that with it is the full-screen shortcut.
        const sc = platform.shortcut;
        if (plat.input.down(sc.fullscreen)) it.saw_shortcut_down = true;
        switch (it.frame) {
            20 => {
                it.stone_hp = s.findConst(.phlebolith).?.hp;
                plat.postKey(.q, true);
                plat.postKey(.e, true);
            },
            26 => {
                plat.postKey(.q, false);
                plat.postKey(.e, false);
            },
            70 => {
                it.check(it.saw_both, "Q and E held in the same frame drive both arms");
                it.check(s.stats.sync_strikes == 1, "simultaneous punches landed as one Sync Strike");
                it.check(s.findConst(.phlebolith).?.hp == it.stone_hp - 10, "Sync Strike did 10 damage to the phlebolith");
                // tool selection: left arm to Shoot (3), right arm to Drill via cycle (X)
                plat.postKey(.n3, true);
                plat.postKey(.x, true);
            },
            72 => {
                plat.postKey(.n3, false);
                plat.postKey(.x, false);
            },
            110 => {
                it.check(s.arms[0].tool == .shoot, "3 selects Shoot on the left arm");
                it.check(s.arms[1].tool == .drill, "X cycles the right arm from Punch to Drill");
                it.saw_drill_and_shoot = false;
                plat.postKey(.q, true);
                plat.postKey(.e, true);
            },
            170 => {
                it.check(it.saw_drill_and_shoot, "different tools run on both arms at once");
                it.check(s.arms[1].engaged, "the drill arm is cutting while the other arm fires");
                it.check(s.arms[0].charge < 1, "the shoot arm fired");
                plat.postKey(.q, false);
                plat.postKey(.e, false);
                it.start_pos = s.pos;
                it.start_yaw = s.yaw;
                plat.postKey(.s, true);
                plat.postKey(.left, true);
            },
            230 => {
                plat.postKey(.s, false);
                // The arrow key comes up while the modifier is down, as it does when the player lets go of
                // it between pressing the full-screen shortcut and releasing the modifier.
                plat.postSystemKey(.left, false);
                it.check(s.pos.dist(it.start_pos) > 20, "S thrusts the drone backward");
                it.check(@abs(s.yaw - it.start_yaw) > 0.3, "arrow keys turn the view");
                plat.postKey(.t, true);
            },
            232 => plat.postKey(.t, false),
            234 => {
                it.check(!plat.input.down(.left), "a key released while " ++ sc.modifier ++ " is held is released");
                it.yaw_after_release = s.yaw;
            },
            246 => {
                it.check(@abs(s.yaw - it.yaw_after_release) < 0.01, "and the view has stopped turning");
                // M and L do nothing in flight, so the key state can be read without the drone moving.
                plat.postSystemKey(.m, true);
            },
            248 => {
                it.check(plat.input.down(.m), "a key pressed while " ++ sc.modifier ++ " is held reaches the game, when it is not a shortcut of the window's");
                plat.postSystemKey(.m, false);
            },
            250 => {
                it.check(!plat.input.down(.m), "and its release does too");
                // The full-screen shortcut belongs to the window. The command is pointed at a counter for
                // these few frames, so the shortcut can be pressed without the window going full screen.
                plat.probeFullscreen(true);
                it.menu_hits = plat.fullscreenProbeHits();
                it.saw_shortcut_down = false;
                plat.postSystemKey(sc.fullscreen, true);
            },
            252 => plat.postSystemKey(sc.fullscreen, false),
            254 => {
                it.check(plat.fullscreenProbeHits() == it.menu_hits + 1, sc.modifier ++ "+" ++ sc.fullscreen_name ++ " reaches the full-screen command, once");
                it.check(!it.saw_shortcut_down, "and is not also read as the " ++ sc.fullscreen_name ++ " key");
                plat.probeFullscreen(false);
            },
            // The quit shortcut, the same way: it has to reach the command that ends the game, and the
            // menus have to name it as this platform does.
            255 => {
                plat.probeQuit(true);
                it.quit_hits = plat.quitProbeHits();
                plat.postQuitShortcut(true);
            },
            257 => plat.postQuitShortcut(false),
            259 => {
                it.check(plat.quitProbeHits() == it.quit_hits + 1, sc.modifier ++ "+" ++ sc.quit_name ++ " reaches the quit command, once");
                plat.probeQuit(false);
                it.check(!plat.shouldQuit(), "and the probe kept it from ending the test");
                const kbm: bindings.Prompt = .{ .lang = app.lang, .device = .kbm, .window = app.window_keys };
                it.check(std.mem.eql(u8, bindings.label(.quit, kbm), sc.modifier ++ "+" ++ sc.quit_name), "the Quit entry of the menus names " ++ sc.modifier ++ "+" ++ sc.quit_name);
                it.check(std.mem.eql(u8, app.window_keys.fullscreen, sc.modifier ++ "+" ++ sc.fullscreen_name), "the pause screen names " ++ sc.modifier ++ "+" ++ sc.fullscreen_name ++ " for full screen");
            },
            260 => {
                plat.postKey(.escape, true);
            },
            262 => plat.postKey(.escape, false),
            280 => {
                it.check(app.screen == .pause, "Esc pauses");
                it.start_lang = app.lang;
                plat.postKey(.tab, true);
            },
            282 => plat.postKey(.tab, false),
            286 => {
                it.check(app.lang == it.start_lang.next() and app.lang != it.start_lang, "Tab in the pause menu switches to the next language");
                it.check(std.mem.eql(u8, plat.menuTitle(.quit), strings.menu.quit.get(app.lang)), "the menu bar follows the language");
                it.check(app.save.lang == app.lang and app.save_path_len == 0, "the choice is recorded for saving, and a scripted run has no save file to write");
                plat.postKey(.tab, true);
            },
            288 => plat.postKey(.tab, false),
            292 => {
                var want = it.start_lang;
                for (0..2) |_| want = want.next();
                it.check(app.lang == want, "Tab again moves on to the language after that");
                while (app.lang != it.start_lang) app.cycleLanguage();
                plat.postKey(.r, true);
            },
            294 => plat.postKey(.r, false),
            312 => {
                it.check(app.screen == .play and s.stats.retries == 1, "R in the pause menu relaunches from the checkpoint");
                // Chapter 2: the tether key, from where the drone arrives among the villi.
                app.chapter = 1;
                app.startChapter(0);
                s.has_tether = true;
                s.stage = .g_tether;
                s.voice.clear();
            },
            341 => it.check(aim(s, true), "a villus is within tether range of the arrival point"),
            342 => plat.postKey(.g, true),
            344 => plat.postKey(.g, false),
            352 => it.check(s.tether != null and s.g.tether_uses == 1, "G fires the tether at the tissue under the reticle"),
            482 => {
                it.check(s.tether != null and s.pos.dist(s.tether_hold) < 30, "the line reels the drone in and holds it with no thrust");
                it.check(aim(s, false), "open lumen is in view from the hold point");
                plat.postKey(.g, true);
            },
            484 => plat.postKey(.g, false),
            497 => {
                it.check(s.tether == null, "G on nothing releases the tether");
                it.finished = true;
            },
            else => {},
        }
    }
};

/// Plays the game from the title screen with a controller and nothing else. The controller is synthetic
/// (see `SyntheticPad`), and from there on its input takes the path a real one's does: `Platform.pump`
/// reads it, `input.Mapper` turns it into actions, and the result is read back from the game. Where the
/// script needs a particular place to stand it sets the simulation up, as the input test does; it never
/// hands the game an action.
const PadTest = struct {
    phase: u32 = 0,
    /// Seconds spent in the current phase.
    t: f32 = 0,
    advanced: bool = false,
    checks: u32 = 0,
    failed: u32 = 0,
    finished: bool = false,
    held: SyntheticPad = .{},
    st: pad.State = .{ .connected = true },
    lang0: Lang = .en,
    pos0: m.Vec3 = .{},
    yaw0: f32 = 0,
    pitch0: f32 = 0,
    stone_hp: f32 = 0,
    sel0: usize = 0,
    steps: u32 = 0,
    pages: usize = 0,
    count0: u32 = 0,
    serial0: u32 = 0,
    top_speed: f32 = 0,
    lift: [2]f32 = .{ 0, 0 },
    saw_both: bool = false,
    saw_mixed: bool = false,
    saw_key_arm: bool = false,
    /// The controller is reported as gone, whatever `st` holds.
    unplugged: bool = false,

    fn begin(pt: *PadTest, plat: *platform.Platform, app: *app_mod.App) void {
        pt.held = SyntheticPad.attach(plat);
        // The route map is walked to chapter 2, which a fresh save has locked.
        app.unlock_all = true;
    }

    fn check(pt: *PadTest, ok: bool, what: []const u8) void {
        pt.checks += 1;
        if (!ok) pt.failed += 1;
        std.debug.print("  [{s}] {s}\n", .{ if (ok) "ok" else "FAIL", what });
    }

    /// True while the script is at the `k`th phase, counting them in the order they are written.
    fn at(pt: *PadTest, k: *u32) bool {
        defer k.* += 1;
        return pt.phase == k.* and !pt.advanced;
    }

    fn next(pt: *PadTest) void {
        pt.phase += 1;
        pt.t = 0;
        pt.advanced = true;
    }

    /// Press `b` and let it go. True once the game has had a few frames to act on the press.
    fn tap(pt: *PadTest, b: pad.Button) bool {
        pt.st.set(b, pt.t < 0.07);
        return pt.t >= 0.2;
    }

    /// `n` taps of `b`, one after another.
    fn taps(pt: *PadTest, b: pad.Button, n: u32) bool {
        const period: f32 = 0.2;
        pt.st.set(b, pt.t < period * @as(f32, @floatFromInt(n)) and @mod(pt.t, period) < 0.07);
        return pt.t >= period * @as(f32, @floatFromInt(n)) + 0.1;
    }

    fn rest(pt: *PadTest) void {
        pt.st = .{ .connected = true };
    }

    /// Everything a controller has, written to the synthetic device and read back by the code that reads
    /// a real one. Opposite d-pad directions cannot be down together, so it takes two states.
    fn roundTrip(pt: *PadTest) bool {
        if (!pt.held.real()) return false;
        const tol = SyntheticPad.tolerance;
        var ok = true;
        for (0..2) |pass| {
            var st: pad.State = .{ .connected = true };
            if (pass == 0) {
                st.left = .{ 0.25, -0.5 };
                st.right = .{ -0.75, 1 };
                st.lt = 0.5;
                st.rt = 1;
            }
            for (std.enums.values(pad.Button)) |b| {
                const second = b == .dpad_down or b == .dpad_left or b == .b or b == .rb;
                // The triggers are analog here; their buttons are derived from the values further on.
                if (b != .lt and b != .rt) st.set(b, second == (pass == 1));
            }
            const got = pt.held.roundTrip(st);
            var analog_ok = @abs(got.lt - st.lt) <= tol and @abs(got.rt - st.rt) <= tol;
            for (0..2) |axis| analog_ok = analog_ok and @abs(got.left[axis] - st.left[axis]) <= tol and @abs(got.right[axis] - st.right[axis]) <= tol;
            if (!analog_ok) {
                std.debug.print("      sticks or triggers read back as {any} {any} {d} {d}\n", .{ got.left, got.right, got.lt, got.rt });
                ok = false;
            }
            for (std.enums.values(pad.Button)) |b| {
                if (got.buttons.contains(b) != st.buttons.contains(b)) {
                    std.debug.print("      {s} was written {} and read back {}\n", .{ @tagName(b), st.buttons.contains(b), got.buttons.contains(b) });
                    ok = false;
                }
            }
        }
        _ = pt.held.roundTrip(.{ .connected = true });
        return ok;
    }

    fn drive(pt: *PadTest, plat: *platform.Platform, app: *app_mod.App, dt: f32) void {
        const s = &app.sim;
        pt.t += dt;
        pt.advanced = false;
        if (s.arms[0].held and s.arms[1].held) pt.saw_both = true;
        if (s.arms[0].held and s.arms[1].held and s.arms[0].tool != s.arms[1].tool) pt.saw_mixed = true;
        pt.top_speed = @max(pt.top_speed, s.vrel.len());
        var k: u32 = 0;

        // ------------------------------------------------------------------ the device and the prompts
        if (pt.at(&k) and pt.t >= 0.4) {
            pt.check(app.screen == .title, "the game opens on the title screen");
            pt.check(app.prompts == .kbm, "an attached controller that nobody has touched leaves the prompts on the keyboard");
            if (pt.held.real()) {
                pt.check(pt.roundTrip(), SyntheticPad.round_trip_name);
            } else {
                std.debug.print("  [--] " ++ SyntheticPad.no_device_note ++ "\n", .{});
            }
            pt.lang0 = app.lang;
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.dpad_right)) {
            pt.check(app.lang == pt.lang0.next() and app.lang != pt.lang0, "d-pad right on the title screen switches to the next language");
            pt.check(std.mem.eql(u8, plat.menuTitle(.quit), strings.menu.quit.get(app.lang)), "the menu bar follows the language");
            pt.check(app.prompts == .xbox, "a button press moves the prompts to the controller (one of no known family gets Xbox names)");
            pt.next();
        }
        if (pt.at(&k) and pt.taps(.back, Lang.count - 1)) {
            pt.check(app.lang == pt.lang0, "View on the title screen switches language too, back to the first");
            pt.next();
        }
        if (pt.at(&k)) {
            plat.postMouseMove();
            if (pt.t >= 0.4) {
                pt.check(app.prompts == .xbox, "mouse-moved events arriving do not take the prompts from the controller");
                plat.postKey(.h, true);
                pt.next();
            }
        }
        if (pt.at(&k) and pt.t >= 0.1) {
            plat.postKey(.h, false);
            pt.check(app.prompts == .kbm, "a key press moves the prompts to the keyboard");
            pt.st.right = .{ pad.look_shape.inner * 0.8, 0 };
            pt.next();
        }
        if (pt.at(&k) and pt.t >= 0.3) {
            pt.check(app.prompts == .kbm, "a stick resting inside its dead zone does not take the prompts");
            pt.st.right = .{ 0.6, 0 };
            pt.next();
        }
        if (pt.at(&k) and pt.t >= 0.2) {
            pt.check(app.prompts == .xbox, "a stick pushed past its dead zone does");
            pt.rest();
            // The framework's own controller has no family; a PlayStation one is written at the seam.
            plat.pad_source = .injected;
            pt.st.family = .playstation;
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.x)) {
            pt.check(app.prompts == .playstation, "a press on a PlayStation controller moves the prompts to PlayStation names");
            pt.rest();
            plat.pad_source = pt.held.source();
            pt.next();
        }

        // ------------------------------------------------------------------ menus
        if (pt.at(&k) and pt.tap(.y)) {
            pt.check(app.screen == .map, "Y on the title screen opens the route map");
            pt.sel0 = app.map_sel;
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.dpad_down)) {
            pt.check(app.map_sel == (pt.sel0 + 1) % campaign.chapters.len, "d-pad down moves the map selection one chapter");
            pt.sel0 = app.map_sel;
            pt.steps = 0;
            pt.next();
        }
        if (pt.at(&k)) {
            // Held down on the stick for the repeat delay and two and a half intervals: one step at once,
            // one at the end of the delay, two more an interval apart.
            pt.st.left = .{ 0, -1 };
            if (app.map_sel != pt.sel0) {
                pt.sel0 = app.map_sel;
                pt.steps += 1;
            }
            if (pt.t >= pad.Repeat.delay + 2.5 * pad.Repeat.interval) {
                pt.st.left = .{ 0, 0 };
                pt.check(pt.steps >= 3 and pt.steps <= 5, "the left stick held down steps the selection and then repeats");
                pt.next();
            }
        }
        if (pt.at(&k) and pt.tap(.b)) {
            pt.check(app.screen == .title, "B backs out of the route map");
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.a)) {
            pt.check(app.screen == .briefing and app.briefing_page == 0, "A on the title screen opens the briefing");
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.b)) {
            pt.check(app.screen == .title, "B backs out of the briefing");
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.a)) {
            pt.pages = 0;
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.a)) {
            pt.pages += 1;
            if (app.screen == .briefing and pt.pages <= strings.briefing.pages.len) {
                pt.t = 0;
            } else {
                pt.check(app.screen == .play and pt.pages == strings.briefing.pages.len, "A pages through the briefing and launches chapter 1");
                pt.next();
            }
        }

        // ------------------------------------------------------------------ flying, chapter 1
        if (pt.at(&k) and pt.t >= 0.3) {
            InputTest.standAtStone(app);
            pt.stone_hp = s.findConst(.phlebolith).?.hp;
            pt.saw_both = false;
            pt.next();
        }
        if (pt.at(&k)) {
            // Both triggers pulled in the same frame, past the press point but not to the end of their travel.
            const pull: f32 = if (pt.t >= 0.3 and pt.t < 0.4) 0.7 else 0;
            pt.st.lt = pull;
            pt.st.rt = pull;
            if (pt.t >= 1.2) {
                pt.check(pt.saw_both, "LT and RT pulled in the same frame drive both arms");
                pt.check(s.stats.sync_strikes == 1, "the two punches landed as one Sync Strike");
                pt.check(s.findConst(.phlebolith).?.hp == pt.stone_hp - 10, "the Sync Strike did 10 damage to the phlebolith");
                pt.next();
            }
        }
        if (pt.at(&k) and pt.tap(.dpad_left)) {
            pt.check(s.arms[0].tool == .shoot, "d-pad left steps the left arm back a tool, Punch to Shoot");
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.lb)) {
            pt.check(s.arms[0].tool == .punch, "LB steps the left arm on a tool, Shoot to Punch");
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.dpad_left)) pt.next();
        if (pt.at(&k) and pt.tap(.rb)) {
            pt.check(s.arms[1].tool == .drill, "RB steps the right arm on a tool, Punch to Drill");
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.dpad_right)) {
            pt.check(s.arms[1].tool == .punch, "d-pad right steps the right arm back a tool, Drill to Punch");
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.rb)) {
            pt.saw_mixed = false;
            pt.next();
        }
        if (pt.at(&k)) {
            pt.st.lt = 1;
            pt.st.rt = 1;
            if (pt.t >= 1.0) {
                pt.check(s.arms[0].tool == .shoot and s.arms[1].tool == .drill and pt.saw_mixed, "different tools run on both arms at once");
                pt.check(s.arms[1].engaged, "the drill arm is cutting while the other arm fires");
                pt.check(s.arms[0].charge < 1, "the shoot arm fired");
                pt.rest();
                pt.pos0 = s.pos;
                pt.yaw0 = s.yaw;
                pt.saw_key_arm = false;
                plat.postKey(.q, true);
                pt.next();
            }
        }
        if (pt.at(&k)) {
            // Thrust and turn on the sticks, with a key held down on the keyboard through it.
            pt.st.left = .{ 0, -1 };
            pt.st.right = .{ -1, 0 };
            if (s.arms[0].held) pt.saw_key_arm = true;
            if (pt.t >= 1.0) {
                plat.postKey(.q, false);
                pt.check(s.pos.dist(pt.pos0) > 20, "the left stick pulled back thrusts the drone backward");
                pt.check(s.yaw - pt.yaw0 > 1.5, "the right stick pushed left turns the view left");
                pt.check(pt.saw_key_arm, "a key held on the keyboard works its arm while the sticks fly");
                pt.rest();
                pt.pitch0 = s.pitch;
                pt.next();
            }
        }
        if (pt.at(&k)) {
            pt.st.right = .{ 0, 1 };
            if (pt.t >= 0.4) {
                pt.check(s.pitch - pt.pitch0 > 0.4, "the right stick pushed up looks up");
                pt.rest();
                pt.next();
            }
        }
        if (pt.at(&k)) {
            pt.st.set(.a, true);
            pt.lift[0] = s.vrel.dot(s.upVec());
            if (pt.t >= 0.4) {
                pt.rest();
                pt.next();
            }
        }
        if (pt.at(&k)) {
            pt.st.set(.b, pt.t >= 0.1);
            pt.lift[1] = s.vrel.dot(s.upVec());
            if (pt.t >= 0.6) {
                pt.check(pt.lift[0] > 100, "A climbs");
                pt.check(pt.lift[1] < -100, "B descends");
                pt.check(app.screen == .play, "and neither confirmed nor backed out of anything while flying");
                pt.rest();
                pt.next();
            }
        }
        if (pt.at(&k)) {
            // Cruise, then a click of the stick while it is pushed: boost, for as long as it stays pushed.
            pt.st.left = .{ 0, 1 };
            if (pt.t < 0.1) pt.top_speed = 0;
            if (pt.t >= 0.7) {
                pt.check(pt.top_speed > game.cruise_speed * 0.7 and pt.top_speed <= game.cruise_speed * 1.01, "the left stick pushed forward thrusts at cruise speed");
                pt.top_speed = 0;
                pt.next();
            }
        }
        if (pt.at(&k)) {
            pt.st.left = .{ 0, 1 };
            pt.st.set(.ls, pt.t < 0.07);
            if (pt.t >= 0.7) {
                pt.check(pt.top_speed > game.cruise_speed * 1.5, "a click of the left stick boosts, and the boost lasts after the click while the stick is pushed");
                pt.rest();
                s.voice.clear();
                pt.next();
            }
        }
        // Let the drone coast to a stop before the one-shot actions.
        if (pt.at(&k) and pt.t >= 0.5) pt.next();
        if (pt.at(&k) and pt.tap(.x)) {
            pt.check(s.examine_cd > 0, "X identifies whatever is under the reticle");
            pt.count0 = s.stats.hints;
            s.voice.clear();
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.y)) {
            pt.check(s.stats.hints == pt.count0 + 1, "Y asks Marín for a hint");
            pt.check(s.voice.current != null, "and she is saying it");
            pt.serial0 = s.voice.serial;
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.back)) {
            pt.check(s.voice.current == null or s.voice.serial != pt.serial0, "View cuts her line short");
            pt.next();
        }

        // ------------------------------------------------------------------ the pause menu
        if (pt.at(&k) and pt.tap(.start)) {
            pt.check(app.screen == .pause and app.pause_sel == .resume_game, "Menu pauses, with Resume selected");
            pt.next();
        }
        if (pt.at(&k) and pt.taps(.dpad_down, 5)) {
            pt.check(app.pause_sel == .language, "d-pad down five times selects the language entry");
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.a)) {
            pt.check(app.lang == pt.lang0.next(), "A on the language entry switches to the next language");
            pt.check(std.mem.eql(u8, plat.menuTitle(.quit), strings.menu.quit.get(app.lang)), "the menu bar follows the language");
            pt.check(app.save.lang == app.lang and app.save_path_len == 0, "the choice is recorded for saving, and a scripted run has no save file to write");
            pt.next();
        }
        if (pt.at(&k) and pt.taps(.dpad_right, Lang.count - 1)) {
            pt.check(app.lang == pt.lang0, "d-pad right on the language entry switches it too, back to the first");
            pt.count0 = s.stats.retries;
            pt.next();
        }
        if (pt.at(&k) and pt.taps(.dpad_up, 4)) {
            pt.check(app.pause_sel == .retry, "d-pad up four times selects Relaunch from last checkpoint");
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.a)) {
            pt.check(app.screen == .play and s.stats.retries == pt.count0 + 1, "A chooses it: the drone is back at the checkpoint");
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.start)) pt.next();
        if (pt.at(&k) and pt.tap(.b)) {
            pt.check(app.screen == .play, "B backs out of the pause menu into the game");
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.start)) {
            pt.check(app.screen == .pause, "Menu pauses again");
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.start)) {
            pt.check(app.screen == .play, "Menu on the pause menu resumes");
            pt.next();
        }

        // ------------------------------------------------------------------ the controller goes away
        if (pt.at(&k)) {
            pt.st.rt = 1;
            if (pt.t >= 0.3) {
                pt.check(s.arms[1].held, "RT held works the right arm");
                plat.pad_source = .injected;
                pt.unplugged = true;
                pt.next();
            }
        }
        if (pt.at(&k)) {
            if (pt.t >= 0.2) {
                pt.check(app.screen == .pause, "the controller in use disconnects in flight: the game pauses itself");
                pt.check(app.prompts == .kbm, "and the prompts return to the keyboard");
                pt.rest();
                pt.unplugged = false;
                plat.pad_source = pt.held.source();
                pt.next();
            }
        }
        if (pt.at(&k) and pt.t >= 0.2) pt.next();
        if (pt.at(&k) and pt.tap(.start)) {
            pt.check(app.screen == .play, "the controller comes back, and Menu resumes");
            pt.next();
        }
        if (pt.at(&k) and pt.t >= 0.2) {
            pt.check(!s.arms[1].held, "the trigger that was held when it went is not held now: the arm is at rest");
            pt.next();
        }

        // ------------------------------------------------------------------ quitting, leaving, and chapter 2 from the map
        if (pt.at(&k) and pt.tap(.start)) pt.next();
        if (pt.at(&k) and pt.taps(.dpad_down, 4)) {
            pt.check(app.screen == .pause and app.pause_sel == .quit, "d-pad down four times selects Quit game");
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.a)) {
            // In play the application quits here; a scripted run leaves the request for its script to read.
            pt.check(app.want_quit, "A chooses it: the game asks to quit");
            app.want_quit = false;
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.dpad_up)) {
            pt.check(app.screen == .pause and app.pause_sel == .leave, "Leave to title is selected");
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.a)) {
            pt.check(app.screen == .title and app.title_sel == .begin, "A chooses it: back on the title screen, with Begin selected");
            pt.next();
        }
        if (pt.at(&k) and pt.taps(.dpad_down, 3)) {
            pt.check(app.title_sel == .quit, "d-pad down three times on the title screen selects Quit");
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.a)) {
            pt.check(app.want_quit and app.screen == .title, "A chooses it: the game asks to quit from the title screen too");
            app.want_quit = false;
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.y)) pt.next();
        if (pt.at(&k) and pt.tap(.dpad_down)) {
            // The selection is wherever the earlier walk left it; step until it is on chapter 2.
            if (app.map_sel != 1 and pt.steps < 40) {
                pt.steps += 1;
                pt.t = 0;
            } else {
                pt.check(app.screen == .map and app.map_sel == 1, "the route map selection is on chapter 2");
                pt.next();
            }
        }
        if (pt.at(&k) and pt.tap(.a)) {
            pt.check(app.screen == .play and app.chapter == 1, "A on the route map launches the selected chapter");
            // The tether, from where the drone arrives among the villi.
            s.has_tether = true;
            s.stage = .g_tether;
            s.voice.clear();
            pt.next();
        }
        if (pt.at(&k) and pt.t >= 0.5) {
            pt.check(InputTest.aim(s, true), "a villus is within tether range of the arrival point");
            pt.next();
        }
        if (pt.at(&k)) {
            // The reticle is held on the villus until the click lands, as a hand would hold it. The drone
            // drifts with the chyme between the frame that aimed and the frame that reads the click, and
            // at a low frame rate (a software renderer draws a few frames a second) it drifts far enough
            // for an aim taken once to miss.
            if (s.tether == null) _ = InputTest.aim(s, true);
            if (pt.tap(.rs)) {
                pt.check(s.tether != null and s.g.tether_uses == 1, "a click of the right stick fires the tether at the tissue under the reticle");
                pt.next();
            }
        }
        if (pt.at(&k) and (pt.t >= 4 or (s.tether != null and s.pos.dist(s.tether_hold) < 30))) {
            pt.check(s.tether != null and s.pos.dist(s.tether_hold) < 30, "the line reels the drone in and holds it with no thrust");
            pt.check(InputTest.aim(s, false), "open lumen is in view from the hold point");
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.dpad_up)) {
            pt.check(s.tether == null, "d-pad up, the tether's other button, releases it on nothing");
            pt.finished = true;
            pt.next();
        }

        if (pt.unplugged) plat.pad = .{} else pt.held.set(plat, pt.st);
    }
};

test {
    _ = @import("math.zig");
    _ = @import("mesh.zig");
    _ = @import("font.zig");
    _ = @import("vein.zig");
    _ = @import("guide.zig");
    _ = @import("game.zig");
    _ = @import("audio.zig");
    _ = @import("gut.zig");
    _ = @import("stomach.zig");
    _ = @import("ch3.zig");
    _ = @import("kidney.zig");
    _ = @import("ch4.zig");
    _ = @import("app.zig");
    _ = @import("bot.zig");
    _ = @import("utf8.zig");
    _ = @import("i18n.zig");
    _ = @import("l10n.zig");
    _ = @import("pad.zig");
    _ = @import("bindings.zig");
    _ = @import("input.zig");
    _ = @import("gpu.zig");
    _ = @import("image.zig");
    _ = @import("util.zig");
    _ = @import("cli.zig");
    _ = @import("render.zig");
    _ = @import("draw.zig");
    _ = @import("platform.zig");
}
