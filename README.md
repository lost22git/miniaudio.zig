
# miniaudio for Zig lang

my learning demonstration of Zig code interacting with C code

[API DOC](https://lost22git.github.io/miniaudio.zig)

## Resources

- https://ziglang.org/documentation/master/#C
- https://github.com/mackron/miniaudio

## Usage

### Build and Run app

```sh
zig build run -Doptimize=ReleaseFast -- your.mp3
```

### Build Docs

```sh
zig build docs
```

### NOTES

- miniaudio could not adjust system volume (only software volume control)
- miniaudio could not adjust playing speed
- miniaudio could not set multi loop points
