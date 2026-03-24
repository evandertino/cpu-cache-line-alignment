# ZIG CPU Cache Line Struct Alignments

This project shows how you can try to model ZIG Structs with proper alignments
to fit the CPU cache line.

Built using **ZIG v0.16.0-dev.2905+5d71e3051**

## Usage

With `-Dcache-line` option, you can pass your CPU architecture **cache line** size.

```fish
zig build -Dcache-line=128 run
```

Without `-Dcache-line` option, it will auto-detect the CPU arch building the
binary and use the correct cache line size.

```fish
zig build run
```
