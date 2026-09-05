/// 帧列表状态管理（对应 MainWindow 中的 m_frames 与两个 spinbox）。
library;

import 'package:flutter/foundation.dart';

import '../models/frame.dart';

/// 画布尺寸（以第一帧为准）。
typedef CanvasSize = ({int width, int height});

/// 全局帧集合 + 导入/生成参数。
class FrameStore extends ChangeNotifier {
  final List<Frame> _frames = [];

  /// 新导入帧的默认延迟（1/100 秒）。
  int defaultDelayNum = kDefaultDelayNum;

  /// 循环次数，0 = 无限循环。
  int loopCount = 0;

  List<Frame> get frames => List.unmodifiable(_frames);

  int get frameCount => _frames.length;

  bool get isEmpty => _frames.isEmpty;

  /// 画布尺寸（以第一帧为准）；无帧时为 null。
  CanvasSize? get canvasSize => _frames.isEmpty
      ? null
      : (width: _frames.first.width, height: _frames.first.height);

  /// 一轮动画的总时长（毫秒）。
  int get totalDurationMs =>
      _frames.fold(0, (sum, f) => sum + f.delayMs);

  /// 添加帧（假定尺寸已由调用方校验）。
  void addFrame(Frame frame) {
    _frames.add(frame);
    notifyListeners();
  }

  void removeAt(int index) {
    assert(index >= 0 && index < _frames.length);
    _frames.removeAt(index).image.dispose();
    notifyListeners();
  }

  /// 拖拽重排：把 [oldIndex] 的帧移动到 [newIndex]（目标索引，无需调用方修正）。
  ///
  /// 配合 `ReorderableListView.onReorderItem` 使用。
  void reorder(int oldIndex, int newIndex) {
    assert(oldIndex >= 0 && oldIndex < _frames.length);
    final frame = _frames.removeAt(oldIndex);
    _frames.insert(newIndex.clamp(0, _frames.length), frame);
    notifyListeners();
  }

  void setDelay(int index, int delayNum) {
    assert(index >= 0 && index < _frames.length);
    _frames[index].delayNum = delayNum;
    notifyListeners();
  }

  void applyDelayToAll(int delayNum) {
    for (final f in _frames) {
      f.delayNum = delayNum;
    }
    notifyListeners();
  }

  void setLoopCount(int value) {
    loopCount = value;
    notifyListeners();
  }

  void clear() {
    for (final f in _frames) {
      f.image.dispose();
    }
    _frames.clear();
    notifyListeners();
  }
}
