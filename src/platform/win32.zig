//! Win32 declared by hand, the way `objc.zig` declares the Objective-C runtime: only what the game calls,
//! with the names and layouts of the Windows SDK headers. Everything here is in a DLL that ships with
//! Windows 10, and the import libraries come with Zig, so the port needs no SDK. COM interfaces are plain
//! structs that start with a pointer to a table of functions; `Com` is the part all of them share.

const std = @import("std");
const builtin = @import("builtin");

pub const BOOL = i32;
pub const HANDLE = ?*anyopaque;
pub const HWND = ?*anyopaque;
pub const HINSTANCE = ?*anyopaque;
pub const HMENU = ?*anyopaque;
pub const HICON = ?*anyopaque;
pub const HCURSOR = ?*anyopaque;
pub const HMONITOR = ?*anyopaque;
pub const WPARAM = usize;
pub const LPARAM = isize;
pub const LRESULT = isize;
pub const HRESULT = i32;
pub const LPCWSTR = [*:0]const u16;
/// A resource's name, or its number in the place of one (MAKEINTRESOURCE), which need not be an even
/// address.
pub const RESOURCE = [*:0]align(1) const u16;
/// The Windows calling convention. On another host these declarations are only compiled for their layout
/// checks and never called, and the host's C convention stands in for one it cannot spell.
pub const WINAPI: std.builtin.CallingConvention = if (builtin.os.tag == .windows) .winapi else .c;

pub const invalid_handle: HANDLE = @ptrFromInt(std.math.maxInt(usize));

pub fn failed(hr: HRESULT) bool {
    return hr < 0;
}

/// An HRESULT as the headers write it, from its unsigned spelling.
pub fn hresult(comptime code: u32) HRESULT {
    return @bitCast(code);
}

pub const GUID = extern struct {
    d1: u32,
    d2: u16,
    d3: u16,
    d4: [8]u8,

    /// From the registry spelling, "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx".
    pub fn parse(comptime s: *const [36:0]u8) GUID {
        @setEvalBranchQuota(4000);
        const hex = struct {
            fn f(comptime T: type, comptime text: []const u8) T {
                return std.fmt.parseInt(T, text, 16) catch unreachable;
            }
        }.f;
        var d4: [8]u8 = undefined;
        d4[0] = hex(u8, s[19..21]);
        d4[1] = hex(u8, s[21..23]);
        for (0..6) |i| d4[2 + i] = hex(u8, s[24 + i * 2 ..][0..2]);
        return .{ .d1 = hex(u32, s[0..8]), .d2 = hex(u16, s[9..13]), .d3 = hex(u16, s[14..18]), .d4 = d4 };
    }
};

/// The three methods every COM interface starts with. An interface struct is `extern struct { vtbl:
/// *const VTable }` whose table begins with these, so any interface pointer can be released through it.
pub const Com = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        QueryInterface: *const fn (*Com, *const GUID, *?*anyopaque) callconv(WINAPI) HRESULT,
        AddRef: *const fn (*Com) callconv(WINAPI) u32,
        Release: *const fn (*Com) callconv(WINAPI) u32,
    };

    /// Release an interface pointer of any type and clear it. Null is fine.
    pub fn release(ptr: anytype) void {
        if (ptr.*) |p| {
            const unknown: *Com = @ptrCast(@alignCast(p));
            _ = unknown.vtbl.Release(unknown);
            ptr.* = null;
        }
    }

    pub fn query(obj: anytype, iid: *const GUID, comptime T: type) ?*T {
        const unknown: *Com = @ptrCast(@alignCast(obj));
        var out: ?*anyopaque = null;
        if (failed(unknown.vtbl.QueryInterface(unknown, iid, &out))) return null;
        return @ptrCast(@alignCast(out));
    }
};

/// Placeholder for a slot of a function table that the game does not call.
pub const Unused = *const anyopaque;

/// Checks at compile time that `field` is entry number `slot` of the function table `VTable`, which is how
/// the hand-written tables are held to the order in the SDK headers.
pub fn expectSlot(comptime VTable: type, comptime field: []const u8, comptime slot: usize) void {
    if (@offsetOf(VTable, field) != slot * @sizeOf(usize)) @compileError(@typeName(VTable) ++ "." ++ field ++ " is not at its slot");
}

