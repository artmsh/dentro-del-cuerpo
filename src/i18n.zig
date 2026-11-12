//! Languages, bilingual text, and the small formatter the HUD uses for text with numbers in it. Pure data
//! and arithmetic: the simulation imports this, so nothing here may touch rendering or the platform.

const std = @import("std");
const utf8 = @import("utf8.zig");

pub const Lang = enum(u8) {
    en,
    uk,

    pub const count = @typeInfo(Lang).@"enum".field_names.len;
    pub const all = [count]Lang{ .en, .uk };

    /// BCP 47 primary subtag; also the token stored in the save file and accepted by `--lang`.
    pub fn tag(l: Lang) []const u8 {
        return @tagName(l);
    }

    /// The language's name in that language, for the switch on the title and pause screens.
    pub fn endonym(l: Lang) []const u8 {
        return switch (l) {
            .en => "English",
            .uk => "Українська",
        };
    }

    pub fn next(l: Lang) Lang {
        return @enumFromInt((@intFromEnum(l) + 1) % count);
    }

    /// Matches a locale identifier by its primary subtag: "uk", "uk-UA", "UK_ua" and "uk-Cyrl-UA" are
    /// all Ukrainian, "ukr" and "u" are nothing.
    pub fn fromTag(s: []const u8) ?Lang {
        const end = std.mem.indexOfAny(u8, s, "-_.@") orelse s.len;
        for (all) |l| if (std.ascii.eqlIgnoreCase(s[0..end], l.tag())) return l;
        return null;
    }

    /// Picks from the user's languages in order of preference (comma-separated locale identifiers, as the
    /// platform layer reports them): the first one the game has wins, and English is the default.
    pub fn fromPreferences(list: []const u8) Lang {
        var it = std.mem.tokenizeAny(u8, list, ", ;");
        while (it.next()) |item| if (fromTag(item)) |l| return l;
        return .en;
    }

    pub fn decimalSeparator(l: Lang) u8 {
        return switch (l) {
            .en => '.',
            .uk => ',',
        };
    }

    /// Number of plural forms a `{n|…}` selector must list.
    pub fn pluralForms(l: Lang) usize {
        return switch (l) {
            .en => 2,
            .uk => 3,
        };
    }

    /// Which of those forms a whole number takes. English: one, other. Ukrainian: one (1, 21, 101),
    /// few (2–4, 22–24), many (0, 5–20, 25–30, 11–14).
    pub fn pluralIndex(l: Lang, n: u64) usize {
        switch (l) {
            .en => return if (n == 1) 0 else 1,
            .uk => {
                const d = n % 10;
                const h = n % 100;
                if (d == 1 and h != 11) return 0;
                if (d >= 2 and d <= 4 and !(h >= 12 and h <= 14)) return 1;
                return 2;
            },
        }
    }
};

/// One piece of text in every language. The fields have no defaults, so leaving a language out of a literal
/// does not compile.
pub const Text = struct {
    en: []const u8,
    uk: []const u8,

    pub fn get(t: Text, lang: Lang) []const u8 {
        return switch (lang) {
            .en => t.en,
            .uk => t.uk,
        };
    }

    /// Length in code points of the longest version: reading time that does not depend on the language
    /// in use, so the simulation runs identically in each.
    pub fn longest(t: Text) usize {
        var n: usize = 0;
        for (Lang.all) |l| n = @max(n, utf8.count(t.get(l)));
        return n;
    }
};

/// A value for a `{n}` placeholder.
pub const Arg = union(enum) {
    int: i64,
    /// Whole number, zero-padded to `width` digits.
    padded: struct { v: u64, width: u8 },
    /// Fixed-point number with `dp` decimals and the language's decimal separator.
    fixed: struct { v: f64, dp: u8 },
    str: []const u8,
    char: u8,
};

pub fn int(v: anytype) Arg {
    return .{ .int = @intCast(v) };
}
pub fn padded(v: anytype, width: u8) Arg {
    return .{ .padded = .{ .v = @intCast(v), .width = width } };
}
pub fn fixed(v: anytype, dp: u8) Arg {
    return .{ .fixed = .{ .v = v, .dp = dp } };
}
pub fn str(s: []const u8) Arg {
    return .{ .str = s };
}
pub fn char(c: u8) Arg {
    return .{ .char = c };
}

