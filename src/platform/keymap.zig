//! Hardware key codes to `platform.Key` and back, for both backends. These are tables and nothing else, so
//! they are tested on whatever machine builds the game.
//!
//! Both code spaces name a position on the keyboard, not a character: a macOS virtual key code and a PC
//! scan code stay the same when the user switches layout, which is what keeps `W A S D` a cluster under
//! the left hand on AZERTY, Dvorak or a Ukrainian layout.

const std = @import("std");
const Key = @import("../platform.zig").Key;

/// macOS virtual key codes (`kVK_ANSI_A` and the rest, from Carbon's Events.h).
const mac_codes = std.enums.EnumArray(Key, u8).init(.{
    .a = 0,
    .s = 1,
    .d = 2,
    .f = 3,
    .h = 4,
    .g = 5,
    .z = 6,
    .x = 7,
    .c = 8,
    .v = 9,
    .b = 11,
    .q = 12,
    .w = 13,
    .e = 14,
    .r = 15,
    .y = 16,
    .t = 17,
    .n1 = 18,
    .n2 = 19,
    .n3 = 20,
    .n4 = 21,
    .n6 = 22,
    .n5 = 23,
    .n9 = 25,
    .n7 = 26,
    .n8 = 28,
    .n0 = 29,
    .o = 31,
    .u = 32,
    .i = 34,
    .p = 35,
    .enter = 36,
    .l = 37,
    .j = 38,
    .k = 40,
    .n = 45,
    .m = 46,
    .tab = 48,
    .space = 49,
    .escape = 53,
    .shift = 56,
    .option = 58,
    .control = 59,
    .left = 123,
    .right = 124,
    .down = 125,
    .up = 126,
});

pub fn toMac(k: Key) u8 {
    return mac_codes.get(k);
}

const mac_table: [128]?Key = blk: {
    var t: [128]?Key = @splat(null);
    for (std.enums.values(Key)) |k| t[mac_codes.get(k)] = k;
    break :blk t;
};

pub fn fromMac(code: u16) ?Key {
    return if (code < mac_table.len) mac_table[code] else null;
}

/// A PC scan code (set 1, the make code Windows reports in a key message's lParam) and whether it came
/// with the E0 prefix, which is what tells the arrow keys from the numeric keypad.
pub const Scan = struct { code: u8, extended: bool = false };

/// The scan code a key is posted with. Shift, Alt and Ctrl each have a second key that maps to the same
/// `Key`; see `fromScan`.
const scan_codes = std.enums.EnumArray(Key, Scan).init(.{
    .a = .{ .code = 0x1E },
    .s = .{ .code = 0x1F },
    .d = .{ .code = 0x20 },
    .f = .{ .code = 0x21 },
    .h = .{ .code = 0x23 },
    .g = .{ .code = 0x22 },
    .z = .{ .code = 0x2C },
    .x = .{ .code = 0x2D },
    .c = .{ .code = 0x2E },
    .v = .{ .code = 0x2F },
    .b = .{ .code = 0x30 },
    .q = .{ .code = 0x10 },
    .w = .{ .code = 0x11 },
    .e = .{ .code = 0x12 },
    .r = .{ .code = 0x13 },
    .y = .{ .code = 0x15 },
    .t = .{ .code = 0x14 },
    .n1 = .{ .code = 0x02 },
    .n2 = .{ .code = 0x03 },
    .n3 = .{ .code = 0x04 },
    .n4 = .{ .code = 0x05 },
    .n6 = .{ .code = 0x07 },
    .n5 = .{ .code = 0x06 },
    .n9 = .{ .code = 0x0A },
    .n7 = .{ .code = 0x08 },
    .n8 = .{ .code = 0x09 },
    .n0 = .{ .code = 0x0B },
    .o = .{ .code = 0x18 },
    .u = .{ .code = 0x16 },
    .i = .{ .code = 0x17 },
    .p = .{ .code = 0x19 },
    .enter = .{ .code = 0x1C },
    .l = .{ .code = 0x26 },
    .j = .{ .code = 0x24 },
    .k = .{ .code = 0x25 },
    .n = .{ .code = 0x31 },
    .m = .{ .code = 0x32 },
    .tab = .{ .code = 0x0F },
    .space = .{ .code = 0x39 },
    .escape = .{ .code = 0x01 },
    .shift = .{ .code = 0x2A },
    .option = .{ .code = 0x38 },
    .control = .{ .code = 0x1D },
    .left = .{ .code = 0x4B, .extended = true },
    .right = .{ .code = 0x4D, .extended = true },
    .down = .{ .code = 0x50, .extended = true },
    .up = .{ .code = 0x48, .extended = true },
});

pub fn toScan(k: Key) Scan {
    return scan_codes.get(k);
}

