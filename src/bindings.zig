//! What each action is bound to, on the keyboard and on a game controller, and the prompts that follow
//! from it. This is the one table both sides read: `input.zig` maps controller state to actions through
//! it, and every on-screen hint gets the name of its control from it, so a prompt cannot name a button the
//! action is not on. No platform or rendering imports: the simulation uses it to time a spoken line.

const std = @import("std");
const i18n = @import("i18n.zig");
const pad = @import("pad.zig");
const strings = @import("strings.zig");
const utf8 = @import("utf8.zig");
const Lang = i18n.Lang;
const Text = i18n.Text;
const Button = pad.Button;

/// What the player is holding, as far as prompts are concerned.
pub const Device = enum(u8) {
    kbm,
    xbox,
    playstation,

    pub const count = @typeInfo(Device).@"enum".field_names.len;
    pub const all = [count]Device{ .kbm, .xbox, .playstation };

    pub fn isPad(d: Device) bool {
        return d != .kbm;
    }

    /// A controller that is neither Xbox nor PlayStation is prompted with Xbox names.
    pub fn ofFamily(f: pad.Family) Device {
        return if (f == .playstation) .playstation else .xbox;
    }

    /// The value of `--prompts`.
    pub fn fromArg(s: []const u8) ?Device {
        if (std.mem.eql(u8, s, "kbm")) return .kbm;
        if (std.mem.eql(u8, s, "xbox")) return .xbox;
        if (std.mem.eql(u8, s, "ps")) return .playstation;
        return null;
    }
};

/// Language and device: everything that decides which words a `Text` is shown in.
pub const Prompt = struct {
    lang: Lang = .en,
    device: Device = .kbm,
};

/// Everything the player can do. The names are the ones text refers to: `{@examine}`.
pub const Action = enum(u8) {
    // flying
    move,
    look,
    up,
    down,
    boost,
    arm_left,
    arm_right,
    /// Next tool on the arm.
    tool_left,
    tool_right,
    /// The keyboard's direct choice of tool (1 2 3, 8 9 0). A controller has no room for six buttons; it
    /// steps back one tool instead, which with three tools reaches any of them in one press too.
    pick_left,
    pick_right,
    examine,
    hint,
    tether,
    skip,
    pause,
    // menus and cards
    confirm,
    back,
    nav,
    map,
    language,
    // pause menu entries
    retry,
    restart,
    leave,
    quit,

    pub const count = @typeInfo(Action).@"enum".field_names.len;
};

/// Where an action sits on a controller.
pub const Control = union(enum) {
    button: Button,
    left_stick,
    right_stick,
    /// D-pad up and down, or the left stick pushed up and down.
    dpad_vertical,
    /// No button of its own: an entry in a menu, reached with `nav` and chosen with `confirm`.
    menu,
};

pub const Binding = struct {
    /// The keyboard and mouse control, by name.
    keys: Text,
    pad: Control,
    /// A second button that does the same, which prompts do not mention.
    pad_also: ?Button = null,
};

const K = strings.keys;

