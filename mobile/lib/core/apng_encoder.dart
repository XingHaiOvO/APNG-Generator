/// APNG 编码核心：PNG 块解析与 APNG 组装。
///
/// 移植自 ApngGenerator.cpp：
/// - [parsePng] 对应原版的 parsePng（提取 IHDR 与合并的 IDAT）；
/// - [ApngAssembler] 对应原版的 generate（签名 + IHDR + acTL + fcTL/IDAT/fdAT + IEND）。
///
/// 与原版唯一的差异：fcTL/fdAT 序列号按 APNG 规范使用同一个严格递增计数器
/// （原版第 i 帧的 fcTL 与 fdAT 使用了相同的序列号 i）。
///
/// 本库不依赖 Flutter，可在纯 Dart 环境中测试。
library;

import 'dart:typed_data';

import 'crc32.dart';

/// PNG 文件签名。
final Uint8List kPngSignature = Uint8List.fromList(
  const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
);

/// 从 PNG 字节流中提取出的关键数据。
class PngImageParts {
  /// IHDR 块的数据（13 字节）。
  final Uint8List ihdr;

  /// 所有 IDAT 块数据的顺序拼接（即 zlib 压缩的图像数据流）。
  final Uint8List idat;

  const PngImageParts(this.ihdr, this.idat);
}

/// 从内存中的 PNG 文件提取 IHDR 数据和 IDAT 数据（连接所有 IDAT 块）。
///
/// 解析失败（签名错误、数据不完整、缺少 IHDR 或 IDAT）返回 null。
PngImageParts? parsePng(Uint8List pngData) {
  const signatureSize = 8;
  if (pngData.length < signatureSize) return null;

  for (var i = 0; i < signatureSize; i++) {
    if (pngData[i] != kPngSignature[i]) return null;
  }

  var pos = signatureSize;
  Uint8List? ihdrData;
  final idatData = BytesBuilder(copy: false);

  while (pos + 8 <= pngData.length) {
    final length = (pngData[pos] << 24) |
        (pngData[pos + 1] << 16) |
        (pngData[pos + 2] << 8) |
        pngData[pos + 3];
    pos += 4;

    if (pos + 4 + length + 4 > pngData.length) return null; // 数据不完整

    final type = Uint8List.sublistView(pngData, pos, pos + 4);
    pos += 4;

    final data = Uint8List.sublistView(pngData, pos, pos + length);
    pos += length + 4; // 跳过数据与 CRC

    if (_typeIs(type, 'IHDR')) {
      if (length != 13) return null;
      ihdrData = Uint8List.fromList(data);
    } else if (_typeIs(type, 'IDAT')) {
      idatData.add(data);
    } else if (_typeIs(type, 'IEND')) {
      break;
    }
  }

  if (ihdrData == null || idatData.isEmpty) return null;
  return PngImageParts(ihdrData, idatData.toBytes());
}

bool _typeIs(Uint8List type, String ascii) {
  for (var i = 0; i < 4; i++) {
    if (type[i] != ascii.codeUnitAt(i)) return false;
  }
  return true;
}

