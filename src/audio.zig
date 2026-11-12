//! Procedural audio through an AudioQueue. No samples on disk: every sound is a few oscillators and noise.
//! Each arm's sounds are panned to its side so the two can be told apart by ear.

const std = @import("std");
const game = @import("game.zig");

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

const rate: f32 = 48000;
const frames_per_buffer = 512;

const Wave = enum(u8) { sine, saw, square, noise };

const Voice = struct {
    active: bool = false,
    t: f32 = 0,
    dur: f32 = 0.1,
    f0: f32 = 440,
    f1: f32 = 440,
    wave: Wave = .sine,
    noise: f32 = 0,
    gain: f32 = 0.2,
    pan: f32 = 0,
    phase: f32 = 0,
    lp: f32 = 1,
    lp_state: f32 = 0,
};

/// Continuous parameters written by the game thread and read by the audio thread.
pub const Params = struct {
    drill_on: [2]f32 = .{ 0, 0 },
    drill_bite: [2]f32 = .{ 0, 0 },
    flow: f32 = 0,
    heart_bpm: f32 = 80,
    alarm: f32 = 0,
    warp: f32 = 0,
    master: f32 = 0.8,
    heart_gain: f32 = 1,
};

pub const Event = struct { id: u8, pan: f32, gain: f32 };

/// Extra one-shots that are not game sound effects.
pub const comm_chirp: u8 = 200;

