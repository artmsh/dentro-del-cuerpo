//! The command line. Parsing is separate from acting on it so that it can be tested: `parse` reads the
//! arguments and returns what to run, a request for the usage text, or the reason they make no sense.

const std = @import("std");
const i18n = @import("i18n.zig");
const bindings = @import("bindings.zig");
const Lang = i18n.Lang;

pub const Mode = enum { play, demo, inputtest, padtest, selftest, shots, icon };

pub const usage =
    \\usage: dentro [--fullscreen] [--software] [--lang en|uk] [--prompts kbm|xbox|ps] [--chapter 1|2]
    \\              [--demo [--pad] | --inputtest | --padtest | --selftest | --shots <dir> | --icon <png|ico>]
    \\
    \\  (no mode)        play in a window
    \\  --demo           the scripted pilot flies a chapter in the window; --pad has it hold a controller
    \\  --inputtest      drive the window with synthetic key events and check what reaches the game
    \\  --padtest        play from the title screen with a synthetic controller
    \\  --selftest       headless: the scripted pilot plays both chapters and prints a summary
    \\  --shots <dir>    render every screen and stage offscreen, one BMP each, into <dir>
    \\  --icon <file>    render the application icon: a .png master, or a Windows .ico
    \\
    \\  --fullscreen     start in full screen (windowed modes)
    \\  --software       render on the system's software rasteriser, where there is one (Windows: WARP)
    \\  --lang en|uk     language for this run (not --selftest or --icon)
    \\  --prompts D      write the prompts for kbm, xbox or ps instead of the device last used
    \\                   (play, --demo, --inputtest, --shots)
    \\  --chapter 1|2    the chapter to open (play), fly (--demo) or render (--shots)
    \\  --help, -h       print this and exit
    \\
;

pub const Options = struct {
    mode: Mode = .play,
    /// The directory of `--shots`, or the file of `--icon`.
    path: []const u8 = "",
    /// Index of the chapter `--chapter` names.
    chapter: ?u8 = null,
    fullscreen: bool = false,
    lang: ?Lang = null,
    prompts: ?bindings.Device = null,
    via_pad: bool = false,
    /// Render without a GPU, where the graphics API has a software rasteriser.
    software: bool = false,
};

pub const Result = union(enum) {
    run: Options,
    help,
    /// Why the arguments were refused, as a sentence without a full stop.
    bad: []const u8,
};

const Flag = enum { fullscreen, lang, prompts, chapter, pad, software };

/// The modes in which each option does something. An option given with a mode outside its set would be
/// ignored without a word, so it is refused instead.
fn applies(flag: Flag, mode: Mode) bool {
    return switch (flag) {
        .fullscreen => mode == .play or mode == .demo or mode == .inputtest or mode == .padtest,
        .lang => mode != .selftest and mode != .icon,
        // --padtest checks which device the prompts follow, so it cannot have them fixed.
        .prompts => mode == .play or mode == .demo or mode == .inputtest or mode == .shots,
        .chapter => mode == .play or mode == .demo or mode == .shots,
        .pad => mode == .demo,
        // The only mode that draws nothing.
        .software => mode != .selftest,
    };
}

fn flagName(flag: Flag) []const u8 {
    return switch (flag) {
        .fullscreen => "--fullscreen",
        .lang => "--lang",
        .prompts => "--prompts",
        .chapter => "--chapter",
        .pad => "--pad",
        .software => "--software",
    };
}

fn modeName(mode: Mode) []const u8 {
    return switch (mode) {
        .play => "normal play",
        .demo => "--demo",
        .inputtest => "--inputtest",
        .padtest => "--padtest",
        .selftest => "--selftest",
        .shots => "--shots",
        .icon => "--icon",
    };
}

