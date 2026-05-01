//! Sprite sheet animator for 2D games.
//!
//! Define frame regions and durations, play/stop/pause animations
//! with loop modes. Works with any texture atlas layout.

const std = @import("std");

/// A single frame in a sprite animation.
pub const Frame = struct {
    /// Source rectangle in the sprite sheet (pixels).
    x: u32,
    y: u32,
    w: u32,
    h: u32,
    /// Duration of this frame in nanoseconds.
    duration_ns: u64,
};

/// Loop mode for an animation.
pub const LoopMode = enum {
    /// Play once, stop at last frame.
    once,
    /// Loop forever.
    loop,
    /// Ping-pong: forward then backward.
    ping_pong,
};

/// A named animation definition.
pub const Animation = struct {
    frames: []const Frame,
    loop_mode: LoopMode = .loop,
};

/// State for a playing animation.
pub const Animator = struct {
    animation: ?*const Animation,
    current_frame: u32,
    elapsed_ns: u64,
    playing: bool,
    direction: enum { forward, backward },
    finished: bool,

    pub fn init() @This() {
        return .{
            .animation = null,
            .current_frame = 0,
            .elapsed_ns = 0,
            .playing = false,
            .direction = .forward,
            .finished = false,
        };
    }

    /// Start playing an animation.
    pub fn play(self: *@This(), anim: *const Animation) void {
        self.animation = anim;
        self.current_frame = 0;
        self.elapsed_ns = 0;
        self.playing = true;
        self.direction = .forward;
        self.finished = false;
    }

    /// Pause the animation.
    pub fn pause(self: *@This()) void {
        self.playing = false;
    }

    /// Resume a paused animation.
    pub fn unpause(self: *@This()) void {
        if (self.animation != null and !self.finished) {
            self.playing = true;
        }
    }

    /// Stop and reset.
    pub fn stop(self: *@This()) void {
        self.playing = false;
        self.current_frame = 0;
        self.elapsed_ns = 0;
        self.finished = false;
        self.direction = .forward;
    }

    /// Advance animation by `dt_ns` nanoseconds. Returns current frame.
    pub fn update(self: *@This(), dt_ns: u64) ?Frame {
        const anim = self.animation orelse return null;
        if (!self.playing) return self.currentFrame(anim);

        self.elapsed_ns += dt_ns;

        while (self.elapsed_ns >= anim.frames[self.current_frame].duration_ns) {
            self.elapsed_ns -= anim.frames[self.current_frame].duration_ns;
            self.advanceFrame(anim);
            if (self.finished) break;
        }

        return self.currentFrame(anim);
    }

    /// Get current frame without advancing.
    pub fn frame(self: *const @This()) ?Frame {
        const anim = self.animation orelse return null;
        return self.currentFrame(anim);
    }

    /// Current frame index.
    pub fn frameIndex(self: *const @This()) u32 {
        return self.current_frame;
    }

    /// Normalized progress through the entire animation (0..1).
    pub fn progress(self: *const @This()) f32 {
        const anim = self.animation orelse return 0;
        var total_ns: u64 = 0;
        for (anim.frames) |f| total_ns += f.duration_ns;
        if (total_ns == 0) return 0;
        var elapsed_to_current: u64 = 0;
        for (anim.frames[0..self.current_frame]) |f| elapsed_to_current += f.duration_ns;
        elapsed_to_current += self.elapsed_ns;
        return @as(f32, @floatFromInt(elapsed_to_current)) / @as(f32, @floatFromInt(total_ns));
    }

    fn currentFrame(self: *const @This(), anim: *const Animation) Frame {
        return anim.frames[self.current_frame];
    }

    fn advanceFrame(self: *@This(), anim: *const Animation) void {
        switch (anim.loop_mode) {
            .once => {
                if (self.current_frame >= anim.frames.len - 1) {
                    self.playing = false;
                    self.finished = true;
                    return;
                }
                self.current_frame += 1;
            },
            .loop => {
                self.current_frame = @intCast((self.current_frame + 1) % anim.frames.len);
            },
            .ping_pong => {
                if (self.direction == .forward) {
                    if (self.current_frame >= anim.frames.len - 1) {
                        self.direction = .backward;
                        if (self.current_frame > 0) self.current_frame -= 1;
                    } else {
                        self.current_frame += 1;
                    }
                } else {
                    if (self.current_frame == 0) {
                        self.direction = .forward;
                        self.current_frame = 1;
                    } else {
                        self.current_frame -= 1;
                    }
                }
            },
        }
    }
};

