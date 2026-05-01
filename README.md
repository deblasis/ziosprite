# ziosprite

> Sprite sheet animator for Zig 2D games. Frame-based animation, loop modes, ping-pong.

Part of the [zio-zig](https://github.com/deblasis/zio-zig) ecosystem.

## Quick start

```zig
const zsprite = @import("ziosprite");

// Define a walk animation from a sprite sheet
const walk = zsprite.Animation{
    .frames = &.{
        .{ .x = 0,   .y = 0, .w = 32, .h = 32, .duration_ns = 80_000_000 },
        .{ .x = 32,  .y = 0, .w = 32, .h = 32, .duration_ns = 80_000_000 },
        .{ .x = 64,  .y = 0, .w = 32, .h = 32, .duration_ns = 80_000_000 },
        .{ .x = 96,  .y = 0, .w = 32, .h = 32, .duration_ns = 80_000_000 },
    },
    .loop_mode = .loop,
};

var animator = zsprite.Animator.init();
animator.play(&walk);

// Each frame
const dt_ns: u64 = 16_000_000; // 16ms
const frame = animator.update(dt_ns);
if (frame) |f| {
    // f.x, f.y, f.w, f.h — source rectangle on sprite sheet
    drawSprite(sheet, f, screen_x, screen_y);
}

// Switch animations
animator.play(&idle_animation);  // stops current, starts new
animator.pause();
animator.unpause();
```

```bash
zig build test          # Run 40 tests
zig build run-example   # Run example
```

## Example output

```
$ zig build run-example
Frame 0: x=32, y=0, w=32, h=32
Frame 1: x=64, y=0, w=32, h=32
Frame 2: x=0, y=0, w=32, h=32
Paused, playing=false
Resumed, playing=true
Idle finished: true
```

## API

### Frame

| Field | Description |
|-------|-------------|
| `x, y` | Top-left corner on sprite sheet |
| `w, h` | Frame dimensions |
| `duration_ns` | How long to display this frame |

### Animation

| Field | Description |
|-------|-------------|
| `frames` | Slice of Frame |
| `loop_mode` | `.once`, `.loop`, or `.ping_pong` |

### Animator

| Method | Description |
|--------|-------------|
| `init()` | Create animator |
| `play(animation)` | Start playing an animation |
| `pause()` | Pause at current frame |
| `resume()` | Resume from pause |
| `update(dt_ns)` | Advance time, returns `?Frame` (current frame) |
| `frame()` | Current frame (may be null) |
| `frameIndex()` | Current frame index |
| `progress()` | Overall progress 0.0 to 1.0 |
| `finished` | `true` when `.once` animation completes |
| `playing` | `true` when actively playing |

### Loop modes
- `.once` — play once, set `finished = true` at end
- `.loop` — loop forever (never sets `finished`)
- `.ping_pong` — play forward then backward, repeat

## License

MIT. Copyright (c) 2026 Alessandro De Blasis.
