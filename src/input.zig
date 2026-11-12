//! Controller input as the game's actions, and the choice of which device the prompts are for. A platform
//! backend supplies `pad.State` and nothing else; the layout comes from `bindings.zig`; what is here is the
//! behaviour around it: which buttons mean what while flying and in menus, how the stick turns the view,
//! how boost latches. It has no platform imports and runs headless, so a controller's whole path to the
//! simulation is tested without a device.

const std = @import("std");
const m = @import("math.zig");
const pad = @import("pad.zig");
const bindings = @import("bindings.zig");
const game = @import("game.zig");
const app_mod = @import("app.zig");
const Button = pad.Button;
const Buttons = pad.Buttons;
const button = bindings.button;

/// Turn rate at full deflection, in radians per second: yaw, pitch. Yaw is a half turn a second, which
/// crosses the field of view in about a third of one; pitch is slower because its range is half as wide.
/// The stick commands a rate and the rate is multiplied by the frame time, so a turn takes as long at 30
/// frames a second as at 120.
pub const look_rate = [2]f32{ 3.2, 2.3 };

/// A press of the confirm button counts only this long after flying stopped. Confirm is also the button
/// that climbs, so the one the player was tapping when a card came up must not dismiss it unread.
pub const confirm_guard: f32 = 0.5;

/// Boost stays on after a click for as long as the thrust stick is pushed at least this far.
pub const boost_hold: f32 = 0.35;

/// What the mapping needs to know about the game.
pub const Context = struct {
    /// The drone is being flown: sticks, triggers and held buttons drive it. False on every menu and on
    /// the cards that stop play, where the same buttons confirm, go back and move a selection.
    flying: bool = false,
    /// The tool on each arm, for the step back to the previous one.
    tools: [2]game.Tool = .{ .punch, .punch },

    pub fn of(app: *const app_mod.App) Context {
        const s = &app.sim;
        return .{
            .flying = app.screen == .play and (s.mode == .playing or s.mode == .transit),
            .tools = .{ s.arms[0].tool, s.arms[1].tool },
        };
    }
};

/// One frame of input from one device, in the game's terms.
pub const Out = struct {
    controls: game.Controls = .{},
    ui: app_mod.UiInput = .{},

    /// Input from two devices in the same frame. Held controls add up and one-shot actions are taken from
    /// either, so keyboard, mouse and controller can be used together: look deltas are summed, never
    /// replaced.
    pub fn merge(a: Out, b: Out) Out {
        var out = a;
        const c = &out.controls;
        const d = &b.controls;
        c.move = .{
            .x = m.clamp(c.move.x + d.move.x, -1, 1),
            .y = m.clamp(c.move.y + d.move.y, -1, 1),
            .z = m.clamp(c.move.z + d.move.z, -1, 1),
        };
        c.look = .{ c.look[0] + d.look[0], c.look[1] + d.look[1] };
        inline for (comptime std.meta.fieldNames(game.Controls)) |name| {
            const F = @FieldType(game.Controls, name);
            if (F == bool) @field(c, name) = @field(c, name) or @field(d, name);
            if (F == [2]bool) @field(c, name) = .{ @field(c, name)[0] or @field(d, name)[0], @field(c, name)[1] or @field(d, name)[1] };
            if (F == [2]?game.Tool) @field(c, name) = .{ @field(c, name)[0] orelse @field(d, name)[0], @field(c, name)[1] orelse @field(d, name)[1] };
        }
        inline for (comptime std.meta.fieldNames(app_mod.UiInput)) |name| {
            @field(out.ui, name) = @field(out.ui, name) or @field(b.ui, name);
        }
        return out;
    }
};

fn previous(t: game.Tool) game.Tool {
    return t.next().next();
}

