//! AppKit window, event pump and input state. No Objective-C source: the delegate class is built at runtime.

const std = @import("std");
const objc = @import("objc.zig");
const id = objc.id;
const SEL = objc.SEL;

extern fn CACurrentMediaTime() f64;
extern fn CGAssociateMouseAndMouseCursorPosition(connected: u32) i32;
extern fn CGWarpMouseCursorPosition(p: objc.Point) i32;
extern const NSDefaultRunLoopMode: id;

/// macOS virtual key codes (hardware positions, layout independent).
pub const Key = enum(u8) {
    a = 0,
    s = 1,
    d = 2,
    f = 3,
    h = 4,
    g = 5,
    z = 6,
    x = 7,
    c = 8,
    v = 9,
    b = 11,
    q = 12,
    w = 13,
    e = 14,
    r = 15,
    y = 16,
    t = 17,
    n1 = 18,
    n2 = 19,
    n3 = 20,
    n4 = 21,
    n6 = 22,
    n5 = 23,
    n9 = 25,
    n7 = 26,
    n8 = 28,
    n0 = 29,
    o = 31,
    u = 32,
    i = 34,
    p = 35,
    enter = 36,
    l = 37,
    j = 38,
    k = 40,
    n = 45,
    m = 46,
    tab = 48,
    space = 49,
    escape = 53,
    shift = 56,
    option = 58,
    control = 59,
    left = 123,
    right = 124,
    down = 125,
    up = 126,
};

pub const Input = struct {
    keys: [128]bool = @splat(false),
    pressed: [128]bool = @splat(false),
    mouse_dx: f32 = 0,
    mouse_dy: f32 = 0,
    lmb: bool = false,
    rmb: bool = false,
    lmb_pressed: bool = false,
    rmb_pressed: bool = false,

    pub fn down(in: *const Input, k: Key) bool {
        return in.keys[@intFromEnum(k)];
    }
    pub fn hit(in: *const Input, k: Key) bool {
        return in.pressed[@intFromEnum(k)];
    }
    pub fn set(in: *Input, k: Key, is_down: bool) void {
        const i = @intFromEnum(k);
        if (is_down and !in.keys[i]) in.pressed[i] = true;
        in.keys[i] = is_down;
    }
    pub fn endFrame(in: *Input) void {
        in.pressed = @splat(false);
        in.mouse_dx = 0;
        in.mouse_dy = 0;
        in.lmb_pressed = false;
        in.rmb_pressed = false;
    }
    pub fn releaseAll(in: *Input) void {
        in.keys = @splat(false);
        in.lmb = false;
        in.rmb = false;
    }
};

var quit_requested: bool = false;
var lost_focus: bool = false;

fn windowWillClose(_: id, _: SEL, _: id) callconv(.c) void {
    quit_requested = true;
}
fn windowDidResignKey(_: id, _: SEL, _: id) callconv(.c) void {
    lost_focus = true;
}
/// Runs when AppKit is about to terminate the process (Cmd+Q, a quit Apple Event, logout). terminate: calls
/// exit() from inside the event pump, so the main loop's own cleanup never runs; this hook is that cleanup.
pub var on_terminate: ?*const fn () void = null;

fn shouldTerminate(_: id, _: SEL, _: id) callconv(.c) u64 {
    quit_requested = true;
    if (on_terminate) |f| f();
    _ = CGAssociateMouseAndMouseCursorPosition(1);
    return 1; // NSTerminateNow
}

fn shouldTerminateAfterLastWindowClosed(_: id, _: SEL, _: id) callconv(.c) bool {
    return true;
}

pub fn now() f64 {
    return CACurrentMediaTime();
}

/// The user's languages in order of preference, as comma-separated locale identifiers ("uk-UA,en-US").
/// On macOS this is the system list, or the application's own list if one is set for it in System Settings.
/// Every platform layer supplies this function; choosing among the game's languages is `i18n`'s job.
pub fn preferredLanguages(buf: []u8) []const u8 {
    const pool = objc.poolPush();
    defer objc.poolPop(pool);
    const list = objc.get(objc.class("NSLocale"), "preferredLanguages");
    const count = objc.send(fn (id, SEL) callconv(.c) u64, list, "count", .{});
    var n: usize = 0;
    for (0..count) |i| {
        const item = objc.send(fn (id, SEL, u64) callconv(.c) id, list, "objectAtIndex:", .{i});
        const tag = std.mem.span(objc.cString(item));
        if (n + tag.len + 1 > buf.len) break;
        if (n > 0) {
            buf[n] = ',';
            n += 1;
        }
        @memcpy(buf[n..][0..tag.len], tag);
        n += tag.len;
    }
    return buf[0..n];
}

/// Titles of the two items in the application menu.
pub const MenuTitles = struct { fullscreen: [*:0]const u8, quit: [*:0]const u8 };

