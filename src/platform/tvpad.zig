//! Controllers on the television. The engine (tvengine) reads Xbox controllers from the kernel's evdev
//! nodes and delivers each change as an event: a device id, the index of a button or an axis, and a value.
//! This file keeps the state those events add up to for as many as two controllers and hands the game the
//! one touched last as a `pad.State`, raw, as every other platform backend does. It imports nothing from
//! the engine, so it is tested on any machine; `tv.zig` passes the events in as plain numbers.

const std = @import("std");
const pad = @import("../pad.zig");

/// Event kinds, as `engine.input.Kind` numbers them.
pub const Kind = enum(c_int) { connected = 1, disconnected = 2, button = 3, axis = 4, _ };

/// Button indices of the engine's events (`engine.input.Button`), in the game's terms. The engine names
/// two of them by position on the kernel's diagram, where the names X and Y are attached to the opposite
/// buttons from the ones an Xbox controller prints them on: the kernel's BTN_NORTH is BTN_X, which is
/// what the controller's X button reports, and BTN_WEST is BTN_Y.
fn buttonOf(index: i32) ?pad.Button {
    return switch (index) {
        1 => .a,
        2 => .b,
        3 => .x,
        4 => .y,
        5 => .lb,
        6 => .rb,
        7 => .back,
        8 => .start,
        9 => .ls,
        10 => .rs,
        else => null,
    };
}

/// Axis indices of the engine's events (`engine.input.Axis`). Sticks arrive in [-1, 1] with y growing
/// downward, triggers in [0, 1], and the d-pad as a hat of -1, 0 or 1 per axis.
const Axis = struct {
    const hat_x = 1;
    const hat_y = 2;
    const lt = 3;
    const rt = 4;
    const lx = 5;
    const ly = 6;
    const rx = 7;
    const ry = 8;
};

pub const Pads = struct {
    slots: [2]Slot = .{ .{}, .{} },
    /// The slot whose controller the game reads: the one touched last.
    current: usize = 0,

    const Slot = struct {
        id: ?u32 = null,
        state: pad.State = .{},
    };

    /// Apply one event from the engine.
    pub fn apply(p: *Pads, kind: Kind, id: u32, index: i32, value: f32) void {
        if (kind == .disconnected) {
            // The slot is emptied but `current` stays on it: the game sees its controller go and pauses,
            // and takes up another controller when that one is touched.
            if (p.find(id)) |i| p.slots[i] = .{};
            return;
        }
        const i = p.find(id) orelse p.adopt(id) orelse return;
        const s = &p.slots[i].state;
        if (!p.slots[p.current].state.connected) p.current = i;
        const v: f32 = if (value == value) std.math.clamp(value, -1.0, 1.0) else 0;
        var touched = false;
        switch (kind) {
            .button => if (buttonOf(index)) |b| {
                s.set(b, v > 0.5);
                touched = v > 0.5;
            },
            .axis => switch (index) {
                Axis.hat_x => {
                    s.set(.dpad_left, v < -0.5);
                    s.set(.dpad_right, v > 0.5);
                    touched = @abs(v) > 0.5;
                },
                Axis.hat_y => {
                    s.set(.dpad_up, v < -0.5);
                    s.set(.dpad_down, v > 0.5);
                    touched = @abs(v) > 0.5;
                },
                Axis.lt => {
                    s.lt = @max(v, 0);
                    touched = v >= pad.trigger_press;
                },
                Axis.rt => {
                    s.rt = @max(v, 0);
                    touched = v >= pad.trigger_press;
                },
                Axis.lx => s.left[0] = v,
                Axis.ly => s.left[1] = -v,
                Axis.rx => s.right[0] = v,
                Axis.ry => s.right[1] = -v,
                else => {},
            },
            else => {},
        }
        // A stick counts as a touch only well outside its dead zone, so a controller lying on the sofa
        // with a drifting stick does not take the game from the one being held.
        if (kind == .axis and index >= Axis.lx and index <= Axis.ry) touched = @abs(v) > 0.6;
        if (touched) p.current = i;
    }

    fn find(p: *const Pads, id: u32) ?usize {
        for (p.slots, 0..) |s, i| if (s.id == id) return i;
        return null;
    }

    fn adopt(p: *Pads, id: u32) ?usize {
        for (&p.slots, 0..) |*s, i| {
            if (s.id != null) continue;
            // The engine opens only controllers that name themselves Xbox ones.
            s.* = .{ .id = id, .state = .{ .connected = true, .family = .xbox } };
            return i;
        }
        return null;
    }

    /// Forget everything that is held, on every controller. The game was not listening (it was suspended)
    /// and a release that happened meanwhile was not delivered.
    pub fn release(p: *Pads) void {
        for (&p.slots) |*s| {
            if (s.id != null) s.state = .{ .connected = true, .family = .xbox };
        }
    }

    /// The controller the game reads this frame.
    pub fn state(p: *const Pads) pad.State {
        return p.slots[p.current].state;
    }
};