pub const Mapper = struct {
    filter: pad.Filter = .{},
    nav: pad.Repeat = .{},
    /// Boost was clicked on and the stick has been held since.
    boosting: bool = false,
    /// Buttons that went down in a menu and have not come up yet. They do nothing in flight until they
    /// do: the press that launched the chapter does not also climb, the one that closed the pause menu
    /// does not also descend.
    parked: Buttons = .empty,
    since_flight: f32 = 0,
    /// The frame's controller input after shaping, for whoever tracks the active device.
    sample: pad.Sample = .{},

    /// `focused` is false while the window is not receiving input; see `pad.Filter.update`.
    pub fn update(mp: *Mapper, raw: pad.State, focused: bool, ctx: Context, dt: f32) Out {
        const s = mp.filter.update(raw, focused);
        mp.sample = s;
        mp.parked = mp.parked.intersectWith(s.down);
        mp.since_flight = if (ctx.flying) 0 else mp.since_flight + dt;
        var out: Out = .{};
        const c = &out.controls;
        const ui = &out.ui;
        if (!s.connected or !focused) {
            mp.nav = .{};
            mp.boosting = false;
            return out;
        }
        ui.pause = s.hit(button(.pause));

        if (ctx.flying) {
            mp.nav = .{};
            const live = s.down.differenceWith(mp.parked);
            c.move = .{
                .x = s.move[0],
                .y = @as(f32, if (live.contains(button(.up))) 1 else 0) - @as(f32, if (live.contains(button(.down))) 1 else 0),
                .z = s.move[1],
            };
            c.look = .{ s.look[0] * look_rate[0] * dt, s.look[1] * look_rate[1] * dt };

            // Boost is a click, not a hold: a thumb cannot comfortably press a stick down and steer with it
            // for five seconds. It lasts until the stick comes back toward the centre. Holding the click
            // also boosts, which is how to boost straight up or down.
            const boost = button(.boost);
            if (s.hit(boost)) mp.boosting = true;
            const pushed = s.move[0] * s.move[0] + s.move[1] * s.move[1] >= boost_hold * boost_hold;
            if (!pushed and !s.held(boost)) mp.boosting = false;
            c.boost = mp.boosting or live.contains(boost);

            c.arm = .{ live.contains(button(.arm_left)), live.contains(button(.arm_right)) };
            c.cycle = .{ s.hit(button(.tool_left)), s.hit(button(.tool_right)) };
            if (s.hit(button(.pick_left))) c.select[0] = previous(ctx.tools[0]);
            if (s.hit(button(.pick_right))) c.select[1] = previous(ctx.tools[1]);
            c.examine = s.hit(button(.examine));
            c.hint = s.hit(button(.hint));
            c.tether = s.hit(button(.tether)) or s.hit(bindings.binding(.tether).pad_also.?);
            c.skip = s.hit(button(.skip));
            return out;
        }

        mp.boosting = false;
        mp.parked = mp.parked.unionWith(s.pressed);
        if (s.hit(button(.confirm)) and mp.since_flight >= confirm_guard) {
            ui.confirm = true;
            c.confirm = true;
        }
        ui.cancel = s.hit(button(.back));
        ui.map = s.hit(button(.map));
        // One button, as on the keyboard: it switches the language where a screen offers that and skips
        // Marín's line where she is talking over a card.
        if (s.hit(button(.language))) {
            ui.language = true;
            c.skip = true;
        }
        var dir: i8 = 0;
        if (s.held(.dpad_up) or s.move[1] > 0.5) dir -= 1;
        if (s.held(.dpad_down) or s.move[1] < -0.5) dir += 1;
        const step = mp.nav.update(dir, dt);
        ui.up = step < 0;
        ui.down = step > 0;
        ui.left = s.hit(.dpad_left);
        ui.right = s.hit(.dpad_right);
        return out;
    }
};

/// Which device the prompts are for: the one the player last used. A press on the other device switches
/// at once. So does holding something on it, a stick outside its dead zone or a key kept down, but only
/// while the current device is doing nothing at all, so a player who steers with the stick and taps a key
/// does not make every prompt on screen flicker. Mouse movement is not part of this: on a handheld the
/// gyroscope and the trackpads arrive as mouse movement while the player's hands are on the controller.
pub const Tracker = struct {
    device: bindings.Device = .kbm,
    /// True for the one frame in which the controller the prompts were on is found to be gone. A
    /// controller nobody was using can come and go unremarked, and losing focus is not losing the controller.
    lost_pad: bool = false,

    /// What the keyboard and mouse did this frame: a key or mouse button went down, or one is held.
    pub const Keys = struct {
        pressed: bool = false,
        held: bool = false,
    };

    pub fn update(t: *Tracker, keys: Keys, sample: *const pad.Sample) bindings.Device {
        const pad_device = bindings.Device.ofFamily(sample.family);
        const pad_pressed = sample.connected and sample.anyPressed();
        const pad_held = sample.connected and (sample.down.count() > 0 or sample.deflected());
        const on_pad = t.device.isPad();
        t.lost_pad = on_pad and !sample.connected;
        if (on_pad and !sample.connected) {
            // The controller is gone; the keyboard is what is left.
            t.device = .kbm;
        } else if (pad_pressed != keys.pressed) {
            t.device = if (pad_pressed) pad_device else .kbm;
        } else if (on_pad) {
            // Nothing new was pressed, or both were at once. A controller in use keeps the prompts, under
            // the names of whichever controller it now is; an idle one gives them up to a held key.
            if (pad_pressed or pad_held) t.device = pad_device else if (keys.held) t.device = .kbm;
        } else if (pad_held and !keys.held and !keys.pressed) {
            t.device = pad_device;
        }
        return t.device;
    }
};

