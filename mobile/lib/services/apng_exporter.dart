/// APNG 导出服务：逐帧编码 PNG → 组装 APNG 写入临时文件 → 系统分享。
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/apng_encoder.dart';
import '../models/frame.dart';

/// 生成 APNG 文件（写入应用临时目录）。
///
/// 逐帧从 [frames] 的 [ui.Image] 提取 PNG 字节并增量写入文件，
/// 内存占用与单帧大小成正比（与帧数无关）。[onProgress] 报告 (已完成帧数, 总帧数)。
///
/// 返回写入的文件。
Future<File> writeApngFile({
  required List<Frame> frames,
  required int loopCount,
  void Function(int done, int total)? onProgress,
}) async {
  if (frames.isEmpty) {
    throw ArgumentError('请添加至少一张图片');
  }

  final dir = await getTemporaryDirectory();
  final path =
      '${dir.path}${Platform.pathSeparator}apng_${DateTime.now().millisecondsSinceEpoch}.png';
  final file = File(path);
  final raf = await file.open(mode: FileMode.write);

  try {
    final assembler = ApngAssembler(onWrite: raf.writeFromSync);
    for (var i = 0; i < frames.length; i++) {
      final data = await frames[i].image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('第 ${i + 1} 帧编码 PNG 失败');
      }
      final png = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      if (i == 0) {
        assembler.start(
          firstFramePng: png,
          frameCount: frames.length,
          loopCount: loopCount,
          delayNum: frames.first.delayNum,
        );
      } else {
        assembler.addFrame(png, delayNum: frames[i].delayNum);
      }
      onProgress?.call(i + 1, frames.length);
    }
    assembler.finish();
  } catch (_) {
    // 留下半成品没有意义，清理后继续向上抛
    try {
      await raf.close();
    } catch (_) {}
    if (await file.exists()) {
      await file.delete();
    }
    rethrow;
  }
  await raf.close();
  return file;
}

/// 拉起系统分享面板分享生成的 APNG 文件。
Future<void> shareApngFile(File file) async {
  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path)], text: 'APNG 动图'),
  );
}

/// 保存到相册时使用的相册（图集）名。
const String kGalleryAlbum = 'APNG 生成器';

/// 将生成的 APNG 文件保存到系统相册。
///
/// Android 走 MediaStore、iOS 走 PhotoKit，文件字节原样保留（仍是合法 APNG，
/// 相册 App 是否播放动画取决于系统查看器对 APNG 的支持程度）。
Future<void> saveApngToGallery(File file, {String album = kGalleryAlbum}) async {
  try {
    await Gal.putImage(file.path, album: album);
  } on GalException catch (e) {
    throw Exception('写入相册失败（${e.type.name}），请检查相册权限');
  }
}