// ---------------------------------------------------------------------------------------------- tests

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "buttons, sticks, triggers and the hat arrive as the game's controller state" {
    var p: Pads = .{};
    try expect(!p.state().connected);
    p.apply(.connected, 1017, 0, 0);
    try expect(p.state().connected);
    try expectEqual(pad.Family.xbox, p.state().family);

    // The engine's index 3 is the kernel's BTN_NORTH, which an Xbox controller's X button reports.
    p.apply(.button, 1017, 3, 1);
    try expect(p.state().buttons.contains(.x) and !p.state().buttons.contains(.y));
    p.apply(.button, 1017, 3, 0);
    p.apply(.button, 1017, 4, 1);
    try expect(p.state().buttons.contains(.y) and !p.state().buttons.contains(.x));
    p.apply(.button, 1017, 7, 1);
    p.apply(.button, 1017, 8, 1);
    try expect(p.state().buttons.contains(.back) and p.state().buttons.contains(.start));

    // Sticks: the kernel's y grows downward, the game's upward.
    p.apply(.axis, 1017, 6, -1.0);
    p.apply(.axis, 1017, 5, 0.25);
    try expectEqual([2]f32{ 0.25, 1.0 }, p.state().left);
    p.apply(.axis, 1017, 8, 0.5);
    try expectEqual([2]f32{ 0, -0.5 }, p.state().right);
    p.apply(.axis, 1017, 3, 0.75);
    p.apply(.axis, 1017, 4, 1.0);
    try expectEqual(@as(f32, 0.75), p.state().lt);
    try expectEqual(@as(f32, 1.0), p.state().rt);

    // The hat: up is negative, and letting go releases both directions of an axis.
    p.apply(.axis, 1017, 2, -1);
    p.apply(.axis, 1017, 1, 1);
    try expect(p.state().buttons.contains(.dpad_up) and p.state().buttons.contains(.dpad_right));
    p.apply(.axis, 1017, 2, 0);
    p.apply(.axis, 1017, 1, -1);
    try expect(!p.state().buttons.contains(.dpad_up) and p.state().buttons.contains(.dpad_left) and !p.state().buttons.contains(.dpad_right));

    // A report that is not a number is an idle axis, and an index the game has no use for is ignored.
    p.apply(.axis, 1017, 5, std.math.nan(f32));
    try expectEqual(@as(f32, 0), p.state().left[0]);
    p.apply(.button, 1017, 11, 1);
    p.apply(.axis, 1017, 40, 1);
}

test "the controller touched last is the one the game reads, and losing it is seen" {
    var p: Pads = .{};
    p.apply(.connected, 1, 0, 0);
    p.apply(.connected, 2, 0, 0);
    p.apply(.button, 1, 1, 1);
    try expect(p.state().buttons.contains(.a));
    // The second controller is touched: the game follows it, and the first one's held button is not its.
    p.apply(.button, 2, 2, 1);
    try expect(p.state().buttons.contains(.b) and !p.state().buttons.contains(.a));
    // A drifting stick on the first does not take the game back; a firm push does.
    p.apply(.axis, 1, 5, 0.3);
    try expect(p.state().buttons.contains(.b));
    p.apply(.axis, 1, 5, 0.9);
    try expect(p.state().buttons.contains(.a));

    // The controller in use goes away: the game sees no controller, although another is connected, and
    // so pauses. Touching the other takes it up.
    p.apply(.disconnected, 1, 0, 0);
    try expect(!p.state().connected);
    p.apply(.button, 2, 2, 0);
    try expect(p.state().connected and !p.state().buttons.contains(.b));

    // The lost one comes back under a new id and is adopted into the free slot; a third is not.
    p.apply(.connected, 7, 0, 0);
    p.apply(.button, 9, 1, 1);
    p.apply(.button, 7, 1, 1);
    try expect(p.state().buttons.contains(.a));
}

test "a suspended game forgets what was held but not which controllers are there" {
    var p: Pads = .{};
    p.apply(.button, 5, 1, 1);
    p.apply(.axis, 5, 4, 1.0);
    p.release();
    try expect(p.state().connected);
    try expectEqual(@as(usize, 0), p.state().buttons.count());
    try expectEqual(@as(f32, 0), p.state().rt);
}