/// Holds a controller the way a wanted `Controls` needs it held: the inverse of `Mapper`, as far as a
/// controller has one. The scripted pilot flies through this in the tests and in `--demo --pad`, which
/// shows that a chapter can be finished with nothing but what a controller can express: a turn rate with a
/// ceiling, climb and descent as buttons, tools reached by stepping, every one-shot action a separate press.
pub const Puppet = struct {
    /// One-shot buttons pressed last frame; they are let go for a frame before they can be pressed again.
    tapped: Buttons = .empty,
    /// Climb and descent are buttons, so a fractional demand is met by pressing for that fraction of the
    /// frames, as a player feathers a button.
    lift: f32 = 0,

    pub fn drive(p: *Puppet, want: game.Controls, ctx: Context, dt: f32) pad.State {
        var st: pad.State = .{ .connected = true, .family = .xbox };
        var taps: Buttons = .empty;
        if (ctx.flying) {
            var mv = [2]f32{ want.move.x, want.move.z };
            const len = @sqrt(mv[0] * mv[0] + mv[1] * mv[1]);
            if (len > 1) mv = .{ mv[0] / len, mv[1] / len };
            st.left = pad.unshape(mv, pad.move_shape);

            var lk = [2]f32{ want.look[0] / (look_rate[0] * dt), want.look[1] / (look_rate[1] * dt) };
            const ll = @sqrt(lk[0] * lk[0] + lk[1] * lk[1]);
            if (ll > 1) lk = .{ lk[0] / ll, lk[1] / ll };
            st.right = pad.unshape(lk, pad.look_shape);

            p.lift += m.clamp(want.move.y, -1, 1);
            if (p.lift >= 0.5) {
                st.set(button(.up), true);
                p.lift -= 1;
            } else if (p.lift <= -0.5) {
                st.set(button(.down), true);
                p.lift += 1;
            }
            st.set(button(.boost), want.boost);
            st.lt = if (want.arm[0]) 1 else 0;
            st.rt = if (want.arm[1]) 1 else 0;
            const next_btn = [2]Button{ button(.tool_left), button(.tool_right) };
            const prev_btn = [2]Button{ button(.pick_left), button(.pick_right) };
            for (0..2) |i| {
                if (want.cycle[i]) taps.insert(next_btn[i]);
                if (want.select[i]) |tool| {
                    if (tool == ctx.tools[i]) continue;
                    taps.insert(if (tool == ctx.tools[i].next()) next_btn[i] else prev_btn[i]);
                }
            }
            if (want.examine) taps.insert(button(.examine));
            if (want.hint) taps.insert(button(.hint));
            if (want.tether) taps.insert(button(.tether));
            if (want.skip) taps.insert(button(.skip));
        } else {
            p.lift = 0;
            if (want.confirm) taps.insert(button(.confirm));
        }
        taps = taps.differenceWith(p.tapped);
        p.tapped = taps;
        st.buttons = st.buttons.unionWith(taps);
        return st;
    }
};

// ---------------------------------------------------------------------------------------------- tests

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectApprox = std.testing.expectApproxEqAbs;
const dt60: f32 = 1.0 / 60.0;

const flying: Context = .{ .flying = true };
const in_menu: Context = .{ .flying = false };

fn idle() pad.State {
    return .{ .connected = true, .family = .xbox };
}

fn with(buttons: []const Button) pad.State {
    var st = idle();
    for (buttons) |b| st.set(b, true);
    return st;
}

/// A mapper that has seen an idle controller, so the next state's buttons are presses.
fn ready(ctx: Context) Mapper {
    var mp: Mapper = .{};
    for (0..60) |_| _ = mp.update(idle(), true, ctx, dt60);
    return mp;
}

