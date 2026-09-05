/// 帧数据模型（对应 C++ 版的 FrameItem）。
library;

import 'dart:ui' as ui;

/// 延迟分母，与原版一致固定为 100（延迟单位 1/100 秒）。
const int frameDelayDen = 100;

/// 默认帧延迟（1/100 秒），与原版 spinbox 默认值一致。
const int kDefaultDelayNum = 10;

/// 一帧动画：已解码的图像与延迟参数。
///
/// 只持有 [ui.Image]（可由引擎管理显存），原始 RGBA 字节在导出时才提取。
class Frame {
  final ui.Image image;
  final int width;
  final int height;

  /// 延迟分子（单位 1/100 秒）。
  int delayNum;

  Frame({
    required this.image,
    required this.width,
    required this.height,
    this.delayNum = kDefaultDelayNum,
  });

  /// 该帧的显示时长（毫秒）。
  int get delayMs => delayNum * 1000 ~/ frameDelayDen;
}