pub const POINT = extern struct { x: i32 = 0, y: i32 = 0 };
pub const RECT = extern struct { left: i32 = 0, top: i32 = 0, right: i32 = 0, bottom: i32 = 0 };

pub const MSG = extern struct {
    hwnd: HWND,
    message: u32,
    wParam: WPARAM,
    lParam: LPARAM,
    time: u32,
    pt: POINT,
    lPrivate: u32,
};

pub const WNDPROC = *const fn (HWND, u32, WPARAM, LPARAM) callconv(WINAPI) LRESULT;

pub const WNDCLASSEXW = extern struct {
    cbSize: u32 = @sizeOf(WNDCLASSEXW),
    style: u32 = 0,
    lpfnWndProc: WNDPROC,
    cbClsExtra: i32 = 0,
    cbWndExtra: i32 = 0,
    hInstance: HINSTANCE,
    hIcon: HICON = null,
    hCursor: HCURSOR = null,
    hbrBackground: ?*anyopaque = null,
    lpszMenuName: ?LPCWSTR = null,
    lpszClassName: LPCWSTR,
    hIconSm: HICON = null,
};

pub const WINDOWPLACEMENT = extern struct {
    length: u32 = @sizeOf(WINDOWPLACEMENT),
    flags: u32 = 0,
    showCmd: u32 = 0,
    ptMinPosition: POINT = .{},
    ptMaxPosition: POINT = .{},
    rcNormalPosition: RECT = .{},
};

pub const MONITORINFO = extern struct {
    cbSize: u32 = @sizeOf(MONITORINFO),
    rcMonitor: RECT = .{},
    rcWork: RECT = .{},
    dwFlags: u32 = 0,
};

pub const MINMAXINFO = extern struct {
    ptReserved: POINT,
    ptMaxSize: POINT,
    ptMaxPosition: POINT,
    ptMinTrackSize: POINT,
    ptMaxTrackSize: POINT,
};

pub const RAWINPUTDEVICE = extern struct {
    usUsagePage: u16,
    usUsage: u16,
    dwFlags: u32,
    hwndTarget: HWND,
};

pub const RAWINPUTHEADER = extern struct {
    dwType: u32,
    dwSize: u32,
    hDevice: HANDLE,
    wParam: WPARAM,
};

pub const RAWMOUSE = extern struct {
    usFlags: u16,
    usButtonFlags: u16 align(4),
    usButtonData: u16,
    ulRawButtons: u32,
    lLastX: i32,
    lLastY: i32,
    ulExtraInformation: u32,
};

/// The fixed part of RAWHID; `dwCount` reports of `dwSizeHid` bytes each follow it.
pub const RAWHID = extern struct {
    dwSizeHid: u32,
    dwCount: u32,
};

pub const RID_DEVICE_INFO_HID = extern struct {
    dwVendorId: u32,
    dwProductId: u32,
    dwVersionNumber: u32,
    usUsagePage: u16,
    usUsage: u16,
};

pub const RID_DEVICE_INFO = extern struct {
    cbSize: u32 = @sizeOf(RID_DEVICE_INFO),
    dwType: u32 = 0,
    /// A union in the headers; the keyboard member is the largest at 24 bytes.
    u: extern union {
        hid: RID_DEVICE_INFO_HID,
        raw: [24]u8,
    } = .{ .raw = @splat(0) },
};

comptime {
    std.debug.assert(@sizeOf(MSG) == 48);
    std.debug.assert(@sizeOf(WNDCLASSEXW) == 80);
    std.debug.assert(@sizeOf(WINDOWPLACEMENT) == 44);
    std.debug.assert(@sizeOf(MONITORINFO) == 40);
    std.debug.assert(@sizeOf(RAWINPUTDEVICE) == 16);
    std.debug.assert(@sizeOf(RAWINPUTHEADER) == 24);
    std.debug.assert(@sizeOf(RAWMOUSE) == 24);
    std.debug.assert(@offsetOf(RAWMOUSE, "lLastX") == 12);
    std.debug.assert(@sizeOf(RID_DEVICE_INFO) == 32);
    std.debug.assert(@sizeOf(GUID) == 16);
}

