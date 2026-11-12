//! Which controller the game listens to on Windows, where there are two ways to hear one: XInput, and the
//! Sony controllers read directly (`pshid.zig`). The game has one pilot, so one controller is current at a
//! time, the one touched last, as on macOS. The complication is a controller that shows up both ways at
//! once: DS4Windows and similar tools create an XInput controller that mirrors a DualShock or DualSense
//! and may leave the real device visible, and then every press would arrive twice, a frame apart. This
//! file decides, as pure code that the tests drive frame by frame.

const std = @import("std");
const pad = @import("../pad.zig");

pub const max_xinput = 4;
pub const max_direct = 4;

/// The controllers visible this frame. An entry that is not connected is an empty slot.
pub const Seen = struct {
    xinput: [max_xinput]pad.State = @splat(.{}),
    direct: [max_direct]pad.State = @splat(.{}),
};

pub const Source = union(enum) {
    xinput: u8,
    direct: u8,
};

/// A controller is in use when a button is down, a trigger is past a light pull, or a stick is well off
/// centre. The thresholds are above the rest position of a worn stick and below any deliberate input;
/// they only decide which controller is current, never what the game does with it.
pub fn busy(st: pad.State) bool {
    if (!st.connected) return false;
    if (st.buttons.count() > 0) return true;
    if (st.lt > 0.3 or st.rt > 0.3) return true;
    const t = 0.4 * 0.4;
    return st.left[0] * st.left[0] + st.left[1] * st.left[1] > t or st.right[0] * st.right[0] + st.right[1] * st.right[1] > t;
}

pub const Selector = struct {
    current: ?Source = null,
    /// An XInput controller has been seen in use in the same frame as a directly read one, which is what
    /// a mirror looks like. While this holds, the directly read controllers stand down.
    mirrored: bool = false,
    /// Seconds a directly read controller has been in use with every XInput controller idle, which a
    /// mirror cannot do for longer than its lag.
    solo: f32 = 0,

    /// How long a directly read controller must be used alone before a suspected mirror is ruled out.
    pub const solo_limit: f32 = 1.0;

    /// The current controller's state this frame, or a disconnected state if there is none.
    pub fn pick(sel: *Selector, seen: *const Seen, dt: f32) pad.State {
        var any_xinput = false;
        var xinput_busy = false;
        var direct_busy = false;
        for (seen.xinput) |st| {
            any_xinput = any_xinput or st.connected;
            xinput_busy = xinput_busy or busy(st);
        }
        for (seen.direct) |st| direct_busy = direct_busy or busy(st);

        if (!any_xinput) {
            sel.mirrored = false;
            sel.solo = 0;
        } else if (xinput_busy and direct_busy) {
            sel.mirrored = true;
            sel.solo = 0;
        } else if (sel.mirrored) {
            if (direct_busy) sel.solo += dt else if (xinput_busy) sel.solo = 0;
            if (sel.solo > solo_limit) {
                sel.mirrored = false;
                sel.solo = 0;
            }
        }

        // The current controller stays current while it is there and allowed.
        if (sel.current) |cur| {
            const st = stateOf(seen, cur);
            if (!st.connected or (cur == .direct and sel.mirrored)) sel.current = null;
        }
        // Another one takes over when it is in use and the current one is not. XInput is looked at
        // first, so when both kinds are pressed in the same frame XInput wins.
        const cur_busy = if (sel.current) |cur| busy(stateOf(seen, cur)) else false;
        if (!cur_busy) {
            if (firstWhere(seen, sel.mirrored, true)) |src| sel.current = src;
        }
        // With nothing current and nothing in use, the first controller attached is reported, so the
        // game knows one is there.
        if (sel.current == null) sel.current = firstWhere(seen, sel.mirrored, false);
        return if (sel.current) |cur| stateOf(seen, cur) else .{};
    }

    fn stateOf(seen: *const Seen, src: Source) pad.State {
        return switch (src) {
            .xinput => |i| seen.xinput[i],
            .direct => |i| seen.direct[i],
        };
    }

    fn firstWhere(seen: *const Seen, mirrored: bool, want_busy: bool) ?Source {
        for (seen.xinput, 0..) |st, i| {
            if (if (want_busy) busy(st) else st.connected) return .{ .xinput = @intCast(i) };
        }
        if (mirrored) return null;
        for (seen.direct, 0..) |st, i| {
            if (if (want_busy) busy(st) else st.connected) return .{ .direct = @intCast(i) };
        }
        return null;
    }
};

// ---------------------------------------------------------------------------- tests

const frame: f32 = 1.0 / 60.0;

fn xbox(buttons: []const pad.Button) pad.State {
    var st: pad.State = .{ .connected = true, .family = .xbox };
    for (buttons) |b| st.set(b, true);
    return st;
}

fn sony(buttons: []const pad.Button) pad.State {
    var st: pad.State = .{ .connected = true, .family = .playstation };
    for (buttons) |b| st.set(b, true);
    return st;
}

test "what counts as a controller in use" {
    try std.testing.expect(!busy(.{}));
    try std.testing.expect(!busy(xbox(&.{})));
    try std.testing.expect(busy(xbox(&.{.a})));
    try std.testing.expect(!busy(.{ .connected = true, .left = .{ 0.2, -0.2 }, .lt = 0.1 }));
    try std.testing.expect(busy(.{ .connected = true, .right = .{ 0, -0.6 } }));
    try std.testing.expect(busy(.{ .connected = true, .rt = 0.5 }));
    try std.testing.expect(!busy(.{ .connected = false, .rt = 1 }));
}