test "flying: sticks thrust and look, triggers work the arms, the face buttons climb and descend" {
    var mp = ready(flying);
    var st = idle();
    st.left = .{ 1, 0 };
    var o = mp.update(st, true, flying, dt60);
    try expectApprox(@as(f32, 1), o.controls.move.x, 1e-5);
    try expectEqual(@as(f32, 0), o.controls.move.z);
    st.left = .{ 0, -1 };
    o = mp.update(st, true, flying, dt60);
    try expectApprox(@as(f32, -1), o.controls.move.z, 1e-5);

    // right stick: right turns right (positive yaw delta), up looks up
    st = idle();
    st.right = .{ 1, 0 };
    o = mp.update(st, true, flying, dt60);
    try expectApprox(look_rate[0] * dt60, o.controls.look[0], 1e-6);
    try expectEqual(@as(f32, 0), o.controls.look[1]);
    st.right = .{ 0, 1 };
    o = mp.update(st, true, flying, dt60);
    try expectApprox(look_rate[1] * dt60, o.controls.look[1], 1e-6);

    st = idle();
    st.lt = 1;
    o = mp.update(st, true, flying, dt60);
    try expect(o.controls.arm[0] and !o.controls.arm[1]);
    st.rt = 1;
    o = mp.update(st, true, flying, dt60);
    try expect(o.controls.arm[0] and o.controls.arm[1]);

    o = mp.update(with(&.{.a}), true, flying, dt60);
    try expectEqual(@as(f32, 1), o.controls.move.y);
    try expect(!o.controls.confirm and !o.ui.confirm);
    o = mp.update(with(&.{.b}), true, flying, dt60);
    try expectEqual(@as(f32, -1), o.controls.move.y);
    try expect(!o.ui.cancel and !o.ui.back);
}

test "flying: one-shot actions fire once per press" {
    const Case = struct { b: Button, field: []const u8 };
    inline for ([_]Case{
        .{ .b = .x, .field = "examine" },
        .{ .b = .y, .field = "hint" },
        .{ .b = .rs, .field = "tether" },
        .{ .b = .dpad_up, .field = "tether" },
        .{ .b = .back, .field = "skip" },
    }) |case| {
        var mp = ready(flying);
        var o = mp.update(with(&.{case.b}), true, flying, dt60);
        try expect(@field(o.controls, case.field));
        o = mp.update(with(&.{case.b}), true, flying, dt60);
        try expect(!@field(o.controls, case.field));
    }
    var mp = ready(flying);
    var o = mp.update(with(&.{ .lb, .rb }), true, flying, dt60);
    try expect(o.controls.cycle[0] and o.controls.cycle[1]);
    o = mp.update(with(&.{ .lb, .rb }), true, flying, dt60);
    try expect(!o.controls.cycle[0] and !o.controls.cycle[1]);
    // d-pad left and right step each arm back one tool
    const ctx: Context = .{ .flying = true, .tools = .{ .punch, .shoot } };
    o = mp.update(with(&.{ .dpad_left, .dpad_right }), true, ctx, dt60);
    try expectEqual(@as(?game.Tool, .shoot), o.controls.select[0]);
    try expectEqual(@as(?game.Tool, .drill), o.controls.select[1]);
    // Start pauses; it is the only flying button that reaches the menus
    o = mp.update(with(&.{.start}), true, flying, dt60);
    try expect(o.ui.pause and !o.ui.back and !o.ui.confirm);
}

test "the look delta scales with frame time, so a turn takes the same time at any frame rate" {
    var st = idle();
    st.right = .{ 0.6, -0.3 };
    var totals: [3][2]f32 = undefined;
    for ([_]f32{ 30, 60, 144 }, 0..) |fps, i| {
        var mp = ready(flying);
        const dt = 1.0 / fps;
        var sum = [2]f32{ 0, 0 };
        const frames: usize = @intFromFloat(fps * 2);
        for (0..frames) |_| {
            const o = mp.update(st, true, flying, dt);
            sum[0] += o.controls.look[0];
            sum[1] += o.controls.look[1];
        }
        totals[i] = sum;
    }
    for (totals[1..]) |t| {
        try expectApprox(totals[0][0], t[0], 1e-3);
        try expectApprox(totals[0][1], t[1], 1e-3);
    }
    try expect(totals[0][0] > 0.5 and totals[0][1] < -0.1);
}

