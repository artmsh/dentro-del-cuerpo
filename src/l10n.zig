//! Walks every piece of bilingual text in the game (the catalogue in strings.zig, the atlas, the route map)
//! and holds the tests that make a missing or malformed translation a build failure rather than a line of
//! English in the middle of a Ukrainian screen.

const std = @import("std");
const i18n = @import("i18n.zig");
const strings = @import("strings.zig");
const guide = @import("guide.zig");
const campaign = @import("campaign.zig");
const game = @import("game.zig");
const font = @import("font.zig");
const utf8 = @import("utf8.zig");
const app = @import("app.zig");
const Text = i18n.Text;
const Lang = i18n.Lang;

/// Calls `visitor.text(where, text)` for every `Text` the game can show. `where` names the entry for a
/// failure message.
pub fn forEach(visitor: anytype) !void {
    try walkNamespace(strings, "strings", visitor);
    var buf: [96]u8 = undefined;
    for (0..guide.Topic.count) |i| {
        const topic: guide.Topic = @enumFromInt(i);
        const e = guide.entry(topic);
        inline for (.{ "name", "size", "short", "deep" }) |field| {
            try visitor.text(std.fmt.bufPrint(&buf, "guide.{s}.{s}", .{ @tagName(topic), field }) catch unreachable, @field(e, field));
        }
    }
    for (campaign.chapters, 0..) |c, i| {
        inline for (.{ "name", "site", "route", "read", "objective", "challenge", "upgrade" }) |field| {
            try visitor.text(std.fmt.bufPrint(&buf, "campaign.chapters[{d}].{s}", .{ i, field }) catch unreachable, @field(c, field));
        }
    }
}

fn walkNamespace(comptime Ns: type, comptime path: []const u8, visitor: anytype) !void {
    inline for (comptime std.meta.declarations(Ns)) |name| {
        try walkValue(@field(Ns, name), path ++ "." ++ name, visitor);
    }
}

fn walkValue(comptime value: anytype, comptime path: []const u8, visitor: anytype) !void {
    const V = @TypeOf(value);
    if (V == type) return walkNamespace(value, path, visitor);
    if (V == Text) return visitor.text(path, value);
    switch (@typeInfo(V)) {
        .array => inline for (value, 0..) |item, i| try walkValue(item, path ++ std.fmt.comptimePrint("[{d}]", .{i}), visitor),
        else => @compileError(path ++ ": the catalogue holds Text, arrays of Text and namespaces of them, nothing else"),
    }
}

/// The entry of a catalogue namespace that is longest in `lang`; the screenshot run uses it to show the
/// worst case for a text box.
pub fn longestIn(comptime Ns: type, lang: Lang) Text {
    const Finder = struct {
        lang: Lang,
        best: ?Text = null,
        pub fn text(f: *@This(), _: []const u8, t: Text) !void {
            if (f.best == null or utf8.count(t.get(f.lang)) > utf8.count(f.best.?.get(f.lang))) f.best = t;
        }
    };
    var finder: Finder = .{ .lang = lang };
    walkNamespace(Ns, "", &finder) catch unreachable;
    return finder.best.?;
}

fn isCyrillic(cp: u21) bool {
    return (cp >= 0x400 and cp <= 0x4FF);
}

fn isLatin(cp: u21) bool {
    return (cp >= 'A' and cp <= 'Z') or (cp >= 'a' and cp <= 'z') or (cp >= 0xC0 and cp <= 0xFF and cp != 0xD7 and cp != 0xF7);
}

fn hasCyrillic(s: []const u8) bool {
    var i: usize = 0;
    while (i < s.len) if (isCyrillic(utf8.next(s, &i))) return true;
    return false;
}

/// True if `s` has a run of two or more lowercase ASCII letters: the mark of an English word, as opposed to
/// a key name, a unit or a symbol.
fn hasEnglishWord(s: []const u8) bool {
    var run: usize = 0;
    for (s) |c| {
        run = if (c >= 'a' and c <= 'z') run + 1 else 0;
        if (run >= 2) return true;
    }
    return false;
}

/// Text that is deliberately the same in every language although it contains Latin words: the binomial,
/// and names printed on the keyboard.
const same_everywhere = [_][]const u8{ "Staphylococcus aureus", "Esc / Enter", "Shift", "Tab", "Cmd+F" };

fn fail(where: []const u8, text: []const u8, comptime what: []const u8) error{Localisation} {
    std.debug.print("{s}: " ++ what ++ "\n    {s}\n", .{ where, text });
    return error.Localisation;
}

test "every string has a Ukrainian translation" {
    const Check = struct {
        count: usize = 0,
        pub fn text(c: *@This(), where: []const u8, t: Text) !void {
            c.count += 1;
            if (t.en.len == 0) return fail(where, t.uk, "the English is empty");
            if (t.uk.len == 0) return fail(where, t.en, "the Ukrainian is empty");
            if (hasCyrillic(t.uk)) return;
            // No Cyrillic at all is right only for text that is not words: a key, a number, a unit, a name.
            if (!std.mem.eql(u8, t.en, t.uk)) return fail(where, t.uk, "the Ukrainian has no Cyrillic and differs from the English");
            if (!hasEnglishWord(t.en)) return;
            for (same_everywhere) |s| if (std.mem.eql(u8, s, t.en)) return;
            return fail(where, t.uk, "the Ukrainian is a copy of the English");
        }
    };
    var check: Check = .{};
    try forEach(&check);
    // The walk reached the script, the atlas and the route map, not just a corner of the catalogue.
    try std.testing.expect(check.count > 300 + 4 * guide.Topic.count + 7 * campaign.chapters.len);
}