// Window messages.
pub const WM_DESTROY = 0x0002;
pub const WM_SIZE = 0x0005;
pub const WM_SETFOCUS = 0x0007;
pub const WM_KILLFOCUS = 0x0008;
pub const WM_CLOSE = 0x0010;
pub const WM_ERASEBKGND = 0x0014;
pub const WM_SETCURSOR = 0x0020;
pub const WM_GETMINMAXINFO = 0x0024;
pub const WM_WINDOWPOSCHANGED = 0x0047;
pub const WM_INPUT_DEVICE_CHANGE = 0x00FE;
pub const WM_INPUT = 0x00FF;
pub const WM_KEYDOWN = 0x0100;
pub const WM_KEYUP = 0x0101;
pub const WM_SYSKEYDOWN = 0x0104;
pub const WM_SYSKEYUP = 0x0105;
pub const WM_SYSCOMMAND = 0x0112;
pub const WM_MOUSEMOVE = 0x0200;
pub const WM_LBUTTONDOWN = 0x0201;
pub const WM_LBUTTONUP = 0x0202;
pub const WM_RBUTTONDOWN = 0x0204;
pub const WM_RBUTTONUP = 0x0205;
pub const WM_CAPTURECHANGED = 0x0215;
pub const WM_EXITMENULOOP = 0x0212;
pub const WM_EXITSIZEMOVE = 0x0232;
pub const WM_QUIT = 0x0012;
pub const WM_ENDSESSION = 0x0016;
pub const WM_DPICHANGED = 0x02E0;

pub const SIZE_MINIMIZED = 1;
pub const HTCLIENT = 1;
pub const SC_CLOSE = 0xF060;
pub const SC_KEYMENU = 0xF100;
pub const VK_RETURN = 0x0D;
pub const VK_F4 = 0x73;
pub const VK_F10 = 0x79;
pub const VK_F11 = 0x7A;
pub const MAPVK_VSC_TO_VK_EX = 3;

pub const WS_OVERLAPPEDWINDOW = 0x00CF0000;
pub const WS_POPUP = 0x80000000;
pub const WS_VISIBLE = 0x10000000;
pub const GWL_STYLE = -16;
pub const SWP_NOSIZE = 0x0001;
pub const SWP_NOMOVE = 0x0002;
pub const SWP_NOZORDER = 0x0004;
pub const SWP_NOACTIVATE = 0x0010;
pub const SWP_FRAMECHANGED = 0x0020;
pub const SWP_NOOWNERZORDER = 0x0200;
pub const SW_SHOWNORMAL = 1;
pub const SW_SHOW = 5;
pub const MONITOR_DEFAULTTONEAREST = 2;
pub const PM_REMOVE = 1;
pub const IDC_ARROW: RESOURCE = @ptrFromInt(32512);
pub const IMAGE_ICON = 1;
pub const LR_DEFAULTSIZE = 0x0040;
pub const LR_SHARED = 0x8000;
pub const SM_CXSMICON = 49;
pub const SM_CYSMICON = 50;
pub const MF_BYCOMMAND = 0x0000;
pub const MF_STRING = 0x0000;
pub const MF_SEPARATOR = 0x0800;
pub const MB_OK = 0x0000;
pub const MB_ICONERROR = 0x0010;
pub const CW_USEDEFAULT: i32 = @bitCast(@as(u32, 0x80000000));

pub const RIDEV_DEVNOTIFY = 0x00002000;
pub const RID_INPUT = 0x10000003;
pub const RIDI_DEVICEINFO = 0x2000000b;
pub const RIM_TYPEMOUSE = 0;
pub const RIM_TYPEHID = 2;
pub const GIDC_REMOVAL = 2;
pub const MOUSE_MOVE_ABSOLUTE = 0x01;
pub const MOUSE_VIRTUAL_DESKTOP = 0x02;
pub const SM_CXSCREEN = 0;
pub const SM_CYSCREEN = 1;
pub const SM_CXVIRTUALSCREEN = 78;
pub const SM_CYVIRTUALSCREEN = 79;
pub const MDT_EFFECTIVE_DPI = 0;

