//! DualShock 4 and DualSense input reports, read without a driver. Windows has no built-in mapping for
//! Sony's controllers: they appear as generic HID game pads, and a game that wants them outside Steam
//! (which would present them through XInput) has to read the reports itself. This file is the pure half
//! of that: which devices are recognised, and how each report layout becomes a `pad.State`. The layouts
//! are the ones documented by the Linux kernel's hid-playstation and hid-sony drivers and by SDL's
//! HIDAPI drivers. `platform/windows.zig` feeds it the bytes Raw Input delivers.
//!
//! This path has been checked against those documented layouts in the tests below and has not been run
//! against a physical controller.

const std = @import("std");
const pad = @import("../pad.zig");

pub const sony_vid: u16 = 0x054C;

pub const Model = enum {
    dualshock4,
    dualsense,

    pub fn name(m: Model) []const u8 {
        return switch (m) {
            .dualshock4 => "DualShock 4",
            .dualsense => "DualSense",
        };
    }
};

/// The Sony controllers this file knows how to read, by USB product id. Bluetooth reports the same ids.
pub fn identify(vid: u32, pid: u32) ?Model {
    if (vid != sony_vid) return null;
    return switch (pid) {
        0x05C4, // DualShock 4, first model (CUH-ZCT1)
        0x09CC, // DualShock 4, second model (CUH-ZCT2)
        0x0BA0, // DualShock 4 USB wireless adaptor
        => .dualshock4,
        0x0CE6, // DualSense
        0x0DF2, // DualSense Edge
        => .dualsense,
        else => null,
    };
}

/// The buttons, sticks and triggers of one report, located by where the block starts. Both controllers
/// send the same three button bytes; what differs between layouts is where the sticks, the triggers and
/// that block sit.
const Layout = struct {
    /// Offset of left stick x; left y, right x and right y follow it.
    sticks: usize,
    /// Offsets of the L2 and R2 analog values.
    l2: usize,
    r2: usize,
    /// Offset of the first of the two button bytes this file reads.
    buttons: usize,
    /// Bytes the report must have for all of the above to be present.
    min_len: usize,
};

/// DualShock 4 over USB, report 0x01 (64 bytes); also the short report 0x01 both controllers send over
/// Bluetooth until a program asks for the full one (10 bytes): sticks at 1 to 4, buttons at 5 to 7,
/// triggers at 8 and 9.
const ds4_usb: Layout = .{ .sticks = 1, .buttons = 5, .l2 = 8, .r2 = 9, .min_len = 10 };
/// DualShock 4 over Bluetooth, report 0x11 (78 bytes): two bytes of flags, then the USB layout.
const ds4_bt: Layout = .{ .sticks = 3, .buttons = 7, .l2 = 10, .r2 = 11, .min_len = 12 };
/// DualSense over USB, report 0x01 (64 bytes): sticks at 1 to 4, triggers at 5 and 6, a sequence number
/// at 7, buttons at 8 to 10.
const ds5_usb: Layout = .{ .sticks = 1, .l2 = 5, .r2 = 6, .buttons = 8, .min_len = 10 };
/// DualSense over Bluetooth, report 0x31 (78 bytes): one byte of flags, then the USB layout.
const ds5_bt: Layout = .{ .sticks = 2, .l2 = 6, .r2 = 7, .buttons = 9, .min_len = 11 };

/// The layout of `report`, whose first byte is the report id, or null for a report that carries no
/// controls (the controllers also send feature and status reports).
fn layoutOf(model: Model, report: []const u8) ?Layout {
    if (report.len == 0) return null;
    const id = report[0];
    const layout: Layout = switch (model) {
        .dualshock4 => switch (id) {
            0x01 => ds4_usb,
            0x11 => ds4_bt,
            else => return null,
        },
        .dualsense => switch (id) {
            // Report 0x01 is the full USB report at 64 bytes and the short Bluetooth one, which has the
            // DualShock 4's arrangement, at 10. A 78-byte 0x01 is the short report padded to the
            // Bluetooth packet size.
            0x01 => if (report.len == 10 or report.len == 78) ds4_usb else ds5_usb,
            0x31 => ds5_bt,
            else => return null,
        },
    };
    return if (report.len >= layout.min_len) layout else null;
}

fn stick(v: u8) f32 {
    // 0 to 255 with the centre between 127 and 128.
    return (@as(f32, @floatFromInt(v)) - 127.5) / 127.5;
}

