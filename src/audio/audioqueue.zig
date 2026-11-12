//! The macOS output of `audio.zig`: an AudioQueue that pulls interleaved float stereo from the synthesiser
//! on its own thread.

const std = @import("std");
const common = @import("../audio.zig");

const Asbd = extern struct {
    sample_rate: f64,
    format_id: u32,
    format_flags: u32,
    bytes_per_packet: u32,
    frames_per_packet: u32,
    bytes_per_frame: u32,
    channels: u32,
    bits_per_channel: u32,
    reserved: u32,
};
const AqBuffer = extern struct {
    capacity: u32,
    data: ?[*]f32,
    byte_size: u32,
    user: ?*anyopaque,
    pd_cap: u32,
    pd: ?*anyopaque,
    pd_count: u32,
};
const Callback = *const fn (?*anyopaque, ?*anyopaque, *AqBuffer) callconv(.c) void;
extern fn AudioQueueNewOutput(fmt: *const Asbd, cb: Callback, user: ?*anyopaque, runloop: ?*anyopaque, mode: ?*anyopaque, flags: u32, out: *?*anyopaque) i32;
extern fn AudioQueueAllocateBuffer(q: ?*anyopaque, bytes: u32, out: *?*AqBuffer) i32;
extern fn AudioQueueEnqueueBuffer(q: ?*anyopaque, buf: *AqBuffer, n: u32, pd: ?*anyopaque) i32;
extern fn AudioQueueStart(q: ?*anyopaque, t: ?*anyopaque) i32;
extern fn AudioQueueStop(q: ?*anyopaque, immediate: bool) i32;
extern fn AudioQueueDispose(q: ?*anyopaque, immediate: bool) i32;

const frames_per_buffer = 512;

pub const Output = struct {
    queue: ?*anyopaque = null,
    source: common.Source = undefined,

    /// Start the output queue. `o` must not move afterwards.
    pub fn start(o: *Output, source: common.Source) bool {
        o.source = source;
        const fmt: Asbd = .{
            .sample_rate = common.rate,
            .format_id = 0x6C70636D, // 'lpcm'
            .format_flags = 1 | 8, // float, packed
            .bytes_per_packet = 8,
            .frames_per_packet = 1,
            .bytes_per_frame = 8,
            .channels = 2,
            .bits_per_channel = 32,
            .reserved = 0,
        };
        if (AudioQueueNewOutput(&fmt, &callback, o, null, null, 0, &o.queue) != 0) return false;
        for (0..3) |_| {
            var buf: ?*AqBuffer = null;
            if (AudioQueueAllocateBuffer(o.queue, frames_per_buffer * 8, &buf) != 0) return false;
            callback(o, o.queue, buf.?);
        }
        return AudioQueueStart(o.queue, null) == 0;
    }

    /// Stop the render thread. Must run before the memory behind the source goes away.
    pub fn stop(o: *Output) void {
        if (o.queue == null) return;
        _ = AudioQueueStop(o.queue, true);
        _ = AudioQueueDispose(o.queue, true);
        o.queue = null;
    }

    fn callback(user: ?*anyopaque, q: ?*anyopaque, buf: *AqBuffer) callconv(.c) void {
        const o: *Output = @ptrCast(@alignCast(user.?));
        o.source.fill(buf.data.?, frames_per_buffer);
        buf.byte_size = frames_per_buffer * 8;
        _ = AudioQueueEnqueueBuffer(q, buf, 0, null);
    }
};