test "placeholders are well formed and the same in both languages" {
    const Check = struct {
        pub fn text(_: *@This(), where: []const u8, t: Text) !void {
            if (i18n.textError(t)) |e| {
                std.debug.print("{s}: {s}\n    {s}\n    {s}\n", .{ where, e, t.en, t.uk });
                return error.Localisation;
            }
        }
    };
    var check: Check = .{};
    try forEach(&check);
}

test "Ukrainian text follows Ukrainian typography" {
    const Check = struct {
        pub fn text(_: *@This(), where: []const u8, t: Text) !void {
            const s = t.uk;
            if (std.mem.indexOfAny(u8, s, "'\"`") != null) return fail(where, s, "straight quote or apostrophe; use « », “ ” and ’");
            if (std.mem.indexOf(u8, s, "...") != null) return fail(where, s, "three full stops; use …");
            if (std.mem.indexOf(u8, s, " - ") != null) return fail(where, s, "hyphen used as a dash; use —");
            var i: usize = 0;
            var prev: u21 = 0;
            var prev2: u21 = 0;
            // Script of the letters in the word being read: a word must not mix the two, which is how a Latin
            // i, o or c typed on the wrong layout hides inside a Cyrillic word.
            var latin = false;
            var cyrillic = false;
            while (i < s.len) {
                const cp = utf8.next(s, &i);
                switch (cp) {
                    0x44B, 0x42B, 0x44D, 0x42D, 0x44A, 0x42A, 0x451, 0x401 => return fail(where, s, "a letter Ukrainian does not have (ы, э, ъ, ё)"),
                    else => {},
                }
                if (cp >= '0' and cp <= '9' and prev == '.' and prev2 >= '0' and prev2 <= '9') return fail(where, s, "decimal point; Ukrainian writes a comma");
                const apostrophe = cp == 0x2019 or cp == 0x2BC;
                if (isLatin(cp)) latin = true else if (isCyrillic(cp)) cyrillic = true else if (!apostrophe) {
                    latin = false;
                    cyrillic = false;
                }
                if (latin and cyrillic) return fail(where, s, "a word mixes Latin and Cyrillic letters");
                prev2 = prev;
                prev = cp;
            }
        }
    };
    var check: Check = .{};
    try forEach(&check);
}

test "every character of every string has a glyph in both faces" {
    const f = try font.Font.build(std.testing.allocator);
    defer std.testing.allocator.free(f.pixels);
    const Check = struct {
        f: *const font.Font,
        pub fn text(c: *@This(), where: []const u8, t: Text) !void {
            for (Lang.all) |l| try c.plain(where, t.get(l));
        }
        fn plain(c: *@This(), where: []const u8, s: []const u8) !void {
            var i: usize = 0;
            while (i < s.len) {
                const cp = utf8.next(s, &i);
                if (cp == '\n') continue;
                for ([_]font.Face{ .regular, .bold }) |face| {
                    if (!c.f.covers(face, cp)) {
                        std.debug.print("{s}: U+{X:0>4} has no glyph in the {s} face\n    {s}\n", .{ where, cp, @tagName(face), s });
                        return error.MissingGlyph;
                    }
                }
            }
        }
    };
    var check: Check = .{ .f = &f };
    try forEach(&check);
    // Text that is not in the catalogue because it is never translated, and what the formatter can emit.
    try check.plain("title", app.title);
    for (Lang.all) |l| try check.plain("endonym", l.endonym());
    try check.plain("formatter", "0123456789.,-?ABCD✓?◆ —·:");
}

test "every stage has an objective and a hint in each language" {
    const sim = try std.testing.allocator.create(game.Sim);
    defer std.testing.allocator.destroy(sim);
    var buf_en: [240]u8 = undefined;
    var buf_uk: [240]u8 = undefined;
    for (0..2) |chapter| {
        sim.* = game.Sim.initChapter(@intCast(chapter));
        inline for (comptime std.meta.fieldNames(game.Stage)) |name| {
            sim.stage = @field(game.Stage, name);
            const en = sim.objective(.en, &buf_en);
            const uk = sim.objective(.uk, &buf_uk);
            try std.testing.expect(en.len > 0 and uk.len > 0);
            try std.testing.expect(hasCyrillic(uk) and !hasCyrillic(en));
            // formatted objectives fit their buffer with room to spare
            try std.testing.expect(en.len < buf_en.len - 40 and uk.len < buf_uk.len - 40);
            for (0..3) |level| {
                sim.hint_level = @intCast(level);
                const hint = sim.hintText();
                try std.testing.expect(hint.en.len > 0 and hasCyrillic(hint.uk));
            }
        }
    }
}
