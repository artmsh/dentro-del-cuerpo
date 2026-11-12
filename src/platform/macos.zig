//! The macOS backend of `platform.zig`: AppKit window, event pump and input state, and the game controller
//! read through the GameController framework. No Objective-C source: the delegate class is built at runtime.

const std = @import("std");
const objc = @import("objc.zig");
const pad = @import("../pad.zig");
const common = @import("../platform.zig");
const keymap = @import("keymap.zig");
const id = objc.id;
const SEL = objc.SEL;
const Key = common.Key;
const Input = common.Input;
const PadSource = common.PadSource;
const MenuTitles = common.MenuTitles;

extern fn CACurrentMediaTime() f64;
extern fn CGAssociateMouseAndMouseCursorPosition(connected: u32) i32;
extern fn CGWarpMouseCursorPosition(p: objc.Point) i32;
extern const NSDefaultRunLoopMode: id;
extern "c" fn _NSGetExecutablePath(buf: [*]u8, size: *u32) c_int;

/// Cmd+F is what the string catalogue already says.
pub const fullscreen_key: ?[]const u8 = null;

/// Cmd+F and Cmd+Q are the application menu's key equivalents.
pub const shortcut: common.Shortcut = .{ .modifier = "Cmd", .fullscreen = .f, .fullscreen_name = "F" };

/// The window's content view; the Metal backend gives it a layer.
pub const Surface = id;

pub fn initProcess() void {}

pub fn scopeBegin() ?*anyopaque {
    return objc.poolPush();
}

pub fn scopeEnd(pool: ?*anyopaque) void {
    objc.poolPop(pool);
}

/// The copy of a shader file in the bundle's Resources, addressed from the executable in MacOS/.
pub fn shaderPath(buf: []u8, file: []const u8) ?[:0]const u8 {
    var path_buf: [1024]u8 = undefined;
    var size: u32 = path_buf.len;
    if (_NSGetExecutablePath(&path_buf, &size) != 0) return null;
    const exe = std.mem.span(@as([*:0]u8, @ptrCast(&path_buf)));
    const slash = std.mem.lastIndexOfScalar(u8, exe, '/') orelse return null;
    return std.fmt.bufPrintSentinel(buf, "{s}/../Resources/shaders/{s}", .{ exe[0..slash], file }, 0) catch null;
}

/// A failure to start is printed by the runtime, and a Mac user who launched from Finder finds it in the
/// system log; there is nothing to add.
pub fn reportFatal(_: []const u8) void {}

pub fn padBackendStatus() []const u8 {
    return if (Gamepad.available()) "GameController framework loaded" else "GameController framework missing";
}

// ---------------------------------------------------------------------------- game controller

