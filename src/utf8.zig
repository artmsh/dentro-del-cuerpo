//! UTF-8 helpers for text that is known to be valid (every string in the game is a source literal).

const std = @import("std");

/// Decodes the code point at `i` and advances `i` past it.
pub fn next(s: []const u8, i: *usize) u21 {
    const c = s[i.*];
    if (c < 0x80) {
        i.* += 1;
        return c;
    }
    const n: usize = if (c >= 0xF0) 4 else if (c >= 0xE0) 3 else 2;
    if (i.* + n > s.len) {
        i.* = s.len;
        return '?';
    }
    var cp: u21 = switch (n) {
        2 => c & 0x1F,
        3 => c & 0x0F,
        else => c & 0x07,
    };
    for (1..n) |k| cp = (cp << 6) | (s[i.* + k] & 0x3F);
    i.* += n;
    return cp;
}

/// Number of code points in `s`.
pub fn count(s: []const u8) usize {
    var n: usize = 0;
    for (s) |c| n += @intFromBool((c & 0xC0) != 0x80);
    return n;
}

/// Length in bytes of the first `n` code points of `s` (all of `s` if it has fewer).
pub fn prefixLen(s: []const u8, n: usize) usize {
    var seen: usize = 0;
    for (s, 0..) |c, i| {
        if ((c & 0xC0) == 0x80) continue;
        if (seen == n) return i;
        seen += 1;
    }
    return s.len;
}

/// Code point of the first character, as a slice of `s` (empty if `s` is empty).
pub fn first(s: []const u8) []const u8 {
    return s[0..prefixLen(s, 1)];
}

/// True if a line may be broken at the space `s[i]`. A space before a dash is not a place to break: in
/// Ukrainian, as in English, a dash closes a line and never opens one.
pub fn breakable(s: []const u8, i: usize) bool {
    if (s[i] != ' ') return false;
    const rest = s[i + 1 ..];
    return !(std.mem.startsWith(u8, rest, "—") or std.mem.startsWith(u8, rest, "–"));
}

test "decode Latin, Cyrillic and punctuation" {
    var i: usize = 0;
    const s = "aµ—їҐ’";
    const want = [_]u21{ 'a', 0xB5, 0x2014, 0x457, 0x490, 0x2019 };
    for (want) |w| try std.testing.expectEqual(w, next(s, &i));
    try std.testing.expectEqual(s.len, i);
    try std.testing.expectEqual(@as(usize, 6), count(s));
}

test "prefixes cut on code point boundaries" {
    const s = "Кров — 5 л";
    try std.testing.expectEqualStrings("", s[0..prefixLen(s, 0)]);
    try std.testing.expectEqualStrings("Кро", s[0..prefixLen(s, 3)]);
    try std.testing.expectEqualStrings("Кров —", s[0..prefixLen(s, 6)]);
    try std.testing.expectEqualStrings(s, s[0..prefixLen(s, 99)]);
    try std.testing.expectEqualStrings("К", first(s));
    try std.testing.expectEqualStrings("", first(""));
}

test "a line breaks at a space, but not before a dash" {
    const s = "на кожній — ударник";
    var breaks: usize = 0;
    for (0..s.len) |i| {
        if (breakable(s, i)) breaks += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), breaks);
    try std.testing.expect(!breakable(s, std.mem.indexOf(u8, s, " —").?));
    try std.testing.expect(breakable(s, std.mem.indexOf(u8, s, "— ").? + "—".len));
    try std.testing.expect(!breakable("a – b", 1));
}