/// One input report as a `pad.State`, or null if it is not a report of controls. No dead zone is applied;
/// a stick at rest reads within a few thousandths of zero, well inside the neutral side's dead zone.
pub fn parse(model: Model, report: []const u8) ?pad.State {
    const l = layoutOf(model, report) orelse return null;
    var st: pad.State = .{ .connected = true, .family = .playstation };
    // HID's y axis grows downward; the game's grows upward.
    st.left = .{ stick(report[l.sticks]), -stick(report[l.sticks + 1]) };
    st.right = .{ stick(report[l.sticks + 2]), -stick(report[l.sticks + 3]) };
    st.lt = @as(f32, @floatFromInt(report[l.l2])) / 255.0;
    st.rt = @as(f32, @floatFromInt(report[l.r2])) / 255.0;

    const b0 = report[l.buttons];
    const b1 = report[l.buttons + 1];
    // Low nibble: the d-pad as a hat switch, clockwise from up, 8 when released.
    const hat = b0 & 0x0F;
    st.set(.dpad_up, hat == 7 or hat == 0 or hat == 1);
    st.set(.dpad_right, hat == 1 or hat == 2 or hat == 3);
    st.set(.dpad_down, hat == 3 or hat == 4 or hat == 5);
    st.set(.dpad_left, hat == 5 or hat == 6 or hat == 7);
    st.set(.x, b0 & 0x10 != 0); // Square
    st.set(.a, b0 & 0x20 != 0); // Cross
    st.set(.b, b0 & 0x40 != 0); // Circle
    st.set(.y, b0 & 0x80 != 0); // Triangle
    st.set(.lb, b1 & 0x01 != 0); // L1
    st.set(.rb, b1 & 0x02 != 0); // R1
    // Bits 2 and 3 are L2 and R2 as switches. The analog values are read instead, so the press point is
    // the game's on every controller.
    st.set(.back, b1 & 0x10 != 0); // Share on a DualShock 4, Create on a DualSense
    st.set(.start, b1 & 0x20 != 0); // Options
    st.set(.ls, b1 & 0x40 != 0); // L3
    st.set(.rs, b1 & 0x80 != 0); // R3
    return st;
}

/// Whether Steam has asked for this device to be left alone. When Steam Input takes a controller over it
/// gives the game an XInput controller in its place and sets SDL_GAMECONTROLLER_IGNORE_DEVICES to the
/// ids of the real one ("0x054C/0x0CE6,0x054C/0x09CC"), so that a game reading the device directly does
/// not hear every press twice. `list` is that variable's value.
pub fn ignoredBy(list: []const u8, vid: u32, pid: u32) bool {
    var it = std.mem.tokenizeAny(u8, list, ", ");
    while (it.next()) |entry| {
        const slash = std.mem.indexOfScalar(u8, entry, '/') orelse continue;
        const v = std.fmt.parseInt(u32, entry[0..slash], 0) catch continue;
        const p = std.fmt.parseInt(u32, entry[slash + 1 ..], 0) catch continue;
        if (v == vid and p == pid) return true;
    }
    return false;
}

// ---------------------------------------------------------------------------- tests

fn expectButtons(st: pad.State, want: []const pad.Button) !void {
    var set: pad.Buttons = .empty;
    for (want) |b| set.insert(b);
    try std.testing.expectEqual(set, st.buttons);
}

/// A DualShock 4 USB report at rest: sticks centred, hat released.
fn ds4Usb() [64]u8 {
    var r: [64]u8 = @splat(0);
    r[0] = 0x01;
    r[1..5].* = .{ 0x80, 0x80, 0x80, 0x80 };
    r[5] = 0x08;
    return r;
}

/// A DualSense USB report at rest.
fn ds5Usb() [64]u8 {
    var r: [64]u8 = @splat(0);
    r[0] = 0x01;
    r[1..5].* = .{ 0x80, 0x80, 0x80, 0x80 };
    r[8] = 0x08;
    return r;
}

/// A report of `len` bytes that is all zero after its id.
fn zeroReport(comptime id: u8, comptime len: usize) [len]u8 {
    var r: [len]u8 = @splat(0);
    r[0] = id;
    return r;
}

test "the known Sony controllers are recognised by vendor and product id" {
    try std.testing.expectEqual(@as(?Model, .dualshock4), identify(0x054C, 0x05C4));
    try std.testing.expectEqual(@as(?Model, .dualshock4), identify(0x054C, 0x09CC));
    try std.testing.expectEqual(@as(?Model, .dualshock4), identify(0x054C, 0x0BA0));
    try std.testing.expectEqual(@as(?Model, .dualsense), identify(0x054C, 0x0CE6));
    try std.testing.expectEqual(@as(?Model, .dualsense), identify(0x054C, 0x0DF2));
    try std.testing.expectEqual(@as(?Model, null), identify(0x054C, 0x0268)); // DualShock 3: another protocol
    try std.testing.expectEqual(@as(?Model, null), identify(0x045E, 0x0CE6)); // right product, wrong vendor
}

