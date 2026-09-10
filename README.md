# APNG Generator

一个 APNG（Animated PNG）生成器，提供三个实现：

- **桌面版**：基于 Qt（C++），Windows / Linux / macOS（[`desktop/`](desktop/)）
- **移动版**：基于 Flutter（Dart），Android / iOS（[`mobile/`](mobile/)）
- **Web 版**：基于 FastAPI（Python），任意现代浏览器访问（[`web/`](web/)）

三者共享同一套核心算法思路：手动组装 PNG/APNG 数据块（IHDR / acTL / fcTL / IDAT / fdAT / IEND），不依赖任何第三方 APNG 库。

## ✨ 功能特性

### 桌面版（Qt）

- 🖼️ 支持常见的图片格式作为帧输入（PNG、JPEG、BMP、GIF、TIFF、WebP 等）
- 🎞️ 帧列表管理：添加、删除、上移、下移
- 🖱️ 支持文件对话框与拖拽添加图片
- ⏱️ 每帧延迟独立设置（单位：1/100 秒）
- 🔁 循环次数可配置（0 = 无限循环）
- 👀 内置预览动画功能
- 🚀 纯标准 C++/Qt 实现，不依赖外部 APNG 库
- 🌍 跨平台支持（Windows、Linux、macOS）

### 移动版（Flutter）

- 🖼️ 从系统相册多选图片作为帧（PNG / JPEG / BMP / GIF）
- 🎞️ 帧列表管理：长按拖拽排序（带常驻操作提示）、删除、缩略图预览
- ⏱️ 每帧延迟独立设置（1/100 秒，1–10000），支持预设值与"应用到全部帧"
- 🔁 循环次数可配置（0 = 无限循环），新帧默认延迟可设置
- 👀 动画预览：按每帧延迟精确步进播放，透明区域棋盘格显示
- 🚀 生成 APNG 一键保存到系统相册（"APNG 生成器"图集，也可通过菜单分享到任意 App）
- 📱 JPEG EXIF 方向自动校正（原生解码器忽略 EXIF，手机竖拍照片常见问题）
- 🧪 APNG 编码核心为纯 Dart 实现（不依赖 Flutter），可脱离设备单元测试

### Web 版（FastAPI）

- 🖼️ 拖拽或点击上传图片作为帧（PNG / JPEG / BMP / GIF / TIFF）
- 🎞️ 帧列表管理：上移、下移、删除、缩略图预览
- ⏱️ 每帧延迟独立设置（1/100 秒），支持"应用到所有帧"
- 🔁 循环次数可配置（0 = 无限循环）
- 👀 前端按延迟步进播放预览
- ⚡ FastAPI 后端，前端零依赖（原生 HTML + CSS + JS）
- 🐳 提供 Dockerfile 与 docker-compose，一键部署
- 🧪 生成后浏览器直接下载 `output.png`

## 📸 界面预览

**桌面版**

