//! Game controller state and the arithmetic that makes it usable: dead zones, response curves, trigger
//! thresholds and press edges. Nothing here knows about a platform or about the game. A platform backend
//! fills a `State` each frame (GameController on macOS, XInput on Windows) and hands it over as it reads it;
//! everything a player can feel is decided on this side of that struct, so it is the same on every
//! platform and can be tested without a device.

const std = @import("std");

/// Which names and symbols are printed on the controller. Anything that is neither is `generic` and is
/// prompted with Xbox names, the layout most third-party controllers copy.
pub const Family = enum(u8) { generic, xbox, playstation };

/// Buttons by position, under their Xbox names. `a` is the bottom face button (Cross on PlayStation),
/// `b` the right one (Circle), `x` the left (Square), `y` the top (Triangle). `back` is View on Xbox and
/// Create or Share on PlayStation; `start` is Menu on Xbox and Options on PlayStation. `lt` and `rt` are
/// the triggers read as buttons.
pub const Button = enum(u8) {
    a,
    b,
    x,
    y,
    lb,
    rb,
    lt,
    rt,
    ls,
    rs,
    dpad_up,
    dpad_down,
    dpad_left,
    dpad_right,
    start,
    back,

    pub const count = @typeInfo(Button).@"enum".field_names.len;
};

pub const Buttons = std.EnumSet(Button);

/// One controller as the device reports it this frame. This is the whole contract with a platform backend:
/// it fills the fields and applies no dead zone, curve or threshold of its own.
pub const State = struct {
    /// False when no controller is attached; every other field is then ignored.
    connected: bool = false,
    family: Family = .generic,
    /// Sticks, x to the right and y up, each axis in [-1, 1].
    left: [2]f32 = .{ 0, 0 },
    right: [2]f32 = .{ 0, 0 },
    /// Triggers, 0 released to 1 fully pulled. A device whose triggers are switches may set the `lt` and
    /// `rt` buttons instead; either is enough.
    lt: f32 = 0,
    rt: f32 = 0,
    buttons: Buttons = .empty,

    pub fn set(s: *State, b: Button, down: bool) void {
        s.buttons.setPresent(b, down);
    }
};

/// How a stick's deflection becomes a command: nothing inside `inner`, full scale from `outer` on, and
/// between them the distance raised to `exponent`.
pub const Shape = struct {
    inner: f32,
    outer: f32,
    exponent: f32,
};

/// Thrust: a wide dead zone, since a drifting stick would push the drone off a wall it is resting on, and
/// a linear response, since thrust is already smoothed by the drone's inertia.
pub const move_shape: Shape = .{ .inner = 0.20, .outer = 0.92, .exponent = 1.0 };
/// Look: squared, so the first half of the travel covers a quarter of the turn rate and small corrections
/// around a target are fine-grained.
pub const look_shape: Shape = .{ .inner = 0.16, .outer = 0.95, .exponent = 2.0 };

/// Radial dead zone and curve. The dead zone is a circle, not a cross: the direction of the stick is kept
/// and only its length is remapped, so diagonals are neither clipped nor snapped to an axis.
pub fn shape(v: [2]f32, s: Shape) [2]f32 {
    const len = @sqrt(v[0] * v[0] + v[1] * v[1]);
    // Written so that a NaN from a broken report falls on the idle side.
    if (!(len > s.inner)) return .{ 0, 0 };
    const t = @min(1.0, (len - s.inner) / (s.outer - s.inner));
    const mag = std.math.pow(f32, t, s.exponent);
    // direction first, then length: a stick hard against its gate comes out as exactly 1, never an ulp over
    return .{ v[0] / len * mag, v[1] / len * mag };
}

/// The deflection that `shape` maps to `out`, for `out` no longer than 1: the inverse the tests and the
/// scripted pilot use to hold the stick where a wanted command needs it.
pub fn unshape(out: [2]f32, s: Shape) [2]f32 {
    const len = @sqrt(out[0] * out[0] + out[1] * out[1]);
    if (!(len > 0)) return .{ 0, 0 };
    const t = std.math.pow(f32, @min(len, 1.0), 1.0 / s.exponent);
    const k = (s.inner + t * (s.outer - s.inner)) / len;
    return .{ out[0] * k, out[1] * k };
}

