//! XInput: the Windows API every Xbox controller speaks, and that Steam Input uses to present any other
//! controller (a DualSense included) to a game as an Xbox one. This file holds the report layout, the
//! mapping to `pad.State` in both directions, and the polling schedule, all as pure code that is tested on
//! any machine; only `Api.load` touches Windows.

const std = @import("std");
const pad = @import("../pad.zig");
const w = @import("win32.zig");

/// XINPUT_GAMEPAD, as XInput.h lays it out.
pub const Gamepad = extern struct {
    wButtons: u16 = 0,
    bLeftTrigger: u8 = 0,
    bRightTrigger: u8 = 0,
    sThumbLX: i16 = 0,
    sThumbLY: i16 = 0,
    sThumbRX: i16 = 0,
    sThumbRY: i16 = 0,
};

/// XINPUT_STATE.
pub const State = extern struct {
    dwPacketNumber: u32 = 0,
    Gamepad: Gamepad = .{},
};

comptime {
    std.debug.assert(@sizeOf(Gamepad) == 12);
    std.debug.assert(@sizeOf(State) == 16);
}

/// The wButtons bits, with the `pad.Button` each one is.
const button_bits = [_]struct { u16, pad.Button }{
    .{ 0x0001, .dpad_up },
    .{ 0x0002, .dpad_down },
    .{ 0x0004, .dpad_left },
    .{ 0x0008, .dpad_right },
    .{ 0x0010, .start },
    .{ 0x0020, .back },
    .{ 0x0040, .ls },
    .{ 0x0080, .rs },
    .{ 0x0100, .lb },
    .{ 0x0200, .rb },
    .{ 0x1000, .a },
    .{ 0x2000, .b },
    .{ 0x4000, .x },
    .{ 0x8000, .y },
};

fn axis(v: i16) f32 {
    // The range is asymmetric (-32768 to 32767); both ends are full deflection.
    return @max(-1.0, @as(f32, @floatFromInt(v)) / 32767.0);
}

/// One XInput report as a `pad.State`. Nothing is shaped here: XInput's own suggested dead zones are
/// left out because the neutral side applies its own. The family is always Xbox, which is also right for
/// a controller Steam is presenting as one, since Steam then draws Xbox glyphs for it as well.
pub fn toState(g: Gamepad) pad.State {
    var st: pad.State = .{ .connected = true, .family = .xbox };
    st.left = .{ axis(g.sThumbLX), axis(g.sThumbLY) };
    st.right = .{ axis(g.sThumbRX), axis(g.sThumbRY) };
    st.lt = @as(f32, @floatFromInt(g.bLeftTrigger)) / 255.0;
    st.rt = @as(f32, @floatFromInt(g.bRightTrigger)) / 255.0;
    for (button_bits) |e| st.set(e[1], g.wButtons & e[0] != 0);
    return st;
}

/// The report that `toState` reads as `st`, to the resolution of the report: sticks to 1/32767, triggers
/// to 1/255. The tests hold a controller this way.
pub fn fromState(st: pad.State) Gamepad {
    const stick = struct {
        fn f(v: f32) i16 {
            return @intFromFloat(@round(std.math.clamp(v, -1.0, 1.0) * 32767.0));
        }
    }.f;
    const trigger = struct {
        fn f(v: f32) u8 {
            return @intFromFloat(@round(std.math.clamp(v, 0.0, 1.0) * 255.0));
        }
    }.f;
    var g: Gamepad = .{
        .bLeftTrigger = trigger(st.lt),
        .bRightTrigger = trigger(st.rt),
        .sThumbLX = stick(st.left[0]),
        .sThumbLY = stick(st.left[1]),
        .sThumbRX = stick(st.right[0]),
        .sThumbRY = stick(st.right[1]),
    };
    for (button_bits) |e| {
        if (st.buttons.contains(e[1])) g.wButtons |= e[0];
    }
    return g;
}

/// The largest difference `toState(fromState(st))` can have from `st` in a stick or trigger value.
pub const resolution: f32 = 0.5 / 255.0 + 1e-6;

pub const slot_count = 4;