/// The GameController framework, polled. It supports Xbox, DualShock 4 and DualSense controllers over
/// USB and Bluetooth with no driver, and presents each as an "extended gamepad": two sticks, two analog
/// triggers, four face buttons, two shoulder buttons, a d-pad and the menu buttons. Nothing is registered
/// with it: the list of controllers and the state of their elements are read once a frame, which covers a
/// controller that was on before launch, one that is switched on later and one that goes away, with no
/// notification to miss. Its bookkeeping runs on the main thread's run loop, which `Platform.pump` turns.
pub const Gamepad = struct {
    /// The controller last read, to notice when it changes.
    seen: id = null,

    pub fn init() Gamepad {
        // Input while another application is in front is not wanted. This is the default for programs
        // built against macOS 11.3 or later; it is set anyway, since the build's SDK is not this code's
        // to choose. `poll` does not rely on it either: it reads nothing while the window is not key.
        if (objc.classOpt("GCController")) |cls| objc.setB(cls, "setShouldMonitorBackgroundEvents:", false);
        return .{};
    }

    /// True if the framework's classes are in the process.
    pub fn available() bool {
        return objc.classOpt("GCController") != null;
    }

    /// The controller to read and its extended-gamepad profile: the one the player touched last if it has
    /// that profile, otherwise the first attached one that does. Null if there is none.
    fn find() ?[2]id {
        const cls = objc.classOpt("GCController") orelse return null;
        if (objc.get(cls, "current")) |c| {
            if (objc.get(c, "extendedGamepad")) |profile| return .{ c, profile };
        }
        const list = objc.get(cls, "controllers") orelse return null;
        const count = objc.send(fn (id, SEL) callconv(.c) u64, list, "count", .{});
        for (0..count) |i| {
            const c = objc.send(fn (id, SEL, u64) callconv(.c) id, list, "objectAtIndex:", .{i});
            if (objc.get(c, "extendedGamepad")) |profile| return .{ c, profile };
        }
        return null;
    }

    /// This frame's controller. While `focused` is false the controller is reported as attached and idle,
    /// whatever is held on it.
    pub fn poll(g: *Gamepad, focused: bool) pad.State {
        const found = find() orelse {
            if (g.seen != null) std.debug.print("gamepad: disconnected\n", .{});
            g.seen = null;
            return .{};
        };
        const controller = found[0];
        const profile = found[1];
        if (controller != g.seen) {
            g.seen = controller;
            adopt(controller, profile);
        }
        if (!focused) return .{ .connected = true, .family = familyOf(profile) };
        return read(profile);
    }

    /// Runs once for each controller that becomes the one in use.
    fn adopt(controller: id, profile: id) void {
        // The Create button of a PlayStation controller (Share on a DualShock 4) is where macOS listens for
        // its screenshot and recording gestures, and by default it holds the press back from the program
        // until it has decided the press was not one. The game uses that button, so it asks for it outright.
        const options = objc.get(profile, "buttonOptions");
        if (options != null and objc.send(fn (id, SEL) callconv(.c) bool, options, "isBoundToSystemGesture", .{})) {
            objc.send(fn (id, SEL, i64) callconv(.c) void, options, "setPreferredSystemGestureState:", .{2}); // GCSystemGestureStateDisabled
        }
        const name = objc.get(controller, "vendorName");
        std.debug.print("gamepad: {s} ({s})\n", .{ if (name != null) std.mem.span(objc.cString(name)) else "unnamed", @tagName(familyOf(profile)) });
    }

    fn isKind(obj: id, class_name: [*:0]const u8) bool {
        const cls = objc.classOpt(class_name) orelse return false;
        return objc.send(fn (id, SEL, id) callconv(.c) bool, obj, "isKindOfClass:", .{cls});
    }

    /// The framework has a profile class for each family it knows; anything else is generic.
    pub fn familyOf(profile: id) pad.Family {
        if (isKind(profile, "GCDualSenseGamepad") or isKind(profile, "GCDualShockGamepad")) return .playstation;
        if (isKind(profile, "GCXboxGamepad")) return .xbox;
        return .generic;
    }

    fn pressed(element: id) bool {
        // An element the controller does not have is nil, and a message to nil answers false.
        return objc.send(fn (id, SEL) callconv(.c) bool, element, "isPressed", .{});
    }

    fn value(element: id) f32 {
        return objc.send(fn (id, SEL) callconv(.c) f32, element, "value", .{});
    }

    /// The state of a `GCExtendedGamepad`, element by element. No dead zone or threshold is applied here.
    pub fn read(profile: id) pad.State {
        var st: pad.State = .{ .connected = true, .family = familyOf(profile) };
        const left = objc.get(profile, "leftThumbstick");
        const right = objc.get(profile, "rightThumbstick");
        st.left = .{ value(objc.get(left, "xAxis")), value(objc.get(left, "yAxis")) };
        st.right = .{ value(objc.get(right, "xAxis")), value(objc.get(right, "yAxis")) };
        st.lt = value(objc.get(profile, "leftTrigger"));
        st.rt = value(objc.get(profile, "rightTrigger"));
        const dpad = objc.get(profile, "dpad");
        inline for (.{
            .{ pad.Button.a, "buttonA" },
            .{ pad.Button.b, "buttonB" },
            .{ pad.Button.x, "buttonX" },
            .{ pad.Button.y, "buttonY" },
            .{ pad.Button.lb, "leftShoulder" },
            .{ pad.Button.rb, "rightShoulder" },
            .{ pad.Button.ls, "leftThumbstickButton" },
            .{ pad.Button.rs, "rightThumbstickButton" },
            .{ pad.Button.start, "buttonMenu" },
            .{ pad.Button.back, "buttonOptions" },
        }) |e| st.set(e[0], pressed(objc.get(profile, e[1])));
        inline for (.{
            .{ pad.Button.dpad_up, "up" },
            .{ pad.Button.dpad_down, "down" },
            .{ pad.Button.dpad_left, "left" },
            .{ pad.Button.dpad_right, "right" },
        }) |e| st.set(e[0], pressed(objc.get(dpad, e[1])));
        return st;
    }

    /// A controller of the framework's own making, not attached to any device, whose elements can be
    /// written. Null if the framework is not there.
    pub fn makeSnapshot() id {
        const cls = objc.classOpt("GCController") orelse return null;
        return objc.get(cls, "controllerWithExtendedGamepad");
    }

    /// Writes `st` onto a snapshot controller's elements, as a device would set them. The framework
    /// ignores the writes on a controller that is a real device.
    pub fn write(controller: id, st: pad.State) void {
        const profile = objc.get(controller, "extendedGamepad");
        const setValue = struct {
            fn f(element: id, v: f32) void {
                objc.send(fn (id, SEL, f32) callconv(.c) void, element, "setValue:", .{v});
            }
        }.f;
        const setXY = struct {
            fn f(element: id, x: f32, y: f32) void {
                objc.send(fn (id, SEL, f32, f32) callconv(.c) void, element, "setValueForXAxis:yAxis:", .{ x, y });
            }
        }.f;
        setXY(objc.get(profile, "leftThumbstick"), st.left[0], st.left[1]);
        setXY(objc.get(profile, "rightThumbstick"), st.right[0], st.right[1]);
        setValue(objc.get(profile, "leftTrigger"), st.lt);
        setValue(objc.get(profile, "rightTrigger"), st.rt);
        inline for (.{
            .{ pad.Button.a, "buttonA" },
            .{ pad.Button.b, "buttonB" },
            .{ pad.Button.x, "buttonX" },
            .{ pad.Button.y, "buttonY" },
            .{ pad.Button.lb, "leftShoulder" },
            .{ pad.Button.rb, "rightShoulder" },
            .{ pad.Button.ls, "leftThumbstickButton" },
            .{ pad.Button.rs, "rightThumbstickButton" },
            .{ pad.Button.start, "buttonMenu" },
            .{ pad.Button.back, "buttonOptions" },
        }) |e| setValue(objc.get(profile, e[1]), if (st.buttons.contains(e[0])) 1 else 0);
        const b = st.buttons;
        setXY(
            objc.get(profile, "dpad"),
            @as(f32, if (b.contains(.dpad_right)) 1 else 0) - @as(f32, if (b.contains(.dpad_left)) 1 else 0),
            @as(f32, if (b.contains(.dpad_up)) 1 else 0) - @as(f32, if (b.contains(.dpad_down)) 1 else 0),
        );
    }
};