/// A trigger counts as pulled from `trigger_press` and as let go below `trigger_release`. The gap keeps a
/// finger resting at the threshold from chattering; the press point is low so the pull registers early in
/// the travel, on the frame it is crossed, which is what a two-trigger Sync Strike is timed against.
pub const trigger_press: f32 = 0.40;
pub const trigger_release: f32 = 0.25;

pub fn triggerDown(was_down: bool, value: f32) bool {
    return if (was_down) value > trigger_release else value >= trigger_press;
}

/// A frame of controller input after shaping, with press and release edges.
pub const Sample = struct {
    connected: bool = false,
    family: Family = .generic,
    /// Left stick through `move_shape`, right stick through `look_shape`; each no longer than 1.
    move: [2]f32 = .{ 0, 0 },
    look: [2]f32 = .{ 0, 0 },
    down: Buttons = .empty,
    pressed: Buttons = .empty,
    released: Buttons = .empty,

    pub fn held(s: *const Sample, b: Button) bool {
        return s.down.contains(b);
    }
    pub fn hit(s: *const Sample, b: Button) bool {
        return s.pressed.contains(b);
    }
    /// A button or trigger went down this frame.
    pub fn anyPressed(s: *const Sample) bool {
        return s.pressed.count() > 0;
    }
    /// A stick is held outside its dead zone.
    pub fn deflected(s: *const Sample) bool {
        return s.move[0] != 0 or s.move[1] != 0 or s.look[0] != 0 or s.look[1] != 0;
    }
};

/// Turns successive `State`s into `Sample`s. It holds the only memory the controller needs: which buttons
/// were down, so presses are edges and the triggers have hysteresis.
pub const Filter = struct {
    down: Buttons = .empty,
    /// The last frame came from a connected controller while the game had focus.
    live: bool = false,

    /// `focused` is false while the game's window is not the one receiving input. Then, and while no
    /// controller is connected, the result is an idle controller: everything that was held is reported
    /// released once and nothing stays down, so a button cannot remain stuck across a disconnection or a
    /// switch to another application. Whatever is already held when input comes back is down but was not
    /// pressed, so it cannot confirm a menu the player never saw.
    pub fn update(f: *Filter, raw: State, focused: bool) Sample {
        if (!raw.connected or !focused) {
            const out: Sample = .{ .connected = raw.connected, .family = raw.family, .released = f.down };
            f.down = .empty;
            f.live = false;
            return out;
        }
        var now = raw.buttons;
        now.setPresent(.lt, raw.buttons.contains(.lt) or triggerDown(f.down.contains(.lt), raw.lt));
        now.setPresent(.rt, raw.buttons.contains(.rt) or triggerDown(f.down.contains(.rt), raw.rt));
        const before = if (f.live) f.down else now;
        const out: Sample = .{
            .connected = true,
            .family = raw.family,
            .move = shape(raw.left, move_shape),
            .look = shape(raw.right, look_shape),
            .down = now,
            .pressed = now.differenceWith(before),
            .released = f.down.differenceWith(now),
        };
        f.down = now;
        f.live = true;
        return out;
    }
};

/// Auto-repeat for a held direction in a menu: one step when the direction is first held, another after
/// `delay`, then one every `interval`.
pub const Repeat = struct {
    dir: i8 = 0,
    wait: f32 = 0,

    pub const delay: f32 = 0.40;
    pub const interval: f32 = 0.12;

    /// `dir` is -1, 0 or 1. Returns the step to take this frame.
    pub fn update(r: *Repeat, dir: i8, dt: f32) i8 {
        if (dir != r.dir) {
            r.dir = dir;
            r.wait = delay;
            return dir;
        }
        if (dir == 0) return 0;
        r.wait -= dt;
        if (r.wait > 0) return 0;
        r.wait += interval;
        return dir;
    }
};

// ---------------------------------------------------------------------------------------------- tests

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectApprox = std.testing.expectApproxEqAbs;

fn length(v: [2]f32) f32 {
    return @sqrt(v[0] * v[0] + v[1] * v[1]);
}