test "DualShock 4 over USB: sticks, triggers, face buttons, shoulders, menu buttons" {
    var r = ds4Usb();
    const idle = parse(.dualshock4, &r).?;
    try std.testing.expect(idle.connected and idle.family == .playstation);
    try expectButtons(idle, &.{});
    for ([_]f32{ idle.left[0], idle.left[1], idle.right[0], idle.right[1] }) |v| try std.testing.expect(@abs(v) < 0.005);
    try std.testing.expectEqual(@as(f32, 0), idle.lt);

    // Left stick hard right and up (y is 0 at the top), right stick hard left and down.
    r[1] = 0xFF;
    r[2] = 0x00;
    r[3] = 0x00;
    r[4] = 0xFF;
    r[8] = 0xFF;
    r[9] = 0x33;
    var st = parse(.dualshock4, &r).?;
    try std.testing.expectEqual([2]f32{ 1, 1 }, st.left);
    try std.testing.expectEqual([2]f32{ -1, -1 }, st.right);
    try std.testing.expectEqual(@as(f32, 1), st.lt);
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), st.rt, 1e-6);

    r = ds4Usb();
    r[5] = 0x08 | 0x20; // Cross
    try expectButtons(parse(.dualshock4, &r).?, &.{.a});
    r[5] = 0x08 | 0x40; // Circle
    try expectButtons(parse(.dualshock4, &r).?, &.{.b});
    r[5] = 0x08 | 0x10; // Square
    try expectButtons(parse(.dualshock4, &r).?, &.{.x});
    r[5] = 0x08 | 0x80; // Triangle
    try expectButtons(parse(.dualshock4, &r).?, &.{.y});
    r[5] = 0x08;
    r[6] = 0x01 | 0x02; // L1, R1
    try expectButtons(parse(.dualshock4, &r).?, &.{ .lb, .rb });
    r[6] = 0x10; // Share
    try expectButtons(parse(.dualshock4, &r).?, &.{.back});
    r[6] = 0x20; // Options
    try expectButtons(parse(.dualshock4, &r).?, &.{.start});
    r[6] = 0x40 | 0x80; // L3, R3
    try expectButtons(parse(.dualshock4, &r).?, &.{ .ls, .rs });
    // L2 and R2 as switches set no button: the analog value decides.
    r[6] = 0x04 | 0x08;
    try expectButtons(parse(.dualshock4, &r).?, &.{});
    // The PS and touchpad buttons in the third byte are not the game's.
    r[6] = 0;
    r[7] = 0x03;
    try expectButtons(parse(.dualshock4, &r).?, &.{});
    st = parse(.dualshock4, &r).?;
    try std.testing.expect(st.connected);
}

test "the d-pad is a hat switch: eight directions clockwise from up, and released" {
    const want = [9][]const pad.Button{
        &.{.dpad_up},
        &.{ .dpad_up, .dpad_right },
        &.{.dpad_right},
        &.{ .dpad_right, .dpad_down },
        &.{.dpad_down},
        &.{ .dpad_down, .dpad_left },
        &.{.dpad_left},
        &.{ .dpad_left, .dpad_up },
        &.{},
    };
    for (want, 0..) |buttons, hat| {
        var r4 = ds4Usb();
        r4[5] = @intCast(hat);
        try expectButtons(parse(.dualshock4, &r4).?, buttons);
        var r5 = ds5Usb();
        r5[8] = @intCast(hat);
        try expectButtons(parse(.dualsense, &r5).?, buttons);
    }
    // Values past 8 do not occur; they read as released rather than as a direction.
    var r = ds4Usb();
    r[5] = 0x0F;
    try expectButtons(parse(.dualshock4, &r).?, &.{});
}

test "DualShock 4 over Bluetooth: report 0x11 is the USB layout two bytes further on" {
    var r: [78]u8 = @splat(0);
    r[0] = 0x11;
    r[1] = 0xC0;
    r[3..7].* = .{ 0xFF, 0x80, 0x80, 0x00 };
    r[7] = 0x02 | 0x20; // d-pad right, Cross
    r[8] = 0x20; // Options
    r[10] = 0x80;
    r[11] = 0xFF;
    const st = parse(.dualshock4, &r).?;
    try std.testing.expectEqual(@as(f32, 1), st.left[0]);
    try std.testing.expect(@abs(st.left[1]) < 0.005);
    try std.testing.expectEqual(@as(f32, 1), st.right[1]);
    try expectButtons(st, &.{ .dpad_right, .a, .start });
    try std.testing.expectApproxEqAbs(@as(f32, 0.502), st.lt, 1e-3);
    try std.testing.expectEqual(@as(f32, 1), st.rt);
}

