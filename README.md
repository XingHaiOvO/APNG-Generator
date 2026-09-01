# APNG Generator

一个基于 Qt 的跨平台 APNG（Animated PNG）生成器。用户可以通过图形界面添加多个图片帧，设置帧延迟和循环次数，并生成可在浏览器和现代图片查看器中播放的 APNG 文件。

## ✨ 功能特性

- 🖼️ 支持常见的图片格式作为帧输入（PNG、JPEG、BMP、GIF、TIFF等）
- 🎞️ 帧列表管理：添加、删除、上移、下移
- ⏱️ 每帧延迟独立设置（单位：1/100 秒）
- 🔁 循环次数可配置（0 = 无限循环）
- 👀 内置预览动画功能
- 🚀 纯标准 C++/Qt 实现，不依赖外部 APNG 库
- 🌍 跨平台支持（Windows、Linux、macOS）

## 📸 界面预览

![](https://cos.xh-net.com/wp-content/uploads/2026/09/xhnet20260901111943image-20260901111930117.png)

## 🛠️ 依赖

- [Qt](https://www.qt.io/) 5.15 或 6.x（Widgets 模块）
- [CMake](https://cmake.org/) ≥ 3.16
- 支持 C++17 的编译器（MSVC、GCC、Clang）

## 🔨 构建步骤

### 1. 安装 Qt

根据您的操作系统选择合适的 Qt 版本进行安装：

- **Windows**: 推荐使用 Qt 在线安装器，选择 MinGW 或 MSVC 组件。
- **Linux**: 使用包管理器安装（例如 Ubuntu 下 `sudo apt install qtbase5-dev` 或 `qt6-base-dev`）。
- **macOS**: 使用 Homebrew 安装 `brew install qt`。

### 2. 获取源码

```bash
git clone https://github.com/yourusername/apng-generator.git
cd apng-generator
```

### 3. 配置并构建

```bash
mkdir build
cd build
cmake .. -DCMAKE_PREFIX_PATH=/path/to/Qt/version/compiler
cmake --build .
```

**示例**（Windows + Qt6 + MinGW）：

```powershell
cmake .. -G "MinGW Makefiles" -DCMAKE_PREFIX_PATH=D:\Qt\6.11.2\mingw_64
cmake --build .
```

**示例**（Linux + Qt5）：

```bash
cmake .. -DCMAKE_PREFIX_PATH=/usr/lib/x86_64-linux-gnu/cmake/Qt5
make
```

## 🚀 使用方法

1. 启动程序。
2. 点击 **“添加”** 按钮，选择多张图片（尺寸需一致，否则自动跳过）。
3. 在列表中选择帧，通过右侧的 **延迟调节器** 修改该帧的显示时间。
4. 通过 **“循环次数”** 设置动画播放次数（0 表示无限循环）。
5. 点击 **“预览图片”** 查看动画效果。
6. 点击 **“生成 APNG”** 保存文件，选择输出路径即可。

## 📁 项目结构

```
.
├── CMakeLists.txt          # CMake 构建脚本
├── main.cpp                # 程序入口
├── MainWindow.h/.cpp       # 主窗口逻辑与 GUI
├── FrameItem.h/.cpp        # 帧数据模型
├── ApngGenerator.h/.cpp    # APNG 核心生成器（手动组装 APNG 块）
└── README.md
```

## 📄 许可证

本项目采用 [MIT License](LICENSE)。您可以自由使用、修改和分发，但需保留版权声明。

## 🙏 致谢

- 感谢 Qt 项目提供的优秀框架。
- APNG 格式规范参考 [APNG Specification](https://wiki.mozilla.org/APNG_Specification)。

---

如果遇到任何问题或建议，欢迎在 GitHub 上提交 Issue 或 Pull Request。