test "a stick inside its dead zone commands nothing, in any direction" {
    for ([_]Shape{ move_shape, look_shape }) |s| {
        var k: usize = 0;
        while (k < 64) : (k += 1) {
            const a = @as(f32, @floatFromInt(k)) * std.math.tau / 64.0;
            const inside = shape(.{ @cos(a) * s.inner * 0.99, @sin(a) * s.inner * 0.99 }, s);
            try expectEqual(@as(f32, 0), inside[0]);
            try expectEqual(@as(f32, 0), inside[1]);
            // just outside, the command starts from zero rather than jumping
            const edge = shape(.{ @cos(a) * (s.inner + 0.01), @sin(a) * (s.inner + 0.01) }, s);
            try expect(length(edge) > 0 and length(edge) < 0.02);
        }
        try expectEqual([2]f32{ 0, 0 }, shape(.{ 0, 0 }, s));
        try expectEqual([2]f32{ 0, 0 }, shape(.{ std.math.nan(f32), 0.5 }, s));
    }
}

test "the response reaches full scale at the outer edge, keeps direction and never exceeds one" {
    for ([_]Shape{ move_shape, look_shape }) |s| {
        try expectApprox(@as(f32, 1), shape(.{ s.outer, 0 }, s)[0], 1e-5);
        try expectApprox(@as(f32, 1), shape(.{ 1, 0 }, s)[0], 1e-5);
        try expectApprox(@as(f32, -1), shape(.{ 0, -1 }, s)[1], 1e-5);
        // a square-gated stick in the corner reports (1, 1); the command is still a unit diagonal
        const corner = shape(.{ 1, 1 }, s);
        try expectApprox(@as(f32, 1), length(corner), 1e-5);
        try expectApprox(corner[0], corner[1], 1e-6);
        // direction is preserved at every length
        const v = shape(.{ 0.3, -0.4 }, s);
        try expectApprox(@as(f32, 0.3 / -0.4), v[0] / v[1], 1e-4);
        // and the response rises monotonically along the travel
        var prev: f32 = 0;
        var k: usize = 0;
        while (k <= 100) : (k += 1) {
            const out = shape(.{ @as(f32, @floatFromInt(k)) / 100.0, 0 }, s)[0];
            try expect(out >= prev and out <= 1);
            prev = out;
        }
    }
}

test "the look curve is the square of the travel past the dead zone" {
    const s = look_shape;
    const half = s.inner + 0.5 * (s.outer - s.inner);
    try expectApprox(@as(f32, 0.25), shape(.{ half, 0 }, s)[0], 1e-5);
    try expectApprox(@as(f32, 0.5), shape(.{ move_shape.inner + 0.5 * (move_shape.outer - move_shape.inner), 0 }, move_shape)[0], 1e-5);
}

test "unshape gives the deflection for a wanted command" {
    for ([_]Shape{ move_shape, look_shape }) |s| {
        for ([_][2]f32{ .{ 1, 0 }, .{ 0.5, 0.5 }, .{ -0.02, 0.3 }, .{ 0.001, 0 }, .{ 0, -0.7 } }) |want| {
            const got = shape(unshape(want, s), s);
            try expectApprox(want[0], got[0], 1e-4);
            try expectApprox(want[1], got[1], 1e-4);
        }
        try expectEqual([2]f32{ 0, 0 }, unshape(.{ 0, 0 }, s));
    }
}

test "a trigger presses at its threshold, holds through the gap and releases below it" {
    try expect(!triggerDown(false, 0));
    try expect(!triggerDown(false, trigger_press - 0.01));
    try expect(triggerDown(false, trigger_press));
    // once down, a value in the gap keeps it down
    try expect(triggerDown(true, (trigger_press + trigger_release) / 2));
    try expect(triggerDown(true, trigger_release + 0.01));
    try expect(!triggerDown(true, trigger_release));
    // and from released, the same value in the gap does not press it
    try expect(!triggerDown(false, (trigger_press + trigger_release) / 2));

    // a finger trembling across the press point yields one press, not one per frame
    var f: Filter = .{};
    var presses: usize = 0;
    var st: State = .{ .connected = true };
    _ = f.update(st, true);
    for (0..40) |k| {
        st.lt = if (k % 2 == 0) trigger_press + 0.03 else trigger_press - 0.03;
        if (f.update(st, true).hit(.lt)) presses += 1;
    }
    try expectEqual(@as(usize, 1), presses);
}