pub fn binding(a: Action) Binding {
    return switch (a) {
        .move => .{ .keys = K.move, .pad = .left_stick },
        .look => .{ .keys = K.look, .pad = .right_stick },
        .up => .{ .keys = K.up, .pad = .{ .button = .a } },
        .down => .{ .keys = K.down, .pad = .{ .button = .b } },
        .boost => .{ .keys = K.boost, .pad = .{ .button = .ls } },
        .arm_left => .{ .keys = K.arm_left, .pad = .{ .button = .lt } },
        .arm_right => .{ .keys = K.arm_right, .pad = .{ .button = .rt } },
        .tool_left => .{ .keys = K.tool_left, .pad = .{ .button = .lb } },
        .tool_right => .{ .keys = K.tool_right, .pad = .{ .button = .rb } },
        .pick_left => .{ .keys = K.pick_left, .pad = .{ .button = .dpad_left } },
        .pick_right => .{ .keys = K.pick_right, .pad = .{ .button = .dpad_right } },
        .examine => .{ .keys = K.examine, .pad = .{ .button = .x } },
        .hint => .{ .keys = K.hint, .pad = .{ .button = .y } },
        // The tether is fired at what the reticle is on, usually while thrusting against a stream, so it
        // sits under the thumb that is aiming. The d-pad does it too, for a hand that is free.
        .tether => .{ .keys = K.tether, .pad = .{ .button = .rs }, .pad_also = .dpad_up },
        .skip => .{ .keys = K.skip, .pad = .{ .button = .back } },
        .pause => .{ .keys = K.pause, .pad = .{ .button = .start } },
        .confirm => .{ .keys = K.confirm, .pad = .{ .button = .a } },
        .back => .{ .keys = K.back, .pad = .{ .button = .b } },
        .nav => .{ .keys = K.nav, .pad = .dpad_vertical },
        .map => .{ .keys = K.map, .pad = .{ .button = .y } },
        .language => .{ .keys = K.language, .pad = .{ .button = .back } },
        .retry => .{ .keys = K.retry, .pad = .menu },
        .restart => .{ .keys = K.restart, .pad = .menu },
        .leave => .{ .keys = K.leave, .pad = .menu },
        .quit => .{ .keys = K.quit, .pad = .menu },
    };
}

/// The button an action is on. For the actions `input.zig` reads as buttons; anything else does not compile.
pub fn button(comptime a: Action) Button {
    return switch (comptime binding(a).pad) {
        .button => |b| b,
        else => @compileError("the action '" ++ @tagName(a) ++ "' is not on a button"),
    };
}

/// A button's name on a controller of the given family.
pub fn buttonName(b: Button, device: Device) Text {
    const P = strings.pad;
    return switch (b) {
        .dpad_up => P.dpad_up,
        .dpad_down => P.dpad_down,
        .dpad_left => P.dpad_left,
        .dpad_right => P.dpad_right,
        else => if (device == .playstation) switch (b) {
            .a => P.playstation.cross,
            .b => P.playstation.circle,
            .x => P.playstation.square,
            .y => P.playstation.triangle,
            .lb => P.playstation.l1,
            .rb => P.playstation.r1,
            .lt => P.playstation.l2,
            .rt => P.playstation.r2,
            .ls => P.playstation.l3,
            .rs => P.playstation.r3,
            .start => P.playstation.options,
            .back => P.playstation.create,
            else => unreachable,
        } else switch (b) {
            .a => P.xbox.a,
            .b => P.xbox.b,
            .x => P.xbox.x,
            .y => P.xbox.y,
            .lb => P.xbox.lb,
            .rb => P.xbox.rb,
            .lt => P.xbox.lt,
            .rt => P.xbox.rt,
            .ls => P.xbox.ls,
            .rs => P.xbox.rs,
            .start => P.xbox.menu,
            .back => P.xbox.view,
            else => unreachable,
        },
    };
}

/// What to call the control an action is on, for the player `p` describes. Empty for an action that is a
/// menu entry on a controller: there is no button to name, and the entry itself is on screen.
pub fn label(a: Action, p: Prompt) []const u8 {
    const b = binding(a);
    if (p.device == .kbm) return b.keys.get(p.lang);
    return switch (b.pad) {
        .button => |btn| buttonName(btn, p.device).get(p.lang),
        .left_stick => strings.pad.left_stick.get(p.lang),
        .right_stick => strings.pad.right_stick.get(p.lang),
        .dpad_vertical => strings.pad.dpad_vertical.get(p.lang),
        .menu => "",
    };
}

fn lookup(ctx: *const anyopaque, name: []const u8) ?[]const u8 {
    const p: *const Prompt = @ptrCast(@alignCast(ctx));
    const a = std.meta.stringToEnum(Action, name) orelse return null;
    return label(a, p.*);
}

fn refs(p: *const Prompt) i18n.Refs {
    return .{ .ctx = p, .lookup = &lookup };
}

/// The words of `t` for this player, before anything is filled in.
pub fn wording(t: Text, p: Prompt) []const u8 {
    return t.wording(p.device.isPad()).get(p.lang);
}