pub const Audio = struct {
    queue: ?*anyopaque = null,
    params: Params = .{},
    events: [64]Event = undefined,
    head: std.atomic.Value(u32) = .init(0),
    tail: std.atomic.Value(u32) = .init(0),

    // audio-thread state
    voices: [40]Voice = @splat(.{}),
    seed: u32 = 0x1234567,
    drill_phase: [2]f32 = .{ 0, 0 },
    drill_amp: [2]f32 = .{ 0, 0 },
    drill_bite: [2]f32 = .{ 0, 0 },
    flow_lp: [2]f32 = .{ 0, 0 },
    flow_amp: f32 = 0,
    beat: f32 = 0,
    beat_t: f32 = 10,
    beat2_t: f32 = 10,
    alarm_t: f32 = 0,
    warp_amp: f32 = 0,
    warp_phase: f32 = 0,

    /// Start the output queue. `a` must not move afterwards.
    pub fn start(a: *Audio) bool {
        const fmt: Asbd = .{
            .sample_rate = rate,
            .format_id = 0x6C70636D, // 'lpcm'
            .format_flags = 1 | 8, // float, packed
            .bytes_per_packet = 8,
            .frames_per_packet = 1,
            .bytes_per_frame = 8,
            .channels = 2,
            .bits_per_channel = 32,
            .reserved = 0,
        };
        if (AudioQueueNewOutput(&fmt, &callback, a, null, null, 0, &a.queue) != 0) return false;
        for (0..3) |_| {
            var buf: ?*AqBuffer = null;
            if (AudioQueueAllocateBuffer(a.queue, frames_per_buffer * 8, &buf) != 0) return false;
            callback(a, a.queue, buf.?);
        }
        return AudioQueueStart(a.queue, null) == 0;
    }

    /// Stop the render thread. Must run before the memory behind `a` goes away.
    pub fn stop(a: *Audio) void {
        if (a.queue == null) return;
        _ = AudioQueueStop(a.queue, true);
        _ = AudioQueueDispose(a.queue, true);
        a.queue = null;
    }

    pub fn play(a: *Audio, id: u8, pan: f32, gain: f32) void {
        const h = a.head.load(.monotonic);
        const next = (h + 1) % @as(u32, a.events.len);
        if (next == a.tail.load(.acquire)) return;
        a.events[h] = .{ .id = id, .pan = pan, .gain = gain };
        a.head.store(next, .release);
    }

    pub fn playSfx(a: *Audio, ev: game.SfxEvent) void {
        a.play(@intFromEnum(ev.id), ev.pan, ev.gain);
    }

    fn rnd(a: *Audio) f32 {
        a.seed ^= a.seed << 13;
        a.seed ^= a.seed >> 17;
        a.seed ^= a.seed << 5;
        return @as(f32, @floatFromInt(a.seed & 0xffff)) / 32768.0 - 1.0;
    }

    fn voice(a: *Audio, v: Voice) void {
        for (&a.voices) |*slot| {
            if (!slot.active) {
                slot.* = v;
                slot.active = true;
                return;
            }
        }
    }

    fn tone(a: *Audio, delay: f32, f0: f32, f1: f32, dur: f32, wave: Wave, gain: f32, pan: f32) void {
        a.voice(.{ .t = -delay, .dur = dur, .f0 = f0, .f1 = f1, .wave = wave, .gain = gain, .pan = pan });
    }

    fn hiss(a: *Audio, delay: f32, dur: f32, lp: f32, gain: f32, pan: f32) void {
        a.voice(.{ .t = -delay, .dur = dur, .wave = .noise, .noise = 1, .gain = gain, .pan = pan, .lp = lp });
    }

    fn trigger(a: *Audio, ev: Event) void {
        const p = ev.pan;
        const g = ev.gain;
        if (ev.id == comm_chirp) {
            a.tone(0, 1250, 1250, 0.045, .sine, 0.06 * g, 0);
            a.tone(0.07, 1560, 1560, 0.05, .sine, 0.06 * g, 0);
            return;
        }
        if (ev.id >= @typeInfo(game.Sfx).@"enum".field_names.len) return;
        const id: game.Sfx = @enumFromInt(ev.id);
        switch (id) {
            .shoot => {
                a.tone(0, 1500, 480, 0.09, .saw, 0.13 * g, p);
                a.hiss(0, 0.05, 0.6, 0.06 * g, p);
            },
            .lance => {
                a.tone(0, 1000, 180, 0.28, .saw, 0.2 * g, 0);
                a.tone(0, 2000, 900, 0.2, .sine, 0.12 * g, 0);
            },
            .swing => a.hiss(0, 0.13, 0.12, 0.2 * g, p),
            .punch_hit => {
                a.tone(0, 150, 48, 0.17, .sine, 0.5 * g, p);
                a.hiss(0, 0.04, 0.5, 0.2 * g, p);
            },
            .sync => {
                a.tone(0, 120, 36, 0.45, .sine, 0.65 * g, 0);
                a.tone(0, 660, 1320, 0.16, .square, 0.08 * g, 0);
                a.tone(0.02, 990, 1980, 0.2, .sine, 0.1 * g, 0);
                a.hiss(0, 0.2, 0.25, 0.25 * g, 0);
            },
            .kill => a.tone(0, 900, 1900, 0.07, .sine, 0.13 * g, p),
            .nest_die => {
                a.hiss(0, 0.6, 0.08, 0.35 * g, 0);
                a.tone(0, 320, 55, 0.5, .sine, 0.3 * g, 0);
            },
            .hurt => {
                a.tone(0, 190, 80, 0.32, .saw, 0.3 * g, 0);
                a.hiss(0, 0.2, 0.3, 0.2 * g, 0);
            },
            .tissue => {
                a.tone(0, 220, 196, 0.2, .square, 0.1 * g, 0);
                a.tone(0, 233, 207, 0.2, .square, 0.1 * g, 0);
            },
            .scan => {
                a.tone(0, 1200, 2400, 0.22, .sine, 0.09 * g, 0);
                a.tone(0.12, 2400, 2400, 0.3, .sine, 0.04 * g, 0);
            },
            .objective => {
                a.tone(0, 523, 523, 0.25, .sine, 0.14 * g, -0.2);
                a.tone(0.1, 659, 659, 0.25, .sine, 0.14 * g, 0);
                a.tone(0.2, 784, 784, 0.4, .sine, 0.14 * g, 0.2);
            },
            .checkpoint => {
                a.tone(0, 659, 659, 0.15, .sine, 0.12 * g, 0);
                a.tone(0.12, 988, 988, 0.3, .sine, 0.12 * g, 0);
            },
            .upgrade => {
                const notes = [_]f32{ 392, 523, 659, 784, 1047 };
                for (notes, 0..) |f, i| a.tone(@as(f32, @floatFromInt(i)) * 0.09, f, f, 0.5, .sine, 0.13 * g, @as(f32, @floatFromInt(i)) * 0.3 - 0.6);
                a.tone(0, 98, 98, 0.9, .saw, 0.08 * g, 0);
            },
            .cut => {
                a.tone(0, 520, 90, 0.2, .saw, 0.22 * g, p);
                a.hiss(0, 0.08, 0.7, 0.2 * g, p);
            },
            .shatter => {
                a.hiss(0, 0.9, 0.2, 0.5 * g, 0);
                a.tone(0, 95, 28, 0.8, .sine, 0.6 * g, 0);
                for (0..6) |i| a.tone(@as(f32, @floatFromInt(i)) * 0.05, 2400 + @as(f32, @floatFromInt(i)) * 300, 1200, 0.06, .square, 0.05 * g, a.rnd());
            },
            .escape => {
                a.tone(0, 440, 415, 0.3, .sine, 0.15 * g, 0);
                a.tone(0.25, 330, 294, 0.5, .sine, 0.15 * g, 0);
            },
            .absorb => a.tone(0, 170, 85, 0.1, .sine, 0.22 * g, p),
            .overheat => a.tone(0, 320, 140, 0.45, .square, 0.12 * g, p),
            .windup => a.tone(0, 700, 1700, 0.7, .sine, 0.07 * g, p),
            .transit => {
                a.hiss(0, 3.2, 0.05, 0.3 * g, 0);
                a.tone(0, 70, 420, 1.6, .saw, 0.08 * g, 0);
                a.tone(1.6, 420, 70, 1.7, .saw, 0.08 * g, 0);
            },
            .ui => a.tone(0, 880, 880, 0.04, .sine, 0.08 * g, p),
            .bump => a.tone(0, 95, 45, 0.13, .sine, 0.4 * g, 0),
        }
    }

    fn render(a: *Audio, out: [*]f32, frames: usize) void {
        while (true) {
            const t = a.tail.load(.monotonic);
            if (t == a.head.load(.acquire)) break;
            a.trigger(a.events[t]);
            a.tail.store((t + 1) % @as(u32, a.events.len), .release);
        }
        const p = a.params;
        const dt = 1.0 / rate;
        for (0..frames) |i| {
            var l: f32 = 0;
            var r: f32 = 0;

            for (&a.voices) |*v| {
                if (!v.active) continue;
                v.t += dt;
                if (v.t < 0) continue;
                if (v.t >= v.dur) {
                    v.active = false;
                    continue;
                }
                const k = v.t / v.dur;
                const f = v.f0 * std.math.pow(f32, v.f1 / v.f0, k);
                v.phase += f * dt;
                v.phase -= @floor(v.phase);
                var s: f32 = switch (v.wave) {
                    .sine => @sin(v.phase * std.math.tau),
                    .saw => v.phase * 2 - 1,
                    .square => if (v.phase < 0.5) @as(f32, 0.7) else -0.7,
                    .noise => 0,
                };
                if (v.noise > 0) {
                    v.lp_state += (a.rnd() - v.lp_state) * v.lp;
                    s = s * (1 - v.noise) + v.lp_state * v.noise * (1 + 2 * (1 - v.lp));
                }
                const env = @min(v.t * 400, 1) * (1 - k) * (1 - k);
                s *= env * v.gain;
                l += s * (1 - v.pan) * 0.5;
                r += s * (1 + v.pan) * 0.5;
            }

            // Drills: left arm in the left ear, right arm in the right.
            for (0..2) |d| {
                a.drill_amp[d] += (p.drill_on[d] - a.drill_amp[d]) * 0.002;
                a.drill_bite[d] += (p.drill_bite[d] - a.drill_bite[d]) * 0.003;
                if (a.drill_amp[d] > 0.001) {
                    const f = 78 + 40 * a.drill_amp[d] + 55 * a.drill_bite[d] + 6 * @sin(a.drill_phase[d] * 0.31);
                    a.drill_phase[d] += f * dt;
                    const ph = a.drill_phase[d] - @floor(a.drill_phase[d]);
                    var s = (ph * 2 - 1) * 0.5 + (if (ph < 0.3) @as(f32, 0.5) else -0.2);
                    s += a.rnd() * 0.8 * a.drill_bite[d];
                    s *= a.drill_amp[d] * (0.075 + 0.05 * a.drill_bite[d]);
                    if (d == 0) {
                        l += s;
                        r += s * 0.15;
                    } else {
                        r += s;
                        l += s * 0.15;
                    }
                }
            }

            // Blood rushing past: filtered noise that opens up with flow speed.
            a.flow_amp += (p.flow - a.flow_amp) * 0.0005;
            const cut = 0.008 + 0.05 * a.flow_amp;
            a.flow_lp[0] += (a.rnd() - a.flow_lp[0]) * cut;
            a.flow_lp[1] += (a.rnd() - a.flow_lp[1]) * cut;
            const fg = 0.25 + 0.9 * a.flow_amp;
            l += a.flow_lp[0] * fg;
            r += a.flow_lp[1] * fg;

            // The patient's heart, heard through tissue.
            a.beat += dt * p.heart_bpm / 60.0;
            if (a.beat >= 1) {
                a.beat -= 1;
                a.beat_t = 0;
            }
            if (a.beat > 0.3 and a.beat_t > 0.25 and a.beat2_t > 0.5) a.beat2_t = 0;
            a.beat_t += dt;
            a.beat2_t += dt;
            var hb: f32 = 0;
            if (a.beat_t < 0.14) hb += @sin(a.beat_t * std.math.tau * 58) * (1 - a.beat_t / 0.14) + 0.4 * @sin(a.beat_t * std.math.tau * 116) * (1 - a.beat_t / 0.14);
            if (a.beat2_t < 0.1) hb += 0.7 * @sin(a.beat2_t * std.math.tau * 72) * (1 - a.beat2_t / 0.1) + 0.3 * @sin(a.beat2_t * std.math.tau * 144) * (1 - a.beat2_t / 0.1);
            hb *= 0.2 * p.heart_gain;
            l += hb;
            r += hb;

            // Low-stability alarm.
            if (p.alarm > 0.5) {
                a.alarm_t += dt;
                if (a.alarm_t > 1.1) a.alarm_t = 0;
                if (a.alarm_t < 0.12) {
                    const s = @sin(a.alarm_t * std.math.tau * 880) * 0.05;
                    l += s;
                    r += s;
                }
            }

            const m = p.master;
            out[i * 2] = std.math.clamp(l * m, -1, 1);
            out[i * 2 + 1] = std.math.clamp(r * m, -1, 1);
        }
    }

    fn callback(user: ?*anyopaque, q: ?*anyopaque, buf: *AqBuffer) callconv(.c) void {
        const a: *Audio = @ptrCast(@alignCast(user.?));
        a.render(buf.data.?, frames_per_buffer);
        buf.byte_size = frames_per_buffer * 8;
        _ = AudioQueueEnqueueBuffer(q, buf, 0, null);
    }

    /// Render offline into `out` (interleaved stereo); used by the tests.
    pub fn renderOffline(a: *Audio, out: []f32) void {
        a.render(out.ptr, out.len / 2);
    }
};

test "arm sounds are panned to their side" {
    var a: Audio = .{};
    a.params.master = 1;
    a.params.heart_gain = 0;
    a.play(@intFromEnum(game.Sfx.shoot), -0.7, 1);
    var buf: [9600]f32 = undefined;
    a.renderOffline(&buf);
    var el: f32 = 0;
    var er: f32 = 0;
    for (0..4800) |i| {
        el += buf[i * 2] * buf[i * 2];
        er += buf[i * 2 + 1] * buf[i * 2 + 1];
    }
    try std.testing.expect(el > er * 3);
    for (buf) |s| try std.testing.expect(s >= -1 and s <= 1);
}
