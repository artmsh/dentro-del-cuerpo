//! Turns application state into one frame: the vein, its cells and organisms, the two arms, and the HUD.

const std = @import("std");
const m = @import("math.zig");
const gpu = @import("gpu.zig");
const render = @import("render.zig");
const game = @import("game.zig");
const guide = @import("guide.zig");
const vein_mod = @import("vein.zig");
const app_mod = @import("app.zig");
const campaign = @import("campaign.zig");
const gut = @import("gut.zig");
const ch2 = @import("ch2.zig");
const i18n = @import("i18n.zig");
const strings = @import("strings.zig");
const bindings = @import("bindings.zig");
const utf8 = @import("utf8.zig");
const font = @import("font.zig");
const Text = i18n.Text;
const Lang = i18n.Lang;
const hud = strings.hud;
const card_text = strings.card;
const Vec3 = m.Vec3;
const v3 = m.v3;
const Mat4 = m.Mat4;
const Vein = vein_mod.Vein;
const Renderer = render.Renderer;
const Color = render.Color;
const App = app_mod.App;

// Left arm is always cyan, right arm always amber: on the arm itself, on the reticle, on the HUD, in the tracers.
const cyan: Color = .{ 0.35, 0.92, 1.0, 1 };
const amber: Color = .{ 1.0, 0.72, 0.25, 1 };
const white: Color = .{ 0.93, 0.95, 0.97, 1 };
const dim: Color = .{ 0.62, 0.68, 0.74, 1 };
const red: Color = .{ 1.0, 0.32, 0.3, 1 };
const green: Color = .{ 0.4, 1.0, 0.72, 1 };
const gold: Color = .{ 1.0, 0.82, 0.3, 1 };
const panel: Color = .{ 0.02, 0.03, 0.05, 0.62 };

fn alpha(c: Color, a: f32) Color {
    return .{ c[0], c[1], c[2], c[3] * a };
}

fn mixc(a: Color, b: Color, t: f32) Color {
    return .{ m.lerp(a[0], b[0], t), m.lerp(a[1], b[1], t), m.lerp(a[2], b[2], t), m.lerp(a[3], b[3], t) };
}

/// Language of the frame being drawn, and the device its prompts are written for; set once at the top of
/// `frame`.
var lang: Lang = .en;
var device: bindings.Device = .kbm;
var window_keys: bindings.WindowKeys = .{};

fn prompt() bindings.Prompt {
    return .{ .lang = lang, .device = device, .window = window_keys };
}

/// Text that names a control is written out afresh for the device each frame; it lives here until the
/// next frame begins.
var scratch: [48 * 1024]u8 = undefined;
var scratch_len: usize = 0;

/// `text` as this frame's player reads it. Everything the HUD shows goes through here or through `tf`.
fn tr(text: Text) []const u8 {
    const free = scratch[scratch_len..];
    const out = bindings.resolve(free, text, prompt());
    if (out.ptr == free.ptr) scratch_len += out.len;
    return out;
}

fn tf(buf: []u8, comptime text: Text, args: anytype) []const u8 {
    return bindings.format(buf, prompt(), text, args);
}

fn number(buf: []u8, v: anytype) []const u8 {
    return i18n.expand(buf, lang, "{0}", &.{i18n.int(v)});
}

fn distText(buf: []u8, d: f32) []const u8 {
    return if (d < 1000) tf(buf, hud.micrometres, .{i18n.fixed(d, 0)}) else tf(buf, hud.millimetres, .{i18n.fixed(d / 1000, 2)});
}

/// `size`, or the largest smaller size at which `s` is no wider than `max_w`. Text in a slot of fixed
/// width goes through this, so a longer translation shrinks a little instead of running out of its panel.
fn fitSize(r: *Renderer, face: font.Face, size: f32, max_w: f32, s: []const u8) f32 {
    const w = r.textWidth(face, size, s);
    return if (w > max_w) size * max_w / w else size;
}

/// How many bytes of `s` its first `n` characters take, for text that types itself out. The reveal is
/// counted in characters so that every script types at the same pace.
fn revealedLen(s: []const u8, n: f32) usize {
    return utf8.prefixLen(s, @intFromFloat(@max(0, n)));
}

/// A rectangle on the HUD canvas.
const Box = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    fn overlaps(a: Box, b: Box) bool {
        return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h;
    }
};

/// A run of text in one face and colour; `drawRuns` sets several side by side.
const Run = struct { face: font.Face = .regular, color: Color, text: []const u8 };

fn runsWidth(r: *Renderer, size: f32, runs: []const Run) f32 {
    var w: f32 = 0;
    for (runs) |run| w += r.textWidth(run.face, size, run.text);
    return w;
}

fn drawRuns(r: *Renderer, x: f32, y: f32, size: f32, runs: []const Run) void {
    var pen = x;
    for (runs) |run| pen += r.text(run.face, pen, y, size, run.color, run.text);
}

/// The language switch: its key, its label, and every language under its own name with the current one
/// lit. Returns the runs in `out`.
fn languageRuns(out: *[4 + 2 * Lang.count]Run, key_color: Color, a: f32, with_key: bool) []const Run {
    var n: usize = 0;
    if (with_key) {
        out[n] = .{ .face = .bold, .color = alpha(key_color, a), .text = tr(strings.language.key) };
        out[n + 1] = .{ .color = alpha(white, a * 0.85), .text = " — " };
        n += 2;
    }
    out[n] = .{ .color = alpha(white, a * 0.85), .text = tr(strings.language.label) };
    out[n + 1] = .{ .color = alpha(white, a * 0.85), .text = ":   " };
    n += 2;
    for (Lang.all, 0..) |l, i| {
        if (i > 0) {
            out[n] = .{ .color = alpha(dim, a * 0.7), .text = "  ·  " };
            n += 1;
        }
        out[n] = if (l == lang) .{ .face = .bold, .color = alpha(white, a), .text = l.endonym() } else .{ .color = alpha(dim, a * 0.8), .text = l.endonym() };
        n += 1;
    }
    return out[0..n];
}

pub const Out = struct { scene: gpu.Frame, arm: gpu.Frame, post: gpu.Post };

pub const View = struct {
    vp: Mat4,
    view: Mat4,
    eye: Vec3,
    fwd: Vec3,
};

var bore_mix: f32 = 1;

pub fn frame(app: *App, r: *Renderer, vm: *const vein_mod.Meshes, dt: f32) Out {
    const s = &app.sim;
    lang = app.lang;
    device = app.prompts;
    window_keys = app.window_keys;
    scratch_len = 0;
    const aspect = r.ui_w / r.ui_h;

    // Camera.
    const f = s.forward();
    const rt = s.right();
    const up = s.upVec();
    const sh = s.shake * 1.4;
    const eye = s.pos.add(rt.scale(@sin(app.time * 71) * sh)).add(up.scale(@cos(app.time * 53) * sh));
    const speed_kick = m.sat((s.vrel.len() - game.cruise_speed) / 400.0);
    const fov = if (app.icon_mode) 0.95 else 1.17 + 0.08 * speed_kick + 0.45 * s.warp;
    const proj = Mat4.perspective(fov, aspect, 1.0, 14000);
    const view = Mat4.view(eye, rt, up, f.neg());
    const vw: View = .{ .vp = proj.mul(view), .view = view, .eye = eye, .fwd = f };
    r.cam_right = rt;
    r.cam_up = up;
    r.cam_pos = eye;

    drawWorld(app, r, vm, &vw);
    const playing = app.screen == .play or app.screen == .pause;
    if (playing and s.mode != .complete) drawArms(app, r, &vw);

    switch (app.screen) {
        .play => {
            drawHud(app, r, &vw);
            drawModeOverlay(app, r);
        },
        .pause => drawPause(app, r),
        .title => if (app.icon_mode) drawIconMark(app, r) else drawTitle(app, r),
        .briefing => drawBriefing(app, r),
        .map => drawMap(app, r),
    }

    // Atmosphere: saline-clear inside the cannula, dark venous red in the stream, darker where it stagnates.
    bore_mix = m.approach(bore_mix, if (s.in_bore) 1 else 0, 3, dt);
    const stagnant: f32 = if (s.station == 2 and s.vein.septum.corked) 1 else 0;
    var fog = [4]f32{ m.lerp(0.075, 0.045, stagnant), m.lerp(0.007, 0.006, stagnant), m.lerp(0.014, 0.03, stagnant), m.lerp(0.00046, 0.0007, stagnant) };
    var amb = [3]f32{ 0.27, 0.058, 0.068 };
    const bore_fog = [4]f32{ 0.03, 0.035, 0.045, 0.0004 };
    const bore_amb = [3]f32{ 0.08, 0.09, 0.11 };
    for (0..4) |i| fog[i] = m.lerp(fog[i], bore_fog[i], bore_mix);
    for (0..3) |i| amb[i] = m.lerp(amb[i], bore_amb[i], bore_mix);
    var lamp_range: f32 = 950;
    if (s.chapter == 1) {
        // Chyme: ochre murk, darker while a contraction has the lumen closed overhead.
        const closed = s.gut.squeeze(s.pos.z);
        fog = .{ m.lerp(0.150, 0.060, closed), m.lerp(0.105, 0.036, closed), m.lerp(0.030, 0.014, closed), m.lerp(0.00078, 0.0011, closed) };
        amb = .{ m.lerp(0.30, 0.17, closed), m.lerp(0.23, 0.12, closed), m.lerp(0.12, 0.07, closed) };
        lamp_range = 800;
    }
    if (app.icon_mode) { // the icon wants the stream as a saturated field, not a dark tunnel
        fog = .{ 0.34, 0.022, 0.04, 0.0011 };
        amb = .{ 0.42, 0.09, 0.10 };
    }
    const pulse = if (s.chapter == 1) 0.5 * s.gut.squeeze(s.pos.z) else m.sat(Vein.pump(s.clock) / 1.5);
    const scene: gpu.Frame = .{
        .view_proj = vw.vp.m,
        .cam_pos = .{ eye.x, eye.y, eye.z, app.time },
        .cam_fwd = .{ f.x, f.y, f.z, 1.05 },
        .fog_color = fog,
        .ambient = .{ amb[0], amb[1], amb[2], pulse },
        .lamp_color = .{ 1.0, 0.93, 0.86, lamp_range },
        .misc = .{ 0, if (s.scan_r >= 0) s.scan_r else 0, 0, 0 },
    };
    var arm = scene;
    arm.view_proj = Mat4.perspective(1.2, aspect, 0.2, 80).m;
    arm.cam_pos = .{ 0, 0, 0, app.time };
    arm.misc = .{ 1, 0, 0, 0 };
    arm.ambient = .{ amb[0] * 0.8 + 0.07, amb[1] * 0.8 + 0.07, amb[2] * 0.8 + 0.085, 0 };

    var post: gpu.Post = .{};
    post.a = .{ 1.0, 0.6, s.hurt * 0.8, s.warp };
    const fade_in = m.sat(app.screen_t / 0.7);
    const fade: f32 = if (app.screen == .play and s.stats.time < 1.5) m.sat(s.stats.time / 1.2) else if (app.screen == .title) fade_in else 1;
    post.b = .{ app.time, fade, 0.004 + 0.02 * s.hurt + 0.012 * s.shake, 0.9 };
    const low = if (playing and s.stability < 25) (0.5 + 0.5 * @sin(app.time * 5)) * (1 - s.stability / 25) else 0;
    post.c = .{ 0, 0, s.heal, low };
    post.tint = switch (app.screen) {
        .play => if (s.mode == .dead or s.mode == .lost) .{ 0.5, 0.25, 0.25, 0.75 } else if (s.mode == .complete or s.mode == .upgrade_card) .{ 0.35, 0.4, 0.45, 0.7 } else .{ 1, 1, 1, 0 },
        .title => if (app.icon_mode) .{ 1, 1, 1, 0 } else .{ 0.75, 0.75, 0.8, 0.35 },
        else => .{ 0.3, 0.33, 0.38, 0.8 },
    };
    return .{ .scene = scene, .arm = arm, .post = post };
}