/// Which of the four XInput slots to ask about, and when. A slot with a controller is read every frame.
/// An empty one is expensive to ask about (XInputGetState on an empty slot takes a device enumeration,
/// of the order of a millisecond), so empty slots are probed one per call at most, each after a delay
/// that doubles from `first_retry` to `max_retry` while the slot stays empty. A controller plugged in
/// is therefore picked up within `max_retry` seconds, and four empty slots cost one probe every half
/// second on average.
pub const Poller = struct {
    slots: [slot_count]Slot = @splat(.{}),

    pub const first_retry: f64 = 0.25;
    pub const max_retry: f64 = 2.0;

    pub const Slot = struct {
        connected: bool = false,
        /// Time of the next probe while empty, and the delay that led to it.
        next_probe: f64 = 0,
        retry: f64 = first_retry,
        state: pad.State = .{},
    };

    /// Read the slots that are due. `source.get(slot)` returns the slot's report or null if it is empty.
    pub fn poll(p: *Poller, now: f64, source: anytype) void {
        var probed_empty = false;
        for (&p.slots, 0..) |*s, i| {
            if (!s.connected) {
                if (probed_empty or now < s.next_probe) continue;
                probed_empty = true;
            }
            if (source.get(@intCast(i))) |g| {
                s.connected = true;
                s.retry = first_retry;
                s.state = toState(g);
            } else {
                // A slot that has just emptied is asked again soon, in case the cable was only jogged.
                if (s.connected) s.retry = first_retry else s.retry = @min(max_retry, s.retry * 2);
                s.connected = false;
                s.state = .{};
                s.next_probe = now + s.retry;
            }
        }
    }
};

/// XInputGetState from whichever XInput DLL the system has, loaded at run time so that a machine without
/// one still starts the game, with no controller.
pub const Api = struct {
    get_state: ?*const fn (u32, *State) callconv(w.WINAPI) u32 = null,
    dll: []const u8 = "",

    pub fn load() Api {
        // 1.4 ships with Windows 8 and later; 9.1.0 is the reduced one every Windows has; 1.3 is the
        // DirectX redistributable's.
        const names = [_][]const u8{ "xinput1_4.dll", "xinput9_1_0.dll", "xinput1_3.dll" };
        for (names) |name| {
            var wide: [32]u16 = undefined;
            const wname = w.toWide(&wide, name) orelse continue;
            const module = w.LoadLibraryW(wname.ptr) orelse continue;
            if (w.GetProcAddress(module, "XInputGetState")) |f| return .{ .get_state = @ptrCast(f), .dll = name };
        }
        return .{};
    }

    pub fn get(api: Api, slot: u32) ?Gamepad {
        const f = api.get_state orelse return null;
        var st: State = .{};
        // ERROR_SUCCESS; anything else (ERROR_DEVICE_NOT_CONNECTED is the usual one) is an empty slot.
        if (f(slot, &st) != 0) return null;
        return st.Gamepad;
    }
};

test "every XInput button bit maps to its button, and no other" {
    for (button_bits) |e| {
        const st = toState(.{ .wButtons = e[0] });
        try std.testing.expectEqual(@as(usize, 1), st.buttons.count());
        try std.testing.expect(st.buttons.contains(e[1]));
    }
    // The values from XInput.h, spelled out for the ones the game leans on.
    try std.testing.expect(toState(.{ .wButtons = 0x1000 }).buttons.contains(.a));
    try std.testing.expect(toState(.{ .wButtons = 0x2000 }).buttons.contains(.b));
    try std.testing.expect(toState(.{ .wButtons = 0x4000 }).buttons.contains(.x));
    try std.testing.expect(toState(.{ .wButtons = 0x8000 }).buttons.contains(.y));
    try std.testing.expect(toState(.{ .wButtons = 0x0010 }).buttons.contains(.start));
    try std.testing.expect(toState(.{ .wButtons = 0x0020 }).buttons.contains(.back));
    try std.testing.expect(toState(.{ .wButtons = 0x0100 }).buttons.contains(.lb));
    try std.testing.expect(toState(.{ .wButtons = 0x0200 }).buttons.contains(.rb));
    try std.testing.expect(toState(.{ .wButtons = 0x0040 }).buttons.contains(.ls));
    try std.testing.expect(toState(.{ .wButtons = 0x0080 }).buttons.contains(.rs));
    // The two unassigned bits (0x0400, 0x0800; the guide button is not reported) set nothing.
    try std.testing.expectEqual(@as(usize, 0), toState(.{ .wButtons = 0x0C00 }).buttons.count());
    // The triggers are analog only; their buttons are derived from the values on the neutral side.
    const pulled = toState(.{ .bLeftTrigger = 255, .bRightTrigger = 255 });
    try std.testing.expect(!pulled.buttons.contains(.lt) and !pulled.buttons.contains(.rt));
}