test "DualSense over USB: triggers come before the buttons" {
    var r = ds5Usb();
    r[1] = 0x00; // left stick hard left
    r[2] = 0xFF; // and down
    r[5] = 0xFF; // L2
    r[6] = 0x40; // R2
    r[7] = 0x9A; // sequence number: must not be read as anything
    r[8] = 0x08 | 0x80; // Triangle
    r[9] = 0x10 | 0x01; // Create, L1
    r[10] = 0x07; // PS, touchpad, mute: not the game's
    const st = parse(.dualsense, &r).?;
    try std.testing.expect(st.family == .playstation);
    try std.testing.expectEqual([2]f32{ -1, -1 }, st.left);
    try std.testing.expectEqual(@as(f32, 1), st.lt);
    try std.testing.expectApproxEqAbs(@as(f32, 0.251), st.rt, 1e-3);
    try expectButtons(st, &.{ .y, .back, .lb });
}

test "DualSense over Bluetooth: report 0x31 is the USB layout one byte further on" {
    var r: [78]u8 = @splat(0);
    r[0] = 0x31;
    r[1] = 0x01;
    r[2..6].* = .{ 0x80, 0x80, 0xFF, 0x00 };
    r[6] = 0x00;
    r[7] = 0xFF;
    r[9] = 0x04 | 0x40; // d-pad down, Circle
    r[10] = 0x80 | 0x20; // R3, Options
    const st = parse(.dualsense, &r).?;
    try std.testing.expectEqual([2]f32{ 1, 1 }, st.right);
    try std.testing.expectEqual(@as(f32, 0), st.lt);
    try std.testing.expectEqual(@as(f32, 1), st.rt);
    try expectButtons(st, &.{ .dpad_down, .b, .rs, .start });
}

test "the short Bluetooth report has the DualShock 4 arrangement on both controllers" {
    // Ten bytes: id, four stick bytes, three button bytes, two triggers.
    const r = [10]u8{ 0x01, 0x80, 0x00, 0x80, 0x80, 0x08 | 0x20, 0x02, 0x00, 0x00, 0xFF };
    inline for (.{ Model.dualshock4, Model.dualsense }) |model| {
        const st = parse(model, &r).?;
        try std.testing.expectEqual(@as(f32, 1), st.left[1]);
        try std.testing.expectEqual(@as(f32, 1), st.rt);
        try expectButtons(st, &.{ .a, .rb });
    }
    // The same bytes at USB length are a DualSense USB report, where byte 5 is L2 and byte 8 the hat.
    var usb: [64]u8 = @splat(0);
    @memcpy(usb[0..10], &r);
    usb[9] = 0;
    const st = parse(.dualsense, &usb).?;
    try std.testing.expectApproxEqAbs(@as(f32, 0.157), st.lt, 1e-3);
    try expectButtons(st, &.{.dpad_up});
}

test "reports that carry no controls, and truncated ones, are refused" {
    try std.testing.expectEqual(@as(?pad.State, null), parse(.dualshock4, &.{}));
    try std.testing.expectEqual(@as(?pad.State, null), parse(.dualshock4, &.{ 0x01, 0x80, 0x80 }));
    try std.testing.expectEqual(@as(?pad.State, null), parse(.dualshock4, &zeroReport(0x31, 78)));
    try std.testing.expectEqual(@as(?pad.State, null), parse(.dualsense, &zeroReport(0x11, 78)));
    try std.testing.expectEqual(@as(?pad.State, null), parse(.dualsense, &zeroReport(0x31, 10)));
    try std.testing.expectEqual(@as(?pad.State, null), parse(.dualshock4, &zeroReport(0x11, 11)));
    try std.testing.expectEqual(@as(?pad.State, null), parse(.dualsense, &zeroReport(0x05, 41)));
}

test "Steam's ignore list names devices by vendor and product id" {
    const list = "0x054C/0x0CE6,0x054C/0x09CC, 0x28DE/0x11FF";
    try std.testing.expect(ignoredBy(list, 0x054C, 0x0CE6));
    try std.testing.expect(ignoredBy(list, 0x054C, 0x09CC));
    try std.testing.expect(ignoredBy(list, 0x28DE, 0x11FF));
    try std.testing.expect(!ignoredBy(list, 0x054C, 0x05C4));
    try std.testing.expect(!ignoredBy("", 0x054C, 0x0CE6));
    try std.testing.expect(!ignoredBy("garbage,0x054C,/,0x054C/zz", 0x054C, 0x0CE6));
    try std.testing.expect(ignoredBy("0x054c/0x0ce6", 0x054C, 0x0CE6));
}
