//! The Windows backend of `platform.zig`: a Win32 window and its message pump, keys by scan code, the
//! mouse through Raw Input while it is captured, and game controllers through XInput and, for Sony's,
//! their HID reports. Win32 only; the declarations are in `win32.zig`.

const std = @import("std");
const w = @import("win32.zig");
const pad = @import("../pad.zig");
const common = @import("../platform.zig");
const keymap = @import("keymap.zig");
const xinput = @import("xinput.zig");
const pshid = @import("pshid.zig");
const padsel = @import("padsel.zig");
const Key = common.Key;
const Input = common.Input;
const PadSource = common.PadSource;
const MenuTitles = common.MenuTitles;

/// Windows has no Cmd key; the pause screen prints this in place of the catalogue's shortcut.
pub const fullscreen_key: ?[]const u8 = "Alt+Enter";

/// Alt+Enter and Alt+F4 are handled in `Platform.onKey`; F11 is a second full-screen key with no modifier.
pub const shortcut: common.Shortcut = .{ .modifier = "Alt", .fullscreen = .enter, .fullscreen_name = "Enter" };

/// The window handle; the Direct3D backend makes a swap chain for it.
pub const Surface = w.HWND;

/// Raw mouse counts to the units the look code was tuned in, which are the points macOS reports after its
/// pointer acceleration. Raw Input is not accelerated, so no factor matches at every speed; this one
/// matches a hand moving at a moderate pace with a 1000 dpi mouse (about 48 degrees of turn per inch).
const mouse_scale: f32 = 0.35;

/// Smallest client area, in units of 1/96 inch: the size at which the HUD is still legible.
const min_client = [2]i32{ 800, 500 };

/// Identifier of the full-screen command in the window's system menu. System-menu commands of an
/// application's own must be below 0xF000 with the low four bits clear.
const cmd_fullscreen: usize = 0x0010;
/// The icon's identifier in the resource script (res/windows/dentro.rc).
const icon_resource: usize = 1;

var quit_requested = false;
var fullscreen_probe = false;
var fullscreen_probe_hits: u32 = 0;
var lost_focus = false;
var on_terminate: ?*const fn () void = null;
/// The platform the window procedure writes input into. Set when the window is shown; messages that
/// arrive earlier carry no input.
var current: ?*Platform = null;

// ---------------------------------------------------------------------------- process

/// The game is a GUI program, so that double-clicking it opens no console window. A GUI program started
/// from a terminal has no standard handles unless its output was redirected, and the test modes print
/// their results; this borrows the parent's console for them when there is one.
pub fn initProcess() void {
    const out = w.GetStdHandle(w.STD_OUTPUT_HANDLE);
    const err = w.GetStdHandle(w.STD_ERROR_HANDLE);
    const have_out = usable(out);
    const have_err = usable(err);
    if (have_out and have_err) return;
    if (w.AttachConsole(w.ATTACH_PARENT_PROCESS) == 0) return;
    const L = std.unicode.utf8ToUtf16LeStringLiteral;
    const console = w.CreateFileW(L("CONOUT$"), w.GENERIC_READ | w.GENERIC_WRITE, w.FILE_SHARE_READ | w.FILE_SHARE_WRITE, null, w.OPEN_EXISTING, 0, null);
    if (!usable(console)) return;
    if (!have_out) _ = w.SetStdHandle(w.STD_OUTPUT_HANDLE, console);
    if (!have_err) _ = w.SetStdHandle(w.STD_ERROR_HANDLE, console);
}

fn usable(h: w.HANDLE) bool {
    return h != null and h != w.invalid_handle and w.GetFileType(h) != w.FILE_TYPE_UNKNOWN;
}

/// Nothing on Windows is freed by scope.
pub fn scopeBegin() ?*anyopaque {
    return null;
}

pub fn scopeEnd(_: ?*anyopaque) void {}

/// The copy of a shader file in the `shaders` folder beside the executable.
pub fn shaderPath(buf: []u8, file: []const u8) ?[:0]const u8 {
    var wide: [1024]u16 = undefined;
    const n = w.GetModuleFileNameW(null, &wide, wide.len);
    if (n == 0 or n >= wide.len) return null;
    var exe_buf: [common_max_path]u8 = undefined;
    const exe = w.fromWide(&exe_buf, wide[0..n]) orelse return null;
    const slash = std.mem.lastIndexOfScalar(u8, exe, '\\') orelse return null;
    return std.fmt.bufPrintSentinel(buf, "{s}\\shaders\\{s}", .{ exe[0..slash], file }, 0) catch null;
}

const common_max_path = 2048;

