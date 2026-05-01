const std = @import("std");
const zs = @import("ziosprite");

pub fn main() !void {
    const anim = zs.Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 100_000_000 },
            .{ .x = 32, .y = 0, .w = 32, .h = 32, .duration_ns = 100_000_000 },
            .{ .x = 64, .y = 0, .w = 32, .h = 32, .duration_ns = 100_000_000 },
        },
        .loop_mode = .loop,
    };

    var a = zs.Animator.init();
    a.play(&anim);

    for (0..8) |i| {
        const f = a.update(100_000_000);
        if (f) |frame| {
            std.debug.print("Frame {d}: x={}, y={}\n", .{ i, frame.x, frame.y });
        }
    }
}