pub const GENERIC_READ = 0x80000000;
pub const GENERIC_WRITE = 0x40000000;
pub const FILE_SHARE_READ = 0x00000001;
pub const FILE_SHARE_WRITE = 0x00000002;
pub const CREATE_ALWAYS = 2;
pub const OPEN_EXISTING = 3;
pub const FILE_ATTRIBUTE_NORMAL = 0x80;
pub const FILE_ATTRIBUTE_DIRECTORY = 0x10;
pub const INVALID_FILE_ATTRIBUTES: u32 = 0xFFFFFFFF;
pub const MOVEFILE_REPLACE_EXISTING = 0x1;
pub const MOVEFILE_WRITE_THROUGH = 0x8;
pub const ATTACH_PARENT_PROCESS: u32 = 0xFFFFFFFF;
pub const STD_OUTPUT_HANDLE: u32 = @bitCast(@as(i32, -11));
pub const STD_ERROR_HANDLE: u32 = @bitCast(@as(i32, -12));
pub const INFINITE: u32 = 0xFFFFFFFF;
pub const WAIT_OBJECT_0 = 0;
pub const MUI_LANGUAGE_NAME = 0x8;
pub const FILE_TYPE_UNKNOWN = 0;
pub const WAIT_TIMEOUT = 258;
pub const COINIT_MULTITHREADED = 0x0;
pub const COINIT_APARTMENTTHREADED = 0x2;
pub const CLSCTX_ALL = 0x17;

pub extern "kernel32" fn GetModuleHandleW(name: ?LPCWSTR) callconv(WINAPI) HINSTANCE;
pub extern "kernel32" fn GetModuleFileNameW(module: HINSTANCE, buf: [*]u16, size: u32) callconv(WINAPI) u32;
pub extern "kernel32" fn LoadLibraryW(name: LPCWSTR) callconv(WINAPI) HINSTANCE;
pub extern "kernel32" fn GetProcAddress(module: HINSTANCE, name: [*:0]const u8) callconv(WINAPI) ?*const anyopaque;
pub extern "kernel32" fn QueryPerformanceCounter(out: *i64) callconv(WINAPI) BOOL;
pub extern "kernel32" fn QueryPerformanceFrequency(out: *i64) callconv(WINAPI) BOOL;
pub extern "kernel32" fn Sleep(ms: u32) callconv(WINAPI) void;
pub extern "kernel32" fn GetLastError() callconv(WINAPI) u32;
pub extern "kernel32" fn CreateFileW(name: LPCWSTR, access: u32, share: u32, security: ?*anyopaque, disposition: u32, flags: u32, template: HANDLE) callconv(WINAPI) HANDLE;
pub extern "kernel32" fn ReadFile(file: HANDLE, buf: [*]u8, len: u32, read: ?*u32, overlapped: ?*anyopaque) callconv(WINAPI) BOOL;
pub extern "kernel32" fn WriteFile(file: HANDLE, buf: [*]const u8, len: u32, written: ?*u32, overlapped: ?*anyopaque) callconv(WINAPI) BOOL;
pub extern "kernel32" fn CloseHandle(h: HANDLE) callconv(WINAPI) BOOL;
pub extern "kernel32" fn CreateDirectoryW(name: LPCWSTR, security: ?*anyopaque) callconv(WINAPI) BOOL;
pub extern "kernel32" fn DeleteFileW(name: LPCWSTR) callconv(WINAPI) BOOL;
pub extern "kernel32" fn RemoveDirectoryW(name: LPCWSTR) callconv(WINAPI) BOOL;
pub extern "kernel32" fn GetFileAttributesW(name: LPCWSTR) callconv(WINAPI) u32;
pub extern "kernel32" fn FlushFileBuffers(file: HANDLE) callconv(WINAPI) BOOL;
pub extern "kernel32" fn MoveFileExW(from: LPCWSTR, to: LPCWSTR, flags: u32) callconv(WINAPI) BOOL;
pub extern "kernel32" fn CreateHardLinkW(new: LPCWSTR, existing: LPCWSTR, security: ?*anyopaque) callconv(WINAPI) BOOL;
pub extern "kernel32" fn GetEnvironmentVariableW(name: LPCWSTR, buf: ?[*]u16, size: u32) callconv(WINAPI) u32;
pub extern "kernel32" fn SetEnvironmentVariableW(name: LPCWSTR, value: ?LPCWSTR) callconv(WINAPI) BOOL;
pub extern "kernel32" fn GetTempPathW(size: u32, buf: [*]u16) callconv(WINAPI) u32;
pub extern "kernel32" fn GetCurrentProcessId() callconv(WINAPI) u32;
pub extern "kernel32" fn AttachConsole(pid: u32) callconv(WINAPI) BOOL;
pub extern "kernel32" fn GetStdHandle(which: u32) callconv(WINAPI) HANDLE;
pub extern "kernel32" fn SetStdHandle(which: u32, h: HANDLE) callconv(WINAPI) BOOL;
pub extern "kernel32" fn GetFileType(h: HANDLE) callconv(WINAPI) u32;
pub extern "kernel32" fn CreateEventW(security: ?*anyopaque, manual_reset: BOOL, initial: BOOL, name: ?LPCWSTR) callconv(WINAPI) HANDLE;
pub extern "kernel32" fn SetEvent(h: HANDLE) callconv(WINAPI) BOOL;
pub extern "kernel32" fn WaitForSingleObject(h: HANDLE, ms: u32) callconv(WINAPI) u32;
pub extern "kernel32" fn WaitForMultipleObjects(count: u32, handles: [*]const HANDLE, wait_all: BOOL, ms: u32) callconv(WINAPI) u32;
pub extern "kernel32" fn CreateThread(security: ?*anyopaque, stack: usize, start: *const fn (?*anyopaque) callconv(WINAPI) u32, param: ?*anyopaque, flags: u32, id: ?*u32) callconv(WINAPI) HANDLE;
pub extern "kernel32" fn GetUserPreferredUILanguages(flags: u32, count: *u32, buf: ?[*]u16, size: *u32) callconv(WINAPI) BOOL;