const Writer = struct {
    buf: []u8,
    n: usize = 0,

    fn put(w: *Writer, s: []const u8) void {
        const k = @min(s.len, w.buf.len - w.n);
        @memcpy(w.buf[w.n..][0..k], s[0..k]);
        w.n += k;
    }

    fn digits(w: *Writer, v: u64, min_width: usize) void {
        var tmp: [20]u8 = undefined;
        var i: usize = tmp.len;
        var x = v;
        while (x > 0 or i == tmp.len) {
            i -= 1;
            tmp[i] = '0' + @as(u8, @intCast(x % 10));
            x /= 10;
        }
        var pad = min_width -| (tmp.len - i);
        while (pad > 0) : (pad -= 1) w.put("0");
        w.put(tmp[i..]);
    }

    fn arg(w: *Writer, lang: Lang, a: Arg) void {
        switch (a) {
            .int => |v| {
                if (v < 0) w.put("-");
                w.digits(@abs(v), 1);
            },
            .padded => |p| w.digits(p.v, p.width),
            .fixed => |f| {
                var scale: f64 = 1;
                for (0..f.dp) |_| scale *= 10;
                const scaled = @round(@abs(f.v) * scale);
                if (!(scaled < 1e18)) return w.put("?");
                const whole: u64 = @intFromFloat(@floor(scaled / scale));
                const frac: u64 = @intFromFloat(scaled - @as(f64, @floatFromInt(whole)) * scale);
                if (f.v < 0 and (whole != 0 or frac != 0)) w.put("-");
                w.digits(whole, 1);
                if (f.dp > 0) {
                    w.put(&.{lang.decimalSeparator()});
                    w.digits(frac, f.dp);
                }
            },
            .str => |s| w.put(s),
            .char => |c| w.put(&.{c}),
        }
    }
};

/// One `{…}` of a template: an argument index and, for a plural selector, the forms after the first bar.
const Hole = struct {
    index: usize,
    forms: ?[]const u8,
    /// Bytes of the template the hole occupies, braces included.
    len: usize,
};

fn parseHole(tpl: []const u8) ?Hole {
    if (tpl.len < 3 or tpl[0] != '{') return null;
    const close = std.mem.indexOfScalar(u8, tpl, '}') orelse return null;
    const body = tpl[1..close];
    const bar = std.mem.indexOfScalar(u8, body, '|');
    const num = body[0 .. bar orelse body.len];
    if (num.len == 0) return null;
    var index: usize = 0;
    for (num) |c| {
        if (c < '0' or c > '9') return null;
        index = index * 10 + (c - '0');
    }
    return .{ .index = index, .forms = if (bar) |b| body[b + 1 ..] else null, .len = close + 1 };
}

/// Expands a template in `lang`. `{0}` inserts argument 0; `{0|form|form|…}` inserts the plural form that
/// argument 0, a whole number, takes in `lang` (see `Lang.pluralForms`). Output that does not fit in `buf`
/// is cut on a code point boundary.
pub fn expand(buf: []u8, lang: Lang, tpl: []const u8, args: []const Arg) []const u8 {
    var w: Writer = .{ .buf = buf };
    var i: usize = 0;
    while (i < tpl.len) {
        const hole = parseHole(tpl[i..]) orelse {
            const next = std.mem.indexOfScalarPos(u8, tpl, i + 1, '{') orelse tpl.len;
            w.put(tpl[i..next]);
            i = next;
            continue;
        };
        i += hole.len;
        if (hole.index >= args.len) {
            w.put("?");
            continue;
        }
        const a = args[hole.index];
        if (hole.forms) |forms| {
            const n: u64 = switch (a) {
                .int => |v| @abs(v),
                .padded => |p| p.v,
                else => 0,
            };
            var it = std.mem.splitScalar(u8, forms, '|');
            var k = lang.pluralIndex(n);
            var chosen: []const u8 = "";
            while (it.next()) |form| {
                chosen = form;
                if (k == 0) break;
                k -= 1;
            }
            w.put(chosen);
        } else w.arg(lang, a);
    }
    if (w.n == buf.len and w.n > 0) {
        // The buffer is full, so the last code point may have been cut: drop it unless it is whole.
        var start = w.n - 1;
        while (start > 0 and (buf[start] & 0xC0) == 0x80) start -= 1;
        const lead = buf[start];
        const need: usize = if (lead < 0x80) 1 else if (lead >= 0xF0) 4 else if (lead >= 0xE0) 3 else 2;
        if (start + need > w.n) w.n = start;
    }
    return buf[0..w.n];
}

