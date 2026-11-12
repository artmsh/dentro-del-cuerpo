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

fn fmt(buf: []u8, comptime f: []const u8, args: anytype) []const u8 {
    return std.fmt.bufPrint(buf, f, args) catch "";
}

fn distText(buf: []u8, d: f32) []const u8 {
    return if (d < 1000) fmt(buf, "{d:.0} µm", .{d}) else fmt(buf, "{d:.2} mm", .{d / 1000});
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
    if (!in_transit) {
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
            _ = r.text(.bold, tx, cy - 9, 15, alpha(col, 0.85), a.tool.name()[0..1]);
        }
        if (s.sync_flash > 0) {
            r.textCentered(.bold, cx, cy - 92, 34, alpha(white, s.sync_flash), "SYNC");
            r.arc(cx, cy, 40 + 60 * (1 - s.sync_flash), 0, m.tau, 3, alpha(white, s.sync_flash));
        }
        if (s.tissue_flash > 0) r.textCentered(.bold, cx, cy + 86, 20, alpha(red, s.tissue_flash), "TISSUE DAMAGE");

        // --- what the reticle is on
        if (s.focus.topic) |tp| {
            const known = s.atlas[@intFromEnum(tp)];
            const e = guide.entry(tp);
            const d = distText(&buf2, s.focus.dist);
            r.rect(cx - 120, cy + 35, 240, 46, .{ 0.02, 0.03, 0.05, 0.42 });
            if (known) {
                const col = if (e.hostile) gold else white;
                r.textCentered(.bold, cx, cy + 40, 17, alpha(col, 0.95), e.name);
                r.textCentered(.regular, cx, cy + 60, 14, alpha(dim, 0.9), fmt(&buf, "{s}  ·  {s}{s}", .{ d, e.size, if (!s.atlas_deep[@intFromEnum(tp)]) "  ·  T: more" else "" }));
            } else {
                const blink = 0.6 + 0.4 * @sin(app.time * 6);
                r.textCentered(.bold, cx, cy + 40, 17, alpha(cyan, blink), "UNIDENTIFIED  —  T");
                r.textCentered(.regular, cx, cy + 60, 14, alpha(dim, 0.9), d);
            }
        }
    }

    // --- waypoint and loose emboli
    if (!in_transit) {
        if (s.waypoint) |wp| marker(r, vw, wp, s.pos, cyan, "", app.time);
        for (&s.ents) |*e| {
            if (e.kind == .embolus) marker(r, vw, e.pos, s.pos, red, "EMBOLUS", app.time);
        }
    }

    // --- patient, top left
    {
        const x: f32 = 28;
        const y: f32 = 24;
        r.rect(x - 10, y - 8, 300, 128, panel);
        const hr = 68 + (100 - s.stability) * 0.75;
        _ = r.text(.bold, x, y, 13, dim, "PATIENT");
        const scol: Color = if (s.stability < 25) red else if (s.stability < 50) gold else green;
        _ = r.text(.bold, x, y + 16, 26, scol, fmt(&buf, "{d:.0}", .{s.stability}));
        _ = r.text(.regular, x + 46, y + 26, 13, dim, "STABILITY");
        r.textRight(.bold, x + 280, y + 16, 26, white, fmt(&buf, "{d:.0}", .{hr}));
        r.textRight(.regular, x + 232, y + 26, 13, dim, "HR");
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
        _ = r.text(.bold, x, y + 100, 13, dim, "HULL");
        bar(r, x + 44, y + 105, 236, 5, s.hull / 100, if (s.hull < 35) red else white);
        _ = r.text(.regular, x, y + 132, 13, alpha(dim, 0.9), fmt(&buf, "ATLAS {d}/{d}", .{ s.atlasCount(), s.atlasTotal() }));
        if (s.has_sync) _ = r.text(.bold, x + 110, y + 132, 13, alpha(white, 0.9), "SYNC SERVO");
    }

    // --- location and flow, top right
    {
        const x = W - 28;
        const y: f32 = 24;
        r.rect(x - 310, y - 8, 320, 128, panel);
        const flow = s.worldFlow(s.pos).len();
        r.textRight(.bold, x, y, 13, dim, if (s.chapter == 1) "PROXIMAL JEJUNUM" else "R. GREAT SAPHENOUS VEIN");
        r.textRight(.bold, x, y + 16, 22, white, fmt(&buf, "{d:.1} cm", .{s.locationCm()}));
        r.textRight(.regular, x - 96, y + 23, 13, dim, if (s.chapter == 1) "PAST DUODENAL FLEXURE" else "TO FEMORAL JUNCTION");
        r.textRight(.bold, x, y + 46, 22, if (s.chapter == 1 and flow > 330) gold else white, fmt(&buf, "{d:.0}", .{flow}));
        r.textRight(.regular, x - 60, y + 53, 13, dim, if (s.chapter == 1) "STREAM  µm/s at 1:100" else "FLOW  µm/s at 1:100");
        bar(r, x - 300, y + 76, 300, 4, flow / (if (s.chapter == 1) @as(f32, 900.0) else 480.0), alpha(white, 0.8));
        // pump cycle
        const ttr = Vein.timeToReflux(s.clock);
        if (s.chapter == 1) {
            if (ch2.underRing(s)) {
                r.textRight(.bold, x, y + 90, 15, red, "CONTRACTION — STAY BETWEEN THE VILLI");
            } else if (ch2.ringEta(s)) |eta| {
                if (eta > 0) r.textRight(.bold, x, y + 90, 15, gold, fmt(&buf, "CONTRACTION RING IN {d:.1} s", .{eta})) else r.textRight(.bold, x, y + 90, 15, green, "RING PASSED");
            } else if (s.tether != null) {
                r.textRight(.bold, x, y + 90, 15, green, "TETHERED  ·  G releases");
            } else {
                r.textRight(.bold, x, y + 90, 15, green, "LUMEN OPEN");
            }
        } else if (s.station == 2 and s.vein.septum.corked) {
            r.textRight(.bold, x, y + 90, 15, gold, "NO FLOW — VEIN OBSTRUCTED");
        } else if (ttr <= 0) {
            r.textRight(.bold, x, y + 90, 15, red, "REFLUX — VALVES SHUT");
        } else if (ttr < 1.6) {
            r.textRight(.bold, x, y + 90, 15, gold, fmt(&buf, "VALVES CLOSING IN {d:.1} s", .{ttr}));
        } else {
            r.textRight(.bold, x, y + 90, 15, green, fmt(&buf, "VALVES OPEN  ·  {d:.1} s", .{ttr}));
        }
    }

    // --- objective, top centre
    {
        var obuf: [160]u8 = undefined;
        const text = s.objective(&obuf);
        const tw = r.textWidth(.bold, 18, text);
        r.rect(cx - tw * 0.5 - 18, 22, tw + 36, 34, panel);
        r.rect(cx - tw * 0.5 - 18, 22, 3, 34, cyan);
        r.textCentered(.bold, cx, 28, 18, white, text);
        if (s.checkpoint_toast > 0) r.textCentered(.bold, cx, 66, 15, alpha(green, m.sat(s.checkpoint_toast)), "CHECKPOINT SAVED");
        if (s.hidden_unlocked) r.textCentered(.bold, cx, 86, 14, alpha(gold, 0.9), "HIDDEN ROUTE LOGGED: BONE MARROW");
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
        _ = r.text(.bold, tx, y + 8, 13, alpha(col, 0.9), if (i == 0) "LEFT ARM  ·  Q  /  left click" else "RIGHT ARM  ·  E  /  right click");
        _ = r.text(.bold, tx, y + 26, 30, mixc(white, col, a.flash), a.tool.name());
        const label: []const u8 = switch (a.tool) {
            .shoot => "CHARGE",
            .drill => if (a.overheated) "OVERHEATED" else if (a.engaged) "CUTTING" else "HEAT",
            .punch => "READY",
        };
        const frac: f32 = switch (a.tool) {
            .shoot => a.charge,
            .drill => a.heat,
            .punch => 1 - m.sat(a.cooldown / 0.5),
        };
        const bcol: Color = if (a.tool == .drill) mixc(col, red, a.heat) else col;
        _ = r.text(.regular, tx + 126, y + 38, 13, if (a.overheated and a.tool == .drill) red else dim, label);
        bar(r, tx, y + 64, pw - 32, 5, frac, bcol);
        _ = r.text(.regular, tx, y + 74, 13, alpha(dim, 0.85), if (i == 0) "Z: change tool   1 2 3: punch / drill / shoot" else "X: change tool   8 9 0: punch / drill / shoot");
    }

    // --- Marín
    drawSubtitles(app, r);

    if (s.stage == .g_arrive) {
        // arrival card: where the transit took the drone
        const a = m.sat(s.stage_t / 0.8) * m.sat((6.5 - s.stage_t) / 1.0);
        r.rect(cx - 430, 232, 860, 150, alpha(panel, a));
        r.textCentered(.bold, cx, 246, 15, alpha(dim, a), "CHAPTER 2  ·  TRANSIT COMPLETE");
        r.textCentered(.bold, cx, 270, 40, alpha(white, a), "Proximal jejunum");
        r.textCentered(.regular, cx, 326, 16, alpha(dim, a), "femoral vein → vena cava → right heart → lungs → left heart → aorta →");
        r.textCentered(.regular, cx, 348, 16, alpha(dim, a), "superior mesenteric artery → villus capillary → out through the tip");
    }
    if (in_transit) {
        r.textCentered(.bold, cx, 300, 30, alpha(white, 0.9), "TRANSIT — TEMPO LINK 1:1");
        r.textCentered(.regular, cx, 340, 18, alpha(dim, 0.9), fmt(&buf, "{d:.1} cm to femoral junction", .{s.locationCm()}));
    }

    r.rect(cx - 300, 874, 600, 22, .{ 0.02, 0.03, 0.05, 0.45 });
    r.textCentered(.regular, cx, 878, 13, alpha(dim, 0.85), if (s.has_tether) "WASD move   Space / C up, down   Shift boost   G tether   T scan   H hint   Tab skip   Esc pause" else "WASD move   Space / C up, down   Shift boost   T identify   H hint   Tab skip line   Esc pause");
}