pub extern "user32" fn RegisterClassExW(class: *const WNDCLASSEXW) callconv(WINAPI) u16;
pub extern "user32" fn CreateWindowExW(ex_style: u32, class: LPCWSTR, title: LPCWSTR, style: u32, x: i32, y: i32, w: i32, h: i32, parent: HWND, menu: HMENU, instance: HINSTANCE, param: ?*anyopaque) callconv(WINAPI) HWND;
pub extern "user32" fn DestroyWindow(hwnd: HWND) callconv(WINAPI) BOOL;
pub extern "user32" fn DefWindowProcW(hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM) callconv(WINAPI) LRESULT;
pub extern "user32" fn PeekMessageW(msg: *MSG, hwnd: HWND, min: u32, max: u32, remove: u32) callconv(WINAPI) BOOL;
pub extern "user32" fn TranslateMessage(msg: *const MSG) callconv(WINAPI) BOOL;
pub extern "user32" fn DispatchMessageW(msg: *const MSG) callconv(WINAPI) LRESULT;
pub extern "user32" fn PostMessageW(hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM) callconv(WINAPI) BOOL;
pub extern "user32" fn ShowWindow(hwnd: HWND, cmd: i32) callconv(WINAPI) BOOL;
pub extern "user32" fn SetForegroundWindow(hwnd: HWND) callconv(WINAPI) BOOL;
pub extern "user32" fn GetForegroundWindow() callconv(WINAPI) HWND;
pub extern "user32" fn GetClientRect(hwnd: HWND, rect: *RECT) callconv(WINAPI) BOOL;
pub extern "user32" fn GetWindowRect(hwnd: HWND, rect: *RECT) callconv(WINAPI) BOOL;
pub extern "user32" fn SetWindowPos(hwnd: HWND, after: HWND, x: i32, y: i32, w: i32, h: i32, flags: u32) callconv(WINAPI) BOOL;
pub extern "user32" fn GetWindowLongPtrW(hwnd: HWND, index: i32) callconv(WINAPI) isize;
pub extern "user32" fn SetWindowLongPtrW(hwnd: HWND, index: i32, value: isize) callconv(WINAPI) isize;
pub extern "user32" fn GetWindowPlacement(hwnd: HWND, wp: *WINDOWPLACEMENT) callconv(WINAPI) BOOL;
pub extern "user32" fn SetWindowPlacement(hwnd: HWND, wp: *const WINDOWPLACEMENT) callconv(WINAPI) BOOL;
pub extern "user32" fn MonitorFromWindow(hwnd: HWND, flags: u32) callconv(WINAPI) HMONITOR;
pub extern "user32" fn GetMonitorInfoW(monitor: HMONITOR, info: *MONITORINFO) callconv(WINAPI) BOOL;
pub extern "user32" fn IsIconic(hwnd: HWND) callconv(WINAPI) BOOL;
pub extern "user32" fn LoadCursorW(instance: HINSTANCE, name: RESOURCE) callconv(WINAPI) HCURSOR;
pub extern "user32" fn LoadImageW(instance: HINSTANCE, name: RESOURCE, kind: u32, cx: i32, cy: i32, flags: u32) callconv(WINAPI) HANDLE;
pub extern "user32" fn SetCursor(cursor: HCURSOR) callconv(WINAPI) HCURSOR;
pub extern "user32" fn ClipCursor(rect: ?*const RECT) callconv(WINAPI) BOOL;
pub extern "user32" fn ClientToScreen(hwnd: HWND, pt: *POINT) callconv(WINAPI) BOOL;
pub extern "user32" fn SetCursorPos(x: i32, y: i32) callconv(WINAPI) BOOL;
pub extern "user32" fn SetCapture(hwnd: HWND) callconv(WINAPI) HWND;
pub extern "user32" fn ReleaseCapture() callconv(WINAPI) BOOL;
pub extern "user32" fn GetSystemMetrics(index: i32) callconv(WINAPI) i32;
pub extern "user32" fn MapVirtualKeyW(code: u32, map_type: u32) callconv(WINAPI) u32;
pub extern "user32" fn RegisterRawInputDevices(devices: [*]const RAWINPUTDEVICE, count: u32, size: u32) callconv(WINAPI) BOOL;
pub extern "user32" fn GetRawInputData(input: ?*anyopaque, command: u32, data: ?*anyopaque, size: *u32, header_size: u32) callconv(WINAPI) u32;
pub extern "user32" fn GetRawInputDeviceInfoW(device: HANDLE, command: u32, data: ?*anyopaque, size: *u32) callconv(WINAPI) u32;
pub extern "user32" fn GetSystemMenu(hwnd: HWND, revert: BOOL) callconv(WINAPI) HMENU;
pub extern "user32" fn InsertMenuW(menu: HMENU, position: u32, flags: u32, id: usize, text: ?LPCWSTR) callconv(WINAPI) BOOL;
pub extern "user32" fn ModifyMenuW(menu: HMENU, position: u32, flags: u32, id: usize, text: ?LPCWSTR) callconv(WINAPI) BOOL;
pub extern "user32" fn GetMenuStringW(menu: HMENU, id: u32, buf: [*]u16, max: i32, flags: u32) callconv(WINAPI) i32;
pub extern "user32" fn MessageBoxW(hwnd: HWND, text: LPCWSTR, caption: LPCWSTR, kind: u32) callconv(WINAPI) i32;