/// Animation set — maps names to animations. Comptime-friendly.
pub fn AnimationSet(comptime entries: []const struct { []const u8, Animation }) type {
    return struct {
        pub fn get(name: []const u8) ?*const Animation {
            inline for (entries) |entry| {
                if (std.mem.eql(u8, entry[0], name)) return &entry[1];
            }
            return null;
        }

        pub fn count() usize {
            return entries.len;
        }
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "Animator play once" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
            .{ .x = 32, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
            .{ .x = 64, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
        },
        .loop_mode = .once,
    };

    var a = Animator.init();
    a.play(&anim);

    _ = a.update(100); // frame 0 → 1
    try std.testing.expectEqual(@as(u32, 1), a.frameIndex());

    _ = a.update(100); // frame 1 → 2
    try std.testing.expectEqual(@as(u32, 2), a.frameIndex());

    _ = a.update(100); // frame 2, done
    try std.testing.expect(a.finished);
    try std.testing.expect(!a.playing);
}

test "Animator loop" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
            .{ .x = 32, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
        },
        .loop_mode = .loop,
    };

    var a = Animator.init();
    a.play(&anim);

    _ = a.update(100); // → frame 1
    _ = a.update(100); // → frame 0 (wraps)
    try std.testing.expectEqual(@as(u32, 0), a.frameIndex());
    try std.testing.expect(!a.finished);
}

test "Animator ping_pong" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
            .{ .x = 32, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
        },
        .loop_mode = .ping_pong,
    };

    var a = Animator.init();
    a.play(&anim);

    _ = a.update(100); // → frame 1
    try std.testing.expectEqual(@as(u32, 1), a.frameIndex());
    _ = a.update(100); // → frame 0 (reversed)
    try std.testing.expectEqual(@as(u32, 0), a.frameIndex());
}

test "Animator pause and resume" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
            .{ .x = 32, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
        },
        .loop_mode = .loop,
    };

    var a = Animator.init();
    a.play(&anim);
    _ = a.update(50);
    a.pause();
    _ = a.update(200); // ignored
    try std.testing.expectEqual(@as(u32, 0), a.frameIndex());
    a.unpause();
    _ = a.update(50); // now advances
    try std.testing.expectEqual(@as(u32, 1), a.frameIndex());
}

test "Animator stop resets" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
        },
        .loop_mode = .once,
    };

    var a = Animator.init();
    a.play(&anim);
    a.stop();
    try std.testing.expect(!a.playing);
    try std.testing.expect(!a.finished);
    try std.testing.expectEqual(@as(u32, 0), a.frameIndex());
}

test "Animator progress" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
            .{ .x = 32, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
        },
        .loop_mode = .once,
    };

    var a = Animator.init();
    a.play(&anim);
    _ = a.update(50);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), a.progress(), 0.01);
}

test "Animator no animation set" {
    var a = Animator.init();
    try std.testing.expect(a.frame() == null);
    try std.testing.expect(a.update(100) == null);
}

test "Frame dimensions" {
    const f = Frame{ .x = 64, .y = 32, .w = 16, .h = 24, .duration_ns = 1000000 };
    try std.testing.expectEqual(@as(u32, 64), f.x);
    try std.testing.expectEqual(@as(u32, 24), f.h);
}

test "Animator variable frame durations" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
            .{ .x = 32, .y = 0, .w = 32, .h = 32, .duration_ns = 200 },
        },
        .loop_mode = .once,
    };

    var a = Animator.init();
    a.play(&anim);

    // First frame lasts 100ns
    try std.testing.expectEqual(@as(u32, 0), a.frameIndex());
    _ = a.update(100); // advance past frame 0
    try std.testing.expectEqual(@as(u32, 1), a.frameIndex());

    // Second frame lasts 200ns
    _ = a.update(200); // advance past frame 1
    try std.testing.expect(a.finished);
}

test "Animator single frame once" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
        },
        .loop_mode = .once,
    };

    var a = Animator.init();
    a.play(&anim);
    _ = a.update(100);
    try std.testing.expect(a.finished);
    try std.testing.expectEqual(@as(u32, 0), a.frameIndex());
}