test "both triggers pulled in one frame reach the arms in that frame: a Sync Strike has no added delay" {
    var mp = ready(flying);
    var st = idle();
    st.lt = 0.5;
    st.rt = 0.5;
    const o = mp.update(st, true, flying, dt60);
    try expect(o.controls.arm[0] and o.controls.arm[1]);
}

test "boost: a click latches while the stick is pushed, and holding the click boosts on its own" {
    var mp = ready(flying);
    var st = idle();
    st.left = .{ 0, 1 };
    try expect(!mp.update(st, true, flying, dt60).controls.boost);
    st.set(.ls, true);
    try expect(mp.update(st, true, flying, dt60).controls.boost);
    st.set(.ls, false);
    for (0..120) |_| try expect(mp.update(st, true, flying, dt60).controls.boost);
    // easing off below the hold point ends it, and pushing again does not bring it back
    st.left = .{ 0, 0.3 };
    try expect(!mp.update(st, true, flying, dt60).controls.boost);
    st.left = .{ 0, 1 };
    try expect(!mp.update(st, true, flying, dt60).controls.boost);
    // held with the stick at rest: boost for as long as it is held
    st = with(&.{ .ls, .a });
    var o = mp.update(st, true, flying, dt60);
    try expect(o.controls.boost and o.controls.move.y == 1);
    o = mp.update(with(&.{.a}), true, flying, dt60);
    try expect(!o.controls.boost);
}

test "menus: confirm, back, map, language, pause, and a d-pad or stick that repeats" {
    var mp = ready(in_menu);
    var o = mp.update(with(&.{.a}), true, in_menu, dt60);
    try expect(o.ui.confirm and o.controls.confirm);
    try expectEqual(@as(f32, 0), o.controls.move.y);
    o = mp.update(with(&.{.a}), true, in_menu, dt60);
    try expect(!o.ui.confirm);
    _ = mp.update(idle(), true, in_menu, dt60);
    o = mp.update(with(&.{.b}), true, in_menu, dt60);
    try expect(o.ui.cancel and !o.ui.back);
    o = mp.update(with(&.{ .b, .y }), true, in_menu, dt60);
    try expect(o.ui.map and !o.ui.cancel);
    o = mp.update(with(&.{.back}), true, in_menu, dt60);
    try expect(o.ui.language and o.controls.skip);
    o = mp.update(with(&.{.start}), true, in_menu, dt60);
    try expect(o.ui.pause);
    o = mp.update(with(&.{ .dpad_left, .dpad_right }), true, in_menu, dt60);
    try expect(o.ui.left and o.ui.right);
    // nothing a menu button does leaks into the simulation's controls
    try expect(!o.controls.examine and !o.controls.hint and !o.controls.tether and o.controls.select[0] == null);

    for ([_]bool{ true, false }) |use_dpad| {
        mp = ready(in_menu);
        var st = idle();
        if (use_dpad) st.set(.dpad_down, true) else st.left = .{ 0, -1 };
        var downs: usize = 0;
        var t: f32 = 0;
        while (t < pad.Repeat.delay + 2.5 * pad.Repeat.interval) : (t += dt60) {
            o = mp.update(st, true, in_menu, dt60);
            downs += @intFromBool(o.ui.down);
            try expect(!o.ui.up);
        }
        // the first step, one at the end of the delay, and two more an interval apart
        try expectEqual(@as(usize, 4), downs);
        st = idle();
        if (use_dpad) st.set(.dpad_up, true) else st.left = .{ 0, 1 };
        o = mp.update(st, true, in_menu, dt60);
        try expect(o.ui.up and !o.ui.down);
    }
}

test "a button pressed in a menu does nothing in flight until it has been let go" {
    var mp = ready(in_menu);
    // A launches the chapter and is still down when flight begins: no climb.
    var o = mp.update(with(&.{.a}), true, in_menu, dt60);
    try expect(o.ui.confirm);
    for (0..30) |_| {
        o = mp.update(with(&.{.a}), true, flying, dt60);
        try expectEqual(@as(f32, 0), o.controls.move.y);
    }
    _ = mp.update(idle(), true, flying, dt60);
    o = mp.update(with(&.{.a}), true, flying, dt60);
    try expectEqual(@as(f32, 1), o.controls.move.y);

    // B closes the pause menu and is still down: no descent. A trigger pulled in the menu does not fire.
    mp = ready(in_menu);
    var st = with(&.{.b});
    st.rt = 1;
    _ = mp.update(st, true, in_menu, dt60);
    o = mp.update(st, true, flying, dt60);
    try expect(o.controls.move.y == 0 and !o.controls.arm[1]);

    // A trigger held from flight through a pause and back keeps its arm working.
    mp = ready(flying);
    st = idle();
    st.lt = 1;
    try expect(mp.update(st, true, flying, dt60).controls.arm[0]);
    _ = mp.update(st, true, in_menu, dt60);
    try expect(mp.update(st, true, flying, dt60).controls.arm[0]);
}