/// `args` are the arguments after the program's name. `msg` holds the text of a refusal.
pub fn parse(args: anytype, msg: []u8) Result {
    var o: Options = .{};
    var mode_flag: ?[]const u8 = null;
    var given: std.EnumSet(Flag) = .empty;
    const eql = std.mem.eql;
    // Asking for help is never an error, whatever else is on the line.
    for (args) |arg| {
        const a: []const u8 = arg;
        if (eql(u8, a, "--help") or eql(u8, a, "-h")) return .help;
    }
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a: []const u8 = args[i];
        // Cocoa reads "-AppleLanguages (uk)" and its kin from the command line as user defaults; they come
        // with a value and are not this program's to judge. Finder passes -psn_… on some launch paths.
        if (std.mem.startsWith(u8, a, "-Apple")) {
            i += 1;
            continue;
        }
        if (std.mem.startsWith(u8, a, "-psn")) continue;

        var new_mode: ?Mode = null;
        if (eql(u8, a, "--selftest")) new_mode = .selftest;
        if (eql(u8, a, "--demo")) new_mode = .demo;
        if (eql(u8, a, "--inputtest")) new_mode = .inputtest;
        if (eql(u8, a, "--padtest")) new_mode = .padtest;
        if (eql(u8, a, "--shots")) new_mode = .shots;
        if (eql(u8, a, "--icon")) new_mode = .icon;
        if (new_mode) |nm| {
            if (mode_flag) |first| {
                if (!eql(u8, first, a)) return bad(msg, "{s} and {s} are different modes; give one", .{ first, a });
            }
            mode_flag = a;
            o.mode = nm;
            if (nm == .shots or nm == .icon) {
                o.path = value(args, &i) orelse return bad(msg, "{s} takes a {s}", .{ a, if (nm == .shots) "directory" else "file name" });
            }
        } else if (eql(u8, a, "--fullscreen")) {
            o.fullscreen = true;
            given.insert(.fullscreen);
        } else if (eql(u8, a, "--software")) {
            o.software = true;
            given.insert(.software);
        } else if (eql(u8, a, "--pad")) {
            o.via_pad = true;
            given.insert(.pad);
        } else if (eql(u8, a, "--lang")) {
            o.lang = Lang.fromTag(value(args, &i) orelse "") orelse return bad(msg, "--lang takes en or uk", .{});
            given.insert(.lang);
        } else if (eql(u8, a, "--prompts")) {
            o.prompts = bindings.Device.fromArg(value(args, &i) orelse "") orelse return bad(msg, "--prompts takes kbm, xbox or ps", .{});
            given.insert(.prompts);
        } else if (eql(u8, a, "--chapter")) {
            const n = std.fmt.parseInt(u8, value(args, &i) orelse "", 10) catch 0;
            if (n < 1 or n > 2) return bad(msg, "--chapter takes 1 or 2 (the playable chapters)", .{});
            o.chapter = n - 1;
            given.insert(.chapter);
        } else {
            return bad(msg, "unknown argument: {s}", .{a});
        }
    }
    for (std.enums.values(Flag)) |flag| {
        if (given.contains(flag) and !applies(flag, o.mode)) {
            if (flag == .pad) return bad(msg, "--pad goes with --demo: it has the scripted pilot hold a controller", .{});
            return bad(msg, "{s} has no effect with {s}", .{ flagName(flag), modeName(o.mode) });
        }
    }
    return .{ .run = o };
}

/// The value of the option at `i`: the next argument, unless there is none or it is another option.
fn value(args: anytype, i: *usize) ?[]const u8 {
    if (i.* + 1 >= args.len) return null;
    const v: []const u8 = args[i.* + 1];
    if (v.len == 0 or v[0] == '-') return null;
    i.* += 1;
    return v;
}

fn bad(msg: []u8, comptime fmt: []const u8, args: anytype) Result {
    return .{ .bad = std.fmt.bufPrint(msg, fmt, args) catch "bad arguments" };
}

// ---------------------------------------------------------------------------------------------- tests

fn run(args: []const []const u8) Result {
    const S = struct {
        var msg: [200]u8 = undefined;
    };
    return parse(args, &S.msg);
}

fn expectBad(args: []const []const u8, needle: []const u8) !void {
    switch (run(args)) {
        .bad => |why| if (std.mem.indexOf(u8, why, needle) == null) {
            std.debug.print("refused with \"{s}\", which does not mention \"{s}\"\n", .{ why, needle });
            return error.TestUnexpectedResult;
        },
        else => {
            std.debug.print("accepted: {any}\n", .{args});
            return error.TestUnexpectedResult;
        },
    }
}

