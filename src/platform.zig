//! The seam between the game and the operating system: what a key is, what a frame of keyboard and mouse
//! input looks like, and the window, clock and system-language functions every backend supplies. The
//! types here are the same on every platform and import nothing from one; the implementation is picked at
//! compile time (`platform/macos.zig` over AppKit, `platform/windows.zig` over Win32).

const std = @import("std");
const builtin = @import("builtin");
const pad = @import("pad.zig");

/// Keys by physical position, named for the legend on a US keyboard. A backend maps its hardware codes to
/// these (macOS virtual key codes, Windows scan codes), so `W A S D` is the same cluster on any layout.
pub const Key = enum(u8) {
    a,
    s,
    d,
    f,
    h,
    g,
    z,
    x,
    c,
    v,
    b,
    q,
    w,
    e,
    r,
    y,
    t,
    n1,
    n2,
    n3,
    n4,
    n6,
    n5,
    n9,
    n7,
    n8,
    n0,
    o,
    u,
    i,
    p,
    enter,
    l,
    j,
    k,
    n,
    m,
    tab,
    space,
    escape,
    /// Either Shift key.
    shift,
    /// Option on a Mac keyboard, Alt on a PC one.
    option,
    control,
    left,
    right,
    down,
    up,

    pub const count = @typeInfo(Key).@"enum".field_names.len;
};

/// Keyboard and mouse state for one frame. A backend's event pump writes it; `endFrame` clears the edges.
pub const Input = struct {
    keys: [Key.count]bool = @splat(false),
    pressed: [Key.count]bool = @splat(false),
    /// Keys the game has no binding for, by the backend's own code. They do nothing, but one being pressed
    /// or held still says the player's hands are on the keyboard.
    other: std.StaticBitSet(256) = .empty,
    other_pressed: bool = false,
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
    /// A key with no `Key` of its own went down or up; `code` is whatever the backend calls it.
    pub fn setOther(in: *Input, code: u8, is_down: bool) void {
        if (is_down and !in.other.isSet(code)) in.other_pressed = true;
        in.other.setValue(code, is_down);
    }
    pub fn endFrame(in: *Input) void {
        in.pressed = @splat(false);
        in.other_pressed = false;
        in.mouse_dx = 0;
        in.mouse_dy = 0;
        in.lmb_pressed = false;
        in.rmb_pressed = false;
    }
    pub fn releaseAll(in: *Input) void {
        in.keys = @splat(false);
        in.other = .empty;
        in.lmb = false;
        in.rmb = false;
    }
    /// A key or mouse button went down this frame. Mouse movement is not counted.
    pub fn anyPressed(in: *const Input) bool {
        return in.lmb_pressed or in.rmb_pressed or in.other_pressed or std.mem.indexOfScalar(bool, &in.pressed, true) != null;
    }
    /// A key or mouse button is down.
    pub fn anyHeld(in: *const Input) bool {
        return in.lmb or in.rmb or in.other.count() > 0 or std.mem.indexOfScalar(bool, &in.keys, true) != null;
    }
};

/// Where `Platform.pad` comes from.
pub const PadSource = enum {
    /// The controller the player last used, as the operating system reports it.
    system,
    /// The backend's `SyntheticPad`: a controller that belongs to no device, written by the tests and read
    /// back by the same code that reads a real one.
    synthetic,
    /// The caller writes `Platform.pad` itself.
    injected,
};

/// Titles of the two window commands that are not on the game's own screens: full screen and quit. macOS
/// shows them in the application menu, Windows in the window's system menu.
pub const MenuTitles = struct { fullscreen: [*:0]const u8, quit: [*:0]const u8 };
pub const MenuItem = enum { fullscreen, quit };

/// The keys that are commands for the window rather than input for the game. A key pressed with `modifier`
/// held is offered to the window first (the menu bar on a Mac, the window's own shortcuts on Windows) and
/// reaches the game only if the window has no use for it; its release always reaches the game.
pub const Shortcut = struct {
    /// The modifier's name as the player knows it: "Cmd" or "Alt".
    modifier: []const u8,
    /// The key that toggles full screen when pressed with the modifier, and its legend.
    fullscreen: Key,
    fullscreen_name: []const u8,
    /// The legend of the key that quits when pressed with the modifier. It need not be a key the game
    /// binds (F4 on Windows), so the input test presses it through `Platform.postQuitShortcut`.
    quit_name: []const u8,
};

/// Drawable size in pixels and the number of pixels per point.
pub const PixelSize = struct { w: u32, h: u32, scale: f64 };

/// The implementation for the target. Each one supplies the declarations re-exported below, with the same
/// names and meanings.
pub const backend = switch (builtin.os.tag) {
    .macos => @import("platform/macos.zig"),
    .windows => @import("platform/windows.zig"),
    else => @compileError("no platform backend for this operating system"),
};

/// The window, its event pump and its input state.
pub const Platform = backend.Platform;
/// A controller the tests can hold; see `PadSource.synthetic`.
pub const SyntheticPad = backend.SyntheticPad;
/// What the window hands the GPU backend to draw into (`gpu.Gpu.attach`).
pub const Surface = backend.Surface;

/// Seconds on a monotonic clock.
pub const now = backend.now;
/// The user's languages in order of preference, as comma-separated locale identifiers ("uk-UA,en-US").
/// Choosing among the game's languages is `i18n`'s job.
pub const preferredLanguages = backend.preferredLanguages;
/// Once, first thing in `main`: whatever the process needs before it prints or opens a window.
pub const initProcess = backend.initProcess;
/// Bracket a stretch of work whose temporary system objects can be freed at its end (an autorelease pool
/// on macOS; nothing elsewhere).
pub const scopeBegin = backend.scopeBegin;
pub const scopeEnd = backend.scopeEnd;
/// Cleanup to run if the system ends the process from inside the event pump, where the main loop's own
/// cleanup would not be reached.
pub const setTerminateHook = backend.setTerminateHook;
/// Path of a shader source file shipped beside the executable, or null if the executable cannot be found.
pub const shaderPath = backend.shaderPath;
/// Tell the player why the game could not start, where there is no terminal to print to.
pub const reportFatal = backend.reportFatal;
/// This platform's window shortcuts; see `Shortcut`.
pub const shortcut: Shortcut = backend.shortcut;
/// The two shortcuts as a prompt prints them: "Cmd+F" and "Cmd+Q" on a Mac, "Alt+Enter" and "Alt+F4" on
/// Windows. The string catalogue holds neither, so a screen cannot name another platform's keys.
pub const fullscreen_keys: []const u8 = shortcut.modifier ++ "+" ++ shortcut.fullscreen_name;
pub const quit_keys: []const u8 = shortcut.modifier ++ "+" ++ shortcut.quit_name;
/// One line for the demo log: where controllers come from and whether that is available.
pub const padBackendStatus = backend.padBackendStatus;

test {
    // The pure parts of every backend are tested on every host; none of them calls its operating system.
    _ = @import("platform/keymap.zig");
    _ = @import("platform/win32.zig");
    _ = @import("platform/xinput.zig");
    _ = @import("platform/pshid.zig");
    _ = @import("platform/padsel.zig");
}