test "sticks and triggers are scaled to the unit range, y up, with both extremes at full deflection" {
    const st = toState(.{ .sThumbLX = 32767, .sThumbLY = -32768, .sThumbRX = -32767, .sThumbRY = 16384, .bLeftTrigger = 255, .bRightTrigger = 51 });
    try std.testing.expectEqual(@as(f32, 1), st.left[0]);
    try std.testing.expectEqual(@as(f32, -1), st.left[1]);
    try std.testing.expectEqual(@as(f32, -1), st.right[0]);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), st.right[1], 1e-4);
    try std.testing.expectEqual(@as(f32, 1), st.lt);
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), st.rt, 1e-6);
    try std.testing.expect(st.connected and st.family == .xbox);
    const idle = toState(.{});
    try std.testing.expectEqual(pad.State{ .connected = true, .family = .xbox }, idle);
}

test "a state written as a report reads back within the report's resolution" {
    var st: pad.State = .{ .connected = true, .family = .xbox, .left = .{ 0.25, -0.5 }, .right = .{ -0.75, 1 }, .lt = 0.5, .rt = 1 };
    for ([_]pad.Button{ .a, .y, .lb, .ls, .dpad_up, .dpad_right, .start }) |b| st.set(b, true);
    const got = toState(fromState(st));
    try std.testing.expectEqual(st.buttons, got.buttons);
    for (0..2) |i| {
        try std.testing.expectApproxEqAbs(st.left[i], got.left[i], resolution);
        try std.testing.expectApproxEqAbs(st.right[i], got.right[i], resolution);
    }
    try std.testing.expectApproxEqAbs(st.lt, got.lt, resolution);
    try std.testing.expectApproxEqAbs(st.rt, got.rt, resolution);
    // Out-of-range input is clamped, not wrapped.
    const wild = fromState(.{ .left = .{ 3, -3 }, .lt = 2, .rt = -1 });
    try std.testing.expectEqual(@as(i16, 32767), wild.sThumbLX);
    try std.testing.expectEqual(@as(i16, -32767), wild.sThumbLY);
    try std.testing.expectEqual(@as(u8, 255), wild.bLeftTrigger);
    try std.testing.expectEqual(@as(u8, 0), wild.bRightTrigger);
}

const FakeBus = struct {
    present: [slot_count]bool = @splat(false),
    calls: [slot_count]u32 = @splat(0),

    pub fn get(bus: *FakeBus, slot: u32) ?Gamepad {
        bus.calls[slot] += 1;
        return if (bus.present[slot]) .{ .wButtons = 0x1000 } else null;
    }
};

test "empty slots are probed with back-off, a connected one every frame" {
    var bus: FakeBus = .{};
    var p: Poller = .{};
    const dt = 1.0 / 60.0;
    var now: f64 = 0;
    // Ten seconds with nothing attached: each slot is asked a handful of times, not six hundred.
    for (0..600) |_| {
        p.poll(now, &bus);
        now += dt;
    }
    var total: u32 = 0;
    for (bus.calls) |c| {
        try std.testing.expect(c >= 4 and c <= 9);
        total += c;
    }
    try std.testing.expect(total <= 30);
    for (p.slots) |s| try std.testing.expect(!s.connected and s.retry == Poller.max_retry);

    // A controller appears in slot 2: found within the longest retry, then read every frame.
    bus.present[2] = true;
    const plugged = now;
    while (!p.slots[2].connected) {
        p.poll(now, &bus);
        now += dt;
        try std.testing.expect(now - plugged <= Poller.max_retry + dt);
    }
    try std.testing.expect(p.slots[2].state.buttons.contains(.a));
    const before = bus.calls[2];
    for (0..60) |_| {
        p.poll(now, &bus);
        now += dt;
    }
    try std.testing.expectEqual(before + 60, bus.calls[2]);

    // It goes away: the state clears at once and the slot is asked again after the short delay.
    bus.present[2] = false;
    p.poll(now, &bus);
    try std.testing.expect(!p.slots[2].connected and !p.slots[2].state.connected);
    try std.testing.expectEqual(Poller.first_retry, p.slots[2].retry);
    bus.present[2] = true;
    const replugged = now;
    while (!p.slots[2].connected) {
        now += dt;
        p.poll(now, &bus);
    }
    try std.testing.expect(now - replugged <= Poller.first_retry + 4 * dt);
}

test "at most one empty slot is probed per call" {
    var bus: FakeBus = .{};
    var p: Poller = .{};
    p.poll(0, &bus);
    var asked: u32 = 0;
    for (bus.calls) |c| asked += c;
    try std.testing.expectEqual(@as(u32, 1), asked);
    // The first four calls go round the four slots, so a controller that was on before launch is
    // found within four frames.
    for (1..4) |i| p.poll(@as(f64, @floatFromInt(i)) / 60.0, &bus);
    for (bus.calls) |c| try std.testing.expectEqual(@as(u32, 1), c);
}