test "Animator single frame loop" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
        },
        .loop_mode = .loop,
    };

    var a = Animator.init();
    a.play(&anim);
    _ = a.update(100);
    try std.testing.expect(!a.finished); // loops forever
    try std.testing.expectEqual(@as(u32, 0), a.frameIndex());
}

test "Animator stop and replay" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
            .{ .x = 32, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
        },
        .loop_mode = .once,
    };

    var a = Animator.init();
    a.play(&anim);
    _ = a.update(100); // frame 1
    a.stop();
    try std.testing.expectEqual(@as(u32, 0), a.frameIndex());

    a.play(&anim); // restart
    try std.testing.expectEqual(@as(u32, 0), a.frameIndex());
    try std.testing.expect(!a.finished);
}

test "Animator ping_pong three frames" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
            .{ .x = 32, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
            .{ .x = 64, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
        },
        .loop_mode = .ping_pong,
    };

    var a = Animator.init();
    a.play(&anim);

    _ = a.update(100); // 0 → 1
    try std.testing.expectEqual(@as(u32, 1), a.frameIndex());
    _ = a.update(100); // 1 → 2
    try std.testing.expectEqual(@as(u32, 2), a.frameIndex());
    _ = a.update(100); // 2 → 1 (reverse)
    try std.testing.expectEqual(@as(u32, 1), a.frameIndex());
    _ = a.update(100); // 1 → 0 (reverse)
    try std.testing.expectEqual(@as(u32, 0), a.frameIndex());
    _ = a.update(100); // 0 → 1 (forward again)
    try std.testing.expectEqual(@as(u32, 1), a.frameIndex());
}

test "Animator update while paused" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
            .{ .x = 32, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
        },
        .loop_mode = .loop,
    };

    var a = Animator.init();
    a.play(&anim);
    a.pause();

    _ = a.update(200); // ignored while paused
    try std.testing.expectEqual(@as(u32, 0), a.frameIndex());
    try std.testing.expect(!a.finished);
}

test "Animation loop_mode enum" {
    try std.testing.expectEqual(LoopMode.once, .once);
    try std.testing.expectEqual(LoopMode.loop, .loop);
    try std.testing.expectEqual(LoopMode.ping_pong, .ping_pong);
}

test "Animator progress zero at start" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
            .{ .x = 32, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
        },
        .loop_mode = .once,
    };

    var a = Animator.init();
    a.play(&anim);
    try std.testing.expectApproxEqAbs(@as(f32, 0), a.progress(), 0.01);
}

test "Animator ping_pong single frame" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
        },
        .loop_mode = .ping_pong,
    };

    var a = Animator.init();
    a.play(&anim);

    // Single frame ping-pong should stay on frame 0
    _ = a.update(100);
    try std.testing.expectEqual(@as(u32, 0), a.frameIndex());
    try std.testing.expect(!a.finished);
}

test "Animator large time jump" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
            .{ .x = 32, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
            .{ .x = 64, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
        },
        .loop_mode = .once,
    };

    var a = Animator.init();
    a.play(&anim);

    // Jump way past the end
    _ = a.update(10000);
    try std.testing.expect(a.finished);
}

test "Animation once with two frames" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 50 },
            .{ .x = 32, .y = 0, .w = 32, .h = 32, .duration_ns = 50 },
        },
        .loop_mode = .once,
    };

    var a = Animator.init();
    a.play(&anim);
    try std.testing.expect(!a.finished);

    _ = a.update(50); // frame 0 → 1
    try std.testing.expect(!a.finished);

    _ = a.update(50); // frame 1 → done
    try std.testing.expect(a.finished);
    try std.testing.expect(!a.playing);
}

test "Animator frame returns current" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
            .{ .x = 32, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
        },
        .loop_mode = .loop,
    };

    var a = Animator.init();
    a.play(&anim);

    const f = a.frame();
    try std.testing.expect(f != null);
    try std.testing.expectEqual(@as(u32, 0), f.?.x);
}

test "Animator unpause after finish does nothing" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
        },
        .loop_mode = .once,
    };

    var a = Animator.init();
    a.play(&anim);
    _ = a.update(100); // finishes
    try std.testing.expect(a.finished);

    a.unpause(); // can't unpause a finished animation
    try std.testing.expect(a.finished);
    try std.testing.expect(!a.playing);
}

