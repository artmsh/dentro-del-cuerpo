//! The Windows output of `audio.zig`: a WASAPI shared-mode stream on the default playback device, pulled
//! by its own thread each time the device signals that it has room. The stream is opened as 48 kHz float
//! stereo, the synthesiser's own format, and Windows converts to whatever the device mixes at.
//!
//! A machine may have no playback device (a server, a CI runner, a laptop whose headphones were just
//! unplugged), and the default device can change while the game runs. Neither is an error: the thread
//! keeps the synthesiser running in real time into nothing, looks for a device again every so often, and
//! moves to the new default when there is one.

const std = @import("std");
const common = @import("../audio.zig");
const w = @import("../platform/win32.zig");

const HRESULT = w.HRESULT;
const WINAPI = w.WINAPI;
const Unused = w.Unused;

const CLSID_MMDeviceEnumerator = w.GUID.parse("bcde0395-e52f-467c-8e3d-c4579291692e");
const IID_IMMDeviceEnumerator = w.GUID.parse("a95664d2-9614-4f35-a746-de8db63617e6");
const IID_IAudioClient = w.GUID.parse("1cb9ad4c-dbfa-4c32-b178-c2f568a703b2");
const IID_IAudioRenderClient = w.GUID.parse("f294acfc-3146-4483-a7bf-addca7c260e2");
const KSDATAFORMAT_SUBTYPE_IEEE_FLOAT = w.GUID.parse("00000003-0000-0010-8000-00aa00389b71");

const eRender = 0;
const eConsole = 0;
const AUDCLNT_SHAREMODE_SHARED = 0;
const AUDCLNT_STREAMFLAGS_EVENTCALLBACK = 0x00040000;
const AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY = 0x08000000;
const AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM = 0x80000000;
const WAVE_FORMAT_EXTENSIBLE = 0xFFFE;
const SPEAKER_FRONT_LEFT_RIGHT = 0x3;

/// How much the stream may hold, in 100 ns units: 32 ms, what the macOS output queues.
const buffer_duration: i64 = 320_000;
/// How often the thread asks whether the default device is still the one it plays through.
const default_check_seconds = 1.0;

const WAVEFORMATEXTENSIBLE = extern struct {
    wFormatTag: u16,
    nChannels: u16,
    nSamplesPerSec: u32,
    nAvgBytesPerSec: u32,
    nBlockAlign: u16,
    wBitsPerSample: u16,
    cbSize: u16,
    wValidBitsPerSample: u16,
    dwChannelMask: u32,
    SubFormat: w.GUID,
};

const Enumerator = extern struct {
    vtbl: *const VTable,
    const VTable = extern struct {
        base: w.Com.VTable,
        EnumAudioEndpoints: Unused,
        GetDefaultAudioEndpoint: *const fn (*Enumerator, u32, u32, *?*Endpoint) callconv(WINAPI) HRESULT,
        GetDevice: Unused,
        RegisterEndpointNotificationCallback: Unused,
        UnregisterEndpointNotificationCallback: Unused,
    };
};

const Endpoint = extern struct {
    vtbl: *const VTable,
    const VTable = extern struct {
        base: w.Com.VTable,
        Activate: *const fn (*Endpoint, *const w.GUID, u32, ?*anyopaque, *?*anyopaque) callconv(WINAPI) HRESULT,
        OpenPropertyStore: Unused,
        GetId: *const fn (*Endpoint, *?[*:0]u16) callconv(WINAPI) HRESULT,
        GetState: Unused,
    };
};

const Client = extern struct {
    vtbl: *const VTable,
    const VTable = extern struct {
        base: w.Com.VTable,
        Initialize: *const fn (*Client, u32, u32, i64, i64, *const WAVEFORMATEXTENSIBLE, ?*const w.GUID) callconv(WINAPI) HRESULT,
        GetBufferSize: *const fn (*Client, *u32) callconv(WINAPI) HRESULT,
        GetStreamLatency: Unused,
        GetCurrentPadding: *const fn (*Client, *u32) callconv(WINAPI) HRESULT,
        IsFormatSupported: Unused,
        GetMixFormat: Unused,
        GetDevicePeriod: Unused,
        Start: *const fn (*Client) callconv(WINAPI) HRESULT,
        Stop: *const fn (*Client) callconv(WINAPI) HRESULT,
        Reset: Unused,
        SetEventHandle: *const fn (*Client, w.HANDLE) callconv(WINAPI) HRESULT,
        GetService: *const fn (*Client, *const w.GUID, *?*anyopaque) callconv(WINAPI) HRESULT,
    };
};

