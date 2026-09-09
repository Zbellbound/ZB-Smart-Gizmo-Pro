# ScalePlusPlusNative

Native backend for `ZB Smart Gizmo` Smart Scale.

## Folder Structure

- `src/scale_engine.cpp`
- `src/ruby_bridge.cpp`
- `mac/scaleplusplus_native.bundle`
- `win/scaleplusplus_native.so`

Ruby loads:

- macOS: `zb_smart_gizmo/native/mac/scaleplusplus_native.bundle`
- Windows: `zb_smart_gizmo/native/win/scaleplusplus_native.so`

If the native binary is missing or fails to load, the extension falls back to the built-in Ruby math path.

## Build on macOS

Requirements:

- SketchUp-compatible Ruby on `PATH`
- Xcode command line tools
- `clang++`

From `zb_smart_gizmo/native`:

```bash
chmod +x build_macos.sh
./build_macos.sh
```

Output:

```text
mac/scaleplusplus_native.bundle
```

## Build on Windows (MSYS2 / MinGW)

Requirements:

- MSYS2 shell
- `g++`
- SketchUp-compatible Ruby on `PATH`

From `zb_smart_gizmo/native`:

```bash
chmod +x build_windows_msys2.sh
./build_windows_msys2.sh
```

Output:

```text
win/scaleplusplus_native.so
```

## Common Errors

`cannot load such file -- scaleplusplus_native`

- The binary is missing from the expected `mac/` or `win/` folder.
- The binary was built against the wrong Ruby version.

`Target dimension must be greater than zero.`

- The requested Smart Scale size is invalid.

`Current X/Y/Z dimension must be greater than zero.`

- The selected object has a zero-size dimension on the chosen reference axis.