test "Animator loop mode values" {
    try std.testing.expectEqual(LoopMode.once, .once);
    try std.testing.expectEqual(LoopMode.loop, .loop);
    try std.testing.expectEqual(LoopMode.ping_pong, .ping_pong);
}

test "Frame zero duration" {
    const f = Frame{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 0 };
    try std.testing.expectEqual(@as(u64, 0), f.duration_ns);
}

test "Animator loop with rapid updates" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
            .{ .x = 32, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
            .{ .x = 64, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
        },
        .loop_mode = .loop,
    };

    var a = Animator.init();
    a.play(&anim);

    // Rapid-fire updates that overshoot multiple frames
    _ = a.update(500); // jumps through multiple loops
    try std.testing.expect(!a.finished); // loop never finishes
}

test "Animator once then replay" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
        },
        .loop_mode = .once,
    };

    var a = Animator.init();
    a.play(&anim);
    _ = a.update(100);
    try std.testing.expect(a.finished);

    // Replay
    a.play(&anim);
    try std.testing.expect(!a.finished);
    try std.testing.expectEqual(@as(u32, 0), a.frameIndex());
}

test "Animator progress with loop" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
            .{ .x = 32, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
        },
        .loop_mode = .loop,
    };

    var a = Animator.init();
    a.play(&anim);
    _ = a.update(50); // halfway through first frame
    try std.testing.expect(a.progress() > 0 and a.progress() < 1);
}

test "Animator update returns current frame when not playing" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
        },
        .loop_mode = .once,
    };
    var a = Animator.init();
    a.play(&anim);
    _ = a.update(100);
    try std.testing.expect(a.finished);
    // Update after finish should return last frame
    const f = a.update(50);
    try std.testing.expect(f != null);
    try std.testing.expectEqual(@as(u32, 0), f.?.x);
}

test "Animator pause preserves frame" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
            .{ .x = 32, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
        },
        .loop_mode = .loop,
    };
    var a = Animator.init();
    a.play(&anim);
    _ = a.update(100); // advance to frame 1
    a.pause();
    try std.testing.expectEqual(@as(u32, 1), a.frameIndex());
}

test "Animator play resets finished state" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
        },
        .loop_mode = .once,
    };
    var a = Animator.init();
    a.play(&anim);
    _ = a.update(200);
    try std.testing.expect(a.finished);
    a.play(&anim);
    try std.testing.expect(!a.finished);
    try std.testing.expect(a.playing);
}

test "Animator update with zero duration frame" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 0 },
            .{ .x = 32, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
        },
        .loop_mode = .once,
    };
    var a = Animator.init();
    a.play(&anim);
    // Zero-duration frame should advance immediately
    _ = a.update(0);
    try std.testing.expectEqual(@as(u32, 1), a.frameIndex());
}

test "Animator full walk cycle workflow" {
    const walk = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 16, .h = 32, .duration_ns = 80 },
            .{ .x = 16, .y = 0, .w = 16, .h = 32, .duration_ns = 80 },
            .{ .x = 32, .y = 0, .w = 16, .h = 32, .duration_ns = 80 },
            .{ .x = 48, .y = 0, .w = 16, .h = 32, .duration_ns = 80 },
        },
        .loop_mode = .loop,
    };
    var a = Animator.init();
    a.play(&walk);

    var frames_seen: u32 = 0;
    var idx: u32 = 0;
    while (idx < 8) : (idx += 1) {
        _ = a.update(80);
        frames_seen += 1;
    }
    try std.testing.expect(frames_seen == 8);
    try std.testing.expect(!a.finished);
}

test "Animator switch between animations" {
    const idle = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 16, .h = 16, .duration_ns = 100 },
        },
        .loop_mode = .loop,
    };
    const run = Animation{
        .frames = &.{
            .{ .x = 0, .y = 16, .w = 16, .h = 16, .duration_ns = 50 },
            .{ .x = 16, .y = 16, .w = 16, .h = 16, .duration_ns = 50 },
        },
        .loop_mode = .loop,
    };

    var a = Animator.init();
    a.play(&idle);
    _ = a.update(50);
    try std.testing.expectEqual(@as(u32, 0), a.frameIndex());

    a.play(&run);
    try std.testing.expect(!a.finished);
    _ = a.update(50);
    try std.testing.expectEqual(@as(u32, 1), a.frameIndex());
}