// ---------------------------------------------------------------------------- world

fn drawWorld(app: *App, r: *Renderer, vm: *const vein_mod.Meshes, vw: *const View) void {
    const s = &app.sim;
    const ms = &r.meshes;
    const vn = &s.vein;

    if (s.chapter == 1) {
        drawGut(app, r, vw);
    } else {
        r.draw(vm.tube, .solid, Mat4.identity, .{ .color = .{ 0.66, 0.19, 0.20, 1 }, .mat = .wall, .anim = vein_mod.wall_cells_around });
        r.draw(vm.needle, .solid, Mat4.identity, .{ .color = .{ 0.42, 0.45, 0.50, 1 }, .mat = .metal });
        r.draw(vm.septum, .solid, Mat4.identity, .{ .color = .{ 0.74, 0.55, 0.47, 1 }, .mat = .fibrin, .seed = 0.4 });
    }
    const jej = s.chapter == 1;

    // Blood cells the display has left in.
    inline for (.{ &app.near, &app.far }, .{ true, false }) |cells, is_near| {
        inline for (.{ app_mod.CellKind.red, app_mod.CellKind.platelet, app_mod.CellKind.white }) |kind| {
            for (cells) |*c| {
                if (!c.visible or c.kind != kind) continue;
                const d2 = c.pos.sub(vw.eye).len2();
                if (d2 < 15 * 15) continue;
                if (!is_near and d2 < 240 * 240) continue; // the near field already covers this shell
                const b0 = c.axis.perp();
                const axis = c.axis.scale(@cos(c.phase)).add(b0.scale(@sin(c.phase)));
                const model = Mat4.place(c.pos, axis, v3(c.scale, c.scale, c.scale));
                switch (kind) {
                    // in the gut the same field is chyme: fat droplets, food debris, mucus
                    .red => if (jej) r.draw(ms.sphere_lo, .solid, model, .{ .color = .{ 0.80, 0.66, 0.20, 1 }, .mat = .cell, .seed = c.tint }) else r.draw(if (is_near) ms.red_cell else ms.red_cell_lo, .solid, model, .{ .color = .{ 0.46 + 0.12 * c.tint, 0.05, 0.065, 1 }, .mat = .cell, .seed = c.tint }),
                    .platelet => r.draw(ms.platelet, .solid, model, .{ .color = if (jej) .{ 0.40, 0.30, 0.16, 1 } else .{ 0.70, 0.64, 0.46, 1 }, .mat = .cell, .seed = c.tint }),
                    .white => r.draw(if (jej) ms.blob[1] else ms.white_cell, .solid, model, .{ .color = if (jej) .{ 0.52, 0.56, 0.40, 1 } else .{ 0.62, 0.64, 0.74, 1 }, .mat = .cell, .seed = c.tint }),
                }
            }
        }
    }

    // Organisms, clot, markers.
    for (&s.ents, 0..) |*e, idx| {
        const seed = e.seed;
        switch (e.kind) {
            .none => {},
            .cocci => {
                const glow: f32 = if (e.state == 1 or e.state == 2) e.aux else 0;
                const model = Mat4.trs(e.pos, v3(@sin(seed * 9), @cos(seed * 5), 0.3), app.time * (1 + seed) + seed * 20, e.radius * (1.25 + 0.3 * glow));
                r.draw(ms.cluster[e.variant % 3], .solid, model, .{ .color = .{ 0.95, 0.70, 0.16, 1 }, .mat = .cell, .emissive = glow * 2.2, .seed = seed });
                if (glow > 0.05) r.particle(e.pos, 6 + 12 * glow, .{ 1.0, 0.75, 0.2, 0.55 * glow });
            },
            .nest => {
                const n = e.end;
                const wob = 1 + 0.04 * @sin(app.time * 2 + seed * 10);
                r.draw(ms.dome, .blend, Mat4.place(e.pos.sub(n.scale(8)), n, v3(e.radius, e.radius * 0.8 * wob, e.radius)), .{ .color = .{ 0.62, 0.52, 0.13, 1 }, .mat = .slime, .emissive = e.flash * 0.6, .seed = seed, .anim = e.aux });
                // the colony core, visible through the slime once the drill has opened it
                const pulse = 0.6 + 0.4 * @sin(app.time * 5 + seed * 7);
                r.draw(ms.cluster[2], .solid, Mat4.trs(e.pos.add(n.scale(6)), n, app.time * 0.5, 15), .{ .color = .{ 1.0, 0.45, 0.12, 1 }, .mat = .cell, .emissive = 0.1 + pulse * (0.15 + 0.45 * e.aux) + e.flash * 1.2, .seed = seed });
                if (e.aux > 0.3) r.particle(e.pos.add(n.scale(22)), 26 * e.aux, .{ 1.0, 0.6, 0.15, 0.35 * e.aux });
            },
            .anchor => {
                const d = e.end.sub(e.pos);
                const k = 0.5 + 0.5 * e.hp / e.max_hp;
                r.draw(ms.cylinder, .solid, Mat4.place(e.pos, d, v3(e.radius * k, d.len(), e.radius * k)), .{ .color = .{ 0.92, 0.86, 0.68, 1 }, .mat = .fibrin, .emissive = e.flash * 0.9 * (1 - k + 0.3), .seed = seed });
                // flared roots at both ends
                r.draw(ms.sphere_lo, .solid, Mat4.trs(e.pos, Vec3.up, 0, e.radius * 2.2), .{ .color = .{ 0.85, 0.75, 0.58, 1 }, .mat = .fibrin, .seed = seed });
                r.draw(ms.sphere_lo, .solid, Mat4.trs(e.end, Vec3.up, 0, e.radius * 2.6), .{ .color = .{ 0.85, 0.75, 0.58, 1 }, .mat = .fibrin, .seed = seed });
            },
            .embolus => {
                r.draw(ms.blob[1], .solid, Mat4.trs(e.pos, v3(0.3, 1, 0.2), app.time * 0.7 + seed * 9, e.radius), .{ .color = .{ 0.5, 0.08, 0.09, 1 }, .mat = .clot, .emissive = e.flash * 1.5, .seed = seed });
            },
            .neutrophil => {
                r.draw(ms.white_cell, .solid, Mat4.trs(e.pos, v3(@sin(seed * 30), 0.2, @cos(seed * 30)), app.time * 0.6 + seed * 12, e.radius), .{ .color = .{ 0.66, 0.68, 0.78, 1 }, .mat = .cell, .seed = seed });
            },
            .odd_cell => {
                const bobp = e.pos.add(v3(0, @sin(app.time * 0.8 + seed * 9) * 3, 0));
                switch (e.variant) {
                    0 => r.draw(ms.red_cell, .solid, Mat4.trs(bobp, v3(1, 0.4, 0.2), app.time * 0.4, e.radius), .{ .color = .{ 0.52, 0.30, 0.62, 1 }, .mat = .cell, .seed = 3.3 }),
                    1 => {
                        r.draw(ms.white_cell, .blend, Mat4.trs(bobp, v3(0.2, 1, 0.3), app.time * 0.3, e.radius), .{ .color = .{ 0.82, 0.80, 0.96, 0.55 }, .mat = .leaflet, .seed = seed });
                        // horseshoe nucleus
                        for (0..7) |k| {
                            const a = -1.9 + 3.8 * @as(f32, @floatFromInt(k)) / 6.0 + app.time * 0.3;
                            r.draw(ms.sphere_lo, .solid, Mat4.trs(bobp.add(v3(@cos(a) * 2.9, @sin(a) * 2.9, 0)), Vec3.up, 0, 1.6), .{ .color = .{ 0.36, 0.2, 0.55, 1 }, .mat = .cell });
                        }
                    },
                    else => {
                        r.draw(ms.red_cell, .solid, Mat4.trs(bobp, v3(0.3, 0.2, 1), app.time * 0.4, e.radius), .{ .color = .{ 0.62, 0.12, 0.2, 1 }, .mat = .cell, .seed = 1.1 });
                        r.draw(ms.sphere_lo, .solid, Mat4.trs(bobp, Vec3.up, 0, 1.9), .{ .color = .{ 0.25, 0.1, 0.4, 1 }, .mat = .cell });
                    },
                }
            },
            .thrombus => {
                const k = e.radius;
                r.draw(ms.blob[0], .solid, Mat4.trs(e.pos, Vec3.up, 0, k), .{ .color = .{ 0.40, 0.06, 0.075, 1 }, .mat = .clot, .emissive = e.flash * 0.5, .seed = 0.2 });
            },
            .phlebolith => {
                const dmg = 1 - e.hp / e.max_hp;
                const j = e.flash * 3;
                r.draw(ms.blob[2], .solid, Mat4.trs(e.pos.add(v3(@sin(app.time * 90) * j, @cos(app.time * 70) * j, 0)), v3(0.2, 1, 0.1), 0.7, e.radius * 0.93), .{ .color = .{ 0.60, 0.57, 0.48, 1 }, .mat = .calcified, .emissive = e.flash * 0.4, .anim = dmg });
            },
            .ring => {
                if (!s.ringVisible(e.variant)) continue;
                const tg = if (jej) v3(0, 0, -1) else Vein.tangent(e.pos.z);
                const pulse = 1 + 0.03 * @sin(app.time * 3);
                r.draw(ms.torus, .blend, Mat4.place(e.pos, tg, v3(e.radius * pulse, e.radius * pulse, e.radius * pulse)), .{ .color = .{ 0.3, 0.95, 1.0, 0.9 }, .mat = .hologram, .emissive = 1 });
                r.draw(ms.torus_thin, .blend, Mat4.place(e.pos.add(tg.scale(40)), tg, v3(e.radius * 0.7, e.radius * 0.7, e.radius * 0.7)), .{ .color = .{ 0.3, 0.95, 1.0, 0.7 }, .mat = .hologram });
                r.draw(ms.torus_thin, .blend, Mat4.place(e.pos.add(tg.scale(80)), tg, v3(e.radius * 0.45, e.radius * 0.45, e.radius * 0.45)), .{ .color = .{ 0.3, 0.95, 1.0, 0.5 }, .mat = .hologram });
            },
            .infected => {
                if (e.state == 0) continue; // looks like its neighbours until the scan resolves it
                const swell = 1 + 0.08 * @sin(app.time * 4 + seed * 20);
                r.draw(ms.blob[1], .solid, Mat4.trs(e.pos.sub(e.end.scale(3)), e.end, seed * 6, e.radius * swell), .{ .color = .{ 0.62, 0.10, 0.36, 1 }, .mat = .cell, .emissive = 0.08 + 0.08 * @sin(app.time * 4 + seed * 20) + e.flash * 0.45, .seed = seed });
            },
            .shed => {
                // blinks faster as it nears bursting
                const rate = 5 + (7.5 - e.timer) * 2.6;
                const blink = 0.5 + 0.5 * @sin(app.time * rate);
                r.draw(ms.blob[1], .solid, Mat4.trs(e.pos, v3(0.4, 1, 0.3), app.time * 1.3 + seed * 9, e.radius), .{ .color = .{ 0.60, 0.10, 0.36, 1 }, .mat = .cell, .emissive = 0.04 + blink * (0.12 + 0.035 * (7.5 - e.timer)) + e.flash * 0.4, .seed = seed });
                r.particle(e.pos, 14 + 8 * blink, .{ 1.0, 0.3, 0.75, 0.10 * blink });
            },
            .virion => {
                const glow: f32 = if (e.state == 1 or e.state == 2) e.aux else 0;
                const model = Mat4.trs(e.pos, v3(@sin(seed * 9), @cos(seed * 5), 0.3), app.time * (1.5 + seed) + seed * 20, e.radius * (1.25 + 0.35 * glow));
                if (e.known) {
                    r.draw(ms.cluster[e.variant % 3], .solid, model, .{ .color = .{ 0.78, 0.14, 0.52, 1 }, .mat = .cell, .emissive = 0.15 + glow * 2.2 + e.flash * 0.6, .seed = seed });
                    if (glow > 0.05) r.particle(e.pos, 6 + 12 * glow, .{ 1.0, 0.3, 0.8, 0.55 * glow });
                } else {
                    r.draw(ms.blob[0], .solid, model, .{ .color = .{ 0.56, 0.54, 0.46, 1 }, .mat = .cell, .seed = seed });
                }
            },
            .commensal => {
                const axis = v3(@sin(seed * 31 + app.time * 0.3), @cos(seed * 17), @sin(seed * 11 + app.time * 0.2));
                if (e.known) {
                    r.draw(ms.capsule, .solid, Mat4.place(e.pos.sub(axis.norm().scale(2.2)), axis, v3(1.15, 4.4, 1.15)), .{ .color = .{ 0.30, 0.78, 0.44, 1 }, .mat = .cell, .emissive = 0.12 + e.flash, .seed = seed });
                } else {
                    r.draw(ms.blob[0], .solid, Mat4.trs(e.pos, axis, seed * 9, e.radius * 1.2), .{ .color = .{ 0.56, 0.54, 0.46, 1 }, .mat = .cell, .seed = seed });
                }
            },
            .factory => {
                const n = e.end;
                const wob = 1 + 0.04 * @sin(app.time * 2 + seed * 10);
                r.draw(ms.dome, .blend, Mat4.place(e.pos.sub(n.scale(14)), n, v3(e.radius * 1.15, e.radius * 0.95 * wob, e.radius * 1.15)), .{ .color = .{ 0.66, 0.56, 0.50, 1 }, .mat = .slime, .emissive = e.flash * 0.6, .seed = seed, .anim = e.aux });
                const pulse = 0.6 + 0.4 * @sin(app.time * 5 + seed * 7);
                for (0..3) |k| {
                    const a = @as(f32, @floatFromInt(k)) * 2.1 + app.time * 0.2;
                    r.draw(ms.cluster[k], .solid, Mat4.trs(e.pos.add(v3(@cos(a) * 20, 4, @sin(a) * 20)), n, app.time * 0.4 + a, 17), .{ .color = .{ 0.58, 0.09, 0.36, 1 }, .mat = .cell, .emissive = 0.05 + pulse * (0.1 + 0.4 * e.aux) + e.flash * 0.9, .seed = seed });
                }
                if (e.aux > 0.3) r.particle(e.pos.add(n.scale(30)), 30 * e.aux, .{ 1.0, 0.35, 0.8, 0.35 * e.aux });
            },
        }
        _ = idx;
    }

    // Loose fibrin strands dressing the clot (not interactive).
    if (s.findConst(.thrombus)) |clot| {
        if (s.stage != .lyse_core and clot.pos.dist(vw.eye) < 5000) {
            var rng = m.Rng.init(4242);
            for (0..14) |_| {
                const d = rng.dir();
                const a = clot.pos.add(d.scale(game.Sim.clotSurface(d) - 10));
                const len = rng.range(120, 420);
                const bend = rng.dir().scale(0.35);
                const b = a.add(d.add(bend).norm().scale(len));
                const sway = v3(0, 0, @sin(app.time * 0.6 + len) * 8);
                r.draw(ms.cylinder, .solid, Mat4.place(a, b.add(sway).sub(a), v3(2.2, len, 2.2)), .{ .color = .{ 0.8, 0.7, 0.55, 1 }, .mat = .fibrin, .seed = len });
            }
        }
    }

    // The tether line.
    if (s.tether) |anchor| {
        r.streak(s.pos.sub(s.upVec().scale(2.5)), anchor, 0.9, .{ 0.75, 1.0, 0.8, 0.9 });
        r.particle(anchor, 7, .{ 0.7, 1.0, 0.8, 0.7 });
    }

    // Valve cusps: rebuilt each frame from the same function the collision uses.
    for (0..2) |vi| {
        if (jej) break;
        const v = &vn.valves[vi];
        if (@abs(vw.eye.z - (v.zb + v.len * 0.5)) > 9000) continue;
        for (0..2) |ci| {
            const sick = v.pinned[ci];
            const col: Color = if (sick) .{ 0.66, 0.42, 0.32, 0.95 } else .{ 0.80, 0.52, 0.50, 0.9 };
            if (r.dynamic(vein_mod.cusp_verts, .blend, .{ .color = col, .mat = .leaflet })) |out| vein_mod.buildCusp(vn, vi, ci, out);
        }
    }

    // Rounds in flight.
    for (&s.shots) |*sh| {
        if (!sh.alive) continue;
        const col: Color = if (sh.lance) .{ 0.85, 0.9, 1.0, 1.0 } else if (sh.arm == 0) cyan else amber;
        const tail = sh.pos.sub(sh.vel.norm().scale(if (sh.lance) 46 else 26));
        r.streak(tail, sh.pos, if (sh.lance) 3.2 else 1.3, alpha(col, 0.9));
        r.particle(sh.pos, if (sh.lance) 7 else 3.2, col);
    }

    for (&s.parts) |*p| {
        if (p.life <= 0) continue;
        const k = p.life / p.max_life;
        r.particle(p.pos, p.size * (0.4 + 0.6 * k), .{ p.color[0], p.color[1], p.color[2], k });
    }

    // Drill contact glare.
    for (0..2) |i| {
        const a = &s.arms[i];
        if (a.engaged) {
            if (a.latch) |lt| r.particle(lt.point, 5 + 2 * @sin(app.time * 60), if (i == 0) alpha(cyan, 0.6) else alpha(amber, 0.6));
        }
    }

    // Motes in the plasma give a sense of speed where there are no cells.
    var rng = m.Rng.init(17);
    const cell: f32 = 180;
    for (0..160) |_| {
        const base = v3(rng.range(0, cell * 4), rng.range(0, cell * 4), rng.range(0, cell * 6));
        const drift = s.clock * 0;
        _ = drift;
        var p = base;
        p.x = vw.eye.x + @mod(base.x - vw.eye.x, cell * 4) - cell * 2;
        p.y = vw.eye.y + @mod(base.y - vw.eye.y, cell * 4) - cell * 2;
        p.z = vw.eye.z + @mod(base.z - vw.eye.z, cell * 6) - cell * 3;
        r.particle(p, 0.9, if (jej) .{ 1.0, 0.9, 0.5, 0.16 } else .{ 1.0, 0.75, 0.7, 0.18 });
    }
}