const RenderClient = extern struct {
    vtbl: *const VTable,
    const VTable = extern struct {
        base: w.Com.VTable,
        GetBuffer: *const fn (*RenderClient, u32, *?[*]f32) callconv(WINAPI) HRESULT,
        ReleaseBuffer: *const fn (*RenderClient, u32, u32) callconv(WINAPI) HRESULT,
    };
};

comptime {
    // Slot numbers from the Vtbl structs in mmdeviceapi.h and audioclient.h.
    std.debug.assert(@sizeOf(WAVEFORMATEXTENSIBLE) == 40);
    w.expectSlot(Enumerator.VTable, "GetDefaultAudioEndpoint", 4);
    w.expectSlot(Endpoint.VTable, "Activate", 3);
    w.expectSlot(Endpoint.VTable, "GetId", 5);
    w.expectSlot(Client.VTable, "Initialize", 3);
    w.expectSlot(Client.VTable, "GetBufferSize", 4);
    w.expectSlot(Client.VTable, "GetCurrentPadding", 6);
    w.expectSlot(Client.VTable, "Start", 10);
    w.expectSlot(Client.VTable, "Stop", 11);
    w.expectSlot(Client.VTable, "SetEventHandle", 13);
    w.expectSlot(Client.VTable, "GetService", 14);
    std.debug.assert(@sizeOf(Client.VTable) == 15 * @sizeOf(usize));
    w.expectSlot(RenderClient.VTable, "GetBuffer", 3);
    w.expectSlot(RenderClient.VTable, "ReleaseBuffer", 4);
}

/// The format asked of the stream: the synthesiser's, interleaved 32-bit float stereo.
fn streamFormat() WAVEFORMATEXTENSIBLE {
    const rate: u32 = @intFromFloat(common.rate);
    return .{
        .wFormatTag = WAVE_FORMAT_EXTENSIBLE,
        .nChannels = 2,
        .nSamplesPerSec = rate,
        .nAvgBytesPerSec = rate * 8,
        .nBlockAlign = 8,
        .wBitsPerSample = 32,
        .cbSize = 22,
        .wValidBitsPerSample = 32,
        .dwChannelMask = SPEAKER_FRONT_LEFT_RIGHT,
        .SubFormat = KSDATAFORMAT_SUBTYPE_IEEE_FLOAT,
    };
}

/// How long to wait before looking for a playback device again, given the last wait: half a second at
/// first, doubling to four.
pub fn nextRetry(last_ms: u32) u32 {
    return if (last_ms == 0) 500 else @min(4000, last_ms * 2);
}

/// An open stream on one device.
const Stream = struct {
    endpoint: ?*Endpoint = null,
    client: ?*Client = null,
    render: ?*RenderClient = null,
    /// The endpoint's identifier, to tell when the default has become another device.
    id: ?[*:0]u16 = null,
    frames: u32 = 0,

    fn close(s: *Stream) void {
        if (s.client) |c| _ = c.vtbl.Stop(c);
        w.Com.release(&s.render);
        w.Com.release(&s.client);
        w.Com.release(&s.endpoint);
        if (s.id) |id| w.CoTaskMemFree(id);
        s.* = .{};
    }
};