test "with one controller attached, that controller is the one read" {
    var sel: Selector = .{};
    var seen: Seen = .{};
    try std.testing.expect(!sel.pick(&seen, frame).connected);
    seen.xinput[1] = xbox(&.{});
    try std.testing.expectEqual(pad.Family.xbox, sel.pick(&seen, frame).family);
    seen.xinput[1] = .{};
    try std.testing.expect(!sel.pick(&seen, frame).connected);
    seen.direct[0] = sony(&.{.x});
    const st = sel.pick(&seen, frame);
    try std.testing.expect(st.family == .playstation and st.buttons.contains(.x));
}

test "with two different controllers, the one touched last is current and stays current" {
    var sel: Selector = .{};
    var seen: Seen = .{};
    seen.xinput[0] = xbox(&.{});
    seen.direct[0] = sony(&.{});
    try std.testing.expectEqual(pad.Family.xbox, sel.pick(&seen, frame).family);
    // The DualSense is picked up and used for two seconds while the Xbox controller lies idle.
    seen.direct[0] = sony(&.{.a});
    for (0..120) |_| try std.testing.expectEqual(pad.Family.playstation, sel.pick(&seen, frame).family);
    try std.testing.expect(!sel.mirrored);
    // Let go: it is still the current one.
    seen.direct[0] = sony(&.{});
    try std.testing.expectEqual(pad.Family.playstation, sel.pick(&seen, frame).family);
    // The Xbox controller is touched: it takes over, and keeps the role after it is released.
    seen.xinput[0] = xbox(&.{.b});
    try std.testing.expectEqual(pad.Family.xbox, sel.pick(&seen, frame).family);
    seen.xinput[0] = xbox(&.{});
    try std.testing.expectEqual(pad.Family.xbox, sel.pick(&seen, frame).family);
}

/// Feeds a mirrored pair through the selector and the game's own filter, and counts the presses of `a`
/// the game would see. `lead` is how many frames the directly read report arrives before its XInput copy
/// (negative: after).
fn pressesThroughMirror(lead: i32, taps: usize, hold_frames: usize) !struct { presses: usize, playstation_after_first: bool } {
    var sel: Selector = .{};
    var filter: pad.Filter = .{};
    var seen: Seen = .{};
    var presses: usize = 0;
    var playstation_after_first = false;
    const lag: usize = @abs(lead);
    const period = hold_frames + 30;
    const total = taps * period + 60;
    for (0..total) |f| {
        const down = struct {
            fn at(index: usize, start_delay: usize, per: usize, hold: usize, n: usize) bool {
                if (index < start_delay) return false;
                const t = index - start_delay;
                return t / per < n and t % per < hold;
            }
        }.at;
        const direct_delay: usize = if (lead >= 0) 0 else lag;
        const xinput_delay: usize = if (lead >= 0) lag else 0;
        seen.direct[0] = if (down(f, 10 + direct_delay, period, hold_frames, taps)) sony(&.{.a}) else sony(&.{});
        seen.xinput[0] = if (down(f, 10 + xinput_delay, period, hold_frames, taps)) xbox(&.{.a}) else xbox(&.{});
        const st = sel.pick(&seen, frame);
        const sample = filter.update(st, true);
        if (sample.hit(.a)) presses += 1;
        if (f > 10 + period and st.family == .playstation) playstation_after_first = true;
    }
    return .{ .presses = presses, .playstation_after_first = playstation_after_first };
}

test "a mirrored controller is heard once per press, whichever copy arrives first" {
    for ([_]i32{ 0, 1, 2, -1, -2 }) |lead| {
        const r = try pressesThroughMirror(lead, 5, 12);
        try std.testing.expectEqual(@as(usize, 5), r.presses);
        // Once the mirror has shown itself the prompts stay on one family: the XInput copy.
        try std.testing.expect(!r.playstation_after_first);
    }
}

test "a suspected mirror is ruled out when the directly read controller is used alone" {
    var sel: Selector = .{};
    var seen: Seen = .{};
    // Two people press a button on two different controllers in the same frame: it looks like a mirror.
    seen.xinput[0] = xbox(&.{.a});
    seen.direct[0] = sony(&.{.a});
    try std.testing.expectEqual(pad.Family.xbox, sel.pick(&seen, frame).family);
    try std.testing.expect(sel.mirrored);
    // The Xbox controller is put down and the DualSense is flown for a while: after a second of that the
    // suspicion is dropped and the DualSense is heard.
    seen.xinput[0] = xbox(&.{});
    seen.direct[0] = .{ .connected = true, .family = .playstation, .left = .{ 0, 1 } };
    var frames: usize = 0;
    while (sel.pick(&seen, frame).family != .playstation) : (frames += 1) try std.testing.expect(frames < 70);
    try std.testing.expect(frames >= 58);
    try std.testing.expect(!sel.mirrored);
}

test "when the XInput controller goes away, a directly read one that was standing down is heard again" {
    var sel: Selector = .{};
    var seen: Seen = .{};
    seen.xinput[0] = xbox(&.{.a});
    seen.direct[0] = sony(&.{.a});
    _ = sel.pick(&seen, frame);
    try std.testing.expect(sel.mirrored);
    seen.xinput[0] = .{};
    const st = sel.pick(&seen, frame);
    try std.testing.expect(st.family == .playstation and st.buttons.contains(.a));
    try std.testing.expect(!sel.mirrored);
    // And with every controller gone, nothing is reported.
    seen.direct[0] = .{};
    try std.testing.expect(!sel.pick(&seen, frame).connected);
}