/// `t` as this player should read it: the wording for their device, in their language, with each control
/// named as it is on that device. Text without references is returned as it is, without touching `buf`.
pub fn resolve(buf: []u8, t: Text, p: Prompt) []const u8 {
    const w = wording(t, p);
    if (std.mem.indexOf(u8, w, "{@") == null) return w;
    return i18n.expandRefs(buf, p.lang, w, &.{}, refs(&p));
}

/// Fills in a template that was already chosen with `wording`: arguments and control names in one pass.
pub fn expand(buf: []u8, p: Prompt, tpl: []const u8, args: []const i18n.Arg) []const u8 {
    return i18n.expandRefs(buf, p.lang, tpl, args, refs(&p));
}

/// `resolve` for text with arguments. The template is checked while compiling, as `i18n.format` checks it.
pub fn format(buf: []u8, p: Prompt, comptime t: Text, args: anytype) []const u8 {
    comptime {
        @setEvalBranchQuota(200_000);
        if (i18n.textError(t)) |e| @compileError("\"" ++ t.en ++ "\": " ++ e);
        if (@popCount(i18n.holes(t.en)) != args.len) @compileError("\"" ++ t.en ++ "\": wrong number of arguments");
    }
    const list: [args.len]i18n.Arg = args;
    return expand(buf, p, wording(t, p), &list);
}

/// Length of `t` in code points as `p` reads it.
pub fn length(t: Text, p: Prompt) usize {
    const Counter = struct {
        n: usize = 0,
        p: Prompt,
        pub fn literal(c: *@This(), s: []const u8) void {
            c.n += utf8.count(s);
        }
        pub fn ref(c: *@This(), name: []const u8) void {
            c.n += utf8.count(lookup(&c.p, name) orelse "?");
        }
    };
    var c: Counter = .{ .p = p };
    i18n.walk(wording(t, p), &c);
    return c.n;
}

/// Length in code points of the longest version of `t` any player can be shown: every language, every
/// device. A spoken line stays up in proportion to this, so the simulation runs identically whichever
/// language is in use and whatever the player is holding.
pub fn readingLength(t: Text) usize {
    var n: usize = 0;
    for (Lang.all) |l| for (Device.all) |d| {
        n = @max(n, length(t, .{ .lang = l, .device = d }));
    };
    return n;
}

// ---------------------------------------------------------------------------------------------- tests

const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;

test "every action is bound on the keyboard and on a controller, and named for each device" {
    var on_button: [Button.count]usize = @splat(0);
    inline for (comptime std.meta.fieldNames(Action)) |name| {
        const a = @field(Action, name);
        const b = binding(a);
        for (Lang.all) |l| {
            try expect(b.keys.get(l).len > 0);
            try expect(label(a, .{ .lang = l, .device = .kbm }).len > 0);
            for ([_]Device{ .xbox, .playstation }) |d| {
                const text = label(a, .{ .lang = l, .device = d });
                // Only a menu entry may go without a button, and then the menu has to offer it: app.zig
                // tests that every entry of the pause menu can be reached and chosen.
                if (b.pad == .menu) try expect(text.len == 0) else try expect(text.len > 0);
            }
        }
        switch (b.pad) {
            .button => |btn| on_button[@intFromEnum(btn)] += 1,
            else => {},
        }
        if (b.pad_also) |btn| on_button[@intFromEnum(btn)] += 1;
    }
    // A button carries at most one action while flying and one in menus: A is up and confirm, B is down
    // and back, Y is hint and map, View is skip and language. Nothing is on three.
    for (on_button) |n| try expect(n <= 2);
    try expect(std.mem.eql(u8, @tagName(button(.confirm)), @tagName(button(.up))));
    // Every button of the controller is used.
    var free: usize = 0;
    for (on_button) |n| free += @intFromBool(n == 0);
    // d-pad up/down are `nav`, which is not a `.button` binding; d-pad up is also the tether's second button.
    try std.testing.expectEqual(@as(usize, 1), free);
    try std.testing.expectEqual(@as(usize, 0), on_button[@intFromEnum(Button.dpad_down)]);
}