/// A double-clicked game that cannot start has nowhere to print, so it says why in a message box. The
/// text is English: this runs before, or instead of, the game learning its language.
pub fn reportFatal(reason: []const u8) void {
    var text_buf: [512]u8 = undefined;
    const known: []const u8 = if (std.mem.eql(u8, reason, "NoDirect3DDevice"))
        "This computer has no Direct3D 11 graphics device (feature level 11_0), which the game needs."
    else if (std.mem.eql(u8, reason, "NoShaderCompiler"))
        "d3dcompiler_47.dll could not be loaded. It is part of Windows 10 and later."
    else if (std.mem.eql(u8, reason, "ShaderCompileFailed"))
        "The shader file in the shaders folder did not compile. Restore the original file, or run the game from a terminal to see the compiler's message."
    else
        "";
    const text = std.fmt.bufPrint(&text_buf, "Dentro del cuerpo could not start.\n\n{s}{s}({s})", .{ known, if (known.len > 0) "\n\n" else "", reason }) catch reason;
    var wide_text: [512]u16 = undefined;
    var wide_title: [64]u16 = undefined;
    const wt = w.toWide(&wide_text, text) orelse return;
    const title = w.toWide(&wide_title, "Dentro del cuerpo") orelse return;
    _ = w.MessageBoxW(null, wt.ptr, title.ptr, w.MB_OK | w.MB_ICONERROR);
}

var pad_status_buf: [96]u8 = undefined;

pub fn padBackendStatus() []const u8 {
    const p = current orelse return "XInput not loaded yet";
    if (p.pads.api.get_state == null) return "no XInput DLL found; Sony controllers are still read directly";
    return std.fmt.bufPrint(&pad_status_buf, "XInput from {s}, Sony controllers read directly", .{p.pads.api.dll}) catch "XInput loaded";
}

/// Cleanup for when Windows ends the session: the process is killed once the window has answered, so the
/// main loop's own cleanup is not reached.
pub fn setTerminateHook(f: *const fn () void) void {
    on_terminate = f;
}

pub fn now() f64 {
    const S = struct {
        var freq: i64 = 0;
    };
    if (S.freq == 0) _ = w.QueryPerformanceFrequency(&S.freq);
    var t: i64 = 0;
    _ = w.QueryPerformanceCounter(&t);
    return @as(f64, @floatFromInt(t)) / @as(f64, @floatFromInt(@max(S.freq, 1)));
}

/// The user's display languages in order of preference, from the list in Settings > Time & language.
pub fn preferredLanguages(buf: []u8) []const u8 {
    var wide: [512]u16 = undefined;
    var count: u32 = 0;
    var size: u32 = wide.len;
    if (w.GetUserPreferredUILanguages(w.MUI_LANGUAGE_NAME, &count, &wide, &size) == 0) return buf[0..0];
    return w.multiSzToList(buf, wide[0..@min(size, wide.len)]);
}

// ---------------------------------------------------------------------------- game controllers