pub const Platform = struct {
    app: id,
    window: id,
    view: id,
    fullscreen_item: id,
    quit_item: id,
    captured: bool = false,
    input: Input = .{},

    pub fn init(title: [*:0]const u8, menu: MenuTitles, layer: id, w: f64, h: f64) Platform {
        const app = objc.get(objc.class("NSApplication"), "sharedApplication");
        _ = objc.send(fn (id, SEL, i64) callconv(.c) bool, app, "setActivationPolicy:", .{0});

        const Delegate = objc.makeClass("NSObject", "DDCDelegate");
        objc.addMethod(Delegate, "windowWillClose:", &windowWillClose, "v@:@");
        objc.addMethod(Delegate, "windowDidResignKey:", &windowDidResignKey, "v@:@");
        objc.addMethod(Delegate, "applicationShouldTerminate:", &shouldTerminate, "Q@:@");
        objc.addMethod(Delegate, "applicationShouldTerminateAfterLastWindowClosed:", &shouldTerminateAfterLastWindowClosed, "B@:@");
        objc.registerClass(Delegate);
        const delegate = objc.send(fn (id, SEL) callconv(.c) id, objc.send(fn (id, SEL) callconv(.c) id, Delegate, "alloc", .{}), "init", .{});
        objc.setObj(app, "setDelegate:", delegate);

        // Menu bar: Quit and Full Screen.
        const menubar = objc.new("NSMenu");
        const app_item = objc.new("NSMenuItem");
        objc.setObj(menubar, "addItem:", app_item);
        objc.setObj(app, "setMainMenu:", menubar);
        const app_menu = objc.new("NSMenu");
        const fs_item = objc.send(fn (id, SEL, id, SEL, id) callconv(.c) id, objc.alloc("NSMenuItem"), "initWithTitle:action:keyEquivalent:", .{ objc.nsString(menu.fullscreen), objc.sel("toggleFullScreen:"), objc.nsString("f") });
        objc.setObj(app_menu, "addItem:", fs_item);
        const quit_item = objc.send(fn (id, SEL, id, SEL, id) callconv(.c) id, objc.alloc("NSMenuItem"), "initWithTitle:action:keyEquivalent:", .{ objc.nsString(menu.quit), objc.sel("terminate:"), objc.nsString("q") });
        objc.setObj(app_menu, "addItem:", quit_item);
        objc.setObj(app_item, "setSubmenu:", app_menu);

        const window = objc.send(fn (id, SEL, objc.Rect, u64, u64, bool) callconv(.c) id, objc.alloc("NSWindow"), "initWithContentRect:styleMask:backing:defer:", .{ objc.Rect{ .x = 0, .y = 0, .w = w, .h = h }, 15, 2, false });
        objc.setObj(window, "setTitle:", objc.nsString(title));
        objc.setObj(window, "setDelegate:", delegate);
        objc.setB(window, "setAcceptsMouseMovedEvents:", true);
        objc.setU(window, "setCollectionBehavior:", 1 << 7);
        objc.setB(window, "setReleasedWhenClosed:", false);
        objc.send(fn (id, SEL, objc.Size) callconv(.c) void, window, "setContentMinSize:", .{objc.Size{ .w = 800, .h = 500 }});
        objc.call(window, "center");

        const view = objc.get(window, "contentView");
        objc.setObj(view, "setLayer:", layer);
        objc.setB(view, "setWantsLayer:", true);

        objc.call(app, "finishLaunching");
        objc.setObj(window, "makeKeyAndOrderFront:", null);
        objc.setB(app, "activateIgnoringOtherApps:", true);
        return .{ .app = app, .window = window, .view = view, .fullscreen_item = fs_item, .quit_item = quit_item };
    }

    /// Retitle the application menu, for when the language changes while the game is running.
    pub fn setMenuTitles(p: *Platform, menu: MenuTitles) void {
        objc.setObj(p.fullscreen_item, "setTitle:", objc.nsString(menu.fullscreen));
        objc.setObj(p.quit_item, "setTitle:", objc.nsString(menu.quit));
    }

    /// The title an item of the application menu shows now, read back from the menu itself. Valid until the
    /// enclosing autorelease pool drains.
    pub fn menuTitle(p: *Platform, item: enum { fullscreen, quit }) []const u8 {
        const title = objc.get(if (item == .quit) p.quit_item else p.fullscreen_item, "title");
        return std.mem.span(objc.send(fn (id, SEL) callconv(.c) [*:0]const u8, title, "UTF8String", .{}));
    }

    /// Drawable size in pixels and the backing scale factor.
    pub fn pixelSize(p: *Platform) struct { w: u32, h: u32, scale: f64 } {
        const b = objc.send(fn (id, SEL) callconv(.c) objc.Rect, p.view, "bounds", .{});
        const scale = objc.send(fn (id, SEL) callconv(.c) f64, p.window, "backingScaleFactor", .{});
        return .{ .w = @intFromFloat(@max(8, b.w * scale)), .h = @intFromFloat(@max(8, b.h * scale)), .scale = scale };
    }

    pub fn shouldQuit(_: *Platform) bool {
        return quit_requested;
    }

    pub fn toggleFullscreen(p: *Platform) void {
        objc.setObj(p.window, "toggleFullScreen:", null);
    }

    /// Hide and freeze the cursor so mouse deltas drive the look direction.
    pub fn capture(p: *Platform, on: bool) void {
        if (on == p.captured) return;
        p.captured = on;
        if (on) {
            const f = objc.send(fn (id, SEL) callconv(.c) objc.Rect, p.window, "frame", .{});
            const screen = objc.get(objc.class("NSScreen"), "mainScreen");
            const sf = objc.send(fn (id, SEL) callconv(.c) objc.Rect, screen, "frame", .{});
            _ = CGWarpMouseCursorPosition(.{ .x = f.x + f.w * 0.5, .y = sf.h - (f.y + f.h * 0.5) });
            _ = CGAssociateMouseAndMouseCursorPosition(0);
            objc.call(objc.class("NSCursor"), "hide");
        } else {
            _ = CGAssociateMouseAndMouseCursorPosition(1);
            objc.call(objc.class("NSCursor"), "unhide");
        }
    }

    /// Drain the event queue into `input`. Returns true if the window lost focus since the last call.
    pub fn pump(p: *Platform) bool {
        const in = &p.input;
        while (true) {
            const ev = objc.send(fn (id, SEL, u64, id, id, bool) callconv(.c) id, p.app, "nextEventMatchingMask:untilDate:inMode:dequeue:", .{ std.math.maxInt(u64), null, NSDefaultRunLoopMode, true }) orelse break;
            const ty = objc.send(fn (id, SEL) callconv(.c) u64, ev, "type", .{});
            const flags = objc.send(fn (id, SEL) callconv(.c) u64, ev, "modifierFlags", .{});
            const cmd = flags & (1 << 20) != 0;
            var forward = true;
            switch (ty) {
                10, 11 => { // key down / up
                    const code = objc.send(fn (id, SEL) callconv(.c) u16, ev, "keyCode", .{});
                    if (!cmd) {
                        forward = false;
                        if (code < 128) {
                            const is_down = ty == 10;
                            if (is_down and !in.keys[code]) in.pressed[code] = true;
                            in.keys[code] = is_down;
                        }
                    }
                },
                12 => { // modifiers
                    in.set(.shift, flags & (1 << 17) != 0);
                    in.set(.control, flags & (1 << 18) != 0);
                    in.set(.option, flags & (1 << 19) != 0);
                },
                5, 6, 7, 27 => {
                    in.mouse_dx += @floatCast(objc.send(fn (id, SEL) callconv(.c) f64, ev, "deltaX", .{}));
                    in.mouse_dy += @floatCast(objc.send(fn (id, SEL) callconv(.c) f64, ev, "deltaY", .{}));
                    if (p.captured) forward = false;
                },
                1, 2 => if (p.captured or (ty == 1 and p.insideContent(ev))) {
                    if (ty == 1 and !in.lmb) in.lmb_pressed = true;
                    in.lmb = ty == 1;
                    if (p.captured) forward = false;
                } else if (ty == 2) {
                    in.lmb = false;
                },
                3, 4 => {
                    if (ty == 3 and !in.rmb) in.rmb_pressed = true;
                    in.rmb = ty == 3;
                    if (p.captured) forward = false;
                },
                else => {},
            }
            if (forward) objc.setObj(p.app, "sendEvent:", ev);
        }
        const lost = lost_focus;
        lost_focus = false;
        if (lost) in.releaseAll();
        return lost;
    }

    fn insideContent(p: *Platform, ev: id) bool {
        if (objc.get(ev, "window") != p.window) return false;
        const loc = objc.send(fn (id, SEL) callconv(.c) objc.Point, ev, "locationInWindow", .{});
        const b = objc.send(fn (id, SEL) callconv(.c) objc.Rect, p.view, "bounds", .{});
        return loc.x >= 0 and loc.y >= 0 and loc.x < b.w and loc.y < b.h;
    }

    /// Post a synthetic key event into this application's own queue (used by the end-to-end demo run, so
    /// scripted input travels the same path as the keyboard without touching other applications).
    pub fn postKey(p: *Platform, key: Key, is_down: bool) void {
        const ev = objc.send(fn (id, SEL, u64, objc.Point, u64, f64, i64, id, id, id, bool, u16) callconv(.c) id, objc.class("NSEvent"), "keyEventWithType:location:modifierFlags:timestamp:windowNumber:context:characters:charactersIgnoringModifiers:isARepeat:keyCode:", .{
            @as(u64, if (is_down) 10 else 11),
            objc.Point{ .x = 0, .y = 0 },
            0,
            now(),
            objc.send(fn (id, SEL) callconv(.c) i64, p.window, "windowNumber", .{}),
            null,
            objc.nsString(""),
            objc.nsString(""),
            false,
            @as(u16, @intFromEnum(key)),
        });
        if (ev != null) objc.send(fn (id, SEL, id, bool) callconv(.c) void, p.app, "postEvent:atStart:", .{ ev, false });
    }
};
