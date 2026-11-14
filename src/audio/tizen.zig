//! The television's output of `audio.zig`. The other outputs pull from the synthesiser on a thread the
//! system gives them. Here the game's own thread renders: tvengine owns the television's audio stream and
//! takes 16-bit stereo pushed into a queue, from which the system's callback only copies. Rendering in
//! that callback instead brought the process down on the television, and the engine's games all push.
//! So this output only converts: `tv.zig` asks it for blocks each frame and hands them to the engine.

const std = @import("std");
const common = @import("../audio.zig");

pub const Output = struct {
    source: ?common.Source = null,
    /// Frames rendered since `start`: the caller's evidence that sound is being made.
    pulled: u32 = 0,

    pub fn start(o: *Output, source: common.Source) bool {
        o.source = source;
        o.pulled = 0;
        return true;
    }

    pub fn stop(o: *Output) void {
        o.source = null;
    }

    /// Render the next `out.len / 2` frames as interleaved 16-bit stereo; silence when not started.
    pub fn render(o: *Output, out: []i16) void {
        const source = o.source orelse return @memset(out, 0);
        var mixed: [1024]f32 = undefined;
        var done: usize = 0;
        while (done < out.len) {
            const n = @min(out.len - done, mixed.len) & ~@as(usize, 1);
            if (n == 0) break;
            source.fill(&mixed, n / 2);
            toPcm(mixed[0..n], out[done..][0..n]);
            done += n;
        }
        o.pulled +%= @intCast(done / 2);
    }
};

/// Float samples to 16-bit, clipped at full scale; a sample that is not a number becomes silence.
pub fn toPcm(in: []const f32, out: []i16) void {
    for (in, out) |x, *y| {
        const v = if (x == x) std.math.clamp(x, -1.0, 1.0) else 0;
        y.* = @intFromFloat(v * 32767.0);
    }
}

test "float samples become 16-bit PCM, clipped, with silence for a sample that is not a number" {
    const in = [_]f32{ 0, 1, -1, 0.5, 4, -4, std.math.nan(f32), std.math.inf(f32) };
    var out: [in.len]i16 = undefined;
    toPcm(&in, &out);
    try std.testing.expectEqualSlices(i16, &.{ 0, 32767, -32767, 16383, 32767, -32767, 0, 32767 }, &out);
}

test "the output renders what its source gives, block by block, and silence without one" {
    const Ramp = struct {
        next: f32 = 0,
        fn render(ctx: *anyopaque, out: [*]f32, frames: usize) void {
            const r: *@This() = @ptrCast(@alignCast(ctx));
            for (0..frames) |i| {
                out[i * 2] = r.next;
                out[i * 2 + 1] = -r.next;
                r.next += 1.0 / 4096.0;
            }
        }
    };
    var ramp: Ramp = .{};
    var o: Output = .{};
    var pcm: [3000]i16 = undefined;
    o.render(&pcm);
    try std.testing.expectEqual(@as(i16, 0), pcm[2998]);
    try std.testing.expect(o.start(.{ .ctx = &ramp, .render = &Ramp.render }));
    o.render(&pcm);
    try std.testing.expectEqual(@as(u32, 1500), o.pulled);
    // Frame 1499 is past the first block of 512 frames: the blocks join without a gap.
    try std.testing.expectEqual(@as(i16, @intFromFloat(1499.0 / 4096.0 * 32767.0)), pcm[2998]);
    try std.testing.expectEqual(-pcm[2998], pcm[2999]);
    o.stop();
    o.render(&pcm);
    try std.testing.expectEqual(@as(i16, 0), pcm[2998]);
}