/// Every controller the game can hear, and the choice of the one it listens to. XInput is polled; the
/// Sony controllers' reports arrive as window messages and are parsed as they come.
const Pads = struct {
    api: xinput.Api = .{},
    poller: xinput.Poller = .{},
    selector: padsel.Selector = .{},
    direct: [padsel.max_direct]Direct = @splat(.{}),
    /// HID game pads that turned out not to be Sony's, remembered so each report does not ask again.
    rejected: [8]w.HANDLE = @splat(null),
    rejected_next: usize = 0,
    /// SDL_GAMECONTROLLER_IGNORE_DEVICES as Steam set it, if it did.
    ignore: [512]u8 = undefined,
    ignore_len: usize = 0,
    last: f64 = 0,

    const Direct = struct {
        handle: w.HANDLE = null,
        model: pshid.Model = .dualshock4,
        state: pad.State = .{},
    };

    fn init() Pads {
        var ps: Pads = .{ .api = xinput.Api.load() };
        var wide: [512]u16 = undefined;
        const L = std.unicode.utf8ToUtf16LeStringLiteral;
        const n = w.GetEnvironmentVariableW(L("SDL_GAMECONTROLLER_IGNORE_DEVICES"), &wide, wide.len);
        if (n > 0 and n < wide.len) {
            if (w.fromWide(&ps.ignore, wide[0..n])) |list| ps.ignore_len = list.len;
        }
        return ps;
    }

    /// The state of the controller in use. An unfocused window hears nothing: every controller reads as
    /// attached and at rest, as the keyboard does.
    fn poll(ps: *Pads, t: f64, focused: bool) pad.State {
        const dt: f32 = @floatCast(std.math.clamp(t - ps.last, 0.0, 0.1));
        ps.last = t;
        ps.poller.poll(t, ps.api);
        var seen: padsel.Seen = .{};
        for (ps.poller.slots, 0..) |s, i| seen.xinput[i] = s.state;
        for (ps.direct, 0..) |dd, i| {
            if (dd.handle != null) seen.direct[i] = dd.state;
        }
        if (!focused) {
            for (&seen.xinput) |*st| st.* = rest(st.*);
            for (&seen.direct) |*st| st.* = rest(st.*);
        }
        return ps.selector.pick(&seen, dt);
    }

    fn rest(st: pad.State) pad.State {
        return if (st.connected) .{ .connected = true, .family = st.family } else .{};
    }

    /// Reports stop arriving while the window is in the background, so what was held then would stay
    /// held; put every directly read controller at rest.
    fn releaseAll(ps: *Pads) void {
        for (&ps.direct) |*dd| dd.state = rest(dd.state);
    }

    fn slotOf(ps: *Pads, handle: w.HANDLE) ?*Direct {
        for (&ps.direct) |*dd| {
            if (dd.handle == handle) return dd;
        }
        return null;
    }

    /// The slot for a device seen for the first time, if it is a controller this file reads.
    fn adopt(ps: *Pads, handle: w.HANDLE) ?*Direct {
        for (ps.rejected) |r| {
            if (r == handle) return null;
        }
        var info: w.RID_DEVICE_INFO = .{};
        var size: u32 = @sizeOf(w.RID_DEVICE_INFO);
        const got = w.GetRawInputDeviceInfoW(handle, w.RIDI_DEVICEINFO, &info, &size);
        const model: ?pshid.Model = if (got != 0 and got != std.math.maxInt(u32) and info.dwType == w.RIM_TYPEHID)
            pshid.identify(info.u.hid.dwVendorId, info.u.hid.dwProductId)
        else
            null;
        const taken = model != null and !pshid.ignoredBy(ps.ignore[0..ps.ignore_len], info.u.hid.dwVendorId, info.u.hid.dwProductId);
        if (taken) {
            for (&ps.direct) |*dd| {
                if (dd.handle == null) {
                    dd.* = .{ .handle = handle, .model = model.? };
                    return dd;
                }
            }
        }
        ps.rejected[ps.rejected_next] = handle;
        ps.rejected_next = (ps.rejected_next + 1) % ps.rejected.len;
        return null;
    }

    fn report(ps: *Pads, handle: w.HANDLE, bytes: []const u8) void {
        // Input that was injected by software has no device.
        if (handle == null) return;
        const dd = ps.slotOf(handle) orelse ps.adopt(handle) orelse return;
        if (pshid.parse(dd.model, bytes)) |st| dd.state = st;
    }

    fn removed(ps: *Pads, handle: w.HANDLE) void {
        if (ps.slotOf(handle)) |dd| dd.* = .{};
        for (&ps.rejected) |*r| {
            if (r.* == handle) r.* = null;
        }
    }
};

// ---------------------------------------------------------------------------- window

/// What full screen has to put back.
const Windowed = struct {
    style: isize = 0,
    placement: w.WINDOWPLACEMENT = .{},
};