pub extern "shcore" fn GetDpiForMonitor(monitor: HMONITOR, kind: u32, x: *u32, y: *u32) callconv(WINAPI) HRESULT;

pub extern "ole32" fn CoInitializeEx(reserved: ?*anyopaque, flags: u32) callconv(WINAPI) HRESULT;
pub extern "ole32" fn CoUninitialize() callconv(WINAPI) void;
pub extern "ole32" fn CoCreateInstance(clsid: *const GUID, outer: ?*anyopaque, ctx: u32, iid: *const GUID, out: *?*anyopaque) callconv(WINAPI) HRESULT;
pub extern "ole32" fn CoTaskMemFree(p: ?*anyopaque) callconv(WINAPI) void;

pub extern "shell32" fn SHGetKnownFolderPath(id: *const GUID, flags: u32, token: HANDLE, path: *?[*:0]u16) callconv(WINAPI) HRESULT;
pub const FOLDERID_RoamingAppData = GUID.parse("3EB685DB-65F9-4CF6-A03A-E3EF65729F3D");

/// A list of strings as Windows returns one ("uk-UA\0en-US\0\0": each ends in a NUL and the list in an
/// empty string), as comma-separated UTF-8 in `buf`. Entries that do not fit are left off the end.
pub fn multiSzToList(buf: []u8, multi_sz: []const u16) []const u8 {
    var n: usize = 0;
    var rest = multi_sz;
    while (rest.len > 0) {
        const len = std.mem.indexOfScalar(u16, rest, 0) orelse rest.len;
        if (len == 0) break;
        const lead: usize = if (n > 0) 1 else 0;
        const item = fromWide(buf[@min(buf.len, n + lead)..], rest[0..len]) orelse break;
        if (lead == 1) buf[n] = ',';
        n += lead + item.len;
        rest = rest[@min(rest.len, len + 1)..];
    }
    return buf[0..n];
}

