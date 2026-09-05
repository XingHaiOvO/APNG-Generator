/// 预览区：棋盘格背景 + 按每帧延迟步进播放（移植 QTimer singleShot 逻辑）。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/frame.dart';

/// 动画预览区。点击播放/暂停按钮或预览区本身切换播放状态。
class PreviewArea extends StatefulWidget {
  final List<Frame> frames;

  const PreviewArea({super.key, required this.frames});

  @override
  State<PreviewArea> createState() => _PreviewAreaState();
}

class _PreviewAreaState extends State<PreviewArea> {
  Timer? _timer;
  int _index = 0;
  bool _playing = false;

  @override
  void didUpdateWidget(covariant PreviewArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 帧集合变化（增删/重排）后重新从头播放，避免引用失效
    if (!identical(widget.frames, oldWidget.frames)) {
      final wasPlaying = _playing;
      _stop();
      _index = 0;
      if (wasPlaying && widget.frames.isNotEmpty) {
        _start();
      }
    }
    if (widget.frames.isEmpty) {
      _stop();
      _index = 0;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggle() {
    if (_playing) {
      _stop();
    } else {
      _start();
    }
    setState(() {});
  }

  void _start() {
    if (widget.frames.isEmpty) return;
    _playing = true;
    _index = 0;
    _scheduleNext();
  }

  void _stop() {
    _playing = false;
    _timer?.cancel();
    _timer = null;
  }

  /// 复刻原版 updatePreviewTimerInterval + QTimer(singleShot)：
  /// 显示当前帧后，按该帧延迟安排下一帧。
  void _scheduleNext() {
    if (!_playing || widget.frames.isEmpty) return;
    final delayMs = widget.frames[_index].delayMs;
    _timer = Timer(Duration(milliseconds: delayMs < 1 ? 1 : delayMs), _advance);
  }

  void _advance() {
    if (!_playing || widget.frames.isEmpty) return;
    setState(() {
      _index = (_index + 1) % widget.frames.length;
    });
    _scheduleNext();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final frame = widget.frames.isEmpty ? null : widget.frames[_index];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.10),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: LayoutBuilder(builder: (context, constraints) {
            return Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: CheckerboardPainter.forBrightness(
                      scheme.brightness),
                  child: ColoredBox(
                      color: scheme.brightness == Brightness.dark
                          ? const Color(0xFF171923)
                          : Colors.white),
                ),
                if (frame != null)
                  Center(
                    child: RawImage(
                      image: frame.image,
                      fit: BoxFit.contain,
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                    ),
                  ),
                if (frame == null)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.image_outlined,
                            size: 48, color: scheme.outline),
                        const SizedBox(height: 8),
                        Text('添加图片后在这里预览动画',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                // 播放/暂停按钮（仅在有帧时叠加；播放中透明但仍可点击暂停）
                if (frame != null)
                  Center(
                    child: AnimatedOpacity(
                      opacity: _playing ? 0.0 : 0.9,
                      duration: const Duration(milliseconds: 150),
                      child: IconButton.filled(
                        onPressed: _toggle,
                        icon: const Icon(Icons.play_arrow),
                        iconSize: 40,
                      ),
                    ),
                  ),
                // 帧指示与循环信息
                if (frame != null)
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: _InfoChip(
                      label: _playing
                          ? '第 ${_index + 1}/${widget.frames.length} 帧'
                          : '第 ${_index + 1}/${widget.frames.length} 帧 · 点击播放',
                    ),
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

/// 透明背景棋盘格（明暗两套配色）。
class CheckerboardPainter extends CustomPainter {
  const CheckerboardPainter._(this._light, this._dark);

  factory CheckerboardPainter.forBrightness(Brightness brightness) {
    return brightness == Brightness.dark
        ? const CheckerboardPainter._(Color(0xFF1E2130), Color(0xFF171923))
        : const CheckerboardPainter._(Color(0xFFEDEFF6), Color(0xFFDDE1EE));
  }

  final Color _light;
  final Color _dark;

  static const double _cell = 10;

  @override
  void paint(Canvas canvas, Size size) {
    final light = Paint()..color = _light;
    final dark = Paint()..color = _dark;
    canvas.drawRect(Offset.zero & size, light);
    final cols = (size.width / _cell).ceil();
    final rows = (size.height / _cell).ceil();
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        if ((row + col) % 2 == 0) continue;
        canvas.drawRect(
          Offset(col * _cell, row * _cell) & const Size(_cell, _cell),
          dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CheckerboardPainter oldDelegate) =>
      oldDelegate._light != _light || oldDelegate._dark != _dark;
}