/// What is wrong with a template for `lang`, or null: an unclosed or malformed hole, a plural selector with
/// the wrong number of forms.
pub fn templateError(lang: Lang, tpl: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (std.mem.indexOfAnyPos(u8, tpl, i, "{}")) |at| {
        if (tpl[at] == '}') return "'}' without '{'";
        const hole = parseHole(tpl[at..]) orelse return "malformed placeholder";
        if (hole.forms) |forms| {
            if (std.mem.count(u8, forms, "|") + 1 != lang.pluralForms()) return "wrong number of plural forms for the language";
        }
        i = at + hole.len;
    }
    return null;
}

/// Bit set of the argument indices a template uses.
pub fn holes(tpl: []const u8) u32 {
    var set: u32 = 0;
    var i: usize = 0;
    while (std.mem.indexOfScalarPos(u8, tpl, i, '{')) |at| {
        const hole = parseHole(tpl[at..]) orelse break;
        if (hole.index < 32) set |= @as(u32, 1) << @intCast(hole.index);
        i = at + hole.len;
    }
    return set;
}

/// What is wrong with a bilingual template, or null. Both languages must be well formed and use the same
/// arguments, with no gaps in the numbering.
pub fn textError(t: Text) ?[]const u8 {
    for (Lang.all) |l| if (templateError(l, t.get(l))) |e| return e;
    const want = holes(t.en);
    if (want & (want +% 1) != 0) return "placeholder numbers skip a value";
    for (Lang.all) |l| if (holes(t.get(l)) != want) return "languages use different placeholders";
    return null;
}

/// Expands `t` in `lang`. The template is checked while compiling: a malformed placeholder, a language that
/// uses different arguments from the others, or a call that passes the wrong number of them does not build.
pub fn format(buf: []u8, lang: Lang, comptime t: Text, args: anytype) []const u8 {
    comptime {
        @setEvalBranchQuota(20_000);
        if (textError(t)) |e| @compileError("\"" ++ t.en ++ "\": " ++ e);
        if (@popCount(holes(t.en)) != args.len) @compileError("\"" ++ t.en ++ "\": wrong number of arguments");
    }
    const list: [args.len]Arg = args;
    return expand(buf, lang, t.get(lang), &list);
}

test "locale identifiers map to languages by primary subtag" {
    try std.testing.expectEqual(@as(?Lang, .uk), Lang.fromTag("uk"));
    try std.testing.expectEqual(@as(?Lang, .uk), Lang.fromTag("uk-UA"));
    try std.testing.expectEqual(@as(?Lang, .uk), Lang.fromTag("UK_ua.UTF-8"));
    try std.testing.expectEqual(@as(?Lang, .en), Lang.fromTag("en-GB"));
    try std.testing.expectEqual(@as(?Lang, null), Lang.fromTag("ukr"));
    try std.testing.expectEqual(@as(?Lang, null), Lang.fromTag("ru-UA"));
    try std.testing.expectEqual(@as(?Lang, null), Lang.fromTag(""));
}

test "the first supported preference wins and English is the default" {
    try std.testing.expectEqual(Lang.uk, Lang.fromPreferences("uk-UA,en-US"));
    try std.testing.expectEqual(Lang.en, Lang.fromPreferences("en-US,uk-UA"));
    try std.testing.expectEqual(Lang.uk, Lang.fromPreferences("pl-PL, uk-UA, en"));
    try std.testing.expectEqual(Lang.en, Lang.fromPreferences("de-DE,fr"));
    try std.testing.expectEqual(Lang.en, Lang.fromPreferences(""));
}