/// Chapter 2 scenery: the crypt floor, the villi around the camera, and, where a contraction ring is passing,
/// the opposite wall's villi coming down between them. All of it is read from the same functions as the
/// collision in gut.zig.
fn drawGut(app: *App, r: *Renderer, vw: *const View) void {
    const s = &app.sim;
    const ms = &r.meshes;
    const g = &s.gut;
    const healthy: Color = .{ 0.74, 0.42, 0.36, 1 };
    const inflamed: Color = .{ 0.66, 0.25, 0.24, 1 };

    r.draw(ms.mucosa_strip, .solid, Mat4.translation(v3(0, 0, gut.z_min - 900)).mul(Mat4.scaling(v3(1, 1, gut.z_max - gut.z_min + 1800))), .{ .color = .{ 0.60, 0.33, 0.30, 1 }, .mat = .crypt_floor });

    const reach: f32 = 3000;
    const c = gut.cellOf(vw.eye.x, vw.eye.z);
    const nz: i32 = @intFromFloat(reach / gut.row);
    const nx: i32 = @intFromFloat(reach / gut.pitch);
    var dz: i32 = -nz;
    while (dz <= nz) : (dz += 1) {
        var dx: i32 = -nx;
        while (dx <= nx) : (dx += 1) {
            const v = gut.villusAt(c[0] + dx, c[1] + dz);
            if (v.z < gut.z_min - 600 or v.z > gut.z_max + 600 or @abs(v.x) > gut.half_w + 1000) continue;
            const mid = v3(v.x, v.base + v.h * 0.5, v.z);
            const rel = mid.sub(vw.eye);
            const d2 = rel.len2();
            if (d2 > reach * reach) continue;
            if (rel.dot(vw.fwd) < -(v.h * 0.6 + 120)) continue;
            // the canopy leans with the stream and sways a little on its own
            const hsh = @as(f32, @floatFromInt((v.ix *% 7 + v.iz *% 13) & 63)) / 63.0;
            const lean = m.sat(g.flowAt(v.top(), s.clock).z / 900) * 0.2;
            const axis = v3(@sin(s.clock * 0.7 + hsh * 6) * 0.025, 1, lean + @sin(s.clock * 0.9 + hsh * 9) * 0.02).norm();
            const base = v3(v.x, v.base - 30, v.z);
            const col = mixc(healthy, inflamed, gut.blunting(v.z));
            const shaft = v.h - v.r + 30;
            r.draw(ms.cylinder, .solid, Mat4.place(base, axis, v3(v.r, shaft, v.r)), .{ .color = col, .mat = .mucosa, .seed = hsh, .anim = v.r });
            r.draw(if (d2 < 900 * 900) ms.sphere else ms.sphere_lo, .solid, Mat4.place(base.add(axis.scale(shaft)), axis, v3(v.r, v.r, v.r)), .{ .color = col, .mat = .mucosa, .seed = hsh, .anim = v.r });
        }
    }

    // The far wall, where the ring has brought it down.
    if (g.ring_z) |rz| {
        if (@abs(rz - vw.eye.z) < reach + gut.ring_half) {
            const span = gut.ring_half + 200;
            var z = rz - span;
            while (z < rz + span) : (z += 500) {
                const y = g.ceilY(z + 250) + 780;
                if (y > gut.roof + 600) continue;
                r.draw(ms.mucosa_strip, .solid, Mat4.translation(v3(0, y, z)).mul(Mat4.scaling(v3(1, 1, 500))), .{ .color = .{ 0.50, 0.26, 0.24, 1 }, .mat = .crypt_floor });
            }
            const cr = gut.cellOf(vw.eye.x, rz);
            const rn: i32 = @intFromFloat(span / gut.row);
            dz = -rn;
            while (dz <= rn) : (dz += 1) {
                var dx: i32 = -nx;
                while (dx <= nx) : (dx += 1) {
                    // the opposing villi sit half a pitch off, so the two sets mesh
                    const v = gut.villusAt(cr[0] + dx + 900, cr[1] + dz + 700);
                    const x = v.x - 900 * gut.pitch + gut.pitch * 0.5;
                    const zz = v.z - 700 * gut.row + gut.row * 0.33;
                    const tip_y = g.ceilY(zz);
                    if (tip_y > gut.roof - 300) continue;
                    const p = v3(x, gut.floorY(x) + tip_y + 780, zz);
                    if (p.sub(vw.eye).len2() > reach * reach) continue;
                    const down = v3(0, -1, 0);
                    r.draw(ms.cylinder, .solid, Mat4.place(p, down, v3(v.r, 780 - v.r, v.r)), .{ .color = healthy, .mat = .mucosa, .seed = 0.5, .anim = v.r });
                    r.draw(ms.sphere_lo, .solid, Mat4.place(p.add(down.scale(780 - v.r)), down, v3(v.r, v.r, v.r)), .{ .color = healthy, .mat = .mucosa, .seed = 0.5, .anim = v.r });
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------- first-person arms

fn drawArms(app: *App, r: *Renderer, vw: *const View) void {
    const s = &app.sim;
    const ms = &r.meshes;
    const steel: Color = .{ 0.36, 0.39, 0.44, 1 };
    const dark: Color = .{ 0.10, 0.11, 0.13, 1 };
    for (0..2) |i| {
        const a = &s.arms[i];
        const side: f32 = if (i == 0) -1 else 1;
        const accent: Color = if (i == 0) cyan else amber;
        const bob = v3(@sin(app.bob) * 0.05, @cos(app.bob * 2) * 0.04, 0);
        const sway = v3(app.sway[0] * 0.55, -app.sway[1] * 0.45, 0);
        const shoulder = v3(side * 3.7, -3.4, 0.6);
        var wrist = v3(side * 2.3, -1.8, -6.0).add(bob).add(sway);

        var target = v3(0, 0, -m.clamp(if (s.focus.topic != null) s.focus.dist else 90, 16, 220));
        if (a.tool == .drill) {
            if (a.latch) |lt| {
                const lp = vw.view.point(lt.point);
                // keep the arm in front of the camera even when the pilot looks away from the cut
                target = v3(m.clamp(lp.x, -30, 30), m.clamp(lp.y, -20, 20), @min(lp.z, -10));
            }
        }
        const dir = target.sub(wrist).norm();
        const reach: f32 = switch (a.tool) {
            .punch => 5.6 * a.ext,
            .drill => 2.7 * a.ext,
            .shoot => 0,
        };
        wrist = wrist.add(dir.scale(reach - a.recoil * 0.9));
        wrist.y -= @sin(m.pi * a.swap) * 3.2;
        if (a.engaged) wrist = wrist.add(v3(@sin(app.time * 97) * 0.05, @cos(app.time * 83) * 0.05, 0));

        const elbow = shoulder.lerp(wrist, 0.5).add(v3(side * 1.3, -1.25, 0.9));
        const flash = a.flash;

        // upper arm, forearm, joints
        r.draw(ms.cylinder, .arm, Mat4.place(shoulder, elbow.sub(shoulder), v3(0.52, elbow.dist(shoulder), 0.52)), .{ .color = steel, .mat = .metal });
        r.draw(ms.cylinder, .arm, Mat4.place(elbow, wrist.sub(elbow), v3(0.42, wrist.dist(elbow), 0.42)), .{ .color = steel, .mat = .metal });
        r.draw(ms.sphere, .arm, Mat4.trs(elbow, Vec3.up, 0, 0.66), .{ .color = dark, .mat = .metal });
        r.draw(ms.sphere, .arm, Mat4.trs(wrist, Vec3.up, 0, 0.58), .{ .color = dark, .mat = .metal });
        // identity band: this arm's colour
        const fore = wrist.sub(elbow).norm();
        r.draw(ms.cylinder, .arm, Mat4.place(elbow.lerp(wrist, 0.62), fore, v3(0.455, 0.42, 0.455)), .{ .color = accent, .mat = .unlit, .emissive = 0.55 + 3 * flash });
        r.draw(ms.cylinder, .arm, Mat4.place(elbow.lerp(wrist, 0.80), fore, v3(0.455, 0.12, 0.455)), .{ .color = accent, .mat = .unlit, .emissive = 0.55 + 3 * flash });

        switch (a.tool) {
            .punch => {
                r.draw(ms.cylinder, .arm, Mat4.place(wrist, dir, v3(0.5, 1.3, 0.5)), .{ .color = steel, .mat = .metal });
                // striker: a knurled ram with a domed face
                r.draw(ms.cylinder, .arm, Mat4.place(wrist.add(dir.scale(1.2)), dir, v3(0.80, 1.05, 0.80)), .{ .color = dark, .mat = .metal });
                r.draw(ms.cylinder, .arm, Mat4.place(wrist.add(dir.scale(1.45)), dir, v3(0.84, 0.16, 0.84)), .{ .color = accent, .mat = .unlit, .emissive = 0.6 + 4 * flash });
                r.draw(ms.cylinder, .arm, Mat4.place(wrist.add(dir.scale(2.25)), dir, v3(0.90, 0.22, 0.90)), .{ .color = steel, .mat = .metal });
                r.draw(ms.sphere, .arm, Mat4.place(wrist.add(dir.scale(2.45)), dir, v3(0.86, 0.42, 0.86)), .{ .color = mixc(steel, accent, 0.15 + 0.85 * flash), .mat = .metal, .emissive = flash * 1.2 });
            },
            .drill => {
                r.draw(ms.cylinder, .arm, Mat4.place(wrist, dir, v3(0.66, 0.9, 0.66)), .{ .color = dark, .mat = .metal });
                const bit = Mat4.place(wrist.add(dir.scale(0.9)), dir, v3(0.56, 3.0, 0.56)).mul(Mat4.rotation(Vec3.up, a.spin));
                const hot = a.heat;
                r.draw(ms.drill_bit, .arm, bit, .{ .color = .{ 0.75 + 0.25 * hot, 0.78 - 0.3 * hot, 0.82 - 0.6 * hot, 1 }, .mat = .metal, .emissive = hot * hot * 1.4 + (if (a.overheated) @as(f32, 1.0) else 0) });
            },
            .shoot => {
                r.draw(ms.cylinder, .arm, Mat4.place(wrist, dir, v3(0.38, 2.7, 0.38)), .{ .color = steel, .mat = .metal });
                // charge cell slung under the barrel
                r.draw(ms.capsule, .arm, Mat4.place(wrist.add(dir.scale(0.5)).add(v3(0, -0.52, 0)), dir, v3(0.24, 1.5, 0.24)), .{ .color = dark, .mat = .metal });
                r.draw(ms.cylinder, .arm, Mat4.place(wrist.add(dir.scale(0.75)).add(v3(0, -0.52, 0)), dir, v3(0.25, 0.25 + 0.75 * a.charge, 0.25)), .{ .color = accent, .mat = .unlit, .emissive = 0.35 + 0.9 * a.charge });
                r.draw(ms.cylinder, .arm, Mat4.place(wrist.add(dir.scale(2.45)), dir, v3(0.46, 0.3, 0.46)), .{ .color = dark, .mat = .metal });
                r.draw(ms.cylinder, .arm, Mat4.place(wrist.add(dir.scale(2.52)), dir, v3(0.47, 0.1, 0.47)), .{ .color = accent, .mat = .unlit, .emissive = 0.5 + 1.6 * a.charge + 5 * a.recoil });
            },
        }
    }
}

// ---------------------------------------------------------------------------- HUD

fn project(r: *Renderer, vw: *const View, p: Vec3) ?[2]f32 {
    const mm = vw.vp.m;
    const w = mm[3] * p.x + mm[7] * p.y + mm[11] * p.z + mm[15];
    if (w <= 0.5) return null;
    const x = (mm[0] * p.x + mm[4] * p.y + mm[8] * p.z + mm[12]) / w;
    const y = (mm[1] * p.x + mm[5] * p.y + mm[9] * p.z + mm[13]) / w;
    return .{ (x * 0.5 + 0.5) * r.ui_w, (1 - (y * 0.5 + 0.5)) * r.ui_h };
}

fn diamond(r: *Renderer, x: f32, y: f32, size: f32, t: f32, col: Color) void {
    r.line(x, y - size, x + size, y, t, col);
    r.line(x + size, y, x, y + size, t, col);
    r.line(x, y + size, x - size, y, t, col);
    r.line(x - size, y, x, y - size, t, col);
}

fn bar(r: *Renderer, x: f32, y: f32, w: f32, h: f32, frac: f32, col: Color) void {
    r.rect(x, y, w, h, .{ 1, 1, 1, 0.10 });
    r.rect(x, y, w * m.sat(frac), h, col);
}

fn ecg(ph: f32) f32 {
    const g = struct {
        fn f(x: f32, c: f32, w: f32) f32 {
            const d = (x - c) / w;
            return @exp(-d * d);
        }
    }.f;
    return 0.12 * g(ph, 0.18, 0.025) - 0.15 * g(ph, 0.275, 0.008) + 1.0 * g(ph, 0.30, 0.010) - 0.25 * g(ph, 0.325, 0.010) + 0.28 * g(ph, 0.52, 0.04);
}

fn drawHud(app: *App, r: *Renderer, vw: *const View) void {
    const s = &app.sim;
    if (s.mode == .complete) return;
    const W = r.ui_w;
    const cx = W * 0.5;
    const cy: f32 = 450;
    var buf: [200]u8 = undefined;
    var buf2: [64]u8 = undefined;

    // --- reticle: left half is the left arm, right half is the right arm
    const in_transit = s.mode == .transit;
    var reticle_block: ?Box = null;
    if (!in_transit) {
        // The arcs and the tool initials either side of them; a marker's label keeps out of this.
        reticle_block = .{ .x = cx - 68, .y = cy - 40, .w = 136, .h = 75 };
        r.rect(cx - 1.5, cy - 1.5, 3, 3, alpha(white, 0.9));
        for (0..2) |i| {
            const a = &s.arms[i];
            const col: Color = if (i == 0) cyan else amber;
            const centre: f32 = if (i == 0) m.pi else 0;
            const half: f32 = 1.05;
            const frac: f32 = switch (a.tool) {
                .shoot => a.charge,
                .drill => 1 - a.heat,
                .punch => 1 - m.sat(a.cooldown / 0.5),
            };
            const rad: f32 = 27 + 6 * a.flash;
            r.arc(cx, cy, rad, centre - half, centre + half, 1.5, alpha(col, 0.22));
            const warn = (a.tool == .drill and a.overheated);
            r.arc(cx, cy, rad, centre + half - 2 * half * frac, centre + half, 3 + 3 * a.flash, if (warn) red else alpha(col, 0.75 + 0.25 * a.flash));
            if (a.engaged) r.arc(cx, cy, rad + 7, centre - 0.5, centre + 0.5, 2, alpha(col, 0.5 + 0.5 * @sin(app.time * 30)));
            // tool initial beside the arc
            const tx = cx + (if (i == 0) @as(f32, -62) else 50);
            _ = r.text(.bold, tx, cy - 9, 15, alpha(col, 0.85), utf8.first(tr(a.tool.name())));
        }
        if (s.sync_flash > 0) {
            r.textCentered(.bold, cx, cy - 92, 34, alpha(white, s.sync_flash), tr(hud.sync));
            r.arc(cx, cy, 40 + 60 * (1 - s.sync_flash), 0, m.tau, 3, alpha(white, s.sync_flash));
        }
        if (s.tissue_flash > 0) r.textCentered(.bold, cx, cy + 86, 20, alpha(red, s.tissue_flash), tr(hud.tissue_damage));

        // --- what the reticle is on
        if (s.focus.topic) |tp| {
            const known = s.atlas[@intFromEnum(tp)];
            const e = guide.entry(tp);
            const d = distText(&buf2, s.focus.dist);
            const name = if (known) tr(e.name) else tr(hud.unidentified);
            const detail = if (!known) d else if (s.atlas_deep[@intFromEnum(tp)]) tf(&buf, hud.focus, .{ i18n.str(d), i18n.str(tr(e.size)) }) else tf(&buf, hud.focus_more, .{ i18n.str(d), i18n.str(tr(e.size)) });
            // the plate grows with its text: names and sizes are longer in some languages
            const pw = @max(240, @max(r.textWidth(.bold, 17, name), r.textWidth(.regular, 14, detail)) + 28);
            r.rect(cx - pw * 0.5, cy + 35, pw, 46, .{ 0.02, 0.03, 0.05, 0.42 });
            // With the plate under it, the block is the reticle and the plate together.
            reticle_block = .{ .x = cx - pw * 0.5, .y = cy - 40, .w = pw, .h = 121 };
            if (known) {
                const col = if (e.hostile) gold else white;
                r.textCentered(.bold, cx, cy + 40, 17, alpha(col, 0.95), name);
            } else {
                const blink = 0.6 + 0.4 * @sin(app.time * 6);
                r.textCentered(.bold, cx, cy + 40, 17, alpha(cyan, blink), name);
            }
            r.textCentered(.regular, cx, cy + 60, 14, alpha(dim, 0.9), detail);
        }
    }

    // --- waypoint and loose emboli
    if (!in_transit) {
        if (s.waypoint) |wp| marker(r, vw, wp, s.pos, cyan, "", app.time, reticle_block);
        for (&s.ents) |*e| {
            if (e.kind == .embolus) marker(r, vw, e.pos, s.pos, red, tr(hud.embolus), app.time, reticle_block);
        }
    }

    // --- patient, top left
    {
        const x: f32 = 28;
        const y: f32 = 24;
        // The panel runs down to the atlas count, which is the last line of it.
        r.rect(x - 10, y - 8, 300, 150, panel);
        const hr = 68 + (100 - s.stability) * 0.75;
        _ = r.text(.bold, x, y, 13, dim, tr(hud.patient));
        const scol: Color = if (s.stability < 25) red else if (s.stability < 50) gold else green;
        _ = r.text(.bold, x, y + 16, 26, scol, i18n.expand(&buf, lang, "{0}", &.{i18n.fixed(s.stability, 0)}));
        _ = r.text(.regular, x + 46, y + 26, 13, dim, tr(hud.stability));
        r.textRight(.bold, x + 280, y + 16, 26, white, i18n.expand(&buf, lang, "{0}", &.{i18n.fixed(hr, 0)}));
        r.textRight(.regular, x + 232, y + 26, 13, dim, tr(hud.heart_rate));
        bar(r, x, y + 50, 280, 5, s.stability / 100, scol);
        // ECG strip
        const n: usize = 90;
        var px: f32 = 0;
        var py: f32 = 0;
        for (0..n + 1) |i| {
            const u = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
            const t = app.time - (1 - u) * 2.6;
            const ph = @mod(t * hr / 60.0, 1.0);
            const xx = x + u * 280;
            const yy = y + 86 - ecg(ph) * 22;
            if (i > 0) r.line(px, py, xx, yy, 1.6, alpha(scol, 0.35 + 0.65 * u));
            px = xx;
            py = yy;
        }
        // the hull bar starts where its label ends (17 units after "HULL", as the panel was drawn)
        const hull_x = x + @round(r.text(.bold, x, y + 100, 13, dim, tr(hud.hull))) + 17;
        bar(r, hull_x, y + 105, x + 280 - hull_x, 5, s.hull / 100, if (s.hull < 35) red else white);
        const atlas_w = r.text(.regular, x, y + 122, 13, alpha(dim, 0.9), tf(&buf, hud.atlas, .{ i18n.int(s.atlasCount()), i18n.int(s.atlasTotal()) }));
        if (s.has_sync) _ = r.text(.bold, x + @max(110, atlas_w + 24), y + 122, 13, alpha(white, 0.9), tr(hud.sync_servo));
    }

    // --- location and flow, top right
    {
        const x = W - 28;
        const y: f32 = 24;
        r.rect(x - 310, y - 8, 320, 128, panel);
        const flow = s.worldFlow(s.pos).len();
        r.textRight(.bold, x, y, 13, dim, if (s.chapter == 1) tr(hud.site_jejunum) else tr(hud.site_vein));
        r.textRight(.bold, x, y + 16, 22, white, tf(&buf, hud.centimetres, .{i18n.fixed(s.locationCm(), 1)}));
        r.textRight(.regular, x - 96, y + 23, 13, dim, if (s.chapter == 1) tr(hud.past_duodenal_flexure) else tr(hud.to_femoral_junction));
        r.textRight(.bold, x, y + 46, 22, if (s.chapter == 1 and flow > 330) gold else white, i18n.expand(&buf, lang, "{0}", &.{i18n.fixed(flow, 0)}));
        r.textRight(.regular, x - 60, y + 53, 13, dim, if (s.chapter == 1) tr(hud.stream_unit) else tr(hud.flow_unit));
        bar(r, x - 300, y + 76, 300, 4, flow / (if (s.chapter == 1) @as(f32, 900.0) else 480.0), alpha(white, 0.8));
        // pump cycle
        const ttr = Vein.timeToReflux(s.clock);
        var status_col = green;
        var status: []const u8 = undefined;
        if (s.chapter == 1) {
            if (ch2.underRing(s)) {
                status_col = red;
                status = tr(hud.contraction_overhead);
            } else if (ch2.ringEta(s)) |eta| {
                if (eta > 0) status_col = gold;
                status = if (eta > 0) tf(&buf, hud.contraction_in, .{i18n.fixed(eta, 1)}) else tr(hud.ring_passed);
            } else if (s.tether != null) {
                status = tr(hud.tethered);
            } else {
                status = tr(hud.lumen_open);
            }
        } else if (s.station == 2 and s.vein.septum.corked) {
            status_col = gold;
            status = tr(hud.no_flow);
        } else if (ttr <= 0) {
            status_col = red;
            status = tr(hud.reflux);
        } else if (ttr < 1.6) {
            status_col = gold;
            status = tf(&buf, hud.valves_closing, .{i18n.fixed(ttr, 1)});
        } else {
            status = tf(&buf, hud.valves_open, .{i18n.fixed(ttr, 1)});
        }
        r.textRight(.bold, x, y + 90, fitSize(r, .bold, 15, 300, status), status_col, status);
    }

    // --- objective, top centre
    {
        var obuf: [240]u8 = undefined;
        const text = s.objective(prompt(), &obuf);
        // between the two top panels, with a margin
        const size = fitSize(r, .bold, 18, W - 2 * 366 - 36, text);
        const tw = r.textWidth(.bold, size, text);
        r.rect(cx - tw * 0.5 - 18, 22, tw + 36, 34, panel);
        r.rect(cx - tw * 0.5 - 18, 22, 3, 34, cyan);
        r.textCentered(.bold, cx, 28 + (18 - size) * 0.6, size, white, text);
        if (s.checkpoint_toast > 0) r.textCentered(.bold, cx, 66, 15, alpha(green, m.sat(s.checkpoint_toast)), tr(hud.checkpoint_saved));
        if (s.hidden_unlocked) r.textCentered(.bold, cx, 86, 14, alpha(gold, 0.9), tr(hud.hidden_route));
    }

    // --- arm panels, bottom corners
    for (0..2) |i| {
        const a = &s.arms[i];
        const col: Color = if (i == 0) cyan else amber;
        const pw: f32 = 250;
        const x: f32 = if (i == 0) 28 else W - 28 - pw;
        const y: f32 = 778;
        r.rect(x, y, pw, 96, panel);
        r.rect(if (i == 0) x else x + pw - 4, y, 4, 96, col);
        const tx = x + 16;
        const inner = pw - 32;
        const head = if (i == 0) tr(hud.left_arm) else tr(hud.right_arm);
        _ = r.text(.bold, tx, y + 8, fitSize(r, .bold, 13, inner, head), alpha(col, 0.9), head);
        const name_w = r.text(.bold, tx, y + 26, 30, mixc(white, col, a.flash), tr(a.tool.name()));
        const label: []const u8 = switch (a.tool) {
            .shoot => tr(hud.charge),
            .drill => if (a.overheated) tr(hud.overheated) else if (a.engaged) tr(hud.cutting) else tr(hud.heat),
            .punch => tr(hud.ready),
        };
        const frac: f32 = switch (a.tool) {
            .shoot => a.charge,
            .drill => a.heat,
            .punch => 1 - m.sat(a.cooldown / 0.5),
        };
        const bcol: Color = if (a.tool == .drill) mixc(col, red, a.heat) else col;
        _ = r.text(.regular, tx + @max(126, name_w + 16), y + 38, 13, if (a.overheated and a.tool == .drill) red else dim, label);
        bar(r, tx, y + 64, inner, 5, frac, bcol);
        const keys = if (i == 0) tr(hud.left_keys) else tr(hud.right_keys);
        _ = r.text(.regular, tx, y + 74, fitSize(r, .regular, 13, inner, keys), alpha(dim, 0.85), keys);
    }

    // --- Marín
    drawSubtitles(app, r);

    if (s.stage == .g_arrive) {
        // arrival card: where the transit took the drone
        const a = m.sat(s.stage_t / 0.8) * m.sat((6.5 - s.stage_t) / 1.0);
        r.rect(cx - 430, 232, 860, 150, alpha(panel, a));
        r.textCentered(.bold, cx, 246, 15, alpha(dim, a), tr(hud.arrival_chapter));
        r.textCentered(.bold, cx, 270, 40, alpha(white, a), tr(hud.arrival_place));
        r.textCentered(.regular, cx, 326, 16, alpha(dim, a), tr(hud.arrival_route[0]));
        r.textCentered(.regular, cx, 348, 16, alpha(dim, a), tr(hud.arrival_route[1]));
    }
    if (in_transit) {
        r.textCentered(.bold, cx, 300, 30, alpha(white, 0.9), tr(hud.transit));
        r.textCentered(.regular, cx, 340, 18, alpha(dim, 0.9), tf(&buf, hud.transit_distance, .{i18n.fixed(s.locationCm(), 1)}));
    }

    const controls = if (s.has_tether) tr(hud.controls_tether) else tr(hud.controls);
    // the strip sits between the two arm panels and widens for a longer line
    const strip = @max(600, r.textWidth(.regular, 13, controls) + 40);
    r.rect(cx - strip * 0.5, 874, strip, 22, .{ 0.02, 0.03, 0.05, 0.45 });
    r.textCentered(.regular, cx, 878, 13, alpha(dim, 0.85), controls);
}

/// Where a marker's distance label goes: under the diamond, unless that would put it across `avoid` (the
/// reticle and the focus plate, which carry text of their own). Then it goes above the diamond, above
/// the name if the marker has one, and if that is covered too, just under the block. Returns the y of
/// the label's top.
fn markerLabelY(x: f32, y: f32, w: f32, named: bool, avoid: ?Box) f32 {
    const below = y + 16;
    const block = avoid orelse return below;
    const h: f32 = 15;
    if (!block.overlaps(.{ .x = x - w * 0.5, .y = below, .w = w, .h = h })) return below;
    const above = y - (if (named) @as(f32, 46) else 30);
    if (!block.overlaps(.{ .x = x - w * 0.5, .y = above, .w = w, .h = h })) return above;
    return block.y + block.h + 3;
}

fn marker(r: *Renderer, vw: *const View, p: Vec3, from: Vec3, col: Color, label: []const u8, time: f32, avoid: ?Box) void {
    var buf: [48]u8 = undefined;
    const W = r.ui_w;
    const dist = p.dist(from);
    const pulse = 0.7 + 0.3 * @sin(time * 4);
    if (project(r, vw, p)) |xy| {
        if (xy[0] > 40 and xy[0] < W - 40 and xy[1] > 70 and xy[1] < 760) {
            diamond(r, xy[0], xy[1], 11, 2, alpha(col, pulse));
            const d = distText(&buf, dist);
            r.textCentered(.bold, xy[0], markerLabelY(xy[0], xy[1], r.textWidth(.bold, 13, d), label.len > 0, avoid), 13, alpha(col, 0.9), d);
            if (label.len > 0) r.textCentered(.bold, xy[0], xy[1] - 30, 12, alpha(col, 0.9), label);
            return;
        }
    }
    // off screen: an arrow on the edge of a circle around the reticle
    const d = vw.view.dir(p.sub(vw.eye));
    const ang = std.math.atan2(-d.y, d.x);
    const cx = W * 0.5;
    const cy: f32 = 450;
    const rad: f32 = 200;
    const ax = cx + @cos(ang) * rad;
    const ay = cy + @sin(ang) * rad;
    const tip_x = ax + @cos(ang) * 16;
    const tip_y = ay + @sin(ang) * 16;
    r.line(ax - @sin(ang) * 9, ay + @cos(ang) * 9, tip_x, tip_y, 2.5, alpha(col, pulse));
    r.line(ax + @sin(ang) * 9, ay - @cos(ang) * 9, tip_x, tip_y, 2.5, alpha(col, pulse));
    r.textCentered(.bold, ax - @cos(ang) * 22, ay - @sin(ang) * 22 - 7, 12, alpha(col, 0.9), if (label.len > 0) label else distText(&buf, dist));
}

fn drawSubtitles(app: *App, r: *Renderer) void {
    const s = &app.sim;
    const text_full = tr(s.voice.current orelse return);
    const W = r.ui_w;
    const cx = W * 0.5;
    const size: f32 = if (s.voice.urgent) 25 else 20;
    const max_w: f32 = 760;
    const h = r.paragraphHeight(.regular, max_w, size, text_full);
    const y = 748 - h;
    const fade = m.sat(s.voice.remaining / 0.3) * m.sat(s.voice.age / 0.1);
    r.rect(cx - max_w * 0.5 - 20, y - 30, max_w + 40, h + 42, alpha(panel, fade));
    r.rect(cx - max_w * 0.5 - 20, y - 30, 3, h + 42, alpha(if (s.voice.urgent) gold else green, fade));
    _ = r.text(.bold, cx - max_w * 0.5, y - 22, 13, alpha(if (s.voice.urgent) gold else green, fade), tr(hud.marin));
    // Typewriter reveal. The whole line is laid out once and revealed within that layout, so a word is on
    // its final line from its first letter.
    _ = r.paragraphRevealed(.regular, cx - max_w * 0.5, y, max_w, size, alpha(if (s.voice.urgent) gold else white, fade), text_full, revealedLen(text_full, s.voice.age * 75 + 1));
}

fn card(r: *Renderer, w: f32, h: f32, accent: Color) [2]f32 {
    const x = (r.ui_w - w) * 0.5;
    const y = (r.ui_h - h) * 0.5;
    r.rect(x, y, w, h, .{ 0.015, 0.02, 0.035, 0.9 });
    r.frame(x, y, w, h, 1.5, alpha(accent, 0.6));
    r.rect(x, y, w, 4, accent);
    return .{ x, y };
}

/// An upgrade card: kicker, name, a figure drawn by the caller in the gap, the explanation, and the key.
/// The card grows with the explanation, which runs to more lines in some languages. Returns the y of the
/// figure's centre line.
fn upgradeCard(app: *App, r: *Renderer, kicker: Text, name: Text, body: Text) f32 {
    const cx = r.ui_w * 0.5;
    const body_h = r.paragraphHeight(.regular, 600, 20, tr(body));
    const h = 380 + @max(0, body_h - 106);
    const o = card(r, 720, h, white);
    r.textCentered(.bold, cx, o[1] + 30, 15, dim, tr(kicker));
    r.textCentered(.bold, cx, o[1] + 58, 54, white, tr(name));
    _ = r.paragraph(.regular, o[0] + 60, o[1] + 220, 600, 20, white, tr(body));
    r.textCentered(.bold, cx, o[1] + h - 44, 18, alpha(green, 0.7 + 0.3 * @sin(app.time * 4)), tr(card_text.install));
    return o[1] + 168;
}

const DebriefRow = struct { label: Text, value: []const u8 };

/// The debrief card shared by both chapters: heading, grade, the rows, and the notes under them.
fn debrief(app: *App, r: *Renderer, kicker: Text, heading: Text, rows: []const DebriefRow, notes: []const ?Text) void {
    const s = &app.sim;
    const cx = r.ui_w * 0.5;
    const o = card(r, 820, 560, green);
    r.textCentered(.bold, cx, o[1] + 26, 15, dim, tr(kicker));
    r.textCentered(.bold, cx, o[1] + 50, 50, white, tr(heading));
    // The grade, with its caption: on an Xbox controller the prompt at the foot of the card is "A" too,
    // and a bare letter does not say which of the two it is.
    const g = s.grade();
    const caption = tr(card_text.grade);
    const gap: f32 = 18;
    const gw = r.textWidth(.bold, 84, &[1]u8{g});
    const cw = r.textWidth(.bold, 15, caption);
    const gx = cx - (cw + gap + gw) * 0.5;
    _ = r.text(.bold, gx, o[1] + 172, 15, dim, caption);
    _ = r.text(.bold, gx + cw + gap, o[1] + 122, 84, if (g == 'A') green else if (g == 'D') red else gold, &[1]u8{g});
    const lx = o[0] + 90;
    const rx = o[0] + 730;
    var y = o[1] + 236;
    for (rows) |row| {
        _ = r.text(.regular, lx, y, 19, dim, tr(row.label));
        r.textRight(.bold, rx, y, 19, white, row.value);
        y += 27;
    }
    y += 10;
    for (notes, 0..) |maybe, i| {
        const note = maybe orelse continue;
        if (i == 0) r.textCentered(.regular, cx, y, fitSize(r, .regular, 17, 760, tr(note)), alpha(gold, 0.95), tr(note)) else r.textCentered(.bold, cx, y, 16, gold, tr(note));
        y += 26;
    }
    r.textCentered(.bold, cx, o[1] + 514, 18, alpha(green, 0.7 + 0.3 * @sin(app.time * 4)), tr(card_text.to_route_map));
}

fn drawModeOverlay(app: *App, r: *Renderer) void {
    const s = &app.sim;
    const cx = r.ui_w * 0.5;
    var buf: [240]u8 = undefined;
    switch (s.mode) {
        .upgrade_card => {
            if (s.chapter == 1) {
                const fy = upgradeCard(app, r, card_text.tether_kicker, card_text.tether_name, card_text.tether_body);
                // a line reeling a dot toward an anchor
                const k = @mod(app.time * 0.6, 1.0);
                r.line(cx - 150, fy, cx + 150, fy, 2, alpha(green, 0.5));
                r.arc(cx + 150, fy, 7, 0, m.tau, 14, green);
                r.arc(cx - 150 + 290 * k, fy, 9, 0, m.tau, 4, white);
                return;
            }
            const fy = upgradeCard(app, r, card_text.sync_kicker, card_text.sync_name, card_text.sync_body);
            // the two arcs closing into one ring
            const k = 0.5 + 0.5 * @sin(app.time * 2.5);
            r.arc(cx - 14 * k, fy, 30, m.pi - 1.3, m.pi + 1.3, 4, cyan);
            r.arc(cx + 14 * k, fy, 30, -1.3, 1.3, 4, amber);
        },
        .dead => {
            const o = card(r, 620, 240, red);
            r.textCentered(.bold, cx, o[1] + 36, 50, red, tr(card_text.signal_lost));
            r.textCentered(.regular, cx, o[1] + 112, fitSize(r, .regular, 20, 580, tr(card_text.hull_failed)), white, tr(card_text.hull_failed));
            r.textCentered(.bold, cx, o[1] + 176, 18, alpha(white, 0.7 + 0.3 * @sin(app.time * 4)), tr(card_text.relaunch));
        },
        .lost => {
            const o = card(r, 660, 240, red);
            const why = if (s.chapter == 1) tr(card_text.lost_gut) else tr(card_text.lost_vein);
            r.textCentered(.bold, cx, o[1] + 36, 50, red, tr(card_text.patient_lost));
            r.textCentered(.regular, cx, o[1] + 112, fitSize(r, .regular, 20, 620, why), white, why);
            r.textCentered(.bold, cx, o[1] + 176, 18, alpha(white, 0.7 + 0.3 * @sin(app.time * 4)), tr(card_text.restart));
        },
        .complete => {
            const stability = tf(buf[0..24], card_text.out_of_100, .{i18n.fixed(s.stability, 0)});
            const atlas = tf(buf[24..48], card_text.out_of, .{ i18n.int(s.atlasCount()), i18n.int(s.atlasTotal()) });
            const relaunches = number(buf[48..64], s.stats.retries);
            const time = tf(buf[64..112], card_text.duration, .{ i18n.int(@as(u32, @intFromFloat(@floor(s.stats.time / 60)))), i18n.padded(@as(u32, @intFromFloat(@floor(@mod(s.stats.time, 60)))), 2) });
            if (s.chapter == 1) {
                const note: Text = if (s.g.spread == 0 and s.g.commensals_lost == 0) card_text.note_gut_clean else if (s.g.commensals_lost > 3) card_text.note_gut_flora else card_text.note_gut_spread;
                debrief(app, r, card_text.gut_kicker, card_text.gut_title, &.{
                    .{ .label = card_text.row_stability, .value = stability },
                    .{ .label = card_text.row_cleared, .value = tf(buf[112..144], card_text.out_of, .{ i18n.int(s.g.cleared), i18n.int(s.g.total) }) },
                    .{ .label = card_text.row_spread, .value = number(buf[144..160], s.g.spread) },
                    .{ .label = card_text.row_commensals, .value = number(buf[160..176], s.g.commensals_lost) },
                    .{ .label = card_text.row_lining, .value = number(buf[176..192], s.stats.tissue_hits) },
                    .{ .label = card_text.row_atlas, .value = atlas },
                    .{ .label = card_text.row_relaunches, .value = relaunches },
                    .{ .label = card_text.row_time, .value = time },
                }, &.{note});
                return;
            }
            const note: Text = if (s.stats.emboli_escaped == 0) card_text.note_no_emboli else card_text.note_emboli;
            debrief(app, r, card_text.vein_kicker, card_text.vein_title, &.{
                .{ .label = card_text.row_stability, .value = stability },
                .{ .label = card_text.row_emboli, .value = number(buf[112..128], s.stats.emboli_escaped) },
                .{ .label = card_text.row_tissue, .value = number(buf[128..144], s.stats.tissue_hits) },
                .{ .label = card_text.row_friendly_fire, .value = number(buf[144..160], s.stats.friendly_fire) },
                .{ .label = card_text.row_sync, .value = number(buf[160..176], s.stats.sync_strikes) },
                .{ .label = card_text.row_atlas, .value = atlas },
                .{ .label = card_text.row_relaunches, .value = relaunches },
                .{ .label = card_text.row_time, .value = time },
            }, &.{ note, if (s.hidden_unlocked) card_text.note_hidden_route else null });
        },
        else => {},
    }
}

fn drawPause(app: *App, r: *Renderer) void {
    const P = strings.pause;
    const cx = r.ui_w * 0.5;
    // The card is as tall as its rows: the options, then the controls, with the rows that depend on the
    // device and on what the drone carries.
    const tether_row = app.sim.has_tether;
    const fullscreen_row = device == .kbm and app.window_keys.fullscreen.len > 0;
    const rows: f32 = @floatFromInt(P.controls.len + @intFromBool(tether_row) + @intFromBool(fullscreen_row));
    const o = card(r, 760, 104 + 30 * @as(f32, app_mod.PauseItem.count) + 48 + 23 * rows + 36, cyan);
    r.textCentered(.bold, cx, o[1] + 28, 46, white, tr(P.heading));
    var y = o[1] + 104;
    // The options. The one under the selection is lit; an option with a key of its own shows it.
    var option: usize = 0;
    for (0..app_mod.PauseItem.count) |i| {
        const item: app_mod.PauseItem = @enumFromInt(i);
        const selected = app.pause_sel == item;
        if (selected) {
            r.rect(o[0] + 60, y - 4, 640, 30, alpha(cyan, 0.16));
            r.rect(o[0] + 60, y - 4, 3, 30, cyan);
        }
        const key = switch (item) {
            .resume_game => tr(P.resume_keys),
            .retry => bindings.label(.retry, prompt()),
            .restart => bindings.label(.restart, prompt()),
            .leave => bindings.label(.leave, prompt()),
            .quit => bindings.label(.quit, prompt()),
            .language => tr(strings.language.key),
        };
        r.textRight(.bold, cx - 20, y, 20, cyan, key);
        if (item == .language) {
            var runs: [4 + 2 * Lang.count]Run = undefined;
            drawRuns(r, cx + 10, y, 20, languageRuns(&runs, cyan, 1, false));
        } else {
            _ = r.text(if (selected) .bold else .regular, cx + 10, y, 20, white, tr(P.options[option]));
            option += 1;
        }
        y += 30;
    }
    y += 4;
    r.textCentered(.regular, cx, y, 14, alpha(dim, 0.9), tr(P.choose));
    y += 30;
    r.rect(o[0] + 60, y, 640, 1, alpha(dim, 0.4));
    y += 14;
    const row = struct {
        fn draw(rr: *Renderer, x: f32, yy: f32, pair: [2]Text) void {
            const what = tr(pair[1]);
            rr.textRight(.bold, x - 20, yy, 16, dim, tr(pair[0]));
            _ = rr.text(.regular, x + 10, yy, fitSize(rr, .regular, 16, 350, what), white, what);
        }
    }.draw;
    for (P.controls) |cc| {
        row(r, cx, y, cc);
        y += 23;
    }
    if (tether_row) {
        row(r, cx, y, P.tether);
        y += 23;
    }
    if (fullscreen_row) {
        // The shortcut belongs to the window, so the platform names it and not the catalogue.
        const what = tr(P.fullscreen);
        r.textRight(.bold, cx - 20, y, 16, dim, app.window_keys.fullscreen);
        _ = r.text(.regular, cx + 10, y, fitSize(r, .regular, 16, 350, what), white, what);
    }
}

/// The app icon: the split reticle (left arm cyan, right arm amber) over the blood stream.
fn drawIconMark(app: *App, r: *Renderer) void {
    _ = app;
    const cx = r.ui_w * 0.5;
    const cy = r.ui_h * 0.5;
    r.arc(cx, cy, 236, 0, m.tau, 34, .{ 0.01, 0.015, 0.03, 0.55 });
    r.arc(cx, cy, 236, m.pi * 0.5 + 0.22, m.pi * 1.5 - 0.22, 26, cyan);
    r.arc(cx, cy, 236, -m.pi * 0.5 + 0.22, m.pi * 0.5 - 0.22, 26, amber);
    r.arc(cx, cy, 17, 0, m.tau, 34, white);
}

fn drawTitle(app: *App, r: *Renderer) void {
    const cx = r.ui_w * 0.5;
    const a = m.sat((app.screen_t - 0.3) / 1.2);
    r.textCentered(.bold, cx, 250, 120, alpha(white, a), app_mod.title);
    r.textCentered(.regular, cx, 392, 28, alpha(dim, a), tr(strings.title.tagline));
    r.rect(cx - 160, 446, 320, 1, alpha(cyan, 0.6 * a));
    // The entries. The one under the selection is lit and shows the button that chooses it; the others
    // show the key of their own, where they have one.
    const blink = 0.65 + 0.35 * @sin(app.time * 3);
    var y: f32 = 498;
    for (0..app_mod.TitleItem.count) |i| {
        const item: app_mod.TitleItem = @enumFromInt(i);
        const selected = app.title_sel == item;
        if (selected) {
            r.rect(cx - 270, y - 5, 540, 36, alpha(panel, a));
            r.rect(cx - 270, y - 5, 3, 36, alpha(cyan, a));
        }
        const own = switch (item) {
            .begin => "",
            .map => bindings.label(.map, prompt()),
            .language => tr(strings.language.key),
            .quit => bindings.label(.quit, prompt()),
        };
        const key = if (selected and own.len == 0) bindings.label(.confirm, prompt()) else own;
        r.textRight(.bold, cx - 46, y, 22, alpha(cyan, a * (if (selected) @as(f32, 1) else 0.8)), key);
        const col = if (selected) alpha(green, a * blink) else alpha(white, a * 0.85);
        switch (item) {
            .language => {
                var runs: [4 + 2 * Lang.count]Run = undefined;
                drawRuns(r, cx - 16, y, 22, languageRuns(&runs, cyan, a, false));
            },
            .begin => _ = r.text(if (selected) .bold else .regular, cx - 16, y, 22, col, tr(strings.title.begin)),
            .map => _ = r.text(if (selected) .bold else .regular, cx - 16, y, 22, col, tr(strings.title.route_map)),
            .quit => _ = r.text(if (selected) .bold else .regular, cx - 16, y, 22, col, tr(strings.title.quit)),
        }
        y += 38;
    }
    r.textCentered(.regular, cx, y + 4, 14, alpha(dim, a * 0.9), tr(strings.title.choose));
    if (app.save.ch1_done) {
        var buf: [200]u8 = undefined;
        r.textCentered(.regular, cx, y + 48, 16, alpha(gold, a * 0.9), if (app.save.ch2_done) tf(&buf, strings.title.progress_two, .{ i18n.char(app.save.grade), i18n.char(app.save.grade2) }) else tf(&buf, strings.title.progress_one, .{i18n.char(app.save.grade)}));
    }
    r.textCentered(.regular, cx, 850, 14, alpha(dim, a * 0.8), tr(strings.title.backdrop));
}

fn drawBriefing(app: *App, r: *Renderer) void {
    const cx = r.ui_w * 0.5;
    const pages = &strings.briefing.pages;
    const o = card(r, 860, 440, cyan);
    var buf: [64]u8 = undefined;
    r.textCentered(.bold, cx, o[1] + 26, 15, dim, tf(&buf, strings.briefing.heading, .{ i18n.int(app.briefing_page + 1), i18n.int(pages.len) }));
    const page = tr(pages[@min(app.briefing_page, pages.len - 1)]);
    _ = r.paragraphRevealed(.regular, o[0] + 70, o[1] + 76, 720, 23, white, page, revealedLen(page, app.screen_t * 140 + 1));
    r.textCentered(.bold, cx, o[1] + 392, 18, alpha(green, 0.7 + 0.3 * @sin(app.time * 4)), if (app.briefing_page + 1 == pages.len) tr(strings.briefing.launch) else tr(strings.briefing.next));
}

// ---------------------------------------------------------------------------- route map

const body_half = [_][2]f32{
    .{ 0.03, 0.13 },  .{ 0.19, 0.17 },  .{ 0.25, 0.33 },  .{ 0.27, 0.42 },  .{ 0.30, 0.55 }, .{ 0.29, 0.60 },
    .{ 0.25, 0.55 },  .{ 0.21, 0.42 },  .{ 0.17, 0.24 },  .{ 0.14, 0.42 },  .{ 0.17, 0.52 }, .{ 0.165, 0.66 },
    .{ 0.13, 0.76 },  .{ 0.11, 0.95 },  .{ 0.14, 0.985 }, .{ 0.06, 0.985 }, .{ 0.06, 0.95 }, .{ 0.05, 0.76 },
    .{ 0.01, 0.56 },
};

fn drawMap(app: *App, r: *Renderer) void {
    const W = r.ui_w;
    var buf: [128]u8 = undefined;
    const mt = strings.map;
    const head_w = r.text(.bold, 60, 36, 40, white, tr(mt.heading));
    _ = r.text(.regular, 60 + @max(130, head_w + 30), 54, 16, dim, tr(mt.subtitle));

    // Body diagram (patient's right is on the left, as on a chart).
    const bx: f32 = 70;
    const by: f32 = 110;
    const bw: f32 = 420;
    const bh: f32 = 740;
    const line_col = alpha(dim, 0.55);
    for ([_]f32{ -1, 1 }) |sgn| {
        for (0..body_half.len - 1) |i| {
            const a = body_half[i];
            const b = body_half[i + 1];
            r.line(bx + (0.5 + sgn * a[0]) * bw, by + a[1] * bh, bx + (0.5 + sgn * b[0]) * bw, by + b[1] * bh, 1.5, line_col);
        }
    }
    r.arc(bx + 0.5 * bw, by + 0.075 * bh, 0.058 * bh, 0, m.tau, 1.5, line_col);

    const chs = &campaign.chapters;
    // route line through the main chapters
    for (0..campaign.main_count - 1) |i| {
        const a = chs[i];
        const b = chs[i + 1];
        const done = app.chapterDone(i);
        r.line(bx + a.x * bw, by + a.y * bh, bx + b.x * bw, by + b.y * bh, if (done) 2.5 else 1.5, if (done) alpha(green, 0.9) else alpha(cyan, 0.45));
    }
    for (chs, 0..) |c, i| {
        const x = bx + c.x * bw;
        const y = by + c.y * bh;
        const sel = i == app.map_sel;
        const known = !c.hidden or (i == campaign.main_count and app.save.marrow);
        const done = app.chapterDone(i);
        const col: Color = if (done) green else if (c.hidden) gold else if (c.playable) white else alpha(cyan, 0.8);
        const rad: f32 = if (sel) 9 else 6;
        if (c.hidden) diamond(r, x, y, rad, 2, col) else r.arc(x, y, rad, 0, m.tau, if (sel) 3 else 2, col);
        if (sel) r.arc(x, y, 15 + 3 * @sin(app.time * 4), 0, m.tau, 1.5, alpha(col, 0.6));
        const label: []const u8 = if (c.hidden) (if (known) "✓" else "?") else number(&buf, i + 1);
        // clear of the node, and of the selection ring around it at its widest
        _ = r.text(.bold, x + (if (sel) @as(f32, 24) else 12), y - 9, 13, alpha(col, 0.95), label);
    }

    // Chapter list.
    const lx: f32 = 560;
    var y: f32 = 112;
    for (chs, 0..) |c, i| {
        const sel = i == app.map_sel;
        const done = app.chapterDone(i);
        const known = !c.hidden or (i == campaign.main_count and app.save.marrow);
        if (i == campaign.main_count) y += 10;
        if (sel) r.rect(lx - 12, y - 3, 330, 27, alpha(cyan, 0.16));
        const num: []const u8 = if (c.hidden) "◆" else number(&buf, i + 1);
        _ = r.text(.bold, lx, y, 17, if (c.hidden) gold else dim, num);
        _ = r.text(if (sel) .bold else .regular, lx + 34, y, 18, if (sel) white else alpha(white, 0.8), if (known) tr(c.name) else tr(mt.unknown_row));
        const status = tr(if (done) mt.complete else if (app.chapterUnlocked(i)) mt.playable else if (c.playable) mt.locked else if (c.hidden and !known) mt.hidden else if (c.hidden) mt.route_logged else mt.mapped);
        r.textRight(.regular, lx + 310, y + 2, 14, if (done) green else if (c.playable) white else alpha(dim, 0.8), status);
        y += 28;
    }

    // Detail of the selected chapter.
    const c = chs[app.map_sel];
    const known = !c.hidden or (app.map_sel == campaign.main_count and app.save.marrow);
    const dx: f32 = 930;
    const dw: f32 = W - dx - 60;
    r.rect(dx - 24, 104, dw + 48, 720, panel);
    r.rect(dx - 24, 104, 3, 720, if (c.hidden) gold else cyan);
    var dy: f32 = 122;
    _ = r.text(.bold, dx, dy, 34, white, if (known) tr(c.name) else tr(mt.unknown_name));
    dy += 46;
    const site = if (known) tr(c.site) else tr(mt.unknown_site);
    _ = r.text(.regular, dx, dy, fitSize(r, .regular, 17, dw, site), dim, site);
    dy += 40;
    const fields = [_][2]Text{
        .{ mt.field_route, c.route },
        .{ mt.field_read, c.read },
        .{ mt.field_objective, c.objective },
        .{ mt.field_challenge, c.challenge },
        .{ mt.field_upgrade, c.upgrade },
    };
    for (fields, 0..) |fl, i| {
        if (!known and i != 2) continue;
        _ = r.text(.bold, dx, dy, 13, if (c.hidden) gold else cyan, tr(fl[0]));
        dy = r.paragraph(.regular, dx, dy + 20, dw, 18, white, tr(fl[1])) + 16;
    }
    const open = app.chapterUnlocked(app.map_sel);
    const foot = tr(if (open) mt.fly else if (c.playable) mt.need_previous else if (c.hidden and !known) mt.not_found else mt.not_built);
    _ = r.text(.bold, dx, 786, fitSize(r, .bold, 17, dw, foot), if (open) alpha(green, 0.7 + 0.3 * @sin(app.time * 4)) else alpha(dim, 0.9), foot);
    // The keys, on a plate: the backdrop's cells drift behind this line and it has to stay readable.
    const keys = tr(mt.keys);
    const kw = r.textWidth(.regular, 14, keys) + 40;
    r.rect((W - kw) * 0.5, 861, kw, 26, panel);
    r.textCentered(.regular, W * 0.5, 866, 14, alpha(white, 0.85), keys);
}

test "a marker's distance label stays out of the reticle and the focus plate" {
    const plate: Box = .{ .x = 600, .y = 410, .w = 240, .h = 121 };
    const w: f32 = 60;
    const label = struct {
        fn box(x: f32, y: f32) Box {
            return .{ .x = x - 30, .y = y, .w = 60, .h = 15 };
        }
    }.box;
    // Nothing to avoid, or a marker well away from the block: the label sits under the diamond.
    try std.testing.expectEqual(@as(f32, 316), markerLabelY(720, 300, w, false, null));
    try std.testing.expectEqual(@as(f32, 216), markerLabelY(720, 200, w, false, plate));
    try std.testing.expectEqual(@as(f32, 466), markerLabelY(300, 450, w, false, plate));
    // Wherever the marker is on the screen, the label and the block do not meet.
    var y: f32 = 80;
    while (y < 760) : (y += 3) {
        var x: f32 = 50;
        while (x < 1390) : (x += 7) {
            for ([_]bool{ false, true }) |named| {
                try std.testing.expect(!plate.overlaps(label(x, markerLabelY(x, y, w, named, plate))));
            }
        }
    }
    // The case from the field: the waypoint dead ahead, behind the reticle. Under the plate.
    try std.testing.expectEqual(plate.y + plate.h + 3, markerLabelY(720, 450, w, false, plate));
}