void _addUint32(BytesBuilder b, int v) {
  b.add([(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);
}

void _addUint16(BytesBuilder b, int v) {
  b.add([(v >> 8) & 0xFF, v & 0xFF]);
}

/// 将一个 PNG 块（长度 + 类型 + 数据 + CRC）写入 [out]。
void writeChunk(BytesBuilder out, String type, List<int> data) {
  assert(type.length == 4, 'PNG 块类型必须为 4 个 ASCII 字符');
  _addUint32(out, data.length);
  out.add(type.codeUnits);
  out.add(data);
  final crcInput = BytesBuilder(copy: false)
    ..add(type.codeUnits)
    ..add(data);
  final crcBytes = BytesBuilder();
  _addUint32(crcBytes, crc32(crcInput.toBytes()));
  out.add(crcBytes.takeBytes());
}

/// 单帧输入：已编码的 PNG 字节与帧控制参数。
class ApngFrameInput {
  /// 该帧完整图像的 PNG 字节流（宽高须与画布一致）。
  final Uint8List png;

  /// 延迟分子（本应用约定 delayDen 固定为 100，单位 1/100 秒）。
  final int delayNum;

  /// 延迟分母。
  final int delayDen;

  /// 0: none, 1: background, 2: previous
  final int disposeOp;

  /// 0: source, 1: over
  final int blendOp;

  const ApngFrameInput(
    this.png, {
    required this.delayNum,
    this.delayDen = 100,
    this.disposeOp = 0,
    this.blendOp = 0,
  });
}

/// APNG 增量组装器。
///
/// 逐帧提供 PNG 字节，内部维护序列号与帧计数。写入端是一个同步回调，
/// 因此既可写入内存（[encodeApng]），也可边生成边写入文件，内存占用与
/// 单帧 PNG 大小成正比（与帧数无关）。
///
/// 画布尺寸取自第一帧 PNG 的 IHDR（与原版一致），所有帧都应与画布同尺寸、
/// 以 disposeOp=NONE / blendOp=SOURCE 的方式整幅替换。
///
/// 典型用法：
/// ```dart
/// final assembler = ApngAssembler(onWrite: sink.write);
/// assembler.start(firstFramePng: png0, frameCount: n, loopCount: 0, delayNum: 10);
/// for (...) { assembler.addFrame(framePng, delayNum: d); }
/// assembler.finish();
/// ```
class ApngAssembler {
  final void Function(List<int> bytes) onWrite;

  int _seq = 0;
  int _framesWritten = 0;
  int _frameCount = 0;
  bool _started = false;
  bool _finished = false;

  ApngAssembler({required this.onWrite});

  void _writeChunk(String type, List<int> data) {
    final b = BytesBuilder(copy: false);
    writeChunk(b, type, data);
    onWrite(b.takeBytes());
  }

  void _writeFcTL(int seq, int delayNum, int delayDen, int disposeOp,
      int blendOp) {
    _checkDelay(delayNum, delayDen);
    final b = BytesBuilder();
    _addUint32(b, seq);
    _addUint32(b, _canvasWidth);
    _addUint32(b, _canvasHeight);
    _addUint32(b, 0); // xOffset
    _addUint32(b, 0); // yOffset
    _addUint16(b, delayNum);
    _addUint16(b, delayDen);
    b.add([disposeOp, blendOp]);
    _writeChunk('fcTL', b.takeBytes());
  }

  static void _checkDelay(int num, int den) {
    if (num < 0 || num > 0xFFFF) {
      throw ArgumentError.value(num, 'delayNum', '须在 0..65535 内');
    }
    if (den <= 0 || den > 0xFFFF) {
      throw ArgumentError.value(den, 'delayDen', '须在 1..65535 内');
    }
  }

  late int _canvasWidth;
  late int _canvasHeight;

  /// 写入文件头：PNG 签名 + IHDR（取自 [firstFramePng]，同时确定画布尺寸）+
  /// acTL（[frameCount] 帧、[loopCount] 次循环）+ 第一帧 fcTL + IDAT。
  void start({
    required Uint8List firstFramePng,
    required int frameCount,
    required int loopCount,
    required int delayNum,
    int delayDen = 100,
    int disposeOp = 0,
    int blendOp = 0,
  }) {
    if (_started) throw StateError('start() 只能调用一次');
    if (frameCount < 1) {
      throw ArgumentError.value(frameCount, 'frameCount', '至少需要 1 帧');
    }
    if (loopCount < 0) {
      throw ArgumentError.value(loopCount, 'loopCount', '不能为负');
    }
    final parts = parsePng(firstFramePng);
    if (parts == null) {
      throw ArgumentError('第一帧 PNG 数据无法解析');
    }
    _started = true;
    _frameCount = frameCount;
    _canvasWidth = _uint32At(parts.ihdr, 0);
    _canvasHeight = _uint32At(parts.ihdr, 4);

    // PNG 签名
    onWrite(kPngSignature);

    // IHDR（直接使用第一帧的 IHDR）
    _writeChunk('IHDR', parts.ihdr);

    // acTL：帧数 + 循环次数
    final actl = BytesBuilder();
    _addUint32(actl, frameCount);
    _addUint32(actl, loopCount);
    _writeChunk('acTL', actl.takeBytes());

    // 第一帧：fcTL + IDAT
    _writeFcTL(_seq++, delayNum, delayDen, disposeOp, blendOp);
    _writeChunk('IDAT', parts.idat);
    _framesWritten++;
  }

  /// 写入后续帧：fcTL + fdAT（序列号共用计数器）。
  void addFrame(
    Uint8List framePng, {
    required int delayNum,
    int delayDen = 100,
    int disposeOp = 0,
    int blendOp = 0,
  }) {
    if (!_started) throw StateError('请先调用 start()');
    if (_finished) throw StateError('finish() 之后不能再添加帧');
    if (_framesWritten >= _frameCount) {
      throw StateError('帧数超出 start() 声明的 frameCount');
    }
    final parts = parsePng(framePng);
    if (parts == null) {
      throw ArgumentError('帧 PNG 数据无法解析');
    }

    _writeFcTL(_seq++, delayNum, delayDen, disposeOp, blendOp);

    // fdAT：序列号 + zlib 图像数据
    final b = BytesBuilder();
    _addUint32(b, _seq++);
    b.add(parts.idat);
    _writeChunk('fdAT', b.takeBytes());
    _framesWritten++;
  }

  /// 写入 IEND，结束组装。
  void finish() {
    if (!_started) throw StateError('请先调用 start()');
    if (_finished) return;
    if (_framesWritten != _frameCount) {
      throw StateError(
          '帧数不足：声明 $_frameCount 帧，实际写入 $_framesWritten 帧');
    }
    _writeChunk('IEND', const []);
    _finished = true;
  }

  bool get isFinished => _finished;
}

int _uint32At(Uint8List data, int offset) =>
    (data[offset] << 24) |
    (data[offset + 1] << 16) |
    (data[offset + 2] << 8) |
    data[offset + 3];

/// 全内存组装（与 ApngGenerator.cpp 的 generate 对应）。
///
/// [frames] 不能为空。返回完整 APNG 文件字节。
Uint8List encodeApng({
  required List<ApngFrameInput> frames,
  int loopCount = 0,
}) {
  if (frames.isEmpty) {
    throw ArgumentError('No frames to generate.');
  }

  final out = BytesBuilder(copy: false);
  final assembler = ApngAssembler(onWrite: out.add);
  assembler.start(
    firstFramePng: frames.first.png,
    frameCount: frames.length,
    loopCount: loopCount,
    delayNum: frames.first.delayNum,
    delayDen: frames.first.delayDen,
    disposeOp: frames.first.disposeOp,
    blendOp: frames.first.blendOp,
  );
  for (var i = 1; i < frames.length; i++) {
    final f = frames[i];
    assembler.addFrame(
      f.png,
      delayNum: f.delayNum,
      delayDen: f.delayDen,
      disposeOp: f.disposeOp,
      blendOp: f.blendOp,
    );
  }
  assembler.finish();
  return out.toBytes();
}
