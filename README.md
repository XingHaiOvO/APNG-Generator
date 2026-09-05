# APNG Generator

一个 APNG（Animated PNG）生成器，提供两个实现：

- **桌面版**：基于 Qt（C++），Windows / Linux / macOS（[`desktop/`](desktop/)）
- **移动版**：基于 Flutter（Dart），Android / iOS（[`mobile/`](mobile/)）

两者共享同一套核心算法思路：手动组装 PNG/APNG 数据块（IHDR / acTL / fcTL / IDAT / fdAT / IEND），不依赖任何第三方 APNG 库。

## ✨ 功能特性

### 桌面版（Qt）

- 🖼️ 支持常见的图片格式作为帧输入（PNG、JPEG、BMP、GIF、TIFF等）
- 🎞️ 帧列表管理：添加、删除、上移、下移
- ⏱️ 每帧延迟独立设置（单位：1/100 秒）
- 🔁 循环次数可配置（0 = 无限循环）
- 👀 内置预览动画功能
- 🚀 纯标准 C++/Qt 实现，不依赖外部 APNG 库
- 🌍 跨平台支持（Windows、Linux、macOS）

### 移动版（Flutter）

- 🖼️ 从系统相册多选图片作为帧（PNG / JPEG / BMP / GIF / WebP）
- 🎞️ 帧列表管理：长按拖拽排序（带常驻操作提示）、删除、缩略图预览
- ⏱️ 每帧延迟独立设置（1/100 秒，1–10000），支持预设值与"应用到全部帧"
- 🔁 循环次数可配置（0 = 无限循环），新帧默认延迟可设置
- 👀 动画预览：按每帧延迟精确步进播放，透明区域棋盘格显示
- 🚀 生成 APNG 一键保存到系统相册（"APNG 生成器"图集，也可通过菜单分享到任意 App）
- 📱 JPEG EXIF 方向自动校正（原生解码器忽略 EXIF，手机竖拍照片常见问题）
- 🧪 APNG 编码核心为纯 Dart 实现（不依赖 Flutter），可脱离设备单元测试

## 📸 界面预览