test "both triggers crossing the threshold in one frame are pressed in that frame" {
    var f: Filter = .{};
    var st: State = .{ .connected = true };
    _ = f.update(st, true);
    st.lt = 0.41;
    st.rt = 0.9;
    const s = f.update(st, true);
    try expect(s.hit(.lt) and s.hit(.rt) and s.held(.lt) and s.held(.rt));
}

test "a press is reported once, on the frame the button goes down" {
    var f: Filter = .{};
    var st: State = .{ .connected = true };
    _ = f.update(st, true);
    st.set(.x, true);
    var s = f.update(st, true);
    try expect(s.hit(.x) and s.held(.x) and s.anyPressed());
    s = f.update(st, true);
    try expect(!s.hit(.x) and s.held(.x) and !s.anyPressed());
    st.set(.x, false);
    s = f.update(st, true);
    try expect(!s.hit(.x) and !s.held(.x) and s.released.contains(.x));
    s = f.update(st, true);
    try expect(s.released.count() == 0);
    // a switch-type trigger reported as a button works like an analog one
    st.set(.rt, true);
    try expect(f.update(st, true).hit(.rt));
}

test "nothing stays down when the controller disconnects or the game loses focus mid-press" {
    for ([_]bool{ true, false }) |by_disconnect| {
        var f: Filter = .{};
        var st: State = .{ .connected = true, .lt = 1, .left = .{ 0, 1 }, .right = .{ 1, 0 } };
        st.set(.a, true);
        st.set(.ls, true);
        _ = f.update(.{ .connected = true }, true);
        var s = f.update(st, true);
        try expect(s.held(.a) and s.held(.lt) and s.held(.ls) and s.deflected());

        // The device goes away, or the window stops being key, with everything still held.
        var gone = st;
        gone.connected = !by_disconnect;
        s = f.update(gone, by_disconnect);
        try expectEqual(@as(usize, 0), s.down.count());
        try expectEqual(@as(usize, 0), s.pressed.count());
        try expect(s.released.contains(.a) and s.released.contains(.lt) and s.released.contains(.ls));
        try expect(!s.deflected());
        try expectEqual(!by_disconnect, s.connected);
        s = f.update(gone, by_disconnect);
        try expectEqual(@as(usize, 0), s.released.count());

        // It comes back with the same buttons held: they are down again, but they were not pressed.
        s = f.update(st, true);
        try expect(s.held(.a) and s.held(.lt));
        try expectEqual(@as(usize, 0), s.pressed.count());
        // A button pressed after that is an ordinary press.
        st.set(.b, true);
        try expect(f.update(st, true).hit(.b));
    }
}

test "a controller that is plugged in with a button held does not press it" {
    var f: Filter = .{};
    var st: State = .{ .connected = true };
    st.set(.start, true);
    const s = f.update(st, true);
    try expect(s.held(.start) and !s.hit(.start));
}

test "a held direction steps once, waits, then repeats" {
    var r: Repeat = .{};
    const dt: f32 = 1.0 / 60.0;
    var steps: i32 = r.update(1, dt);
    try expectEqual(@as(i32, 1), steps);
    var t: f32 = 0;
    while (t < Repeat.delay - 2 * dt) : (t += dt) steps += r.update(1, dt);
    try expectEqual(@as(i32, 1), steps);
    while (t < Repeat.delay + 2.5 * Repeat.interval) : (t += dt) steps += r.update(1, dt);
    // the first step, one at the end of the delay, and two more an interval apart
    try expectEqual(@as(i32, 4), steps);
    // letting go stops it; the other direction starts at once
    try expectEqual(@as(i8, 0), r.update(0, dt));
    try expectEqual(@as(i8, 0), r.update(0, dt));
    try expectEqual(@as(i8, -1), r.update(-1, dt));
    try expectEqual(@as(i8, 0), r.update(-1, dt));
    try expectEqual(@as(i8, 1), r.update(1, dt));
}