pub const Platform = struct {
    hwnd: w.HWND,
    menu: w.HMENU,
    captured: bool = false,
    input: Input = .{},
    /// The game controller this frame, as the device reports it; `pump` refreshes it from `pad_source`.
    /// This struct is all the rest of the program knows of a controller.
    pad: pad.State = .{},
    pad_source: PadSource = .system,
    pads: Pads = .{},
    /// The XInput report `SyntheticPad` writes, read when `pad_source` is `.synthetic`.
    synthetic: xinput.Gamepad = .{},

    fullscreen: bool = false,
    windowed: Windowed = .{},
    focused: bool = false,
    last_size: [2]u32 = .{ 8, 8 },
    /// Last absolute position from a pointing device that reports positions instead of movement.
    abs_last: ?[2]f32 = null,
    title_buf: [200]u8 = undefined,

    /// Builds the window without showing it. The GPU backend attaches to `surface()` next, and `show`
    /// puts the window on screen. `width` and `height` are the client area in units of 1/96 inch, scaled
    /// by the monitor's DPI and limited to its work area.
    pub fn init(title: [*:0]const u8, menu: MenuTitles, width: f64, height: f64) Platform {
        const L = std.unicode.utf8ToUtf16LeStringLiteral;
        const instance = w.GetModuleHandleW(null);
        const class_name = L("DentroDelCuerpo");
        const res: w.RESOURCE = @ptrFromInt(icon_resource);
        _ = w.RegisterClassExW(&.{
            .lpfnWndProc = &windowProc,
            .hInstance = instance,
            .hIcon = w.LoadImageW(instance, res, w.IMAGE_ICON, 0, 0, w.LR_DEFAULTSIZE | w.LR_SHARED),
            .hIconSm = w.LoadImageW(instance, res, w.IMAGE_ICON, w.GetSystemMetrics(w.SM_CXSMICON), w.GetSystemMetrics(w.SM_CYSMICON), w.LR_SHARED),
            .hCursor = w.LoadCursorW(null, w.IDC_ARROW),
            .lpszClassName = class_name,
        });
        var wide_title: [256]u16 = undefined;
        const wt = w.toWide(&wide_title, std.mem.span(title)) orelse L("Dentro del cuerpo");
        const hwnd = w.CreateWindowExW(0, class_name, wt.ptr, w.WS_OVERLAPPEDWINDOW, w.CW_USEDEFAULT, w.CW_USEDEFAULT, 1280, 800, null, null, instance, null);

        // The frame's thickness depends on the monitor's DPI and the Windows version, so it is measured
        // from the window that exists and the client area is then set to the size asked for.
        const scale = scaleOf(hwnd);
        var mi: w.MONITORINFO = .{};
        _ = w.GetMonitorInfoW(w.MonitorFromWindow(hwnd, w.MONITOR_DEFAULTTONEAREST), &mi);
        const frame = frameSize(hwnd);
        const work_w = mi.rcWork.right - mi.rcWork.left;
        const work_h = mi.rcWork.bottom - mi.rcWork.top;
        const ww = @min(work_w, @as(i32, @intFromFloat(width * scale)) + frame[0]);
        const wh = @min(work_h, @as(i32, @intFromFloat(height * scale)) + frame[1]);
        if (work_w > 0 and work_h > 0)
            _ = w.SetWindowPos(hwnd, null, mi.rcWork.left + @divTrunc(work_w - ww, 2), mi.rcWork.top + @divTrunc(work_h - wh, 2), ww, wh, w.SWP_NOZORDER | w.SWP_NOACTIVATE);

        // The game's two window commands live in the system menu (the icon in the title bar, or a right
        // click on it): full screen is added and Close is retitled, each with its shortcut.
        const sys_menu = w.GetSystemMenu(hwnd, 0);
        _ = w.InsertMenuW(sys_menu, w.SC_CLOSE, w.MF_BYCOMMAND | w.MF_STRING, cmd_fullscreen, L("Full screen\tAlt+Enter"));
        _ = w.InsertMenuW(sys_menu, w.SC_CLOSE, w.MF_BYCOMMAND | w.MF_SEPARATOR, 0, null);

        // Mouse movement as the device reports it, and HID game pads (Sony's are read from their reports).
        const devices = [_]w.RAWINPUTDEVICE{
            .{ .usUsagePage = 1, .usUsage = 2, .dwFlags = 0, .hwndTarget = hwnd },
            .{ .usUsagePage = 1, .usUsage = 5, .dwFlags = w.RIDEV_DEVNOTIFY, .hwndTarget = hwnd },
        };
        _ = w.RegisterRawInputDevices(&devices, devices.len, @sizeOf(w.RAWINPUTDEVICE));

        var p: Platform = .{ .hwnd = hwnd, .menu = sys_menu, .pads = Pads.init() };
        p.setMenuTitles(menu);
        return p;
    }

    pub fn surface(p: *Platform) Surface {
        return p.hwnd;
    }

    pub fn show(p: *Platform) void {
        current = p;
        _ = w.ShowWindow(p.hwnd, w.SW_SHOWNORMAL);
        _ = w.SetForegroundWindow(p.hwnd);
        p.focused = w.GetForegroundWindow() == p.hwnd;
    }

    /// True while this window is the one the keyboard types into.
    pub fn isKey(p: *Platform) bool {
        return p.focused;
    }

    /// Whether controller input should count this frame. A real controller is heard only while the window
    /// has the focus, like the keyboard; a source the tests supply is theirs to control.
    pub fn padFocused(p: *Platform) bool {
        return p.pad_source != .system or p.isKey();
    }

    /// Retitle the two commands in the system menu, for when the language changes while the game is
    /// running. The rest of that menu is Windows' own and follows the system language.
    pub fn setMenuTitles(p: *Platform, menu: MenuTitles) void {
        p.retitle(cmd_fullscreen, std.mem.span(menu.fullscreen), "Alt+Enter");
        p.retitle(w.SC_CLOSE, std.mem.span(menu.quit), "Alt+F4");
    }

    fn retitle(p: *Platform, command: usize, title: []const u8, keys: []const u8) void {
        var text: [200]u8 = undefined;
        var wide: [200]u16 = undefined;
        const s = std.fmt.bufPrint(&text, "{s}\t{s}", .{ title, keys }) catch return;
        const ws = w.toWide(&wide, s) orelse return;
        _ = w.ModifyMenuW(p.menu, @intCast(command), w.MF_BYCOMMAND | w.MF_STRING, command, ws.ptr);
    }

    /// The title a command of the system menu shows now, read back from the menu itself, without its
    /// shortcut. Valid until the next call.
    pub fn menuTitle(p: *Platform, item: common.MenuItem) []const u8 {
        var wide: [200]u16 = undefined;
        const n = w.GetMenuStringW(p.menu, if (item == .quit) w.SC_CLOSE else @intCast(cmd_fullscreen), &wide, wide.len, w.MF_BYCOMMAND);
        if (n <= 0) return "";
        const text = w.fromWide(&p.title_buf, wide[0..@intCast(n)]) orelse return "";
        return text[0 .. std.mem.indexOfScalar(u8, text, '\t') orelse text.len];
    }

    /// Client size in pixels and the monitor's scale (1 at 96 dpi). A minimised window has no client
    /// area; it reports the size it had, so nothing is rebuilt for a window nobody can see.
    pub fn pixelSize(p: *Platform) common.PixelSize {
        var rc: w.RECT = .{};
        if (w.IsIconic(p.hwnd) == 0 and w.GetClientRect(p.hwnd, &rc) != 0 and rc.right > 0 and rc.bottom > 0)
            p.last_size = .{ @intCast(@max(8, rc.right)), @intCast(@max(8, rc.bottom)) };
        return .{ .w = p.last_size[0], .h = p.last_size[1], .scale = scaleOf(p.hwnd) };
    }

    pub fn shouldQuit(_: *Platform) bool {
        return quit_requested;
    }

    /// Borderless full screen on the monitor the window is on: the frame is taken off and the window
    /// sized to the monitor, which the flip-model swap chain presents without a mode change. Leaving
    /// puts back the frame and the position the window had.
    pub fn toggleFullscreen(p: *Platform) void {
        if (fullscreen_probe) {
            fullscreen_probe_hits += 1;
            return;
        }
        const flags = w.SWP_NOOWNERZORDER | w.SWP_FRAMECHANGED;
        if (!p.fullscreen) {
            var mi: w.MONITORINFO = .{};
            p.windowed.style = w.GetWindowLongPtrW(p.hwnd, w.GWL_STYLE);
            if (w.GetWindowPlacement(p.hwnd, &p.windowed.placement) == 0) return;
            if (w.GetMonitorInfoW(w.MonitorFromWindow(p.hwnd, w.MONITOR_DEFAULTTONEAREST), &mi) == 0) return;
            _ = w.SetWindowLongPtrW(p.hwnd, w.GWL_STYLE, p.windowed.style & ~@as(isize, w.WS_OVERLAPPEDWINDOW));
            _ = w.SetWindowPos(p.hwnd, null, mi.rcMonitor.left, mi.rcMonitor.top, mi.rcMonitor.right - mi.rcMonitor.left, mi.rcMonitor.bottom - mi.rcMonitor.top, flags);
            p.fullscreen = true;
        } else {
            _ = w.SetWindowLongPtrW(p.hwnd, w.GWL_STYLE, p.windowed.style);
            _ = w.SetWindowPlacement(p.hwnd, &p.windowed.placement);
            _ = w.SetWindowPos(p.hwnd, null, 0, 0, 0, 0, w.SWP_NOMOVE | w.SWP_NOSIZE | w.SWP_NOZORDER | flags);
            p.fullscreen = false;
        }
        if (p.captured) p.clip(true);
    }

    /// Quit as Alt+F4 and the system menu's Close do: the window is asked to close, the main loop sees
    /// the request on its next turn and leaves through its own cleanup.
    pub fn quit(p: *Platform) void {
        _ = w.PostMessageW(p.hwnd, w.WM_CLOSE, 0, 0);
    }

    /// For the input test. While `on`, the full-screen command counts its activations instead of acting,
    /// so the test can press Alt+Enter and see the shortcut arrive without the window changing mode.
    pub fn probeFullscreen(_: *Platform, on: bool) void {
        fullscreen_probe = on;
    }

    pub fn fullscreenProbeHits(_: *Platform) u32 {
        return fullscreen_probe_hits;
    }

    /// Hide the cursor and keep it inside the window so mouse movement drives the look direction. The
    /// movement itself comes from Raw Input, which does not stop at the edge of anything.
    pub fn capture(p: *Platform, on: bool) void {
        if (on == p.captured) return;
        p.captured = on;
        p.abs_last = null;
        p.clip(on);
        if (on) {
            _ = w.SetCursor(null);
        } else {
            _ = w.SetCursor(w.LoadCursorW(null, w.IDC_ARROW));
        }
    }

    fn clip(p: *Platform, on: bool) void {
        if (!on) {
            _ = w.ClipCursor(null);
            return;
        }
        var rc: w.RECT = .{};
        if (w.GetClientRect(p.hwnd, &rc) == 0) return;
        var tl: w.POINT = .{ .x = rc.left, .y = rc.top };
        var br: w.POINT = .{ .x = rc.right, .y = rc.bottom };
        _ = w.ClientToScreen(p.hwnd, &tl);
        _ = w.ClientToScreen(p.hwnd, &br);
        // Centred first, so the hidden cursor is not left on the window's edge where a click would land
        // on the frame.
        _ = w.SetCursorPos(@divTrunc(tl.x + br.x, 2), @divTrunc(tl.y + br.y, 2));
        _ = w.ClipCursor(&.{ .left = tl.x, .top = tl.y, .right = br.x, .bottom = br.y });
    }

    /// Drain the message queue into `input`. Returns true if the window lost focus since the last call.
    pub fn pump(p: *Platform) bool {
        current = p;
        var msg: w.MSG = undefined;
        // No TranslateMessage: the game reads keys, not characters, and an untranslated Alt+letter cannot
        // reach the default handling that would beep for a menu the window does not have.
        while (w.PeekMessageW(&msg, null, 0, 0, w.PM_REMOVE) != 0) {
            if (msg.message == w.WM_QUIT) quit_requested = true;
            _ = w.DispatchMessageW(&msg);
        }
        // A minimised window is not presented to, so nothing paces the loop; this does.
        if (w.IsIconic(p.hwnd) != 0) w.Sleep(16);
        switch (p.pad_source) {
            .system => p.pad = p.pads.poll(now(), p.focused),
            .synthetic => p.pad = xinput.toState(p.synthetic),
            .injected => {},
        }
        const lost = lost_focus;
        lost_focus = false;
        if (lost) p.input.releaseAll();
        return lost;
    }

    /// Post a mouse-moved message into this window's own queue. It carries no movement (movement comes
    /// from Raw Input); what it tests is that a message of this kind arriving changes nothing.
    pub fn postMouseMove(p: *Platform) void {
        _ = w.PostMessageW(p.hwnd, w.WM_MOUSEMOVE, 0, (10 << 16) | 10);
    }

    /// Post a key message into this window's own queue (used by the scripted runs, so their input travels
    /// the same path as the keyboard's without touching other applications).
    pub fn postKey(p: *Platform, key: Key, is_down: bool) void {
        p.postKeyMessage(key, is_down, false);
    }

    /// `postKey` with Alt held: the message Windows sends then is WM_SYSKEYDOWN or WM_SYSKEYUP, with the
    /// context bit set.
    pub fn postSystemKey(p: *Platform, key: Key, is_down: bool) void {
        p.postKeyMessage(key, is_down, true);
    }

    fn postKeyMessage(p: *Platform, key: Key, is_down: bool, alt: bool) void {
        const scan = keymap.toScan(key);
        const code: u32 = scan.code;
        const vk = w.MapVirtualKeyW(code | (if (scan.extended) @as(u32, 0xE000) else 0), w.MAPVK_VSC_TO_VK_EX);
        var lp: usize = 1 | (@as(usize, code) << 16);
        if (scan.extended) lp |= 1 << 24;
        if (alt) lp |= 1 << 29;
        if (!is_down) lp |= (1 << 30) | (1 << 31);
        const msg: u32 = if (alt) (if (is_down) w.WM_SYSKEYDOWN else w.WM_SYSKEYUP) else (if (is_down) w.WM_KEYDOWN else w.WM_KEYUP);
        _ = w.PostMessageW(p.hwnd, msg, vk, @bitCast(lp));
    }

    // ------------------------------------------------------------------------ messages

    fn onKey(p: *Platform, msg: u32, wp: w.WPARAM, lp: w.LPARAM) void {
        const bits: usize = @bitCast(lp);
        const code: u8 = @truncate(bits >> 16);
        const extended = bits & (1 << 24) != 0;
        const repeat = bits & (1 << 30) != 0;
        const is_down = msg == w.WM_KEYDOWN or msg == w.WM_SYSKEYDOWN;
        const alt = bits & (1 << 29) != 0;
        if (is_down and !repeat) {
            // The window's own shortcuts. They are not game input, as Cmd shortcuts are not on a Mac.
            if (wp == w.VK_F11 or (wp == w.VK_RETURN and alt)) return p.toggleFullscreen();
            if (wp == w.VK_F4 and alt) {
                _ = w.PostMessageW(p.hwnd, w.WM_CLOSE, 0, 0);
                return;
            }
        }
        if (wp == w.VK_F11 or (wp == w.VK_RETURN and alt and is_down)) return;
        if (keymap.fromScan(code, extended)) |key| {
            p.input.set(key, is_down);
        } else {
            p.input.setOther(code | (if (extended) @as(u8, 0x80) else 0), is_down);
        }
    }

    fn onRawInput(p: *Platform, handle: w.LPARAM) void {
        var buf: [1024]u8 align(8) = undefined;
        var size: u32 = buf.len;
        const got = w.GetRawInputData(@ptrFromInt(@as(usize, @bitCast(handle))), w.RID_INPUT, &buf, &size, @sizeOf(w.RAWINPUTHEADER));
        if (got == std.math.maxInt(u32) or got < @sizeOf(w.RAWINPUTHEADER)) return;
        const header: *const w.RAWINPUTHEADER = @ptrCast(&buf);
        const body = buf[@sizeOf(w.RAWINPUTHEADER)..got];
        if (header.dwType == w.RIM_TYPEMOUSE and body.len >= @sizeOf(w.RAWMOUSE)) {
            const mouse: *const w.RAWMOUSE = @ptrCast(@alignCast(body.ptr));
            p.onMouse(mouse);
        } else if (header.dwType == w.RIM_TYPEHID and body.len >= @sizeOf(w.RAWHID)) {
            const hid: *const w.RAWHID = @ptrCast(@alignCast(body.ptr));
            const data = body[@sizeOf(w.RAWHID)..];
            if (hid.dwSizeHid == 0 or hid.dwCount == 0) return;
            const total = @as(usize, hid.dwSizeHid) * hid.dwCount;
            if (total > data.len) return;
            // Several reports may have queued up since the last message; the newest is the state.
            p.pads.report(header.hDevice, data[total - hid.dwSizeHid .. total]);
        }
    }

    fn onMouse(p: *Platform, mouse: *const w.RAWMOUSE) void {
        var dx: f32 = @floatFromInt(mouse.lLastX);
        var dy: f32 = @floatFromInt(mouse.lLastY);
        if (mouse.usFlags & w.MOUSE_MOVE_ABSOLUTE != 0) {
            // A tablet, a touch screen or a remote session reports where the pointer is, in 1/65535ths
            // of the screen; the movement is the difference from the last report.
            const virtual = mouse.usFlags & w.MOUSE_VIRTUAL_DESKTOP != 0;
            const sw: f32 = @floatFromInt(w.GetSystemMetrics(if (virtual) w.SM_CXVIRTUALSCREEN else w.SM_CXSCREEN));
            const sh: f32 = @floatFromInt(w.GetSystemMetrics(if (virtual) w.SM_CYVIRTUALSCREEN else w.SM_CYSCREEN));
            const pos = [2]f32{ dx / 65535.0 * sw, dy / 65535.0 * sh };
            const last = p.abs_last orelse pos;
            p.abs_last = pos;
            dx = pos[0] - last[0];
            dy = pos[1] - last[1];
        }
        p.input.mouse_dx += dx * mouse_scale;
        p.input.mouse_dy += dy * mouse_scale;
    }

    fn onButton(p: *Platform, left: bool, is_down: bool) void {
        const in = &p.input;
        if (left) {
            if (is_down and !in.lmb) in.lmb_pressed = true;
            in.lmb = is_down;
        } else {
            if (is_down and !in.rmb) in.rmb_pressed = true;
            in.rmb = is_down;
        }
        // Hold the mouse while a button is down, so its release is heard even outside the window.
        if (in.lmb or in.rmb) {
            _ = w.SetCapture(p.hwnd);
        } else {
            _ = w.ReleaseCapture();
        }
    }
};