test "Animator frame index always valid" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 16, .h = 16, .duration_ns = 50 },
            .{ .x = 16, .y = 0, .w = 16, .h = 16, .duration_ns = 50 },
            .{ .x = 32, .y = 0, .w = 16, .h = 16, .duration_ns = 50 },
        },
        .loop_mode = .loop,
    };
    var a = Animator.init();
    a.play(&anim);

    var ns: u64 = 0;
    while (ns < 1000) : (ns += 37) {
        _ = a.update(37);
        try std.testing.expect(a.frameIndex() < 3);
    }
}

test "Animator progress is always in [0,1] for loop" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
            .{ .x = 32, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
        },
        .loop_mode = .loop,
    };
    var a = Animator.init();
    a.play(&anim);

    var ns: u64 = 0;
    while (ns < 500) : (ns += 33) {
        _ = a.update(33);
        try std.testing.expect(a.progress() >= 0);
        try std.testing.expect(a.progress() <= 1);
    }
}

test "Animator update with zero elapsed time" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
            .{ .x = 32, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
        },
        .loop_mode = .loop,
    };
    var a = Animator.init();
    a.play(&anim);
    const f = a.update(0);
    try std.testing.expect(f != null);
    try std.testing.expectEqual(@as(u32, 0), a.frameIndex());
}

test "Animator single frame once animation" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 64, .h = 64, .duration_ns = 200 },
        },
        .loop_mode = .once,
    };
    var a = Animator.init();
    a.play(&anim);
    try std.testing.expect(!a.finished);
    _ = a.update(200);
    try std.testing.expect(a.finished);
}

test "Animation total duration" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
            .{ .x = 32, .y = 0, .w = 32, .h = 32, .duration_ns = 200 },
            .{ .x = 64, .y = 0, .w = 32, .h = 32, .duration_ns = 300 },
        },
        .loop_mode = .once,
    };
    // Total duration should be 600ns
    var a = Animator.init();
    a.play(&anim);
    try std.testing.expect(!a.finished);
    _ = a.update(599);
    try std.testing.expect(!a.finished);
    _ = a.update(1);
    try std.testing.expect(a.finished);
}

test "example: 3-frame loop cycle" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
            .{ .x = 32, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
            .{ .x = 64, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
        },
        .loop_mode = .loop,
    };
    var a = Animator.init();
    a.play(&anim);
    _ = a.update(100);
    try std.testing.expectEqual(@as(u32, 1), a.frameIndex()); // frame 1: x=32
    _ = a.update(100);
    try std.testing.expectEqual(@as(u32, 2), a.frameIndex()); // frame 2: x=64
    _ = a.update(100);
    try std.testing.expectEqual(@as(u32, 0), a.frameIndex()); // wraps to frame 0
}

test "Animator variable frame durations per frame" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 50 },
            .{ .x = 32, .y = 0, .w = 32, .h = 32, .duration_ns = 150 },
            .{ .x = 64, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
        },
        .loop_mode = .once,
    };
    var a = Animator.init();
    a.play(&anim);

    // Frame 0 lasts 50ns
    _ = a.update(49);
    try std.testing.expectEqual(@as(u32, 0), a.frameIndex());
    _ = a.update(1);
    try std.testing.expectEqual(@as(u32, 1), a.frameIndex());

    // Frame 1 lasts 150ns
    _ = a.update(149);
    try std.testing.expectEqual(@as(u32, 1), a.frameIndex());
    _ = a.update(1);
    try std.testing.expectEqual(@as(u32, 2), a.frameIndex());

    // Frame 2 lasts 100ns
    try std.testing.expect(!a.finished);
    _ = a.update(100);
    try std.testing.expect(a.finished);
}

test "Animator ping_pong reverses at end" {
    const anim = Animation{
        .frames = &.{
            .{ .x = 0, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
            .{ .x = 32, .y = 0, .w = 32, .h = 32, .duration_ns = 100 },
        },
        .loop_mode = .ping_pong,
    };
    var a = Animator.init();
    a.play(&anim);

    // Forward: 0→1
    _ = a.update(100);
    try std.testing.expectEqual(@as(u32, 1), a.frameIndex());
    // Backward: 1→0
    _ = a.update(100);
    try std.testing.expectEqual(@as(u32, 0), a.frameIndex());
    // Forward again: 0→1
    _ = a.update(100);
    try std.testing.expectEqual(@as(u32, 1), a.frameIndex());
}
