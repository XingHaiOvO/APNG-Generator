/// 图片加载服务：文件字节 → 已解码、已做 EXIF 方向校正的 [ui.Image]。
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import '../core/exif.dart';

/// 加载完成的图像。
class DecodedImage {
  final ui.Image image;
  final int width;
  final int height;

  /// 是否因 EXIF orientation 做过旋转/翻转校正。
  final bool exifCorrected;

  const DecodedImage(this.image, this.width, this.height, {this.exifCorrected = false});
}

/// 解码图片字节流的第一帧。
///
/// 支持 PNG/JPEG/BMP/GIF/WebP（Flutter 平台原生解码能力）。对 JPEG 解析
/// EXIF orientation 并旋转校正（原生解码器不处理 EXIF，手机照片常见方向错误）。
///
/// 解码失败抛出 [Exception]，由调用方提示用户。
Future<DecodedImage> decodeImageBytes(Uint8List bytes) async {
  final isJpeg = bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
  final orientation = isJpeg ? jpegExifOrientation(bytes) : null;

  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final src = frame.image;

  if (orientation == null || orientation <= 1) {
    return DecodedImage(src, src.width, src.height);
  }
  try {
    final rotated = await _applyOrientation(src, orientation);
    return DecodedImage(rotated, rotated.width, rotated.height, exifCorrected: true);
  } finally {
    src.dispose();
  }
}

/// 按 EXIF orientation（2..8）对图像做旋转/翻转，返回新图像。
Future<ui.Image> _applyOrientation(ui.Image src, int orientation) async {
  // 5/6/7/8 需要交换宽高
  final swapped = orientation >= 5 && orientation <= 8;
  final outWidth = swapped ? src.height : src.width;
  final outHeight = swapped ? src.width : src.height;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.transform(
    _affineFor(orientation, src.width.toDouble(), src.height.toDouble()),
  );
  canvas.drawImage(src, ui.Offset.zero, ui.Paint());
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(outWidth, outHeight);
  } finally {
    picture.dispose();
  }
}

/// 构造 2D 仿射矩阵（dart:ui 的 4×4 列主序），满足
/// x' = a*x + c*y + e、y' = b*x + d*y + f。
Float64List _affineFor(int orientation, double w, double h) {
  double a = 1, b = 0, c = 0, d = 1, e = 0, f = 0;
  switch (orientation) {
    case 2: // 水平镜像
      a = -1; e = w;
    case 3: // 旋转 180°
      a = -1; d = -1; e = w; f = h;
    case 4: // 垂直镜像
      d = -1; f = h;
    case 5: // 转置（沿主对角线翻转）
      a = 0; b = 1; c = 1; d = 0;
    case 6: // 顺时针旋转 90°
      a = 0; b = 1; c = -1; d = 0; e = h;
    case 7: // 反转置（沿副对角线翻转）
      a = 0; b = -1; c = -1; d = 0; e = h; f = w;
    case 8: // 逆时针旋转 90°
      a = 0; b = -1; c = 1; d = 0; f = w;
  }
  return Float64List.fromList([a, b, 0, 0, c, d, 0, 0, 0, 0, 1, 0, e, f, 0, 1]);
}