test "the climb button does not dismiss a card that has only just appeared" {
    var mp = ready(flying);
    // tapping A to climb when the card comes up
    var o = mp.update(with(&.{.a}), true, flying, dt60);
    try expectEqual(@as(f32, 1), o.controls.move.y);
    _ = mp.update(idle(), true, in_menu, dt60);
    o = mp.update(with(&.{.a}), true, in_menu, dt60);
    try expect(!o.ui.confirm and !o.controls.confirm);
    // after the guard, a fresh press confirms
    var t: f32 = 0;
    while (t < confirm_guard) : (t += dt60) _ = mp.update(idle(), true, in_menu, dt60);
    o = mp.update(with(&.{.a}), true, in_menu, dt60);
    try expect(o.ui.confirm and o.controls.confirm);
}

test "no controller, a disconnection or a lost focus leaves no input behind" {
    var mp: Mapper = .{};
    var o = mp.update(.{}, true, flying, dt60);
    try expectEqual(game.Controls{}, o.controls);
    try expectEqual(app_mod.UiInput{}, o.ui);

    for ([_]bool{ true, false }) |by_disconnect| {
        mp = ready(flying);
        var st = with(&.{ .a, .ls });
        st.left = .{ 0, 1 };
        st.right = .{ 1, 0 };
        st.lt = 1;
        st.rt = 1;
        o = mp.update(st, true, flying, dt60);
        try expect(o.controls.arm[0] and o.controls.arm[1] and o.controls.boost and o.controls.move.z > 0.9 and o.controls.look[0] > 0);
        var gone = st;
        gone.connected = !by_disconnect;
        for (0..3) |_| {
            o = mp.update(gone, by_disconnect, flying, dt60);
            try expectEqual(game.Controls{}, o.controls);
            try expectEqual(app_mod.UiInput{}, o.ui);
        }
        // Back, still held: the held controls resume, nothing counts as a new press, and the boost
        // latch did not survive.
        st.set(.ls, false);
        st.set(.x, true);
        o = mp.update(st, true, flying, dt60);
        try expect(o.controls.arm[0] and o.controls.move.z > 0.9);
        try expect(!o.controls.boost and !o.controls.examine);
    }
    // In a menu, a button already held when focus returns does not confirm anything.
    mp = ready(in_menu);
    _ = mp.update(idle(), false, in_menu, dt60);
    o = mp.update(with(&.{.a}), true, in_menu, dt60);
    try expect(!o.ui.confirm);
}

test "keyboard and controller input in one frame add up" {
    var kb: Out = .{};
    kb.controls.move = m.v3(1, 0, 1);
    kb.controls.look = .{ 0.01, -0.02 };
    kb.controls.arm = .{ true, false };
    kb.controls.select = .{ .drill, null };
    kb.ui.back = true;
    var pd: Out = .{};
    pd.controls.move = m.v3(0.5, 1, -0.25);
    pd.controls.look = .{ 0.03, 0.01 };
    pd.controls.arm = .{ false, true };
    pd.controls.select = .{ .shoot, .punch };
    pd.controls.boost = true;
    pd.controls.examine = true;
    pd.ui.confirm = true;
    const o = kb.merge(pd);
    try expectEqual(@as(f32, 1), o.controls.move.x);
    try expectEqual(@as(f32, 1), o.controls.move.y);
    try expectEqual(@as(f32, 0.75), o.controls.move.z);
    try expectApprox(@as(f32, 0.04), o.controls.look[0], 1e-7);
    try expectApprox(@as(f32, -0.01), o.controls.look[1], 1e-7);
    try expect(o.controls.arm[0] and o.controls.arm[1] and o.controls.boost and o.controls.examine);
    try expectEqual(@as(?game.Tool, .drill), o.controls.select[0]);
    try expectEqual(@as(?game.Tool, .punch), o.controls.select[1]);
    try expect(o.ui.back and o.ui.confirm and !o.ui.map);
    try expectEqual(kb.controls, kb.merge(.{}).controls);
}