fn scaleOf(hwnd: w.HWND) f64 {
    var dx: u32 = 96;
    var dy: u32 = 96;
    if (w.failed(w.GetDpiForMonitor(w.MonitorFromWindow(hwnd, w.MONITOR_DEFAULTTONEAREST), w.MDT_EFFECTIVE_DPI, &dx, &dy)) or dx == 0) return 1;
    return @as(f64, @floatFromInt(dx)) / 96.0;
}

/// How much larger the window is than its client area.
fn frameSize(hwnd: w.HWND) [2]i32 {
    var outer: w.RECT = .{};
    var inner: w.RECT = .{};
    if (w.GetWindowRect(hwnd, &outer) == 0 or w.GetClientRect(hwnd, &inner) == 0) return .{ 0, 0 };
    return .{ (outer.right - outer.left) - inner.right, (outer.bottom - outer.top) - inner.bottom };
}

fn windowProc(hwnd: w.HWND, msg: u32, wp: w.WPARAM, lp: w.LPARAM) callconv(w.WINAPI) w.LRESULT {
    const p = current;
    switch (msg) {
        w.WM_CLOSE => {
            // The main loop sees the flag, leaves, and its cleanup runs; the window goes with the process.
            quit_requested = true;
            return 0;
        },
        w.WM_ENDSESSION => {
            if (wp != 0) {
                quit_requested = true;
                if (on_terminate) |f| f();
            }
            return 0;
        },
        w.WM_ERASEBKGND => return 1,
        w.WM_SETFOCUS => {
            if (p) |plat| {
                plat.focused = true;
                if (plat.captured) plat.clip(true);
            }
            return 0;
        },
        w.WM_KILLFOCUS => {
            lost_focus = true;
            _ = w.ClipCursor(null);
            if (p) |plat| {
                plat.focused = false;
                plat.abs_last = null;
                plat.pads.releaseAll();
            }
            return 0;
        },
        w.WM_EXITMENULOOP, w.WM_EXITSIZEMOVE => {
            // A menu or a drag of the frame ran its own message loop and swallowed whatever key releases
            // happened meanwhile.
            if (p) |plat| {
                plat.input.releaseAll();
                if (plat.captured) plat.clip(true);
            }
            return 0;
        },
        w.WM_SETCURSOR => {
            if (p) |plat| {
                if (plat.captured and (@as(usize, @bitCast(lp)) & 0xFFFF) == w.HTCLIENT) {
                    _ = w.SetCursor(null);
                    return 1;
                }
            }
        },
        w.WM_GETMINMAXINFO => {
            const info: *w.MINMAXINFO = @ptrFromInt(@as(usize, @bitCast(lp)));
            const scale = scaleOf(hwnd);
            const frame = frameSize(hwnd);
            info.ptMinTrackSize = .{ .x = @as(i32, @intFromFloat(@as(f64, @floatFromInt(min_client[0])) * scale)) + frame[0], .y = @as(i32, @intFromFloat(@as(f64, @floatFromInt(min_client[1])) * scale)) + frame[1] };
            return 0;
        },
        w.WM_DPICHANGED => {
            // Moved to a monitor of another density: Windows suggests the rectangle that keeps the
            // window's physical size.
            const r: *const w.RECT = @ptrFromInt(@as(usize, @bitCast(lp)));
            _ = w.SetWindowPos(hwnd, null, r.left, r.top, r.right - r.left, r.bottom - r.top, w.SWP_NOZORDER | w.SWP_NOACTIVATE);
            return 0;
        },
        w.WM_SIZE => {
            if (p) |plat| {
                if (plat.captured and wp != w.SIZE_MINIMIZED) plat.clip(true);
            }
            return 0;
        },
        w.WM_SYSCOMMAND => {
            const command = wp & 0xFFF0;
            if (command == cmd_fullscreen) {
                if (p) |plat| plat.toggleFullscreen();
                return 0;
            }
            // A tap of Alt or F10 would otherwise put the window into menu mode, which freezes the game.
            if (command == w.SC_KEYMENU and lp != ' ') return 0;
        },
        w.WM_KEYDOWN, w.WM_KEYUP, w.WM_SYSKEYDOWN, w.WM_SYSKEYUP => {
            if (p) |plat| {
                plat.onKey(msg, wp, lp);
                // Alt+Space opens the system menu, where the window's commands are, except in flight,
                // where Space is the climb key and a menu must not open under the pilot's thumb.
                const bits: usize = @bitCast(lp);
                if (msg == w.WM_SYSKEYDOWN and !plat.captured and (bits >> 16) & 0xFF == 0x39 and bits & (1 << 29) != 0)
                    return w.DefWindowProcW(hwnd, w.WM_SYSCOMMAND, w.SC_KEYMENU, ' ');
            }
            return 0;
        },
        w.WM_INPUT => {
            if (p) |plat| plat.onRawInput(lp);
            // The default handling releases the system's copy of the data.
            return w.DefWindowProcW(hwnd, msg, wp, lp);
        },
        w.WM_INPUT_DEVICE_CHANGE => {
            if (p) |plat| {
                if (wp == w.GIDC_REMOVAL) plat.pads.removed(@ptrFromInt(@as(usize, @bitCast(lp))));
            }
            return 0;
        },
        w.WM_LBUTTONDOWN, w.WM_LBUTTONUP => {
            if (p) |plat| plat.onButton(true, msg == w.WM_LBUTTONDOWN);
            return 0;
        },
        w.WM_RBUTTONDOWN, w.WM_RBUTTONUP => {
            if (p) |plat| plat.onButton(false, msg == w.WM_RBUTTONDOWN);
            return 0;
        },
        else => {},
    }
    return w.DefWindowProcW(hwnd, msg, wp, lp);
}