![](https://cos.xh-net.com/wp-content/uploads/2026/09/xhnet20260901111943image-20260901111930117.png)

## 🛠️ 依赖

**桌面版**

- [Qt](https://www.qt.io/) 5.15 或 6.x（Widgets 模块）
- [CMake](https://cmake.org/) ≥ 3.16
- 支持 C++17 的编译器（MSVC、GCC、Clang）

**移动版**

- [Flutter](https://docs.flutter.dev/get-started/install) SDK ≥ 3.13（Dart ≥ 3.13）
- Android：Android SDK（`flutter doctor` 检查）
- iOS：macOS + Xcode

## 🔨 构建步骤

### 桌面版（Qt）

1. 安装 Qt：

   - **Windows**: 推荐使用 Qt 在线安装器，选择 MinGW 或 MSVC 组件。
   - **Linux**: 使用包管理器安装（例如 Ubuntu 下 `sudo apt install qtbase5-dev` 或 `qt6-base-dev`）。
   - **macOS**: 使用 Homebrew 安装 `brew install qt`。

2. 配置并构建（源码位于 [`desktop/`](desktop/)）：

```bash
cd desktop
cmake -B build -DCMAKE_PREFIX_PATH=/path/to/Qt/version/compiler
cmake --build build
```

**示例**（Windows + Qt6 + MinGW）：

```powershell
cd desktop
cmake -B build -G "MinGW Makefiles" -DCMAKE_PREFIX_PATH=D:\Qt\6.11.2\mingw_64
cmake --build build
```

**示例**（Linux + Qt5）：

```bash
cd desktop
cmake -B build -DCMAKE_PREFIX_PATH=/usr/lib/x86_64-linux-gnu/cmake/Qt5
cmake --build build
```

### 移动版（Flutter）

```bash
cd mobile
flutter pub get
flutter run                # 调试运行
```

构建发布包：

```bash
flutter build apk          # Android APK
flutter build appbundle    # Android AAB（上架用）
flutter build ipa          # iOS（需 macOS）
```

## 🚀 使用方法

### 桌面版

1. 启动程序。
2. 点击 **"添加"** 按钮，选择多张图片（尺寸需一致，否则自动跳过）。
3. 在列表中选择帧，通过右侧的 **延迟调节器** 修改该帧的显示时间。
4. 通过 **"循环次数"** 设置动画播放次数（0 表示无限循环）。
5. 点击 **"预览图片"** 查看动画效果。
6. 点击 **"生成 APNG"** 保存文件，选择输出路径即可。

### 移动版

1. 启动 App，点击 **"添加图片"** 从相册多选图片（尺寸需与第一帧一致，否则提示并跳过）。
2. 在帧列表 **长按并上下拖动** 调整顺序，点击 ⏲ 图标编辑该帧延迟（可勾选"应用到全部帧"）。
3. 通过 AppBar 的 **"循环 N 次"** 设置播放次数（0 = 无限循环），菜单中可修改新帧的默认延迟。
4. 点击预览区的 **▶ 播放** 查看动画效果。
5. 点击 **"保存到相册"**，直接存入系统相册的"APNG 生成器"图集；也可通过 ⋮ 菜单的 **"分享 APNG"** 发送给其他 App（直接分享可能不是原图）。注意：文件本身始终是合法 APNG，相册中是否播放动画取决于系统图片查看器对 APNG 的支持（iOS 13+ / 部分 Android 相册支持）。

## 🧪 测试

**桌面版**：使用 CTest / 手动运行。

**移动版**（不依赖模拟器）：

```bash
cd mobile
flutter test               # 33 个测试：编码器块结构/CRC/像素往返、EXIF 解析、导出链路、界面交互
flutter analyze            # 静态分析（当前零告警）
```

移动版核心测试用程序化生成的 PNG 夹具验证生成文件的全部数据块（签名 / IHDR / acTL / fcTL / fdAT / IEND、每块 CRC、序列号严格递增），并把 fdAT 载荷反解压回原始像素做往返比对。

## 📁 项目结构

```
.
├── desktop/                # 桌面版（Qt / C++）
│   ├── CMakeLists.txt           # CMake 构建脚本
│   ├── main.cpp                 # 程序入口
│   ├── MainWindow.h/.cpp        # 主窗口逻辑与 GUI
│   ├── FrameItem.h/.cpp         # 帧数据模型
│   └── ApngGenerator.h/.cpp     # APNG 核心生成器（手动组装 APNG 块）
├── mobile/                 # 移动版（Flutter）
│   └── lib/
│       ├── core/                # APNG 编码核心（纯 Dart，可脱离 Flutter 测试）
│       │   ├── crc32.dart            # CRC32 查表法（与桌面版实现逐位一致）
│       │   ├── apng_encoder.dart     # parsePng + ApngAssembler（增量组装）
│       │   └── exif.dart             # JPEG EXIF orientation 解析
│       ├── models/              # 帧数据模型
│       ├── services/            # 图片解码加载（含 EXIF 校正）、生成导出 + 分享
│       ├── state/               # FrameStore（ChangeNotifier 状态管理）
│       └── ui/                  # Material 3 界面
└── docs/superpowers/specs/      # 设计文档（Flutter 移动版等）
```

## 📄 桌面版与移动版的差异

| 项目 | 桌面版 (Qt) | 移动版 (Flutter) |
|---|---|---|
| 帧排序 | 上移 / 下移按钮 | 长按拖拽排序（列表上方有操作提示） |
| 添加图片 | 文件对话框 / 拖拽 | 系统相册多选 |
| 导出 | 另存为对话框 | 保存到系统相册 |
| 输入格式 | PNG/JPEG/BMP/GIF/TIFF | PNG/JPEG/BMP/GIF/WebP（Flutter 平台解码限制，TIFF/HEIC 暂不支持） |
| fcTL/fdAT 序列号 | 每帧 fcTL 与 fdAT 使用相同序列号（不符合 APNG 规范，宽松查看器可播放） | **已修复**：全部块共用严格递增计数器，符合 [APNG 规范](https://wiki.mozilla.org/APNG_Specification) |

## 📄 许可证

本项目采用 [MIT License](LICENSE)。您可以自由使用、修改和分发，但需保留版权声明。

## 🙏 致谢

- 感谢 Qt 项目提供的优秀框架。
- 感谢 Flutter 团队提供的跨端方案。
- APNG 格式规范参考 [APNG Specification](https://wiki.mozilla.org/APNG_Specification)。

---

如果遇到任何问题或建议，欢迎在 GitHub 上提交 Issue 或 Pull Request。
