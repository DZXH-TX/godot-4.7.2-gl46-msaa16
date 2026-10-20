# Godot 4.7.2: OpenGL 4.6 + Vulkan 2D MSAA patches

Experimental Windows rendering patches against upstream Godot **4.7.2-stable**, commit `ed1daf0bf001b61586d9930840f2f1394092c079`. This repository distributes **patches and a pinned source-fetch/build script**, not a copy of the upstream source tree. Precompiled .NET editor and Windows export templates are provided in Releases.

This is an independent community modification, not an official Godot release. Godot's existing Vulkan renderer is upstream work.

## Changes

| Patch | Scope |
| --- | --- |
| `godot-4.7.2-gl46.patch` | Windows native OpenGL 4.6 core context; Canvas instance VBOs use DSA immutable storage and persistent coherent mapping; fence completion controls reuse, with allocation accounting and cleanup |
| `godot-4.7.2-msaa16.patch` | Adds a **2D-only** 16× MSAA enum/path without changing existing 0/2×/4×/8× values; adds a Vulkan color-attachment sample-count query; keeps 3D 16× disabled |

The OpenGL patch retains Godot's Compatibility renderer and shader pipeline. It does not implement an OpenGL RenderingDevice/Forward+ backend. GLES follows its existing buffer-upload path.

**16× is hardware dependent.** Tested RTX 5080 and RTX 5060 Ti configurations reported sample mask `15` (1/2/4/8), so 16× requests must use an explicitly reported 8× fallback. The 16× native path is implemented, but rendering on hardware that actually supports 16× has not been validated. Do not infer the effective sample count from a requested setting or successful texture creation: upstream Vulkan can silently choose a lower count.

Windows Vulkan HDR display output remains disabled by upstream 4.7.2. These patches do not remove that guard, add frame generation, or claim a measured performance uplift. Correct `source_color` handling and HDR 2D internal rendering are separate from monitor HDR output.

## Obtain source / build

Prerequisites: Git; for builds, Python, Visual Studio C++ Build Tools, Windows SDK and a compatible .NET SDK. Tested with SCons 4.11.1, MSVC 14.5 and Windows SDK 10.0.28000.0. Downloads and generated files stay in `.work/`; the script does not change PATH or reset an existing checkout.

```powershell
# Fetch the exact upstream revision and apply both patches.
pwsh -File Get-Godot.ps1

# Build the .NET editor and obtain matching upstream managed assemblies.
pwsh -File Get-Godot.ps1 -Build -Target editor

# Build export templates.
pwsh -File Get-Godot.ps1 -Build -Target template_debug
pwsh -File Get-Godot.ps1 -Build -Target template_release
```

Outputs are in `.work/godot/bin`. The provided build profile enables Vulkan and OpenGL, and disables D3D12 and ANGLE. Use `--rendering-method gl_compatibility --rendering-driver opengl3` for OpenGL, or `--rendering-method forward_plus --rendering-driver vulkan` for desktop Vulkan.

For OpenGL, verify both the `OpenGL API 4.6...` startup line and `TL_GL46: DSA immutable storage + persistent coherent canvas instance buffers active`.

## Query before enabling MSAA

```gdscript
var rd = RenderingServer.get_rendering_device()
var mask = rd.call("get_supported_color_attachment_sample_counts",
    RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM, true)
var requested = 16
var effective = 0
for count in [2, 4, 8, 16]:
    if count <= requested and (mask & count) != 0:
        effective = count
get_viewport().msaa_2d = [0, 2, 4, 8, 16].find(effective)
print("Requested: ", requested, "; effective: ", effective)
```

Use `R16G16B16A16_SFLOAT` when querying an HDR 2D target and recompute when its format changes. The query covers optimal-tiled **2D color attachments**, including the driver's global color/depth limits, and accepts the mutable-format flag used by Canvas shared views. It is implemented for Vulkan; other drivers conservatively report one sample.

Existing official 4.7.2 .NET bindings remain usable. The additional method can be invoked through `GodotObject.Call`; the additional enum through `ClassDB.ClassGetIntegerConstant("Viewport", "MSAA_16X")`. The old generated C# `Msaa.Max` name has value 4, so do not use that name as a quality setting or bound in a patched engine; resolve the added constant explicitly.

## Validation

Validated on Windows with NVIDIA driver 617.14:

- RTX 5080 and RTX 5060 Ti: Vulkan 0/2×/4×/8×, explicit 16×→8× fallback, HDR-2D/SDR color-mode capability queries.
- Pixel readback verified different geometry-edge coverage at 2×/4×/8× and stable opaque SDR swatches through the internal linear pipeline.
- OpenGL 4.6 and Vulkan ran a four-canvas, 2048-rectangles-per-canvas, 240-frame stress fixture. These runs used a 60 FPS cap and are **not benchmarks**.
- Native editor, Debug and Release templates built successfully. An independently exported .NET Release quality probe ran under OpenGL and Vulkan. See release notes for the exact precompiled artifacts.

AMD/Intel, mobile, and true hardware 16× operation are not validated. Transparency, blur and font blending in linear space are not promised to match old sRGB blending pixel for pixel.

## 中文说明

本仓库仅发布补丁、固定版本获取/构建脚本及必要说明；预编译包放在 Releases。OpenGL 改动针对现有 2D Canvas 实例缓冲，Vulkan 渲染器本身来自 Godot 上游。16× 是否生效必须以设备/格式能力查询为准，目前两张测试显卡的实际最高档位均为 8×。Windows Vulkan 原生 HDR 输出限制保持不变。

## License and upstream

Patches and helper script are distributed under MIT. Preserve upstream Godot license and third-party notices when redistributing built binaries. Upstream source: [godotengine/godot](https://github.com/godotengine/godot/tree/4.7.2-stable).