var quit_requested: bool = false;
var lost_focus: bool = false;
var menu_probe_hits: u32 = 0;

fn menuProbe(_: id, _: SEL, _: id) callconv(.c) void {
    menu_probe_hits += 1;
}

fn windowWillClose(_: id, _: SEL, _: id) callconv(.c) void {
    quit_requested = true;
}
fn windowDidResignKey(_: id, _: SEL, _: id) callconv(.c) void {
    lost_focus = true;
}
/// Runs when AppKit is about to terminate the process (Cmd+Q, a quit Apple Event, logout). terminate: calls
/// exit() from inside the event pump, so the main loop's own cleanup never runs; this hook is that cleanup.
var on_terminate: ?*const fn () void = null;

pub fn setTerminateHook(f: *const fn () void) void {
    on_terminate = f;
}

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

/// The system's list of preferred languages, or the application's own list if one is set for it in System
/// Settings.
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

/// The Cmd bit of an event's modifier flags.
const cmd_flag: u64 = 1 << 20;

/// Where to put the cursor so that it sits at the centre of a window. `frame` is the window's frame as
/// AppKit gives it: in points, y up, origin at the bottom left of the primary display. The answer is in
/// the coordinates `CGWarpMouseCursorPosition` takes: y down, origin at the top left of the primary
/// display. Both spaces span every display, so the flip is about the height of the primary display, the
/// one at index 0 of `NSScreen.screens`, whichever display the window is on.
pub fn warpTarget(frame: objc.Rect, primary_height: f64) objc.Point {
    return .{ .x = frame.x + frame.w * 0.5, .y = primary_height - (frame.y + frame.h * 0.5) };
}

