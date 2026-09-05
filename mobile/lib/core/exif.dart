/// JPEG EXIF 方向（orientation）解析。
///
/// 背景：dart:ui 的原生解码器不应用 JPEG 的 EXIF orientation，Android
/// 相册照片会出现方向错误。本模块从 JPEG 字节流中解析 orientation 标签
/// （IFD0 的 0x0112），配合 services 层的画布变换完成校正。
///
/// 纯 Dart 实现，不依赖 Flutter，可单元测试。
library;

import 'dart:typed_data';

/// EXIF orientation 标签 ID（IFD0）。
const int _tagOrientation = 0x0112;

/// 解析 JPEG 字节流中的 EXIF orientation。
///
/// 返回 1..8；无 EXIF、无该标签或字节流异常时返回 null（即无需/无法校正）。
int? jpegExifOrientation(Uint8List bytes) {
  // 最小长度：SOI + 任意 marker
  if (bytes.length < 4) return null;

  // JPEG 必须以 SOI (FF D8) 开头
  if (bytes[0] != 0xFF || bytes[1] != 0xD8) return null;

  var pos = 2;
  while (pos + 4 <= bytes.length) {
    // 段前可能有填充字节 0xFF
    if (bytes[pos] != 0xFF) return null;
    var marker = bytes[pos + 1];
    var offset = 2;
    while (marker == 0xFF && pos + offset < bytes.length) {
      marker = bytes[pos + offset];
      offset++;
    }
    if (marker == 0xFF) return null;
    pos += offset;

    // 独立标记（无长度字段）
    if (marker == 0xD8 || (marker >= 0xD0 && marker <= 0xD7) || marker == 0x01) {
      continue;
    }
    // SOS 之后是压缩数据，不会再有 APP 段
    if (marker == 0xDA) return null;

    if (pos + 2 > bytes.length) return null;
    final segmentLength = (bytes[pos] << 8) | bytes[pos + 1];
    if (segmentLength < 2 || pos + segmentLength > bytes.length) return null;

    if (marker == 0xE1 && _hasExifHeader(bytes, pos + 2)) {
      final tiffStart = pos + 2 + 6;
      return _parseOrientationInTiff(bytes, tiffStart, pos + segmentLength);
    }
    pos += segmentLength;
  }
  return null;
}

bool _hasExifHeader(Uint8List bytes, int offset) {
  const exifMagic = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00]; // "Exif\0\0"
  if (offset + exifMagic.length > bytes.length) return false;
  for (var i = 0; i < exifMagic.length; i++) {
    if (bytes[offset + i] != exifMagic[i]) return false;
  }
  return true;
}

/// 在 TIFF 头（从 [tiffStart] 开始）所在的 IFD0 中查找 orientation。
int? _parseOrientationInTiff(Uint8List bytes, int tiffStart, int segmentEnd) {
  if (tiffStart + 8 > bytes.length) return null;

  final byteOrderLe = bytes[tiffStart] == 0x49 && bytes[tiffStart + 1] == 0x49;
  final byteOrderBe = bytes[tiffStart] == 0x4D && bytes[tiffStart + 1] == 0x4D;
  if (!byteOrderLe && !byteOrderBe) return null;

  int u16(int offset) {
    if (offset + 2 > segmentEnd) throw const FormatException('EXIF 数据越界');
    return byteOrderLe
        ? bytes[offset] | (bytes[offset + 1] << 8)
        : (bytes[offset] << 8) | bytes[offset + 1];
  }

  int u32(int offset) {
    if (offset + 4 > segmentEnd) throw const FormatException('EXIF 数据越界');
    return byteOrderLe
        ? bytes[offset] |
            (bytes[offset + 1] << 8) |
            (bytes[offset + 2] << 16) |
            (bytes[offset + 3] << 24)
        : (bytes[offset] << 24) |
            (bytes[offset + 1] << 16) |
            (bytes[offset + 2] << 8) |
            bytes[offset + 3];
  }

  try {
    if (u16(tiffStart + 2) != 42) return null; // TIFF 魔数
    final ifd0Offset = u32(tiffStart + 4);
    final ifd0 = tiffStart + ifd0Offset;
    if (ifd0 < tiffStart || ifd0 + 2 > segmentEnd) return null;

    final entryCount = u16(ifd0);
    final entriesStart = ifd0 + 2;
    if (entriesStart + entryCount * 12 > segmentEnd) return null;

    for (var i = 0; i < entryCount; i++) {
      final entry = entriesStart + i * 12;
      if (u16(entry) == _tagOrientation) {
        final value = u16(entry + 8); // SHORT 类型值内联在 value 字段前 2 字节
        if (value >= 1 && value <= 8) return value;
        return null;
      }
    }
    return null;
  } on FormatException {
    return null;
  }
}