test "no arguments is normal play, and each mode is chosen by its flag" {
    try std.testing.expectEqualDeep(Result{ .run = .{} }, run(&.{}));
    try std.testing.expectEqual(Mode.selftest, run(&.{"--selftest"}).run.mode);
    try std.testing.expectEqual(Mode.inputtest, run(&.{"--inputtest"}).run.mode);
    try std.testing.expectEqual(Mode.padtest, run(&.{"--padtest"}).run.mode);
    const demo = run(&.{ "--demo", "--pad", "--chapter", "2", "--lang", "uk", "--fullscreen", "--prompts", "ps" }).run;
    try std.testing.expectEqualDeep(Options{ .mode = .demo, .via_pad = true, .chapter = 1, .lang = .uk, .fullscreen = true, .prompts = .playstation }, demo);
    const shots = run(&.{ "--prompts", "xbox", "--lang", "uk", "--shots", "out dir", "--chapter", "1" }).run;
    try std.testing.expectEqualDeep(Options{ .mode = .shots, .path = "out dir", .chapter = 0, .lang = .uk, .prompts = .xbox }, shots);
    try std.testing.expectEqualStrings("icon.png", run(&.{ "--icon", "icon.png" }).run.path);
    try std.testing.expectEqual(@as(?u8, 1), run(&.{ "--chapter", "2" }).run.chapter);
}

test "an option that needs a value is refused without one, wherever it stands" {
    inline for (.{ "--chapter", "--shots", "--icon", "--lang", "--prompts" }) |flag| {
        // last on the line, and followed by another option instead of a value
        try expectBad(&.{flag}, flag);
        try expectBad(&.{ flag, "--fullscreen" }, flag);
        try expectBad(&.{ "--fullscreen", flag }, flag);
    }
    try expectBad(&.{ "--shots", "--chapter", "1" }, "--shots takes a directory");
    try expectBad(&.{ "--chapter", "3" }, "--chapter takes 1 or 2");
    try expectBad(&.{ "--chapter", "one" }, "--chapter takes 1 or 2");
    try expectBad(&.{ "--lang", "de" }, "--lang takes en or uk");
    try expectBad(&.{ "--prompts", "switch" }, "--prompts takes kbm, xbox or ps");
}

test "options that would be ignored are refused, and so are two modes at once" {
    try expectBad(&.{"--pad"}, "--pad goes with --demo");
    try expectBad(&.{ "--pad", "--padtest" }, "--pad goes with --demo");
    try expectBad(&.{ "--demo", "--selftest" }, "different modes");
    try expectBad(&.{ "--shots", "d", "--icon", "f" }, "different modes");
    try expectBad(&.{ "--selftest", "--chapter", "2" }, "--chapter has no effect with --selftest");
    try expectBad(&.{ "--inputtest", "--chapter", "1" }, "--chapter has no effect with --inputtest");
    try expectBad(&.{ "--selftest", "--lang", "uk" }, "--lang has no effect with --selftest");
    try expectBad(&.{ "--shots", "d", "--fullscreen" }, "--fullscreen has no effect with --shots");
    try expectBad(&.{ "--padtest", "--prompts", "ps" }, "--prompts has no effect with --padtest");
    try expectBad(&.{ "--icon", "f", "--prompts", "ps" }, "--prompts has no effect with --icon");
    try expectBad(&.{ "--selftest", "--software" }, "--software has no effect with --selftest");
    try std.testing.expect(run(&.{ "--software", "--shots", "d" }).run.software);
    try std.testing.expect(run(&.{ "--padtest", "--software" }).run.software);
    try expectBad(&.{"--frobnicate"}, "unknown argument: --frobnicate");
    try expectBad(&.{"shots"}, "unknown argument: shots");
    // The same mode twice is only a repetition.
    try std.testing.expectEqual(Mode.demo, run(&.{ "--demo", "--demo" }).run.mode);
}

test "help wins over everything else on the line" {
    try std.testing.expectEqual(Result.help, run(&.{"--help"}));
    try std.testing.expectEqual(Result.help, run(&.{"-h"}));
    try std.testing.expectEqual(Result.help, run(&.{ "--demo", "-h", "--nonsense" }));
    try std.testing.expectEqual(Result.help, run(&.{ "--shots", "--help" }));
}

test "what Cocoa and Finder add to the command line passes through" {
    const r = run(&.{ "-AppleLanguages", "(uk)", "-psn_0_12345", "--chapter", "2" }).run;
    try std.testing.expectEqualDeep(Options{ .chapter = 1 }, r);
}