pub const Platform = struct {
    app: id,
    window: id,
    view: id,
    fullscreen_item: id,
    quit_item: id,
    delegate: id = null,
    captured: bool = false,
    /// Keys whose press the menu bar took as a shortcut. Their repeats are nobody's until the key comes up.
    menu_keys: [128]bool = @splat(false),
    input: Input = .{},
    /// The game controller this frame, as the device reports it; `pump` refreshes it from `pad_source`.
    /// This struct is all the rest of the program knows of a controller.
    pad: pad.State = .{},
    pad_source: PadSource = .system,
    gamepad: Gamepad = .{},
    /// The framework-made controller `SyntheticPad` writes to, read when `pad_source` is `.synthetic`.
    synthetic: id = null,

    /// Builds the window without showing it. The GPU backend attaches to `surface()` next, and `show`
    /// puts the window on screen.
    pub fn init(title: [*:0]const u8, menu: MenuTitles, w: f64, h: f64) Platform {
        const app = objc.get(objc.class("NSApplication"), "sharedApplication");
        _ = objc.send(fn (id, SEL, i64) callconv(.c) bool, app, "setActivationPolicy:", .{0});

        const Delegate = objc.makeClass("NSObject", "DDCDelegate");
        objc.addMethod(Delegate, "windowWillClose:", &windowWillClose, "v@:@");
        objc.addMethod(Delegate, "windowDidResignKey:", &windowDidResignKey, "v@:@");
        objc.addMethod(Delegate, "applicationShouldTerminate:", &shouldTerminate, "Q@:@");
        objc.addMethod(Delegate, "applicationShouldTerminateAfterLastWindowClosed:", &shouldTerminateAfterLastWindowClosed, "B@:@");
        objc.addMethod(Delegate, "ddcMenuProbe:", &menuProbe, "v@:@");
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
        return .{ .app = app, .window = window, .view = view, .fullscreen_item = fs_item, .quit_item = quit_item, .delegate = delegate, .gamepad = Gamepad.init() };
    }

    pub fn surface(p: *Platform) Surface {
        return p.view;
    }

    pub fn show(p: *Platform) void {
        objc.call(p.app, "finishLaunching");
        objc.setObj(p.window, "makeKeyAndOrderFront:", null);
        objc.setB(p.app, "activateIgnoringOtherApps:", true);
    }

    /// True while this window is the one the keyboard types into.
    pub fn isKey(p: *Platform) bool {
        return objc.send(fn (id, SEL) callconv(.c) bool, p.window, "isKeyWindow", .{});
    }

    /// Whether controller input should count this frame. A real controller is heard only while the window
    /// is key, like the keyboard; a source the tests supply is theirs to control.
    pub fn padFocused(p: *Platform) bool {
        return p.pad_source != .system or p.isKey();
    }

    /// Retitle the application menu, for when the language changes while the game is running.
    pub fn setMenuTitles(p: *Platform, menu: MenuTitles) void {
        objc.setObj(p.fullscreen_item, "setTitle:", objc.nsString(menu.fullscreen));
        objc.setObj(p.quit_item, "setTitle:", objc.nsString(menu.quit));
    }

    /// The title an item of the application menu shows now, read back from the menu itself. Valid until the
    /// enclosing autorelease pool drains.
    pub fn menuTitle(p: *Platform, item: common.MenuItem) []const u8 {
        const title = objc.get(if (item == .quit) p.quit_item else p.fullscreen_item, "title");
        return std.mem.span(objc.send(fn (id, SEL) callconv(.c) [*:0]const u8, title, "UTF8String", .{}));
    }

    /// Drawable size in pixels and the backing scale factor.
    pub fn pixelSize(p: *Platform) common.PixelSize {
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

    /// Quit as the Quit menu item does: AppKit runs `applicationShouldTerminate:` and exits the process.
    pub fn quit(p: *Platform) void {
        objc.setObj(p.app, "terminate:", null);
    }

    /// For the input test. While `on`, the Full Screen menu item counts its activations instead of acting,
    /// so the test can press Cmd+F and see the shortcut arrive without the window changing mode.
    pub fn probeFullscreen(p: *Platform, on: bool) void {
        objc.setObj(p.fullscreen_item, "setTarget:", if (on) p.delegate else null);
        objc.send(fn (id, SEL, SEL) callconv(.c) void, p.fullscreen_item, "setAction:", .{objc.sel(if (on) "ddcMenuProbe:" else "toggleFullScreen:")});
    }

    pub fn fullscreenProbeHits(_: *Platform) u32 {
        return menu_probe_hits;
    }

    /// Hide and freeze the cursor so mouse deltas drive the look direction.
    pub fn capture(p: *Platform, on: bool) void {
        if (on == p.captured) return;
        p.captured = on;
        if (on) {
            // The primary display is the first of `screens`. `mainScreen` is the one with the key window,
            // which is a different display, of a different height, when the game is on a second monitor.
            const screens = objc.get(objc.class("NSScreen"), "screens");
            if (objc.send(fn (id, SEL) callconv(.c) u64, screens, "count", .{}) > 0) {
                const primary = objc.send(fn (id, SEL, u64) callconv(.c) id, screens, "objectAtIndex:", .{@as(u64, 0)});
                const pf = objc.send(fn (id, SEL) callconv(.c) objc.Rect, primary, "frame", .{});
                const f = objc.send(fn (id, SEL) callconv(.c) objc.Rect, p.window, "frame", .{});
                _ = CGWarpMouseCursorPosition(warpTarget(f, pf.h));
            }
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
            const cmd = flags & cmd_flag != 0;
            var forward = true;
            switch (ty) {
                10, 11 => { // key down / up
                    // Key events stop here. With no text field to take them AppKit would only beep, and it
                    // discards a key-up that arrives while Cmd is held. What AppKit would have done with a
                    // key pressed under Cmd is done directly: the menu bar is offered it, which is where
                    // Cmd+F and Cmd+Q are. A press the menu takes is not the game's, and neither are its
                    // repeats. Every other press is recorded whatever the modifiers, and every release is
                    // recorded without exception: a key held through Cmd+F and let go before Cmd comes up
                    // with the Cmd flag set, and dropping it left the key down for good.
                    forward = false;
                    const code = objc.send(fn (id, SEL) callconv(.c) u16, ev, "keyCode", .{});
                    const is_down = ty == 10;
                    if (code < 128) {
                        const key = keymap.fromMac(code);
                        const held = if (key) |k| in.down(k) else in.other.isSet(code);
                        if (!is_down) {
                            p.menu_keys[code] = false;
                            record(in, key, code, false);
                        } else if (!p.menu_keys[code]) {
                            if (cmd and !held and objc.send(fn (id, SEL, id) callconv(.c) bool, objc.get(p.app, "mainMenu"), "performKeyEquivalent:", .{ev})) {
                                p.menu_keys[code] = true;
                            } else {
                                record(in, key, code, true);
                            }
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
        switch (p.pad_source) {
            .system => p.pad = p.gamepad.poll(p.isKey()),
            .synthetic => p.pad = Gamepad.read(objc.get(p.synthetic, "extendedGamepad")),
            .injected => {},
        }
        const lost = lost_focus;
        lost_focus = false;
        if (lost) {
            in.releaseAll();
            p.menu_keys = @splat(false);
        }
        return lost;
    }

    /// Post a synthetic mouse-moved event into this application's own queue. It carries no movement; what
    /// it tests is that an event of this kind arriving changes nothing but the look direction.
    pub fn postMouseMove(p: *Platform) void {
        const ev = objc.send(fn (id, SEL, u64, objc.Point, u64, f64, i64, id, i64, i64, f32) callconv(.c) id, objc.class("NSEvent"), "mouseEventWithType:location:modifierFlags:timestamp:windowNumber:context:eventNumber:clickCount:pressure:", .{
            @as(u64, 5),
            objc.Point{ .x = 10, .y = 10 },
            0,
            now(),
            objc.send(fn (id, SEL) callconv(.c) i64, p.window, "windowNumber", .{}),
            null,
            0,
            0,
            0,
        });
        if (ev != null) objc.send(fn (id, SEL, id, bool) callconv(.c) void, p.app, "postEvent:atStart:", .{ ev, false });
    }

    fn record(in: *Input, key: ?Key, code: u16, is_down: bool) void {
        if (key) |k| in.set(k, is_down) else in.setOther(@intCast(code), is_down);
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
        p.postKeyWith(key, is_down, 0, "");
    }

    /// `postKey` with Cmd held. The event carries the character the key types, which is what a menu
    /// shortcut is matched on; only letters have one here, which covers the menu's two shortcuts.
    pub fn postSystemKey(p: *Platform, key: Key, is_down: bool) void {
        const name = @tagName(key);
        var chars: [2:0]u8 = .{ 0, 0 };
        if (name.len == 1) chars[0] = name[0];
        p.postKeyWith(key, is_down, cmd_flag, &chars);
    }

    fn postKeyWith(p: *Platform, key: Key, is_down: bool, flags: u64, chars: [*:0]const u8) void {
        const ev = objc.send(fn (id, SEL, u64, objc.Point, u64, f64, i64, id, id, id, bool, u16) callconv(.c) id, objc.class("NSEvent"), "keyEventWithType:location:modifierFlags:timestamp:windowNumber:context:characters:charactersIgnoringModifiers:isARepeat:keyCode:", .{
            @as(u64, if (is_down) 10 else 11),
            objc.Point{ .x = 0, .y = 0 },
            flags,
            now(),
            objc.send(fn (id, SEL) callconv(.c) i64, p.window, "windowNumber", .{}),
            null,
            objc.nsString(chars),
            objc.nsString(chars),
            false,
            @as(u16, keymap.toMac(key)),
        });
        if (ev != null) objc.send(fn (id, SEL, id, bool) callconv(.c) void, p.app, "postEvent:atStart:", .{ ev, false });
    }
};

/// The controller the scripted modes hold. It is one of the GameController framework's own objects where
/// the framework will make one, so that the state is read back through `Gamepad.read`, the code that reads
/// a real device; failing that the state is written straight into `Platform.pad`.
pub const SyntheticPad = struct {
    controller: id = null,

    /// How far a value read back may be from the one written. The framework stores floats; there is none.
    pub const tolerance: f32 = 0;

    pub fn attach(plat: *Platform) SyntheticPad {
        const c = Gamepad.makeSnapshot();
        plat.synthetic = c;
        plat.pad_source = if (c != null) .synthetic else .injected;
        return .{ .controller = c };
    }

    /// True if there is a device-side object to write to, so `set` goes through the code that reads a
    /// device.
    pub fn real(sp: SyntheticPad) bool {
        return sp.controller != null;
    }

    /// The source to select for this controller: the synthetic device if there is one.
    pub fn source(sp: SyntheticPad) PadSource {
        return if (sp.controller != null) .synthetic else .injected;
    }

    pub fn set(sp: SyntheticPad, plat: *Platform, st: pad.State) void {
        switch (plat.pad_source) {
            .synthetic => Gamepad.write(sp.controller, st),
            else => plat.pad = st,
        }
    }

    /// Write `st` to the device-side object and read it back with the code that reads a device.
    pub fn roundTrip(sp: SyntheticPad, st: pad.State) pad.State {
        Gamepad.write(sp.controller, st);
        return Gamepad.read(objc.get(sp.controller, "extendedGamepad"));
    }

    pub fn describe(sp: SyntheticPad) []const u8 {
        return if (sp.controller != null) "GCController snapshot, read by the device code" else "state written to Platform.pad";
    }

    /// What the round-trip check is called in the test log.
    pub const round_trip_name = "every stick, trigger and button written to a GCController is read back by the device code";
    pub const no_device_note = "the GameController framework made no controller to write to; the state goes straight to Platform.pad";
};

test "the capture warp flips about the primary display, whichever display the window is on" {
    // A window on the primary display (1512 x 982 points): its centre, measured from the top.
    const on_primary = warpTarget(.{ .x = 36, .y = 41, .w = 1440, .h = 900 }, 982);
    try std.testing.expectEqual(@as(f64, 756), on_primary.x);
    try std.testing.expectEqual(@as(f64, 491), on_primary.y);
    // A 2560 x 1440 display standing to the right of it with the bottom edges level: in AppKit's space it
    // spans x 1512..4072, y 0..1440, and in the space the cursor is warped in its top edge is at y = -458.
    // A full-screen window there has its centre 720 points below that top edge.
    const on_second = warpTarget(.{ .x = 1512, .y = 0, .w = 2560, .h = 1440 }, 982);
    try std.testing.expectEqual(@as(f64, 2792), on_second.x);
    try std.testing.expectEqual(@as(f64, -458 + 720), on_second.y);
    // Flipping about that display's own height, as the code once did, lands 458 points lower, off centre.
    try std.testing.expect(warpTarget(.{ .x = 1512, .y = 0, .w = 2560, .h = 1440 }, 1440).y != on_second.y);
}