pub const Output = struct {
    source: common.Source = undefined,
    thread: w.HANDLE = null,
    /// Signalled by `stop`.
    quit: w.HANDLE = null,
    /// Signalled by the device when the stream has room.
    ready: w.HANDLE = null,
    /// True while a stream is open; for the log only.
    playing: bool = false,

    /// Start the render thread. `o` must not move afterwards. True unless the thread itself could not be
    /// made: a machine with no playback device is not a failure, the game is then silent until one
    /// appears.
    pub fn start(o: *Output, source: common.Source) bool {
        o.source = source;
        o.quit = w.CreateEventW(null, 1, 0, null);
        o.ready = w.CreateEventW(null, 0, 0, null);
        if (o.quit == null or o.ready == null) return false;
        o.thread = w.CreateThread(null, 0, &threadMain, o, 0, null);
        return o.thread != null;
    }

    /// Stop the render thread. Must run before the memory behind the source goes away.
    pub fn stop(o: *Output) void {
        if (o.thread) |t| {
            _ = w.SetEvent(o.quit);
            _ = w.WaitForSingleObject(t, w.INFINITE);
            _ = w.CloseHandle(t);
            o.thread = null;
        }
        if (o.quit != null) _ = w.CloseHandle(o.quit);
        if (o.ready != null) _ = w.CloseHandle(o.ready);
        o.quit = null;
        o.ready = null;
    }

    fn threadMain(param: ?*anyopaque) callconv(WINAPI) u32 {
        const o: *Output = @ptrCast(@alignCast(param.?));
        const com = !w.failed(w.CoInitializeEx(null, w.COINIT_MULTITHREADED));
        defer if (com) w.CoUninitialize();
        raisePriority();

        var enumerator: ?*Enumerator = null;
        defer w.Com.release(&enumerator);
        var retry_ms: u32 = 0;
        while (true) {
            if (enumerator == null) {
                var raw: ?*anyopaque = null;
                if (!w.failed(w.CoCreateInstance(&CLSID_MMDeviceEnumerator, null, w.CLSCTX_ALL, &IID_IMMDeviceEnumerator, &raw))) enumerator = @ptrCast(@alignCast(raw));
            }
            var stream: Stream = .{};
            if (enumerator != null and o.open(enumerator.?, &stream)) {
                retry_ms = 0;
                o.playing = true;
                const quit = o.play(enumerator.?, &stream);
                o.playing = false;
                stream.close();
                if (quit) return 0;
                // The device went away or the default changed: look again at once.
                continue;
            }
            stream.close();
            retry_ms = nextRetry(retry_ms);
            if (o.idle(retry_ms)) return 0;
        }
    }

    /// Open a stream on the default playback device and fill it with its first buffer.
    fn open(o: *Output, enumerator: *Enumerator, s: *Stream) bool {
        if (w.failed(enumerator.vtbl.GetDefaultAudioEndpoint(enumerator, eRender, eConsole, &s.endpoint)) or s.endpoint == null) return false;
        const endpoint = s.endpoint.?;
        _ = endpoint.vtbl.GetId(endpoint, &s.id);
        var raw: ?*anyopaque = null;
        if (w.failed(endpoint.vtbl.Activate(endpoint, &IID_IAudioClient, w.CLSCTX_ALL, null, &raw)) or raw == null) return false;
        s.client = @ptrCast(@alignCast(raw));
        const client = s.client.?;
        const format = streamFormat();
        const flags: u32 = AUDCLNT_STREAMFLAGS_EVENTCALLBACK | AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM | AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY;
        if (w.failed(client.vtbl.Initialize(client, AUDCLNT_SHAREMODE_SHARED, flags, buffer_duration, 0, &format, null))) return false;
        if (w.failed(client.vtbl.SetEventHandle(client, o.ready))) return false;
        if (w.failed(client.vtbl.GetBufferSize(client, &s.frames)) or s.frames == 0) return false;
        raw = null;
        if (w.failed(client.vtbl.GetService(client, &IID_IAudioRenderClient, &raw)) or raw == null) return false;
        s.render = @ptrCast(@alignCast(raw));
        // The stream starts with whatever is in its buffer, so it is filled before it is started.
        if (!o.fill(s)) return false;
        return !w.failed(client.vtbl.Start(client));
    }

    /// Write as many frames as the stream has room for. False if the device is gone.
    fn fill(o: *Output, s: *Stream) bool {
        const client = s.client.?;
        const render = s.render.?;
        var padding: u32 = 0;
        if (w.failed(client.vtbl.GetCurrentPadding(client, &padding))) return false;
        const room = s.frames -| padding;
        if (room == 0) return true;
        var data: ?[*]f32 = null;
        if (w.failed(render.vtbl.GetBuffer(render, room, &data)) or data == null) return false;
        o.source.fill(data.?, room);
        return !w.failed(render.vtbl.ReleaseBuffer(render, room, 0));
    }

    /// Feed the stream until asked to stop (true) or until it has to be reopened (false).
    fn play(o: *Output, enumerator: *Enumerator, s: *Stream) bool {
        const handles = [_]w.HANDLE{ o.quit, o.ready };
        var last_check = seconds();
        while (true) {
            // The device signals every few milliseconds. A second without a signal means it has stopped
            // without saying so, which a reopen cures.
            const got = w.WaitForMultipleObjects(handles.len, &handles, 0, 1000);
            if (got == w.WAIT_OBJECT_0) return true;
            if (got != w.WAIT_OBJECT_0 + 1) return false;
            if (!o.fill(s)) return false;
            const t = seconds();
            if (t - last_check >= default_check_seconds) {
                last_check = t;
                if (!isDefault(enumerator, s)) return false;
            }
        }
    }

    /// No device: keep the synthesiser's clock running, so sounds triggered meanwhile end when they
    /// should and are not all heard at once when a device appears. Returns true when asked to stop.
    fn idle(o: *Output, ms: u32) bool {
        var scratch: [480 * 2]f32 = undefined;
        var left = ms;
        while (left > 0) {
            const step = @min(left, 10);
            if (w.WaitForSingleObject(o.quit, step) == w.WAIT_OBJECT_0) return true;
            o.source.fill(&scratch, @as(usize, step) * 48);
            left -= step;
        }
        return false;
    }
};