/// The key at a scan code, or null for one the game does not bind. Right Shift, right Alt and right Ctrl
/// count as their left twins, as they do on macOS, where the modifier flags do not say which side. The
/// keypad is deliberately left out: its Enter and its arrows (2 4 6 8 without Num Lock) are separate keys
/// on macOS too, and are not bound there.
pub fn fromScan(code: u8, extended: bool) ?Key {
    if (extended) return switch (code) {
        0x4B => .left,
        0x4D => .right,
        0x50 => .down,
        0x48 => .up,
        0x38 => .option,
        0x1D => .control,
        else => null,
    };
    if (code == 0x36) return .shift;
    return plain_scan_table[code];
}

const plain_scan_table: [256]?Key = blk: {
    var t: [256]?Key = @splat(null);
    for (std.enums.values(Key)) |k| {
        const s = scan_codes.get(k);
        if (!s.extended) t[s.code] = k;
    }
    break :blk t;
};

test "every key has a macOS code of its own, and the codes are the ones the game shipped with" {
    for (std.enums.values(Key)) |k| try std.testing.expectEqual(@as(?Key, k), fromMac(toMac(k)));
    // Spot checks against Events.h: the positions, not the alphabet, are what is numbered.
    try std.testing.expectEqual(@as(u8, 13), toMac(.w));
    try std.testing.expectEqual(@as(u8, 0), toMac(.a));
    try std.testing.expectEqual(@as(u8, 49), toMac(.space));
    try std.testing.expectEqual(@as(u8, 126), toMac(.up));
    try std.testing.expectEqual(@as(?Key, null), fromMac(10)); // the ISO section key
    try std.testing.expectEqual(@as(?Key, null), fromMac(76)); // keypad Enter
    try std.testing.expectEqual(@as(?Key, null), fromMac(300));
}

test "every key has a scan code of its own and reads back from it" {
    for (std.enums.values(Key)) |k| {
        const s = toScan(k);
        try std.testing.expectEqual(@as(?Key, k), fromScan(s.code, s.extended));
    }
}

test "scan codes are positions: the WASD cluster, the number row and the arrows" {
    // The second and third letter rows of a PC keyboard, left to right, are 0x10.. and 0x1E..
    try std.testing.expectEqual(@as(?Key, .q), fromScan(0x10, false));
    try std.testing.expectEqual(@as(?Key, .w), fromScan(0x11, false));
    try std.testing.expectEqual(@as(?Key, .e), fromScan(0x12, false));
    try std.testing.expectEqual(@as(?Key, .a), fromScan(0x1E, false));
    try std.testing.expectEqual(@as(?Key, .s), fromScan(0x1F, false));
    try std.testing.expectEqual(@as(?Key, .d), fromScan(0x20, false));
    // 1 to 0 are consecutive from 0x02.
    const row = [_]Key{ .n1, .n2, .n3, .n4, .n5, .n6, .n7, .n8, .n9, .n0 };
    for (row, 0..) |k, i| try std.testing.expectEqual(@as(?Key, k), fromScan(@intCast(0x02 + i), false));
    try std.testing.expectEqual(@as(?Key, .escape), fromScan(0x01, false));
    try std.testing.expectEqual(@as(?Key, .tab), fromScan(0x0F, false));
    try std.testing.expectEqual(@as(?Key, .enter), fromScan(0x1C, false));
    try std.testing.expectEqual(@as(?Key, .space), fromScan(0x39, false));
}

test "the arrows are the extended codes; the same codes without the prefix are the keypad and unbound" {
    try std.testing.expectEqual(@as(?Key, .up), fromScan(0x48, true));
    try std.testing.expectEqual(@as(?Key, .down), fromScan(0x50, true));
    try std.testing.expectEqual(@as(?Key, .left), fromScan(0x4B, true));
    try std.testing.expectEqual(@as(?Key, .right), fromScan(0x4D, true));
    for ([_]u8{ 0x48, 0x50, 0x4B, 0x4D }) |c| try std.testing.expectEqual(@as(?Key, null), fromScan(c, false));
    try std.testing.expectEqual(@as(?Key, null), fromScan(0x1C, true)); // keypad Enter
}

test "both Shift, Alt and Ctrl keys are one key each" {
    try std.testing.expectEqual(@as(?Key, .shift), fromScan(0x2A, false));
    try std.testing.expectEqual(@as(?Key, .shift), fromScan(0x36, false));
    try std.testing.expectEqual(@as(?Key, .option), fromScan(0x38, false));
    try std.testing.expectEqual(@as(?Key, .option), fromScan(0x38, true));
    try std.testing.expectEqual(@as(?Key, .control), fromScan(0x1D, false));
    try std.testing.expectEqual(@as(?Key, .control), fromScan(0x1D, true));
}

test "keys the game does not bind have no Key" {
    try std.testing.expectEqual(@as(?Key, null), fromScan(0x57, false)); // F11
    try std.testing.expectEqual(@as(?Key, null), fromScan(0x3B, false)); // F1
    try std.testing.expectEqual(@as(?Key, null), fromScan(0x5B, true)); // left Windows key
    try std.testing.expectEqual(@as(?Key, null), fromScan(0x27, false)); // semicolon
}