fn sampleOf(st: pad.State) pad.Sample {
    var f: pad.Filter = .{};
    _ = f.update(.{ .connected = true, .family = st.family }, true);
    return f.update(st, true);
}

test "prompts follow the device last used, and mouse movement is not use" {
    var t: Tracker = .{};
    const quiet = sampleOf(idle());
    try expectEqual(bindings.Device.kbm, t.update(.{}, &quiet));

    // a button press switches to the controller's family
    try expectEqual(bindings.Device.xbox, t.update(.{}, &sampleOf(with(&.{.a}))));
    // Mouse movement reaches the tracker as nothing at all: `Keys` has no field for it. With the
    // controller idle and only the mouse moving, the prompts stay where they are.
    for (0..600) |_| try expectEqual(bindings.Device.xbox, t.update(.{}, &quiet));
    // a key press switches back, and so does a mouse button, which arrives the same way
    try expectEqual(bindings.Device.kbm, t.update(.{ .pressed = true, .held = true }, &quiet));
    try expectEqual(bindings.Device.kbm, t.update(.{ .held = true }, &quiet));

    // a stick past its dead zone switches; one inside it does not
    var st = idle();
    st.right = .{ pad.look_shape.inner * 0.9, 0 };
    try expectEqual(bindings.Device.kbm, t.update(.{}, &sampleOf(st)));
    st.right = .{ 0.5, 0 };
    try expectEqual(bindings.Device.xbox, t.update(.{}, &sampleOf(st)));
    // a trigger pull is a press
    t = .{};
    st = idle();
    st.rt = 1;
    try expectEqual(bindings.Device.xbox, t.update(.{}, &sampleOf(st)));

    // the family decides the names
    t = .{};
    var ps = with(&.{.x});
    ps.family = .playstation;
    try expectEqual(bindings.Device.playstation, t.update(.{}, &sampleOf(ps)));
    var other = with(&.{.x});
    other.family = .generic;
    try expectEqual(bindings.Device.xbox, t.update(.{}, &sampleOf(other)));
}

test "holding one device while tapping the other does not make the prompts flicker" {
    var t: Tracker = .{};
    var st = idle();
    st.left = .{ 0, 1 };
    const steering = sampleOf(st);
    try expectEqual(bindings.Device.xbox, t.update(.{}, &steering));
    // a key is tapped while the stick stays pushed: keyboard prompts for as long as the key is down
    try expectEqual(bindings.Device.kbm, t.update(.{ .pressed = true, .held = true }, &steering));
    for (0..10) |_| try expectEqual(bindings.Device.kbm, t.update(.{ .held = true }, &steering));
    // the key comes up and the stick is still pushed: back to the controller
    try expectEqual(bindings.Device.xbox, t.update(.{}, &steering));

    // the other way round: W held on the keyboard, a drifting stick does not take the prompts
    t = .{};
    for (0..10) |_| try expectEqual(bindings.Device.kbm, t.update(.{ .held = true }, &steering));
    // but a button press does
    var pressed = st;
    pressed.set(.x, true);
    var f: pad.Filter = .{};
    _ = f.update(st, true);
    try expectEqual(bindings.Device.xbox, t.update(.{ .held = true }, &f.update(pressed, true)));
}

test "prompts return to the keyboard when the controller is unplugged, not when focus is lost" {
    var t: Tracker = .{ .device = .playstation };
    var f: pad.Filter = .{};
    var st = idle();
    st.family = .playstation;
    _ = f.update(st, true);
    try expectEqual(bindings.Device.playstation, t.update(.{}, &f.update(st, false)));
    try expect(!t.lost_pad);
    try expectEqual(bindings.Device.kbm, t.update(.{}, &f.update(.{}, true)));
    try expect(t.lost_pad);
    // The loss is reported for that frame only.
    _ = t.update(.{}, &f.update(.{}, true));
    try expect(!t.lost_pad);
}