fn marker(r: *Renderer, vw: *const View, p: Vec3, from: Vec3, col: Color, label: []const u8, time: f32) void {
    var buf: [48]u8 = undefined;
    const W = r.ui_w;
    const dist = p.dist(from);
    const pulse = 0.7 + 0.3 * @sin(time * 4);
    if (project(r, vw, p)) |xy| {
        if (xy[0] > 40 and xy[0] < W - 40 and xy[1] > 70 and xy[1] < 760) {
            diamond(r, xy[0], xy[1], 11, 2, alpha(col, pulse));
            r.textCentered(.bold, xy[0], xy[1] + 16, 13, alpha(col, 0.9), distText(&buf, dist));
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
    const text_full = s.voice.current orelse return;
    const W = r.ui_w;
    const cx = W * 0.5;
    const size: f32 = if (s.voice.urgent) 25 else 20;
    const max_w: f32 = 760;
    // typewriter reveal, cut on a UTF-8 boundary
    var n: usize = @intFromFloat(@min(@as(f32, @floatFromInt(text_full.len)), s.voice.age * 75 + 1));
    while (n < text_full.len and (text_full[n] & 0xC0) == 0x80) n += 1;
    const h = r.paragraphHeight(.regular, max_w, size, text_full);
    const y = 748 - h;
    const fade = m.sat(s.voice.remaining / 0.3) * m.sat(s.voice.age / 0.1);
    r.rect(cx - max_w * 0.5 - 20, y - 30, max_w + 40, h + 42, alpha(panel, fade));
    r.rect(cx - max_w * 0.5 - 20, y - 30, 3, h + 42, alpha(if (s.voice.urgent) gold else green, fade));
    _ = r.text(.bold, cx - max_w * 0.5, y - 22, 13, alpha(if (s.voice.urgent) gold else green, fade), "DRA. MARÍN");
    _ = r.paragraph(.regular, cx - max_w * 0.5, y, max_w, size, alpha(if (s.voice.urgent) gold else white, fade), text_full[0..n]);
}

fn card(r: *Renderer, w: f32, h: f32, accent: Color) [2]f32 {
    const x = (r.ui_w - w) * 0.5;
    const y = (r.ui_h - h) * 0.5;
    r.rect(x, y, w, h, .{ 0.015, 0.02, 0.035, 0.9 });
    r.frame(x, y, w, h, 1.5, alpha(accent, 0.6));
    r.rect(x, y, w, 4, accent);
    return .{ x, y };
}

fn drawModeOverlay(app: *App, r: *Renderer) void {
    const s = &app.sim;
    const cx = r.ui_w * 0.5;
    var buf: [200]u8 = undefined;
    switch (s.mode) {
        .upgrade_card => {
            if (s.chapter == 1) {
                const o = card(r, 720, 380, white);
                r.textCentered(.bold, cx, o[1] + 30, 15, dim, "MUCIN SYNTHESIS CALIBRATED  —  UPGRADE");
                r.textCentered(.bold, cx, o[1] + 58, 54, white, "MUCUS TETHER");
                // a line reeling a dot toward an anchor
                const k = @mod(app.time * 0.6, 1.0);
                r.line(cx - 150, o[1] + 168, cx + 150, o[1] + 168, 2, alpha(green, 0.5));
                r.arc(cx + 150, o[1] + 168, 7, 0, m.tau, 14, green);
                r.arc(cx - 150 + 290 * k, o[1] + 168, 9, 0, m.tau, 4, white);
                _ = r.paragraph(.regular, o[0] + 60, o[1] + 220, 600, 20, white, "G fires a mucin line at whatever tissue the reticle is on, up to 0.4 mm away, reels the drone in and holds it there against any stream. G on a new point moves the line; G on nothing releases it. Hold on through a contraction, or cross a stream the thrusters cannot beat one pull at a time.");
                r.textCentered(.bold, cx, o[1] + 336, 18, alpha(green, 0.7 + 0.3 * @sin(app.time * 4)), "Enter — install");
                return;
            }
            const o = card(r, 720, 380, white);
            r.textCentered(.bold, cx, o[1] + 30, 15, dim, "FIELD CALIBRATION COMPLETE  —  UPGRADE");
            r.textCentered(.bold, cx, o[1] + 58, 54, white, "SYNC SERVO");
            // the two arcs closing into one ring
            const k = 0.5 + 0.5 * @sin(app.time * 2.5);
            r.arc(cx - 14 * k, o[1] + 168, 30, m.pi - 1.3, m.pi + 1.3, 4, cyan);
            r.arc(cx + 14 * k, o[1] + 168, 30, -1.3, 1.3, 4, amber);
            _ = r.paragraph(.regular, o[0] + 60, o[1] + 220, 600, 20, white, "Trigger both arms within a tenth of a second and they land as one Sync Strike: three times the effect, with a shockwave that clears small organisms around you. Two punches shatter calcium. Two rounds merge into a lance that pierces.");
            r.textCentered(.bold, cx, o[1] + 336, 18, alpha(green, 0.7 + 0.3 * @sin(app.time * 4)), "Enter — install");
        },
        .dead => {
            const o = card(r, 620, 240, red);
            r.textCentered(.bold, cx, o[1] + 36, 50, red, "SIGNAL LOST");
            r.textCentered(.regular, cx, o[1] + 112, 20, white, "The hull failed. The patient is unharmed; the drone is not.");
            r.textCentered(.bold, cx, o[1] + 176, 18, alpha(white, 0.7 + 0.3 * @sin(app.time * 4)), "Enter — relaunch from the last checkpoint");
        },
        .lost => {
            const o = card(r, 660, 240, red);
            r.textCentered(.bold, cx, o[1] + 36, 50, red, "PATIENT LOST");
            r.textCentered(.regular, cx, o[1] + 112, 20, white, if (s.chapter == 1) "Too much damage to the lining, too much virus spread. She did not make it." else "Too much damage to healthy tissue, too many emboli. She did not make it.");
            r.textCentered(.bold, cx, o[1] + 176, 18, alpha(white, 0.7 + 0.3 * @sin(app.time * 4)), "Enter — restart the chapter");
        },
        .complete => {
            if (s.chapter == 1) {
                const o = card(r, 820, 560, green);
                r.textCentered(.bold, cx, o[1] + 26, 15, dim, "CHAPTER 2  ·  INTESTINES");
                r.textCentered(.bold, cx, o[1] + 50, 50, white, "Up the lumen");
                const g = s.grade();
                r.textCentered(.bold, cx, o[1] + 122, 84, if (g == 'A') green else if (g == 'D') red else gold, &[1]u8{g});
                const lx = o[0] + 90;
                const rx = o[0] + 730;
                var y = o[1] + 236;
                const rows = [_]struct { k: []const u8, v: []const u8 }{
                    .{ .k = "Patient stability", .v = fmt(buf[0..24], "{d:.0} / 100", .{s.stability}) },
                    .{ .k = "Infected cells cleared", .v = fmt(buf[24..48], "{d} / {d}", .{ s.g.cleared, s.g.total }) },
                    .{ .k = "Times the virus spread", .v = fmt(buf[48..72], "{d}", .{s.g.spread}) },
                    .{ .k = "Commensal bacteria killed", .v = fmt(buf[72..96], "{d}", .{s.g.commensals_lost}) },
                    .{ .k = "Hits on the lining", .v = fmt(buf[96..120], "{d}", .{s.stats.tissue_hits}) },
                    .{ .k = "Atlas entries identified", .v = fmt(buf[120..144], "{d} / {d}", .{ s.atlasCount(), s.atlasTotal() }) },
                    .{ .k = "Relaunches", .v = fmt(buf[144..168], "{d}", .{s.stats.retries}) },
                    .{ .k = "Time on the link", .v = fmt(buf[168..200], "{d:.0} min {d:0>2.0} s", .{ @floor(s.stats.time / 60), @mod(s.stats.time, 60) }) },
                };
                for (rows) |row| {
                    _ = r.text(.regular, lx, y, 19, dim, row.k);
                    r.textRight(.bold, rx, y, 19, white, row.v);
                    y += 27;
                }
                const note: []const u8 = if (s.g.spread == 0 and s.g.commensals_lost == 0) "Nothing spread and her flora is intact. The villi will be back within the week." else if (s.g.commensals_lost > 3) "The virus is cleared, and so is some of what kept other things out." else "Cleared. What spread will slow her recovery by a day or two.";
                r.textCentered(.regular, cx, y + 10, 17, alpha(gold, 0.95), note);
                r.textCentered(.bold, cx, o[1] + 514, 18, alpha(green, 0.7 + 0.3 * @sin(app.time * 4)), "Enter — route map");
                return;
            }
            const o = card(r, 820, 560, green);
            r.textCentered(.bold, cx, o[1] + 26, 15, dim, "CHAPTER 1  ·  VEIN");
            r.textCentered(.bold, cx, o[1] + 50, 50, white, "Into the femoral vein");
            const g = s.grade();
            r.textCentered(.bold, cx, o[1] + 122, 84, if (g == 'A') green else if (g == 'D') red else gold, &[1]u8{g});
            const lx = o[0] + 90;
            const rx = o[0] + 730;
            var y = o[1] + 236;
            const rows = [_]struct { k: []const u8, v: []const u8 }{
                .{ .k = "Patient stability", .v = fmt(buf[0..24], "{d:.0} / 100", .{s.stability}) },
                .{ .k = "Emboli that reached the lungs", .v = fmt(buf[24..48], "{d}", .{s.stats.emboli_escaped}) },
                .{ .k = "Hits on healthy tissue", .v = fmt(buf[48..72], "{d}", .{s.stats.tissue_hits}) },
                .{ .k = "Immune cells lost to friendly fire", .v = fmt(buf[72..96], "{d}", .{s.stats.friendly_fire}) },
                .{ .k = "Sync Strikes landed", .v = fmt(buf[96..120], "{d}", .{s.stats.sync_strikes}) },
                .{ .k = "Atlas entries identified", .v = fmt(buf[120..144], "{d} / {d}", .{ s.atlasCount(), s.atlasTotal() }) },
                .{ .k = "Relaunches", .v = fmt(buf[144..168], "{d}", .{s.stats.retries}) },
                .{ .k = "Time on the link", .v = fmt(buf[168..200], "{d:.0} min {d:0>2.0} s", .{ @floor(s.stats.time / 60), @mod(s.stats.time, 60) }) },
            };
            for (rows) |row| {
                _ = r.text(.regular, lx, y, 19, dim, row.k);
                r.textRight(.bold, rx, y, 19, white, row.v);
                y += 27;
            }
            const note: []const u8 = if (s.stats.emboli_escaped == 0) "No emboli escaped. The lungs will be a shorter job." else "What escaped is lodged in her pulmonary arteries. You will meet it again in chapter 7.";
            r.textCentered(.regular, cx, y + 10, 17, alpha(gold, 0.95), note);
            if (s.hidden_unlocked) r.textCentered(.bold, cx, y + 36, 16, gold, "Hidden route logged: Bone Marrow");
            r.textCentered(.bold, cx, o[1] + 514, 18, alpha(green, 0.7 + 0.3 * @sin(app.time * 4)), "Enter — route map");
        },
        else => {},
    }
}

fn drawPause(app: *App, r: *Renderer) void {
    const cx = r.ui_w * 0.5;
    const o = card(r, 760, 600, cyan);
    r.textCentered(.bold, cx, o[1] + 28, 46, white, "PAUSED");
    const opts = [_][2][]const u8{
        .{ "Esc / Enter", "Resume" },
        .{ "R", "Relaunch from last checkpoint" },
        .{ "N", "Restart chapter" },
        .{ "L", "Leave to title" },
    };
    var y = o[1] + 104;
    for (opts) |op| {
        r.textRight(.bold, cx - 20, y, 20, cyan, op[0]);
        _ = r.text(.regular, cx + 10, y, 20, white, op[1]);
        y += 30;
    }
    y += 16;
    r.rect(o[0] + 60, y, 640, 1, alpha(dim, 0.4));
    y += 16;
    const ctl = [_][2][]const u8{
        .{ "Mouse / arrow keys", "Look" },
        .{ "W A S D", "Thrust and strafe" },
        .{ "Space / C", "Up / down" },
        .{ "Shift", "Boost" },
        .{ "Q  ·  left click", "Left arm" },
        .{ "E  ·  right click", "Right arm" },
        .{ "Z / X", "Cycle left / right arm tool" },
        .{ "1 2 3  ·  8 9 0", "Punch, drill, shoot on left · right arm" },
        .{ "T", "Identify what the reticle is on (again for more)" },
        .{ "H", "Hint" },
        .{ "Tab", "Skip the current line" },
        .{ "Cmd+F", "Full screen" },
    };
    for (ctl) |cc| {
        r.textRight(.bold, cx - 20, y, 16, dim, cc[0]);
        _ = r.text(.regular, cx + 10, y, 16, white, cc[1]);
        y += 23;
    }
    drawSubtitlesPaused(app, r);
}

fn drawSubtitlesPaused(app: *App, r: *Renderer) void {
    _ = app;
    _ = r;
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
    r.textCentered(.bold, cx, 250, 120, alpha(white, a), "Dentro del cuerpo");
    r.textCentered(.regular, cx, 392, 28, alpha(dim, a), "I N S I D E   T H E   B O D Y");
    r.rect(cx - 160, 446, 320, 1, alpha(cyan, 0.6 * a));
    const blink = 0.65 + 0.35 * @sin(app.time * 3);
    r.textCentered(.bold, cx, 520, 24, alpha(green, a * blink), "Enter — begin");
    r.textCentered(.regular, cx, 560, 20, alpha(white, a * 0.85), "M — route map");
    if (app.save.ch1_done) {
        var buf: [96]u8 = undefined;
        r.textCentered(.regular, cx, 610, 16, alpha(gold, a * 0.9), if (app.save.ch2_done) fmt(&buf, "Chapters 1 and 2 complete  ·  grades {c} and {c}  ·  M for the route map", .{ app.save.grade, app.save.grade2 }) else fmt(&buf, "Chapter 1 complete  ·  grade {c}  ·  chapter 2 is open on the route map — M", .{ app.save.grade }));
    }
    r.textCentered(.regular, cx, 850, 14, alpha(dim, a * 0.8), "Right great saphenous vein, 3.6 mm across. Every disc is a red blood cell, 7.8 µm.");
}

fn drawBriefing(app: *App, r: *Renderer) void {
    const cx = r.ui_w * 0.5;
    const o = card(r, 860, 440, cyan);
    var buf: [32]u8 = undefined;
    r.textCentered(.bold, cx, o[1] + 26, 15, dim, fmt(&buf, "BRIEFING  ·  {d} / {d}", .{ app.briefing_page + 1, app_mod.briefing_pages.len }));
    const page = app_mod.briefing_pages[@min(app.briefing_page, app_mod.briefing_pages.len - 1)];
    var n: usize = @intFromFloat(@min(@as(f32, @floatFromInt(page.len)), app.screen_t * 140 + 1));
    while (n < page.len and (page[n] & 0xC0) == 0x80) n += 1;
    _ = r.paragraph(.regular, o[0] + 70, o[1] + 76, 720, 23, white, page[0..n]);
    r.textCentered(.bold, cx, o[1] + 392, 18, alpha(green, 0.7 + 0.3 * @sin(app.time * 4)), if (app.briefing_page + 1 == app_mod.briefing_pages.len) "Enter — launch" else "Enter — continue");
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
    _ = r.text(.bold, 60, 36, 40, white, "Route");
    _ = r.text(.regular, 190, 54, 16, dim, "right leg to third ventricle  ·  eleven stops, two off the chart");

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
        const label: []const u8 = if (c.hidden) (if (known) "✓" else "?") else fmt(&buf, "{d}", .{i + 1});
        _ = r.text(.bold, x + 12, y - 9, 13, alpha(col, 0.95), label);
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
        const num: []const u8 = if (c.hidden) "◆" else fmt(&buf, "{d}", .{i + 1});
        _ = r.text(.bold, lx, y, 17, if (c.hidden) gold else dim, num);
        _ = r.text(if (sel) .bold else .regular, lx + 34, y, 18, if (sel) white else alpha(white, 0.8), if (known) c.name else "— unknown —");
        const status: []const u8 = if (done) "complete" else if (app.chapterUnlocked(i)) "playable" else if (c.playable) "locked" else if (c.hidden and !known) "hidden" else if (c.hidden) "route logged" else "mapped";
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
    _ = r.text(.bold, dx, dy, 34, white, if (known) c.name else "Unknown");
    dy += 46;
    _ = r.text(.regular, dx, dy, 17, dim, if (known) c.site else "Something along the way does not belong. Look closely.");
    dy += 40;
    const fields = [_][2][]const u8{
        .{ "HOW THE DRONE GETS THERE", c.route },
        .{ "WHAT YOU LEARN TO READ", c.read },
        .{ "OBJECTIVE", c.objective },
        .{ "WHAT MAKES IT HARD HERE", c.challenge },
        .{ "UPGRADE", c.upgrade },
    };
    for (fields, 0..) |fl, i| {
        if (!known and i != 2) continue;
        _ = r.text(.bold, dx, dy, 13, if (c.hidden) gold else cyan, fl[0]);
        dy = r.paragraph(.regular, dx, dy + 20, dw, 18, white, fl[1]) + 16;
    }
    const open = app.chapterUnlocked(app.map_sel);
    const foot: []const u8 = if (open) "Enter — fly this chapter" else if (c.playable) "Complete the chapter before it to fly this one." else if (c.hidden and !known) "Not yet found." else "Designed and routed; not yet flyable in this build.";
    _ = r.text(.bold, dx, 786, 17, if (open) alpha(green, 0.7 + 0.3 * @sin(app.time * 4)) else alpha(dim, 0.9), foot);
    r.textCentered(.regular, W * 0.5, 868, 14, alpha(dim, 0.8), "↑ ↓ select    Enter fly    Esc back");
}