/// UTF-8 to a NUL-terminated UTF-16 string in `buf`. Null if it does not fit or is not valid UTF-8.
pub fn toWide(buf: []u16, utf8: []const u8) ?[:0]u16 {
    if (buf.len == 0) return null;
    // A UTF-8 string never needs more UTF-16 units than it has bytes.
    if (utf8.len >= buf.len) {
        const need = std.unicode.calcUtf16LeLen(utf8) catch return null;
        if (need >= buf.len) return null;
    }
    const n = std.unicode.utf8ToUtf16Le(buf, utf8) catch return null;
    buf[n] = 0;
    return buf[0..n :0];
}

/// UTF-16 to UTF-8 in `buf`. Unpaired surrogates, which Windows file names may contain, become U+FFFD.
/// Null if it does not fit.
pub fn fromWide(buf: []u8, wide: []const u16) ?[]u8 {
    var n: usize = 0;
    var it = std.unicode.Wtf16LeIterator.init(wide);
    while (it.nextCodepoint()) |raw| {
        const cp: u21 = if (raw >= 0xD800 and raw <= 0xDFFF) 0xFFFD else raw;
        const len = std.unicode.utf8CodepointSequenceLength(cp) catch return null;
        if (n + len > buf.len) return null;
        _ = std.unicode.utf8Encode(cp, buf[n..]) catch return null;
        n += len;
    }
    return buf[0..n];
}

test "a Windows string list becomes a comma-separated one" {
    const L = std.unicode.utf8ToUtf16LeStringLiteral;
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("uk-UA,en-US", multiSzToList(&buf, L("uk-UA\x00en-US\x00\x00")));
    try std.testing.expectEqualStrings("en-GB", multiSzToList(&buf, L("en-GB\x00\x00")));
    try std.testing.expectEqualStrings("", multiSzToList(&buf, L("\x00")));
    try std.testing.expectEqualStrings("", multiSzToList(&buf, &.{}));
    // A list that was cut off before its terminators still yields what is there.
    try std.testing.expectEqualStrings("uk-UA,en", multiSzToList(&buf, L("uk-UA\x00en")));
    // No room for the second entry: it is dropped whole, with its comma.
    var small: [8]u8 = undefined;
    try std.testing.expectEqualStrings("uk-UA", multiSzToList(&small, L("uk-UA\x00en-US\x00\x00")));
}

test "GUIDs parse from their registry spelling" {
    const g = comptime GUID.parse("50c83a1c-e072-4c48-87b0-3630fa36a6d0");
    try std.testing.expectEqual(@as(u32, 0x50c83a1c), g.d1);
    try std.testing.expectEqual(@as(u16, 0xe072), g.d2);
    try std.testing.expectEqual(@as(u16, 0x4c48), g.d3);
    try std.testing.expectEqualSlices(u8, &.{ 0x87, 0xb0, 0x36, 0x30, 0xfa, 0x36, 0xa6, 0xd0 }, &g.d4);
}

test "paths convert between UTF-8 and UTF-16 with their non-ASCII letters" {
    var wide: [64]u16 = undefined;
    var narrow: [64]u8 = undefined;
    const path = "C:\\Users\\Олена\\save.txt";
    const w = toWide(&wide, path).?;
    try std.testing.expectEqual(@as(usize, 23), w.len);
    try std.testing.expectEqual(@as(u16, 0x041E), w[9]); // О
    try std.testing.expectEqualStrings(path, fromWide(&narrow, w).?);
    var tiny: [4]u16 = undefined;
    try std.testing.expectEqual(@as(?[:0]u16, null), toWide(&tiny, path));
    var tiny8: [4]u8 = undefined;
    try std.testing.expectEqual(@as(?[]u8, null), fromWide(&tiny8, w));
}