test "only the loss of the controller in use is a loss: one nobody touched can go unremarked" {
    var t: Tracker = .{};
    var f: pad.Filter = .{};
    // Attached and idle while the player is on the keyboard, then unplugged.
    try expectEqual(bindings.Device.kbm, t.update(.{ .pressed = true }, &f.update(idle(), true)));
    try expectEqual(bindings.Device.kbm, t.update(.{}, &f.update(.{}, true)));
    try expect(!t.lost_pad);
    // Picked up and used, then gone.
    _ = f.update(idle(), true);
    try expectEqual(bindings.Device.xbox, t.update(.{}, &f.update(with(&.{.a}), true)));
    try expect(!t.lost_pad);
    try expectEqual(bindings.Device.kbm, t.update(.{}, &f.update(.{}, true)));
    try expect(t.lost_pad);
}

test "the puppet's controller state maps back to the controls it was asked for" {
    var mp = ready(flying);
    var pp: Puppet = .{};
    var want: game.Controls = .{};
    want.move = m.v3(0.3, 0, -0.6);
    want.look = .{ 0.01, -0.004 };
    want.boost = true;
    want.arm = .{ true, true };
    want.examine = true;
    want.select = .{ .shoot, .drill };
    const ctx: Context = .{ .flying = true, .tools = .{ .punch, .punch } };
    const o = mp.update(pp.drive(want, ctx, dt60), true, ctx, dt60);
    try expectApprox(@as(f32, 0.3), o.controls.move.x, 1e-4);
    try expectApprox(@as(f32, -0.6), o.controls.move.z, 1e-4);
    try expectApprox(@as(f32, 0.01), o.controls.look[0], 1e-5);
    try expectApprox(@as(f32, -0.004), o.controls.look[1], 1e-5);
    try expect(o.controls.boost and o.controls.arm[0] and o.controls.arm[1] and o.controls.examine);
    // punch to shoot is one step back; punch to drill is one step forward
    try expectEqual(@as(?game.Tool, .shoot), o.controls.select[0]);
    try expect(o.controls.cycle[1]);

    // a turn faster than the stick allows is held at the stick's ceiling
    want = .{};
    want.look = .{ 7.0 * dt60, 0 };
    _ = mp.update(pp.drive(.{}, ctx, dt60), true, ctx, dt60);
    const fast = mp.update(pp.drive(want, ctx, dt60), true, ctx, dt60);
    try expectApprox(look_rate[0] * dt60, fast.controls.look[0], 1e-5);

    // a third of full climb is the climb button on one frame in three
    want = .{};
    want.move.y = 1.0 / 3.0;
    var up: usize = 0;
    for (0..300) |_| up += @intFromBool(mp.update(pp.drive(want, ctx, dt60), true, ctx, dt60).controls.move.y > 0);
    try expect(up >= 99 and up <= 101);
}

/// The scripted pilot's controls, passed through a controller and back.
const ThroughPad = struct {
    puppet: Puppet = .{},
    mapper: Mapper = .{},

    pub fn pass(t: *ThroughPad, want: game.Controls, sim: *const game.Sim, dt: f32) game.Controls {
        const ctx: Context = .{
            .flying = sim.mode == .playing or sim.mode == .transit,
            .tools = .{ sim.arms[0].tool, sim.arms[1].tool },
        };
        return t.mapper.update(t.puppet.drive(want, ctx, dt), true, ctx, dt).controls;
    }
};

test "the scripted pilot finishes both chapters through a controller alone" {
    const bot = @import("bot.zig");
    const gpa = std.testing.allocator;
    const sim = try gpa.create(game.Sim);
    defer gpa.destroy(sim);
    const cp = try gpa.create(game.Sim);
    defer gpa.destroy(cp);

    var through: ThroughPad = .{};
    const vein = bot.runHeadlessVia(sim, cp, 0, 1500, false, &through);
    try expect(vein.completed);
    try expect(sim.has_sync);
    try expect(vein.stats.dual_time > 3);
    // the stone at the exit only breaks to Sync Strikes: both triggers inside the window, repeatedly
    try expect(vein.stats.sync_strikes >= 3);
    try expect(vein.stability > 0);

    through = .{};
    const gut = bot.runHeadlessVia(sim, cp, 1, 1500, false, &through);
    try expect(gut.completed);
    try expect(sim.has_tether);
    try expect(sim.g.extruded >= 8);
    try expect(sim.g.waves_survived >= 2);
    try expect(sim.g.tether_uses >= 6);
    try expect(gut.stats.dual_time > 1.5);
    try expect(gut.stability > 0);
}