test "Ukrainian plural categories" {
    const one = [_]u64{ 1, 21, 31, 101, 1001 };
    const few = [_]u64{ 2, 3, 4, 22, 23, 24, 102, 1004 };
    const many = [_]u64{ 0, 5, 6, 10, 11, 12, 13, 14, 15, 19, 20, 25, 100, 111, 112, 114, 1000 };
    for (one) |n| try std.testing.expectEqual(@as(usize, 0), Lang.uk.pluralIndex(n));
    for (few) |n| try std.testing.expectEqual(@as(usize, 1), Lang.uk.pluralIndex(n));
    for (many) |n| try std.testing.expectEqual(@as(usize, 2), Lang.uk.pluralIndex(n));
    try std.testing.expectEqual(@as(usize, 0), Lang.en.pluralIndex(1));
    for ([_]u64{ 0, 2, 11, 21 }) |n| try std.testing.expectEqual(@as(usize, 1), Lang.en.pluralIndex(n));
}

test "templates expand with plurals and the language's decimal separator" {
    var buf: [128]u8 = undefined;
    const cells: Text = .{ .en = "{0} {0|cell|cells} in {1} s", .uk = "{0} {0|клітина|клітини|клітин} за {1} с" };
    try std.testing.expectEqualStrings("1 cell in 2.5 s", format(&buf, .en, cells, .{ int(1), fixed(2.46, 1) }));
    try std.testing.expectEqualStrings("3 cells in 0.0 s", format(&buf, .en, cells, .{ int(3), fixed(0.04, 1) }));
    try std.testing.expectEqualStrings("1 клітина за 2,5 с", format(&buf, .uk, cells, .{ int(1), fixed(2.46, 1) }));
    try std.testing.expectEqualStrings("3 клітини за 12,0 с", format(&buf, .uk, cells, .{ int(3), fixed(11.96, 1) }));
    try std.testing.expectEqualStrings("11 клітин за 7 с", format(&buf, .uk, cells, .{ int(11), fixed(7.4, 0) }));
    try std.testing.expectEqualStrings("21 клітина за 0,38 с", format(&buf, .uk, cells, .{ int(21), fixed(0.38, 2) }));

    const clock: Text = .{ .en = "{0} min {1} s, grade {2}, {3}", .uk = "{0} хв {1} с, оцінка {2}, {3}" };
    try std.testing.expectEqualStrings("2 хв 05 с, оцінка B, −", format(&buf, .uk, clock, .{ int(2), padded(5, 2), char('B'), str("−") }));
    try std.testing.expectEqualStrings("-4", expand(&buf, .en, "{0}", &.{int(-4)}));
    try std.testing.expectEqualStrings("-0,5", expand(&buf, .uk, "{0}", &.{fixed(-0.5, 1)}));
    try std.testing.expectEqualStrings("0", expand(&buf, .uk, "{0}", &.{fixed(-0.2, 0)}));
}

test "output that does not fit is cut on a code point boundary" {
    var buf: [5]u8 = undefined;
    try std.testing.expectEqualStrings("кл", expand(&buf, .uk, "клітина", &.{}));
    try std.testing.expectEqualStrings("ab", expand(buf[0..4], .uk, "ab—c", &.{}));
}

test "malformed and mismatched templates are reported" {
    try std.testing.expect(textError(.{ .en = "{0} of {1}", .uk = "{0} з {1}" }) == null);
    try std.testing.expect(textError(.{ .en = "{1} of {0}", .uk = "{0} з {1}" }) == null);
    try std.testing.expect(textError(.{ .en = "{0} of {1}", .uk = "{0} з 3" }) != null);
    try std.testing.expect(textError(.{ .en = "{0} left", .uk = "ще {0" }) != null);
    try std.testing.expect(textError(.{ .en = "{1} left", .uk = "ще {1}" }) != null);
    try std.testing.expect(textError(.{ .en = "{0|cell|cells}", .uk = "{0|клітина|клітини}" }) != null);
    try std.testing.expect(textError(.{ .en = "{0|cell|cells}", .uk = "{0|клітина|клітини|клітин}" }) == null);
    try std.testing.expect(textError(.{ .en = "50 }", .uk = "50" }) != null);
    try std.testing.expect(textError(.{ .en = "{x}", .uk = "{x}" }) != null);
}

test "reading length is the longest language's, in code points" {
    const t: Text = .{ .en = "Hold on!", .uk = "Тримайтеся!" };
    try std.testing.expectEqual(@as(usize, 11), t.longest());
}