![](https://cos.xh-net.com/wp-content/uploads/2026/09/xhnet20260901111943image-20260901111930117.png)

**Web 版**

![](https://cos.xh-net.com/wp-content/uploads/2026/09/xhnet20260910201429屏幕截图-2026-09-10-201409.png)

## 🛠️ 依赖

**桌面版**

- [Qt](https://www.qt.io/) 5.15 或 6.x（Widgets 模块）
- [CMake](https://cmake.org/) ≥ 3.16
- 支持 C++17 的编译器（MSVC、GCC、Clang）

**移动版**

- [Flutter](https://docs.flutter.dev/get-started/install) SDK ≥ 3.13（Dart ≥ 3.13）
- Android：Android SDK（`flutter doctor` 检查）
- iOS：macOS + Xcode

**Web 版**

- Python ≥ 3.10
- 依赖见 [`web/requirements.txt`](web/requirements.txt)：`fastapi`、`uvicorn[standard]`、`python-multipart`、`Pillow`
- 可选：[Docker](https://www.docker.com/) ≥ 20（用于容器化部署）

## 🔨 构建步骤

### 桌面版（Qt）

1. 安装 Qt：

   - **Windows**：推荐使用 Qt 在线安装器，选择 MinGW 或 MSVC 组件。
   - **Linux**：使用包管理器安装（例如 Ubuntu 下 `sudo apt install qtbase5-dev` 或 `qt6-base-dev`）。
   - **macOS**：使用 Homebrew 安装 `brew install qt`。

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

### Web 版（FastAPI）

**本地开发**

```bash
cd web
python -m venv .venv
source .venv/bin/activate       # Windows: .venv\Scripts\activate
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

浏览器访问 <http://127.0.0.1:8000>。

**Docker 部署**

```bash
cd web
docker build -t apng-generator-web .
docker run -d --name apng-generator-web -p 8000:8000 --restart unless-stopped apng-generator-web
```

或使用 docker-compose：

```bash
cd web
docker compose up -d --build
```

## 🚀 使用方法

### 桌面版

1. 启动程序。
2. 点击 **“添加帧”** 按钮，选择多张图片（尺寸需一致，否则自动跳过）；也可直接将图片拖拽到窗口。
3. 在列表中选择帧，通过右侧的 **延迟调节器** 修改该帧的显示时间。
4. 通过 **“循环次数”** 设置动画播放次数（0 表示无限循环）。
5. 点击 **“播放预览”** 查看动画效果。
6. 点击 **“生成 APNG”** 保存文件，选择输出路径即可。

### 移动版

1. 启动 App，点击 **“添加图片”** 从相册多选图片（尺寸需与第一帧一致，否则提示并跳过）。
2. 在帧列表 **长按并上下拖动** 调整顺序，点击 ⏲ 图标编辑该帧延迟（可勾选“应用到全部帧”）。
3. 通过 AppBar 的 **“循环 N 次”** 设置播放次数（0 = 无限循环），菜单中可修改新帧的默认延迟。
4. 点击预览区的 **▶ 播放** 查看动画效果。
5. 点击 **“保存到相册”**，直接存入系统相册的“APNG 生成器”图集；也可通过 ⋮ 菜单的 **“分享 APNG”** 发送给其他 App。注意：文件本身始终是合法 APNG，相册中是否播放动画取决于系统图片查看器对 APNG 的支持（iOS 13+ / 部分 Android 相册支持）。

### Web 版

1. 打开浏览器访问 Web 服务地址。
2. 将多张图片 **拖拽** 到上传区域，或点击 **“点击选择图片”** 按钮多选（尺寸需一致，否则后端返回错误）。
3. 在帧列表中使用 ↑ / ↓ 调整顺序，或点击 **“删除”** 移除某一帧。
4. 修改每帧的延迟，或使用 **“批量延迟 + 应用到所有帧”** 一键统一。
5. 设置 **循环次数**（0 = 无限循环）。
6. 点击 **“播放预览”** 在浏览器内查看动画效果。
7. 点击 **“生成 APNG”**，浏览器自动下载 `output.png`。

## 🧪 测试

**桌面版**：使用 CTest / 手动运行。

**移动版**（不依赖模拟器）：

```bash
cd mobile
flutter test               # 33 个测试：编码器块结构/CRC/像素往返、EXIF 解析、导出链路、界面交互
flutter analyze            # 静态分析（当前零告警）
```

移动版核心测试用程序化生成的 PNG 夹具验证生成文件的全部数据块（签名 / IHDR / acTL / fcTL / fdAT / IEND、每块 CRC、序列号严格递增），并把 fdAT 载荷反解压回原始像素做往返比对。

**Web 版**：

```bash
cd web
pip install pytest httpx
pytest                     # 后续补充
```

手动验证：启动服务后通过浏览器访问 `/api/health` 应返回 `{"status": "ok"}`。

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
└── web/                    # Web 版（FastAPI + 原生前端）
    ├── main.py                  # FastAPI 入口（/api/generate、/api/health）
    ├── apng_generator.py        # APNG 编码核心（纯 Python，块组装）
    ├── requirements.txt         # Python 依赖
    ├── Dockerfile               # 容器镜像构建脚本
    ├── docker-compose.yml       # 一键部署配置
    └── static/                  # 前端（原生 HTML / CSS / JS）
        ├── index.html
        ├── style.css            # 当前主题样式
        └── app.js
```

## 📄 三端实现差异

| 项目             | 桌面版 (Qt)                                                  | 移动版 (Flutter)                            | Web 版 (FastAPI)                     |
| ---------------- | ------------------------------------------------------------ | ------------------------------------------- | ------------------------------------ |
| 运行平台         | Windows / Linux / macOS                                      | Android / iOS                               | 浏览器（服务端任意平台）             |
| 帧排序           | 上移 / 下移按钮                                              | 长按拖拽排序                                | 上移 / 下移按钮                      |
| 添加图片         | 文件对话框 / 拖拽                                            | 系统相册多选                                | 拖拽上传 / 文件选择                  |
| 导出             | 另存为对话框                                                 | 系统分享面板 / 相册                         | 浏览器下载                           |
| 输入格式         | PNG/JPEG/BMP/GIF/TIFF/WebP                                   | PNG/JPEG/BMP/GIF/WebP（TIFF/HEIC 暂不支持） | PNG/JPEG/BMP/GIF/TIFF/WebP           |
| 批量延迟         | 无（逐帧设置）                                               | 有（应用到全部帧）                          | 有（应用到所有帧）                   |
| fcTL/fdAT 序列号 | 每帧 fcTL 与 fdAT 使用相同序列号（不符合 APNG 规范，宽松查看器可播放） | **已修复**：全部块共用严格递增计数器        | **已修复**：全部块共用严格递增计数器 |

## 🐳 Docker 部署（Web 版）

快速启动：

```bash
docker run -d --name apng-generator-web -p 8000:8000 --restart unless-stopped \
  ghcr.io/xinghaiovo/apng-generator-web:latest
```

自行构建：

```bash
cd web
docker build -t apng-generator-web:latest .
docker run -d -p 8000:8000 apng-generator-web:latest
```

生产环境建议配合 Nginx 反向代理 + HTTPS，并设置 `client_max_body_size`（例如 50M）以支持较大的帧文件上传。

## 📄 许可证

本项目采用 [MIT License](LICENSE)。您可以自由使用、修改和分发，但需保留版权声明。

## 🙏 致谢

- 感谢 Qt 项目提供的优秀框架。
- 感谢 Flutter 团队提供的跨端方案。
- 感谢 FastAPI 与 Pillow 项目。
- APNG 格式规范参考 [APNG Specification](https://wiki.mozilla.org/APNG_Specification)。

## ⚠️ 免责声明

本项目为开源工具，仅供学习、研究与个人合法用途。在使用前，请务必阅读并理解以下内容：

1. **按“原样”提供**
   本软件按“原样”（AS IS）提供，不附带任何形式的明示或默示担保，包括但不限于对适销性、特定用途适用性及非侵权性的担保。作者不对软件的功能完整性、稳定性、兼容性或生成结果的正确性作出任何承诺。
2. **内容责任自负**
   您通过本软件加载、处理、生成的任何图片与文件，其来源合法性、版权归属及内容合规性均由您自行负责。您不得使用本软件处理、生成或传播任何侵犯他人知识产权、违反当地法律法规或含有违法、暴力、色情等内容的数据。因您的使用行为引起的任何法律纠纷或责任，均由您自行承担。
3. **Web 版的数据与隐私**
   Web 版通过 HTTP 上传图片到服务端进行处理，图片会在服务器内存中短暂驻留，生成结果返回后不做持久化存储（除非自行修改代码）。
   - 公共部署环境下的数据传输与隐私安全无法得到绝对保证，**请勿上传涉密、敏感或私人重要图片**。
   - 若需处理敏感内容，请自行在可信环境中本地部署，并自行承担网络与服务器安全责任。
   - 作者不对任何因第三方部署、服务器配置不当或网络传输导致的数据泄露、丢失或滥用承担责任。
4. **生成结果与兼容性**
   生成的 APNG 文件本身遵循 APNG 规范，但能否在特定软件、系统相册或社交平台中播放动画，取决于该查看器/平台对 APNG 的支持程度。作者不对兼容性问题及由此产生的后果负责。
5. **责任限制**
   在适用法律允许的最大范围内，作者及贡献者不对因使用或无法使用本软件而导致的任何直接、间接、附带、特殊或后果性损害（包括但不限于数据丢失、业务中断、设备损坏等）承担任何责任，即使已被告知此类损害的可能性。
6. **最终解释**
   使用本软件即表示您已阅读、理解并同意上述条款。若您不同意其中任何内容，请立即停止使用并删除本软件。

---

如果遇到任何问题或建议，欢迎在 GitHub 上提交 Issue 或 Pull Request。