/// The controller the scripted modes hold: an XInput report, written here and read through
/// `xinput.toState`, the code that reads a real controller's. XInput has no way to create a controller, so
/// this is as near the device as a test can stand.
pub const SyntheticPad = struct {
    attached: bool = false,

    /// How far a value read back may be from the one written: the report holds a trigger in eight bits.
    pub const tolerance: f32 = xinput.resolution;

    pub fn attach(plat: *Platform) SyntheticPad {
        plat.synthetic = .{};
        plat.pad_source = .synthetic;
        return .{ .attached = true };
    }

    /// True if there is a device-side report to write to, so `set` goes through the code that reads a
    /// device.
    pub fn real(sp: SyntheticPad) bool {
        return sp.attached;
    }

    pub fn source(sp: SyntheticPad) PadSource {
        return if (sp.attached) .synthetic else .injected;
    }

    pub fn set(_: SyntheticPad, plat: *Platform, st: pad.State) void {
        switch (plat.pad_source) {
            .synthetic => plat.synthetic = xinput.fromState(st),
            else => plat.pad = st,
        }
    }

    /// Encode `st` as a report and read it back with the code that reads a device.
    pub fn roundTrip(_: SyntheticPad, st: pad.State) pad.State {
        return xinput.toState(xinput.fromState(st));
    }

    pub fn describe(sp: SyntheticPad) []const u8 {
        return if (sp.attached) "XInput report, read by the device code" else "state written to Platform.pad";
    }

    /// What the round-trip check is called in the test log.
    pub const round_trip_name = "every stick, trigger and button written to an XInput report is read back by the device code";
    pub const no_device_note = "no XInput report to write to; the state goes straight to Platform.pad";
};