test "every button has a name in each family, and the two families differ where the plastic does" {
    inline for (comptime std.meta.fieldNames(Button)) |name| {
        const b = @field(Button, name);
        for ([_]Device{ .xbox, .playstation }) |d| for (Lang.all) |l| {
            try expect(buttonName(b, d).get(l).len > 0);
        };
        const same = std.mem.eql(u8, buttonName(b, .xbox).en, buttonName(b, .playstation).en);
        const is_dpad = std.mem.startsWith(u8, name, "dpad_");
        try expect(same == is_dpad);
    }
    try expectEqualStrings("LT", label(.arm_left, .{ .device = .xbox }));
    try expectEqualStrings("L2", label(.arm_left, .{ .device = .playstation }));
    try expectEqualStrings("Q", label(.arm_left, .{ .device = .kbm }));
    try expectEqualStrings("□", label(.examine, .{ .device = .playstation }));
    try expectEqualStrings("Пробіл", label(.up, .{ .lang = .uk, .device = .kbm }));
    try expectEqualStrings("Правий стік", label(.look, .{ .lang = .uk, .device = .xbox }));
}

test "text is resolved for the device: its wording, its language, its button names" {
    var buf: [200]u8 = undefined;
    const press: Text = .{ .en = "Aim and press {@examine}.", .uk = "Наведіть і натисніть {@examine}." };
    try expectEqualStrings("Aim and press T.", resolve(&buf, press, .{ .device = .kbm }));
    try expectEqualStrings("Aim and press X.", resolve(&buf, press, .{ .device = .xbox }));
    try expectEqualStrings("Наведіть і натисніть □.", resolve(&buf, press, .{ .lang = .uk, .device = .playstation }));

    const thrust: Text = .{
        .en = "Hold W, then {@boost}.",
        .uk = "Утримуйте W, потім {@boost}.",
        .pad = &.{ .en = "Push the left stick, then click {@boost}.", .uk = "Відхиліть лівий стік, потім натисніть {@boost}." },
    };
    try expectEqualStrings("Hold W, then Shift.", resolve(&buf, thrust, .{}));
    try expectEqualStrings("Push the left stick, then click LS.", resolve(&buf, thrust, .{ .device = .xbox }));
    try expectEqualStrings("Відхиліть лівий стік, потім натисніть L3.", resolve(&buf, thrust, .{ .lang = .uk, .device = .playstation }));

    // Text with nothing to resolve is not copied.
    const plain: Text = .{ .en = "Hold on!", .uk = "Тримайтеся!" };
    try expect(resolve(&buf, plain, .{ .device = .xbox }).ptr == plain.en.ptr);

    const counted: Text = .{ .en = "{0} left — {@examine}", .uk = "ще {0} — {@examine}" };
    try expectEqualStrings("3 left — △", format(&buf, .{ .device = .playstation }, .{ .en = "{0} left — {@hint}", .uk = "ще {0} — {@hint}" }, .{i18n.int(3)}));
    try expectEqualStrings("ще 3 — T", format(&buf, .{ .lang = .uk }, counted, .{i18n.int(3)}));
}

test "reading length is that of the longest version any player sees, in code points" {
    const plain: Text = .{ .en = "Hold on!", .uk = "Тримайтеся!" };
    try std.testing.expectEqual(@as(usize, 11), readingLength(plain));
    // "press T" is 7, "press X" is 7, "press □" is 7; the Xbox View button makes the longest
    const skip: Text = .{ .en = "press {@skip}", .uk = "{@skip}" };
    try std.testing.expectEqual(@as(usize, "press Create".len), readingLength(skip));
    try std.testing.expectEqual(@as(usize, "press Tab".len), length(skip, .{}));
    const worded: Text = .{ .en = "W", .uk = "W", .pad = &.{ .en = "the stick", .uk = "стік" } };
    try std.testing.expectEqual(@as(usize, 9), readingLength(worded));
}