fn seconds() f64 {
    var t: i64 = 0;
    var f: i64 = 1;
    _ = w.QueryPerformanceCounter(&t);
    _ = w.QueryPerformanceFrequency(&f);
    return @as(f64, @floatFromInt(t)) / @as(f64, @floatFromInt(@max(f, 1)));
}

/// Whether the stream's device is still the default playback device.
fn isDefault(enumerator: *Enumerator, s: *Stream) bool {
    var endpoint: ?*Endpoint = null;
    if (w.failed(enumerator.vtbl.GetDefaultAudioEndpoint(enumerator, eRender, eConsole, &endpoint)) or endpoint == null) return false;
    defer w.Com.release(&endpoint);
    var id: ?[*:0]u16 = null;
    if (w.failed(endpoint.?.vtbl.GetId(endpoint.?, &id)) or id == null) return true;
    defer w.CoTaskMemFree(id);
    const mine = s.id orelse return true;
    return std.mem.eql(u16, std.mem.span(mine), std.mem.span(id.?));
}

/// Ask the multimedia scheduler to treat this thread as audio, so a busy frame does not starve it. The
/// DLL is looked up at run time; without it the thread runs at normal priority, which still works.
fn raisePriority() void {
    const L = std.unicode.utf8ToUtf16LeStringLiteral;
    const avrt = w.LoadLibraryW(L("avrt.dll")) orelse return;
    const Set = *const fn (w.LPCWSTR, *u32) callconv(WINAPI) w.HANDLE;
    const set: Set = @ptrCast(@alignCast(w.GetProcAddress(avrt, "AvSetMmThreadCharacteristicsW") orelse return));
    var task: u32 = 0;
    _ = set(L("Pro Audio"), &task);
}

test "the wait for a playback device doubles from half a second to four" {
    var ms: u32 = 0;
    var total: u32 = 0;
    const want = [_]u32{ 500, 1000, 2000, 4000, 4000 };
    for (want) |expected| {
        ms = nextRetry(ms);
        total += ms;
        try std.testing.expectEqual(expected, ms);
    }
    try std.testing.expectEqual(@as(u32, 11500), total);
}

test "the stream is asked for the synthesiser's own format" {
    const f = streamFormat();
    try std.testing.expectEqual(@as(u32, 48000), f.nSamplesPerSec);
    try std.testing.expectEqual(@as(u32, f.nSamplesPerSec * f.nBlockAlign), f.nAvgBytesPerSec);
    try std.testing.expectEqual(@as(u16, f.nChannels * f.wBitsPerSample / 8), f.nBlockAlign);
    try std.testing.expectEqual(@as(u16, @sizeOf(WAVEFORMATEXTENSIBLE) - 18), f.cbSize);
}
