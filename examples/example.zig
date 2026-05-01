const std = @import("std");
const zsprite = @import("ziosprite");

pub fn main() !void {
    const walk = zsprite.Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 80_000_000 },
            .{ .x = 32, .y = 0, .w = 32, .h = 32, .duration_ns = 80_000_000 },
            .{ .x = 64, .y = 0, .w = 32, .h = 32, .duration_ns = 80_000_000 },
        },
        .loop_mode = .loop,
    };

    var animator = zsprite.Animator.init();
    animator.play(&walk);

    // Each frame: advance animation
    for (0..6) |i| {
        const frame = animator.update(80_000_000);
        if (frame) |f| {
            std.debug.print("Frame {d}: x={d}, y={d}, w={d}, h={d}\n", .{ i, f.x, f.y, f.w, f.h });
        }
    }

    // Pause and resume
    animator.pause();
    std.debug.print("Paused, playing={}\n", .{animator.playing});
    animator.unpause();
    std.debug.print("Resumed, playing={}\n", .{animator.playing});

    // Switch to idle animation (once mode)
    const idle = zsprite.Animation{
        .frames = &.{
            .{ .x = 0, .y = 32, .w = 32, .h = 32, .duration_ns = 200_000_000 },
        },
        .loop_mode = .once,
    };
    animator.play(&idle);
    _ = animator.update(200_000_000);
    std.debug.print("Idle finished: {}\n", .{animator.finished});
}
